import Foundation

extension AlbumStore {
  /// 批量标为已读，并提供撤销
  public func markAllRead(_ ids: [String], scopeLabel: String) {
    let targets = ids.filter { entries[$0].map { !$0.read } ?? false }
    guard !targets.isEmpty else { return }
    setRead(targets, true)
    toasts.show(
      "已将\(scopeLabel)的 \(targets.count) 个图集标为已读",
      tone: .success,
      action: ToastCenter.Action(label: "撤销") { [weak self] in self?.setRead(targets, false) }
    )
  }

  /// 订阅的全部未读：先向服务端取齐未读文章（含还没加载的），再标为已读，可撤销
  public func markFeedRead(_ feed: Feed) async {
    guard let endpoint else { return }
    let label = "「\(feed.author)」"
    let epoch = generation
    do {
      let provider = try provider(for: endpoint)
      var ids: [String] = []
      var cursor: String?
      repeat {
        let since = queue.revision
        let page = try await provider.entries(EntryScope(feedId: feed.id, unread: true), cursor: cursor, limit: 500)
        guard epoch == generation else { return }
        let parsed = await EntryParser.parseAll(page.entries, server: endpoint.server, mediaOrigin: endpoint.mediaOrigin)
        guard epoch == generation else { return }
        entries = merge(entries, parsed, remotes: page.entries, endpoint: endpoint, since: since)
        order = Selectors.sortOrder(entries)
        ids += page.entries.map(\.id)
        cursor = page.cursor
      } while cursor != nil
      if ids.isEmpty {
        toasts.show("\(label)没有未读的图集", tone: .success)
      } else {
        markAllRead(ids, scopeLabel: label)
      }
    } catch {
      if epoch == generation { toasts.show("标为已读失败", detail: errorMessage(error), tone: .warning) }
    }
  }

  /// 请求服务立即抓取订阅（Miniflux 与演示数据支持），完成后同步
  public func refreshFeed(_ feedID: String) async {
    guard let endpoint, !refreshingFeeds.contains(feedID) else { return }
    let epoch = generation
    refreshingFeeds.insert(feedID)
    defer { if epoch == generation { refreshingFeeds.remove(feedID) } }
    do {
      let provider = try provider(for: endpoint)
      guard provider.supportsRefresh else { throw APIError("当前服务不支持手动抓取，请在 RSS 服务中刷新后同步") }
      try await provider.refreshFeed(feedID)
      guard epoch == generation else { return }
      toasts.show(
        endpoint.isDemo ? "已刷新订阅" : "已提交抓取请求，服务完成抓取后请再次同步",
        tone: .success
      )
      await sync(explicit: true)
    } catch {
      guard epoch == generation else { return }
      if endpoint.isDemo, let demoProvider {
        // 演示里的抓取错误会累加到订阅上，让页面看到新的错误次数
        let updated = await demoProvider.currentFeeds()
        guard epoch == generation else { return }
        feeds = updated
      }
      toasts.show("刷新失败", detail: errorMessage(error), tone: .warning)
    }
  }

  public var canRefreshFeeds: Bool {
    guard let endpoint else { return false }
    return endpoint.isDemo || endpoint.service == .miniflux
  }

  /// 保存到相册。全部成功后按设置把图集标为已读；失败时给出原因和备用操作（默认打开原图）
  public func download(key: String, entry: Entry, images: [ImageAsset], fallback: ToastCenter.Action? = nil) async {
    guard let endpoint, downloads[key]?.status != .running, !images.isEmpty else { return }
    let epoch = generation
    let total = images.count
    func setState(_ state: DownloadState?) {
      guard epoch == generation else { return }
      downloads[key] = state
    }
    func clearLater(_ delay: Duration) {
      Task { [weak self, sleep = environment.sleep] in
        try? await sleep(delay)
        guard let self, epoch == self.generation else { return }
        self.downloads[key] = nil
      }
    }
    setState(DownloadState(status: .running, done: 0, total: total))
    if endpoint.isDemo {
      // 演示数据不写入相册，只演示进度与结果
      for done in 1...total {
        try? await environment.sleep(.milliseconds(Int.random(in: 220...480)))
        guard epoch == generation else { return }
        setState(DownloadState(status: done == total ? .done : .running, done: done, total: total))
      }
      if settings.downloadRead { setRead([entry.id], true) }
      toasts.show(total > 1 ? "已保存 \(total) 张图片" : "已保存图片", detail: "演示数据，没有写入相册。", tone: .success)
      clearLater(.milliseconds(2600))
      return
    }
    let counter = ProgressCounter()
    do {
      try await environment.imageSaver.save(images, endpoint: endpoint) { [weak self] done in
        counter.set(done)
        Task { @MainActor [weak self] in
          guard let self, epoch == self.generation, self.downloads[key]?.status == .running else { return }
          self.downloads[key] = DownloadState(status: done == total ? .done : .running, done: done, total: total)
        }
      }
      guard epoch == generation else { return }
      setState(DownloadState(status: .done, done: total, total: total))
      if settings.downloadRead { setRead([entry.id], true) }
      toasts.show(total > 1 ? "已保存 \(total) 张图片到相册" : "已保存到相册", tone: .success)
    } catch {
      guard epoch == generation else { return }
      let done = counter.value
      setState(DownloadState(status: .blocked, done: done, total: total))
      toasts.show(
        done > 0 ? "已保存 \(done) 张，其余图片没能保存" : "图片没能保存",
        detail: errorMessage(error),
        tone: .warning,
        action: fallback
      )
    }
    clearLater(.seconds(4))
  }

  /// 演示：恢复初始的已读、收藏状态和设置
  public func resetDemo() {
    environment.defaults.setData(nil, forKey: Self.settingsKey)
    settings = Settings()
    if endpoint?.isDemo == true { enterDemo() }
  }
}

/// 保存进度：在后台线程更新，失败时读取已完成的张数
private final class ProgressCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var done = 0

  var value: Int { lock.withLock { done } }

  func set(_ value: Int) {
    lock.withLock { done = max(done, value) }
  }
}
