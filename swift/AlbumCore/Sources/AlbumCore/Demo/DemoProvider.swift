import Foundation

/// 演示数据的“服务”：在内存里按真实服务的方式分页、筛选和写入状态，
/// 文章以 HTML 正文返回，和真实服务走同一条解析、分页、写入路径。
public actor DemoProvider: RSSProvider {
  private var folders: [Folder]
  private var feeds: [Feed]
  /// 新的在前
  private var entries: [Entry]
  private var arrivals: [Entry]
  private var readingListRequests = 0
  private let latency: Duration

  public init(now: Date, latency: Duration = .milliseconds(350)) {
    let data = DemoContent.generate(now: now)
    folders = data.folders
    feeds = data.feeds
    entries = data.entries
    arrivals = data.arrivals
    self.latency = latency
  }

  public nonisolated var supportsRefresh: Bool { true }

  private func wait(_ duration: Duration? = nil) async {
    let duration = duration ?? latency
    if duration > .zero { try? await Task.sleep(for: duration) }
  }

  public func authenticate() async throws -> String {
    "demo"
  }

  public func subscriptions() async throws -> Subscriptions {
    await wait()
    return Subscriptions(folders: folders, feeds: feeds)
  }

  public func currentFeeds() -> [Feed] {
    feeds
  }

  public func unreadCounts() async throws -> [String: Int]? {
    var counts: [String: Int] = [:]
    for entry in entries where !entry.read { counts[entry.feedId, default: 0] += 1 }
    return counts
  }

  public func entries(_ scope: EntryScope, cursor: String?, limit: Int) async throws -> EntryPage {
    await wait()
    let readingList = scope.feedId == nil && scope.folderId == nil && !scope.starred
    if cursor == nil && readingList {
      // 第一次是初始加载；之后每次刷新“到”两篇新文章，用来演示同步与新内容提示
      readingListRequests += 1
      if readingListRequests > 1 && !arrivals.isEmpty {
        let now = Date()
        let fresh = arrivals.prefix(2).enumerated().map { index, entry -> Entry in
          var copy = entry
          copy.publishedAt = now.addingTimeInterval(-Double(index) * 90)
          return copy
        }
        arrivals.removeFirst(fresh.count)
        entries.insert(contentsOf: fresh, at: 0)
      }
    }
    let feedsInFolder = scope.folderId.map { folder in Set(feeds.filter { $0.folderIds.contains(folder) }.map(\.id)) }
    let matching = entries.filter { entry in
      if let feedId = scope.feedId, entry.feedId != feedId { return false }
      if let feedsInFolder, !feedsInFolder.contains(entry.feedId) { return false }
      if scope.unread && entry.read { return false }
      if scope.starred && !entry.starred { return false }
      return true
    }
    let offset = cursor.flatMap(Int.init) ?? 0
    let end = min(matching.count, offset + limit)
    let page = offset < end ? Array(matching[offset..<end]) : []
    return EntryPage(entries: page.map(Self.remote), cursor: end < matching.count ? String(end) : nil)
  }

  public func setRead(_ ids: [String], read: Bool) async throws {
    let targets = Set(ids)
    for index in entries.indices where targets.contains(entries[index].id) { entries[index].read = read }
  }

  public func setStarred(_ id: String, starred: Bool) async throws {
    for index in entries.indices where entries[index].id == id { entries[index].starred = starred }
  }

  public func refreshFeed(_ id: String) async throws {
    await wait(.milliseconds(1200))
    guard let index = feeds.firstIndex(where: { $0.id == id }) else { return }
    if let error = feeds[index].parsingError {
      feeds[index].parsingErrorCount += 1
      throw APIError(error)
    }
    feeds[index].checkedAt = Date()
  }

  /// 把演示文章写成 HTML 正文：段落和图片（少数图片带宽高，和真实订阅一样）
  static func remote(_ entry: Entry) -> RemoteEntry {
    var html = entry.paragraphs.map { "<p>\(escape($0))</p>" }.joined()
    for image in entry.images {
      var tag = "<img src=\"\(escape(image.url))\""
      if let width = image.width, let height = image.height { tag += " width=\"\(Int(width))\" height=\"\(Int(height))\"" }
      html += tag + ">"
    }
    return RemoteEntry(
      id: entry.id,
      feedId: entry.feedId,
      title: entry.title,
      author: entry.author,
      url: entry.url,
      publishedAt: entry.publishedAt,
      content: html,
      tags: entry.tags,
      read: entry.read,
      starred: entry.starred
    )
  }

  private static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
