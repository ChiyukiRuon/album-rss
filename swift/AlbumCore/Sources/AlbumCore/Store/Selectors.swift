import Foundation

/// 列表筛选与计数规则，与 Web 端 `prototype/selectors.ts` 一致
public enum Selectors {
  /// 文章是否出现在这个列表里
  public static func isVisible(_ entry: Entry?, in query: ListQuery, showImageless: Bool) -> Bool {
    guard let entry else { return false }
    if query.status == .unread && entry.read { return false }
    if query.status == .starred && !entry.starred { return false }
    return entry.hasImages || showImageless
  }

  /// 订阅所属的分类名，来自 RSS 服务（Miniflux 每个订阅一个分类；Google Reader 可能有多个标签）。
  /// 账号里不到两个分类时（例如全部在 Miniflux 默认的 All 里）不显示，和分类筛选的规则一致。
  public static func categoryLabel(_ folderIds: [String], folders: [Folder]) -> String? {
    guard folders.count >= 2 else { return nil }
    let names = folderIds.compactMap { id in folders.first { $0.id == id }?.title }
    return names.isEmpty ? nil : names.joined(separator: "、")
  }

  public struct UnreadCounts: Equatable, Sendable {
    public var total: Int
    public var byFeed: [String: Int]
    public var byFolder: [String: Int]

    public init(total: Int = 0, byFeed: [String: Int] = [:], byFolder: [String: Int] = [:]) {
      self.total = total
      self.byFeed = byFeed
      self.byFolder = byFolder
    }
  }

  /// 未读计数。服务提供计数接口时用服务端的数字（按文章计，未加载的文章也算在内），
  /// 否则按已读取的文章统计，并和列表一样遵循“是否显示无图文章”的设置。
  public static func unreadCounts(
    entries: [String: Entry],
    feeds: [Feed],
    serverCounts: [String: Int]?,
    showImageless: Bool
  ) -> UnreadCounts {
    var byFeed = serverCounts ?? [:]
    if serverCounts == nil {
      for entry in entries.values where !entry.read && (entry.hasImages || showImageless) {
        byFeed[entry.feedId, default: 0] += 1
      }
    }
    var total = 0
    var byFolder: [String: Int] = [:]
    for feed in feeds {
      let count = byFeed[feed.id] ?? 0
      total += count
      for folderId in feed.folderIds { byFolder[folderId, default: 0] += count }
    }
    return UnreadCounts(total: total, byFeed: byFeed, byFolder: byFolder)
  }

  /// 文章顺序：新的在前；发布时间相同时按 ID 倒序，数字 ID 按数值比较
  public static func sortOrder(_ entries: [String: Entry]) -> [String] {
    entries.values.sorted(by: isNewer).map(\.id)
  }

  public static func isNewer(_ a: Entry, _ b: Entry) -> Bool {
    if a.publishedAt != b.publishedAt { return a.publishedAt > b.publishedAt }
    if let x = Int64(a.id), let y = Int64(b.id) { return x > y }
    return a.id > b.id
  }
}
