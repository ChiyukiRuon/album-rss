import Foundation
import Observation

public struct SyncState: Equatable, Sendable {
  public enum Status: Sendable {
    case idle
    case syncing
  }

  public var status: Status = .idle
  public var lastSyncedAt: Date
  /// 后台同步拿到、还没放进列表的新文章；点“有新图集”后才出现，列表不会自己跳动
  public var pendingIDs: [String] = []
  public var error: String?

  public init(status: Status = .idle, lastSyncedAt: Date, pendingIDs: [String] = [], error: String? = nil) {
    self.status = status
    self.lastSyncedAt = lastSyncedAt
    self.pendingIDs = pendingIDs
    self.error = error
  }
}

/// 每个端点缓存最后一次的数据，切回时立即显示
struct EndpointData {
  var folders: [Folder]
  var feeds: [Feed]
  var entries: [String: Entry]
  var order: [String]
  var scopes: [ListQuery: ScopeState]
  var unread: [String: Int]?
  var lastSyncedAt: Date
}

/// 页面状态与服务操作，对应 Web 端的 `prototype/store.ts`。
/// 所有状态都在主线程；网络请求与正文解析在后台进行，回来后用 generation 和 token 丢弃过期结果。
@MainActor @Observable
public final class AlbumStore {
  /// 每页文章数。切换或添加端点时只读第一页，列表滚到底再读下一页
  public static let pageSize = 100
  /// 切回已缓存的端点时，距上次同步超过这个时间才在后台检查新内容
  static let staleInterval: TimeInterval = 60
  /// 回到前台时，距上次同步超过这个时间才同步
  static let foregroundInterval: TimeInterval = 30

  /// 正在使用的端点
  public internal(set) var endpoint: Endpoint?
  /// 已添加的端点，不含演示数据
  public internal(set) var endpoints: [Endpoint] = []
  public internal(set) var loaded = false
  public internal(set) var settings: Settings
  public internal(set) var folders: [Folder] = []
  public internal(set) var feeds: [Feed] = []
  public internal(set) var entries: [String: Entry] = [:]
  /// 已读取的全部文章 ID，新的在前
  public internal(set) var order: [String] = []
  /// 各列表在服务端的分页进度；只读用户看到的部分，滚到底再读下一页
  public internal(set) var scopes: [ListQuery: ScopeState] = [:]
  /// 服务端的未读计数（订阅 ID → 篇数）；服务不提供时为 nil，改按已读取的文章统计
  public internal(set) var unread: [String: Int]?
  public internal(set) var sync: SyncState
  /// 列表快照版本：回滚失败的改动或放入新内容时递增，各列表据此重新取数
  public internal(set) var listVersion = 0
  public internal(set) var downloads: [String: DownloadState] = [:]
  public internal(set) var refreshingFeeds: Set<String> = []
  /// 当前查看器的翻页顺序，取自打开它的那个列表
  public var viewerSequence: [String]?
  /// 还没写入服务的已读、收藏改动数（当前端点）
  public internal(set) var pendingWrites = 0
  /// 写入被服务拒绝（凭据失效）时的说明，键为端点 ID；队列暂停到重新连接
  public internal(set) var writeErrors: [String: String] = [:]

  public let toasts: ToastCenter

  @ObservationIgnored let environment: StoreEnvironment
  @ObservationIgnored var generation = 0
  @ObservationIgnored var connectionAttempt = 0
  @ObservationIgnored var scopeToken = 0
  @ObservationIgnored var cache: [String: EndpointData] = [:]
  @ObservationIgnored var providers: [String: (key: String, provider: any RSSProvider)] = [:]
  @ObservationIgnored var demoProvider: DemoProvider?
  /// 正在显示的列表：同步时只刷新它们
  @ObservationIgnored var mounted: [ListQuery: Int] = [:]
  /// 后台同步读到的新一页，点“有新图集”时替换对应列表
  @ObservationIgnored var pending: (generation: Int, scopes: [ListQuery: ScopeState])?
  @ObservationIgnored var syncTask: Task<Void, Never>?
  /// 正在进行的同步属于哪一代（哪个端点）
  @ObservationIgnored var syncGeneration = 0
  @ObservationIgnored var queuedExplicitSync = false
  @ObservationIgnored var persistTask: Task<Void, Never>?
  @ObservationIgnored var started = false
  @ObservationIgnored var queue = WriteQueue()

  static let settingsKey = "album-rss.settings"
  static let endpointsKey = "album-rss.endpoints"
  static let activeKey = "album-rss.active"
  static let installedKey = "album-rss.installed"

  public init(environment: StoreEnvironment) {
    self.environment = environment
    toasts = ToastCenter(sleep: environment.sleep)
    let defaults = environment.defaults
    settings = defaults.data(forKey: Self.settingsKey).flatMap { try? JSONDecoder().decode(Settings.self, from: $0) }
      ?? Settings()
    sync = SyncState(lastSyncedAt: .distantPast)
    // 钥匙串在删除 App 后仍会保留：首次启动时清掉上一次安装遗留的令牌
    if defaults.data(forKey: Self.installedKey) == nil {
      environment.credentials.removeAll()
      defaults.setData(Data([1]), forKey: Self.installedKey)
    }
    let saved = defaults.data(forKey: Self.endpointsKey).flatMap { try? JSONDecoder().decode([Endpoint].self, from: $0) }
    // 读不到令牌的端点（例如钥匙串暂时不可用）这次不显示，但不改写保存的列表，也不删除它的本地数据
    endpoints = (saved ?? []).compactMap { saved in
      guard saved.kind == .connected, let token = environment.credentials.token(for: saved.id) else { return nil }
      var endpoint = saved
      endpoint.token = token
      endpoint.remember = true
      return endpoint
    }
    let activeID = defaults.data(forKey: Self.activeKey).map { String(decoding: $0, as: UTF8.self) }
    if activeID == Endpoint.demoID {
      endpoint = .demo
      demoProvider = DemoProvider(now: environment.now(), latency: environment.demoLatency)
    } else {
      endpoint = endpoints.first { $0.id == activeID }
    }
    environment.database?.removeUnknownEndpoints(keeping: Set((saved ?? []).map(\.id)))
  }

  /// 启动：恢复待发送的改动，有本地快照就先显示，再在后台同步
  public func start() async {
    guard !started else { return }
    started = true
    await restoreChanges()
    if let endpoint, let data = await loadStored(endpoint) {
      apply(endpoint, data)
      Task { await self.sync(explicit: false) }
    } else if endpoint != nil {
      await sync(explicit: true)
    }
    flushWrites()
  }

  var defaultQuery: ListQuery { ListQuery(listStatus: settings.defaultStatus) }

  // MARK: 端点

  func provider(for endpoint: Endpoint) throws -> any RSSProvider {
    if endpoint.isDemo {
      if let demoProvider { return demoProvider }
      let provider = DemoProvider(now: environment.now(), latency: environment.demoLatency)
      demoProvider = provider
      return provider
    }
    let key = [endpoint.service.rawValue, endpoint.server, endpoint.token ?? ""].joined(separator: "\n")
    if let cached = providers[endpoint.id], cached.key == key { return cached.provider }
    let provider = try environment.makeProvider(endpoint)
    providers[endpoint.id] = (key, provider)
    return provider
  }

  func persistEndpoints() {
    let remembered = endpoints.filter(\.remember).map { endpoint -> Endpoint in
      var copy = endpoint
      copy.token = nil
      return copy
    }
    environment.defaults.setData(try? JSONEncoder().encode(remembered), forKey: Self.endpointsKey)
  }

  func setActive(_ id: String?) {
    environment.defaults.setData(id.map { Data($0.utf8) }, forKey: Self.activeKey)
  }

  func nextScopeToken() -> Int {
    scopeToken += 1
    return scopeToken
  }

  func freshScope(_ query: ListQuery, _ page: EntryPage) -> ScopeState {
    var ids: [String] = []
    var seen = Set<String>()
    for entry in page.entries where seen.insert(entry.id).inserted { ids.append(entry.id) }
    return ScopeState(
      query: query, ids: ids, cursor: page.cursor, done: page.cursor == nil, token: nextScopeToken(),
      pages: [PageMark(count: ids.count, cursor: page.cursor)])
  }

  /// 读取端点的订阅、未读计数和指定列表的第一页
  func loadEndpoint(_ endpoint: Endpoint, _ provider: any RSSProvider, _ queries: [ListQuery]) async throws
    -> EndpointData
  {
    let since = queue.revision
    async let pagesRequest = Self.firstPages(provider, queries)
    async let subscriptionsRequest = provider.subscriptions()
    async let unreadRequest = provider.unreadCounts()
    let pages = try await pagesRequest
    let subscriptions = try await subscriptionsRequest
    let unread = try await unreadRequest
    let remotes = pages.flatMap(\.entries)
    let parsed = await EntryParser.parseAll(remotes, server: endpoint.server, mediaOrigin: endpoint.mediaOrigin)
    let entries = merge([:], parsed, remotes: remotes, endpoint: endpoint, since: since)
    var scopes: [ListQuery: ScopeState] = [:]
    for (query, page) in zip(queries, pages) { scopes[query] = freshScope(query, page) }
    return EndpointData(
      folders: subscriptions.folders,
      feeds: subscriptions.feeds,
      entries: entries,
      order: Selectors.sortOrder(entries),
      scopes: scopes,
      unread: adjustedUnread(unread, endpointID: endpoint.id),
      lastSyncedAt: environment.now()
    )
  }

  /// 文章页最大，先排进请求队列
  nonisolated static func firstPages(_ provider: any RSSProvider, _ queries: [ListQuery]) async throws -> [EntryPage] {
    try await withThrowingTaskGroup(of: (Int, EntryPage).self) { group in
      for (index, query) in queries.enumerated() {
        group.addTask { (index, try await provider.entries(query.entryScope, cursor: nil, limit: pageSize)) }
      }
      var pages = [EntryPage?](repeating: nil, count: queries.count)
      for try await (index, page) in group { pages[index] = page }
      return pages.compactMap { $0 }
    }
  }

  /// 合并服务端返回的文章；本地还没确认的已读、收藏改动优先。同时写入本地数据库
  func merge(
    _ current: [String: Entry],
    _ parsed: [Entry],
    remotes: [RemoteEntry],
    endpoint: Endpoint,
    since: Int
  ) -> [String: Entry] {
    var result = current
    var merged: [Entry] = []
    for var entry in parsed {
      for field in EntryField.allCases {
        let key = ChangeKey(endpointID: endpoint.id, entryID: entry.id, field: field)
        if let change = queue.change(key) {
          entry[field] = change.value
        } else if (queue.lastChanges[key] ?? 0) > since {
          entry[field] = current[entry.id]?[field] ?? entry[field]
        }
      }
      result[entry.id] = entry
      merged.append(entry)
    }
    if persists(endpoint), let database = environment.database {
      let items = Array(zip(remotes, merged))
      Task { try? await database.upsertEntries(endpoint.id, items: items.map { (remote: $0.0, entry: $0.1) }) }
    }
    return result
  }

  /// 只有保存了凭据的真实端点才写入本地数据库
  func persists(_ endpoint: Endpoint) -> Bool {
    endpoint.kind == .connected && endpoint.remember && environment.database != nil
  }

  /// 切换到端点：先缓存当前端点的数据，再换上新数据
  func activate(_ endpoint: Endpoint, _ data: EndpointData) {
    if self.endpoint?.id != endpoint.id { stash() }
    cache[endpoint.id] = nil
    if endpoint.kind == .connected {
      if let index = endpoints.firstIndex(where: { $0.id == endpoint.id }) {
        endpoints[index] = endpoint
      } else {
        endpoints.append(endpoint)
      }
      environment.credentials.setToken(endpoint.remember ? endpoint.token : nil, for: endpoint.id)
      persistEndpoints()
      if !endpoint.remember { environment.database?.removeEndpoint(endpoint.id) }
    }
    apply(endpoint, data)
    schedulePersist()
  }

  func apply(_ endpoint: Endpoint, _ data: EndpointData) {
    generation += 1
    pending = nil
    toasts.clear()
    setActive(endpoint.id)
    self.endpoint = endpoint
    loaded = true
    folders = data.folders
    feeds = data.feeds
    entries = data.entries
    order = data.order
    scopes = data.scopes
    unread = data.unread
    sync = SyncState(lastSyncedAt: data.lastSyncedAt)
    downloads = [:]
    refreshingFeeds = []
    viewerSequence = nil
    listVersion += 1
    updatePendingCount()
  }

  func stash() {
    guard let endpoint, endpoint.kind == .connected, loaded, endpoints.contains(where: { $0.id == endpoint.id }) else {
      return
    }
    persistNow()
    cache[endpoint.id] = EndpointData(
      folders: folders,
      feeds: feeds,
      entries: entries,
      order: order,
      scopes: scopes.mapValues { scope in
        var copy = scope
        copy.loading = false
        return copy
      },
      unread: unread,
      lastSyncedAt: sync.lastSyncedAt
    )
  }

  /// 不再使用任何端点，回到连接页
  func deactivate() {
    connectionAttempt += 1
    generation += 1
    pending = nil
    toasts.clear()
    setActive(nil)
    endpoint = nil
    loaded = true
    folders = []
    feeds = []
    entries = [:]
    order = []
    scopes = [:]
    unread = nil
    downloads = [:]
    refreshingFeeds = []
    viewerSequence = nil
    sync = SyncState(lastSyncedAt: .distantPast)
    listVersion += 1
    updatePendingCount()
  }

  public func enterDemo() {
    connectionAttempt += 1
    stash()
    demoProvider = DemoProvider(now: environment.now(), latency: environment.demoLatency)
    generation += 1
    pending = nil
    toasts.clear()
    setActive(Endpoint.demoID)
    endpoint = .demo
    loaded = false
    folders = []
    feeds = []
    entries = [:]
    order = []
    scopes = [:]
    unread = nil
    downloads = [:]
    refreshingFeeds = []
    viewerSequence = nil
    sync = SyncState(lastSyncedAt: .distantPast)
    listVersion += 1
    queue.forget(endpointID: Endpoint.demoID)
    updatePendingCount()
    Task { await sync(explicit: true) }
  }

  public func exitDemo() {
    demoProvider = nil
    deactivate()
  }

  /// 添加或编辑端点：验证凭据、读取第一页，然后切换过去。onStep 依次报告 0 连接、1 验证、2 读取
  public func connect(_ input: ConnectInput, onStep: @MainActor (Int) -> Void = { _ in }) async throws {
    let server = try normalizeServer(input.server)
    connectionAttempt += 1
    let attempt = connectionAttempt
    onStep(0)
    let username = input.username.trimmingCharacters(in: .whitespacesAndNewlines)
    let token: String
    if input.service == .miniflux {
      token = input.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    } else if let saved = input.token {
      token = saved
    } else {
      token = try await environment.login(server, username, input.password)
    }
    let origin = input.mediaOrigin?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let name = input.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    var endpoint = Endpoint(
      id: input.id ?? UUID().uuidString,
      name: name.isEmpty ? nil : name,
      kind: .connected,
      service: input.service,
      server: server,
      username: username,
      remember: input.remember,
      token: token,
      mediaOrigin: origin.isEmpty ? nil : try normalizeServer(origin)
    )
    onStep(1)
    let provider = try provider(for: endpoint)
    let serviceUser = try await provider.authenticate()
    if !serviceUser.isEmpty { endpoint.username = serviceUser }
    onStep(2)
    let data = try await loadEndpoint(endpoint, provider, [defaultQuery])
    guard attempt == connectionAttempt else { throw APIError.cancelled }
    activate(endpoint, data)
    // 重新连接后，之前因凭据失效暂停或正在退避的写入可以继续
    writeErrors[endpoint.id] = nil
    queue.paused.remove(endpoint.id)
    queue.failures[endpoint.id] = nil
    queue.retryAt[endpoint.id] = nil
    flushWrites()
  }

  /// 放弃进行中的连接；迟到的结果不会切换端点
  public func cancelConnect() {
    connectionAttempt += 1
  }

  /// 切换端点。访问过的端点直接用缓存或本地快照，必要时在后台检查新内容
  public func switchEndpoint(_ id: String) async throws {
    guard let endpoint = endpoints.first(where: { $0.id == id }), endpoint.id != self.endpoint?.id else { return }
    connectionAttempt += 1
    let attempt = connectionAttempt
    if let cached = cache[id] {
      activate(endpoint, cached)
      if environment.now().timeIntervalSince(cached.lastSyncedAt) > Self.staleInterval {
        Task { await sync(explicit: false) }
      }
      return
    }
    if let stored = await loadStored(endpoint) {
      guard attempt == connectionAttempt else { throw APIError.cancelled }
      activate(endpoint, stored)
      Task { await sync(explicit: false) }
      return
    }
    let data = try await loadEndpoint(endpoint, try provider(for: endpoint), [defaultQuery])
    guard attempt == connectionAttempt else { throw APIError.cancelled }
    activate(endpoint, data)
  }

  /// 删除端点及其保存的凭据和本地数据；删除正在使用的端点时切到下一个，没有了就回到连接页
  public func removeEndpoint(_ id: String) async {
    let wasActive = endpoint?.id == id
    if wasActive {
      persistTask?.cancel()
      persistTask = nil
    }
    endpoints.removeAll { $0.id == id }
    cache[id] = nil
    providers[id] = nil
    queue.forget(endpointID: id)
    writeErrors[id] = nil
    environment.credentials.setToken(nil, for: id)
    environment.database?.removeEndpoint(id)
    environment.didRemoveEndpoint(id)
    persistEndpoints()
    updatePendingCount()
    guard wasActive else { return }
    if let next = endpoints.first {
      do {
        try await switchEndpoint(next.id)
        return
      } catch {
        toasts.show("无法连接「\(next.label)」", detail: errorMessage(error), tone: .warning)
      }
    }
    deactivate()
  }

  public func updateSettings(_ change: (inout Settings) -> Void) {
    var next = settings
    change(&next)
    guard next != settings else { return }
    settings = next
    environment.defaults.setData(try? JSONEncoder().encode(next), forKey: Self.settingsKey)
  }

  // MARK: 本地快照

  func loadStored(_ endpoint: Endpoint) async -> EndpointData? {
    guard persists(endpoint), let database = environment.database else { return nil }
    let counter = TokenCounter(start: scopeToken)
    guard
      let stored = try? await database.loadSnapshot(
        endpoint.id, server: endpoint.server, mediaOrigin: endpoint.mediaOrigin, nextToken: { counter.next() })
    else { return nil }
    scopeToken = max(scopeToken, counter.current)
    var entries: [String: Entry] = [:]
    for var entry in stored.entries {
      for field in EntryField.allCases {
        if let change = queue.change(ChangeKey(endpointID: endpoint.id, entryID: entry.id, field: field)) {
          entry[field] = change.value
        }
      }
      entries[entry.id] = entry
    }
    var scopes: [ListQuery: ScopeState] = [:]
    for scope in stored.scopes { scopes[scope.query] = scope }
    return EndpointData(
      folders: stored.folders,
      feeds: stored.feeds,
      entries: entries,
      order: Selectors.sortOrder(entries),
      scopes: scopes,
      unread: stored.unread,
      lastSyncedAt: stored.lastSyncedAt
    )
  }

  /// 合并后稍等再写入，连续的改动只写一次
  func schedulePersist() {
    guard let endpoint, persists(endpoint) else { return }
    persistTask?.cancel()
    persistTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled else { return }
      self?.persistNow()
    }
  }

  /// 立即写入当前端点的状态（切换端点、进入后台时）
  public func persistNow() {
    persistTask?.cancel()
    persistTask = nil
    guard let endpoint, loaded, persists(endpoint), endpoints.contains(where: { $0.id == endpoint.id }),
      let database = environment.database
    else { return }
    let state = StoredState(
      folders: folders,
      feeds: feeds,
      scopes: Array(scopes.values).sorted { $0.query.storageKey < $1.query.storageKey },
      unread: unread,
      lastSyncedAt: sync.lastSyncedAt,
      states: entries.values.map { ($0.id, $0.read, $0.starred) },
      keep: pending.map { Array($0.scopes.values.flatMap(\.ids)) } ?? []
    )
    Task { try? await database.saveState(endpoint.id, state) }
  }
}

private final class TokenCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Int

  init(start: Int) {
    value = start
  }

  var current: Int { lock.withLock { value } }

  func next() -> Int {
    lock.withLock {
      value += 1
      return value
    }
  }
}
