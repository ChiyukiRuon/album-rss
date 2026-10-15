import Foundation

extension AlbumStore {
  /// 列表出现在屏幕上；同步时只刷新这些列表
  public func listAppeared(_ query: ListQuery) {
    mounted[query, default: 0] += 1
  }

  public func listDisappeared(_ query: ListQuery) {
    guard let count = mounted[query] else { return }
    if count <= 1 { mounted[query] = nil } else { mounted[query] = count - 1 }
  }

  /// 读取列表的下一页（还没读过时读第一页）。不等待结果，视图消失也不会取消
  @discardableResult
  public func loadMore(_ query: ListQuery) -> Task<Void, Never> {
    Task { await performLoadMore(query) }
  }

  func performLoadMore(_ query: ListQuery) async {
    let scope = scopes[query]
    guard let endpoint, loaded, scope?.loading != true, scope?.done != true else { return }
    let epoch = generation
    let token = scope?.token ?? nextScopeToken()
    let since = queue.revision
    let cursor = scope?.cursor
    let restored = scope?.restored == true && cursor != nil

    func update(_ change: (inout ScopeState) -> Void) {
      if let existing = scopes[query], existing.token != token { return }
      var next = scopes[query] ?? ScopeState(query: query, token: token)
      change(&next)
      scopes[query] = next
    }

    update {
      $0.loading = true
      $0.error = nil
    }
    do {
      let provider = try provider(for: endpoint)
      let page = try await provider.entries(query.entryScope, cursor: cursor, limit: Self.pageSize)
      guard epoch == generation else { return }
      let parsed = await EntryParser.parseAll(page.entries, server: endpoint.server, mediaOrigin: endpoint.mediaOrigin)
      guard epoch == generation, scopes[query].map({ $0.token == token }) ?? true else { return }
      entries = merge(entries, parsed, remotes: page.entries, endpoint: endpoint, since: since)
      order = Selectors.sortOrder(entries)
      update { scope in
        var seen = Set(scope.ids)
        for entry in page.entries where seen.insert(entry.id).inserted { scope.ids.append(entry.id) }
        scope.cursor = page.cursor
        scope.done = page.cursor == nil
        scope.loading = false
        scope.restored = false
        scope.pages.append(PageMark(count: scope.ids.count, cursor: page.cursor))
      }
      schedulePersist()
    } catch {
      guard epoch == generation else { return }
      let transient = error is CancellationError || (error as? APIError)?.isTransient == true
      if restored, !transient, scopes[query]?.token == token {
        // 本地快照里的游标可能已经失效（例如 Google Reader 的 continuation 过期）：这个列表从第一页重新读取。
        // 离线或服务暂时不可用时保留已有内容，只显示错误
        scopes[query] = nil
        return
      }
      update {
        $0.loading = false
        $0.error = errorMessage(error)
      }
    }
  }

  /// 同步。explicit 为用户主动刷新：重新读取正在显示的列表，新内容直接进入列表；
  /// 否则（回到前台等）只记下数量，由用户决定何时放进列表。
  /// 同步进行中再次要求显式同步时，等这次结束后再同步一次。
  public func sync(explicit: Bool) async {
    if let running = syncTask {
      // 正在进行的是切换前那个端点的同步：它的结果会被丢弃，结束后为当前端点再同步一次
      let stale = syncGeneration != generation
      if explicit { queuedExplicitSync = true }
      await running.value
      if explicit, queuedExplicitSync {
        queuedExplicitSync = false
        await sync(explicit: true)
      } else if stale, !explicit {
        await sync(explicit: false)
      }
      return
    }
    syncGeneration = generation
    // 在任务内部清空：等待中的调用方恢复时，看到的一定是“没有在同步”，不会再等一个已经结束的任务
    let task = Task { [weak self] in
      await self?.performSync(explicit: explicit)
      self?.syncTask = nil
    }
    syncTask = task
    await task.value
  }

  private func performSync(explicit: Bool) async {
    let epoch = generation
    sync.status = .syncing
    guard let endpoint else {
      sync.status = .idle
      return
    }
    do {
      // 只等正在发送的那一批写入，免得读回发送前的旧状态；积压的改动由合并规则保护
      await waitForInFlightWrite(endpointID: endpoint.id)
      let since = queue.revision
      let queries = syncQueries(explicit: explicit)
      let provider = try provider(for: endpoint)
      async let pagesRequest = Self.firstPages(provider, queries)
      async let subscriptionsRequest = provider.subscriptions()
      async let unreadRequest = provider.unreadCounts()
      let pages = try await pagesRequest
      let subscriptions = try await subscriptionsRequest
      let counts = try await unreadRequest
      guard epoch == generation else { return }
      let remotes = pages.flatMap(\.entries)
      let parsed = await EntryParser.parseAll(remotes, server: endpoint.server, mediaOrigin: endpoint.mediaOrigin)
      guard epoch == generation else { return }
      var fresh: [ListQuery: ScopeState] = [:]
      for (query, page) in zip(queries, pages) { fresh[query] = freshScope(query, page) }
      let replace = explicit || !loaded
      var pendingIDs: [String] = []
      var nextPending: [ListQuery: ScopeState] = [:]
      if !replace {
        // 后台同步：新文章只计数，点“有新图集”时再换上这一页
        var seen = Set<String>()
        for (query, scope) in fresh.sorted(by: { $0.key.storageKey < $1.key.storageKey }) {
          let known = Set(scopes[query]?.ids ?? [])
          for id in scope.ids where !known.contains(id) && seen.insert(id).inserted { pendingIDs.append(id) }
        }
        if !pendingIDs.isEmpty { nextPending = fresh }
      } else if let current = pending, current.generation == generation {
        // 显式同步只刷新了正在显示的列表：其他列表（例如另一个页签里的浏览页）待放入的新内容继续保留
        let remaining = current.scopes.filter { fresh[$0.key] == nil }
        if !remaining.isEmpty {
          nextPending = remaining
          pendingIDs = sync.pendingIDs
        }
      }
      pending = nextPending.isEmpty ? nil : (generation, nextPending)
      entries = merge(entries, parsed, remotes: remotes, endpoint: endpoint, since: since)
      order = Selectors.sortOrder(entries)
      folders = subscriptions.folders
      feeds = subscriptions.feeds
      unread = adjustedUnread(counts, endpointID: endpoint.id)
      if replace {
        for (query, scope) in fresh { scopes[query] = scope }
      }
      loaded = true
      sync = SyncState(lastSyncedAt: environment.now(), pendingIDs: pendingIDs)
      schedulePersist()
      if explicit { toasts.show("同步完成", tone: .success) }
    } catch {
      guard epoch == generation else { return }
      loaded = true
      sync.status = .idle
      sync.error = errorMessage(error)
      // 后台同步（回到前台等）失败只显示页面上的横幅，用户主动同步时才弹出提示
      if explicit { toasts.show("同步失败", detail: errorMessage(error), tone: .warning) }
    }
  }

  /// 同步时要刷新的列表：显式同步刷新正在显示的列表，后台同步只检查浏览页
  func syncQueries(explicit: Bool) -> [ListQuery] {
    guard loaded else { return [defaultQuery] }
    let feedIDs = Set(feeds.map(\.id))
    let folderIDs = Set(folders.map(\.id))
    let shown = mounted.keys
      .filter { ($0.feedId.map(feedIDs.contains) ?? true) && ($0.folderId.map(folderIDs.contains) ?? true) }
      .sorted { $0.storageKey < $1.storageKey }
    if explicit { return shown.isEmpty ? [defaultQuery] : shown }
    let browse = shown.filter { $0.feedId == nil && $0.status != .starred }
    return (browse.isEmpty ? [defaultQuery] : browse).filter { scopes[$0] != nil }
  }

  /// 把后台同步到的新内容放进列表
  public func applyPending() {
    if let pending, pending.generation == generation {
      for (query, scope) in pending.scopes { scopes[query] = scope }
    }
    pending = nil
    sync.pendingIDs = []
    listVersion += 1
    schedulePersist()
  }

  /// App 回到前台：距上次同步超过 30 秒就在后台同步，并继续发送积压的写入
  public func didBecomeActive() {
    retryWrites()
    guard endpoint != nil, loaded, syncTask == nil else { return }
    if environment.now().timeIntervalSince(sync.lastSyncedAt) >= Self.foregroundInterval {
      Task { await sync(explicit: false) }
    }
  }

  /// App 进入后台：立即写入本地快照
  public func didEnterBackground() {
    persistNow()
  }
}
