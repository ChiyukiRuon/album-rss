import Foundation

/// 一个文章列表的筛选条件；也是列表在 store 里的键
public struct ListQuery: Hashable, Codable, Sendable {
  public enum Status: String, Codable, Sendable {
    case unread
    case all
    case starred
  }

  public var status: Status
  public var feedId: String?
  public var folderId: String?

  public init(status: Status, feedId: String? = nil, folderId: String? = nil) {
    self.status = status
    self.feedId = feedId
    self.folderId = folderId
  }

  public init(listStatus status: ListStatus, feedId: String? = nil, folderId: String? = nil) {
    let mapped: Status = status == ListStatus.unread ? .unread : .all
    self.init(status: mapped, feedId: feedId, folderId: folderId)
  }

  public var entryScope: EntryScope {
    EntryScope(feedId: feedId, folderId: folderId, unread: status == .unread, starred: status == .starred)
  }

  /// 持久化用的稳定字符串，与 Web 端 scopeKey 的 JSON 形式相同
  public var storageKey: String {
    func json(_ value: String?) -> String {
      guard let value else { return "null" }
      let data = (try? JSONEncoder().encode(value)) ?? Data()
      return String(decoding: data, as: UTF8.self)
    }
    return "[\(json(status.rawValue)),\(json(feedId)),\(json(folderId))]"
  }

  public init?(storageKey: String) {
    guard
      let data = storageKey.data(using: .utf8),
      let parts = try? JSONDecoder().decode([String?].self, from: data),
      parts.count == 3,
      let raw = parts[0],
      let status = Status(rawValue: raw)
    else { return nil }
    self.init(status: status, feedId: parts[1], folderId: parts[2])
  }
}

/// 读完一页后的位置：持久化时按页截断，恢复后从这一页的游标继续读
public struct PageMark: Codable, Equatable, Sendable {
  public var count: Int
  public var cursor: String?

  public init(count: Int, cursor: String?) {
    self.count = count
    self.cursor = cursor
  }
}

/// 列表在服务端的分页进度
public struct ScopeState: Equatable, Sendable {
  public var query: ListQuery
  /// 按服务端顺序读到的文章，只会在末尾追加
  public var ids: [String]
  public var cursor: String?
  /// 服务端已经没有更早的文章
  public var done: Bool
  public var loading: Bool
  public var error: String?
  /// 重新读取第一页时更换，迟到的旧页据此丢弃；列表快照也据此判断是否换了一份列表
  public var token: Int
  public var pages: [PageMark]
  /// 游标来自本地快照：翻页失败时回到第一页
  public var restored: Bool

  public init(
    query: ListQuery,
    ids: [String] = [],
    cursor: String? = nil,
    done: Bool = false,
    loading: Bool = false,
    error: String? = nil,
    token: Int,
    pages: [PageMark] = [],
    restored: Bool = false
  ) {
    self.query = query
    self.ids = ids
    self.cursor = cursor
    self.done = done
    self.loading = loading
    self.error = error
    self.token = token
    self.pages = pages
    self.restored = restored
  }
}

public enum DownloadStatus: String, Sendable {
  case running
  case done
  case blocked
}

public struct DownloadState: Equatable, Sendable {
  public var status: DownloadStatus
  public var done: Int
  public var total: Int

  public init(status: DownloadStatus, done: Int, total: Int) {
    self.status = status
    self.done = done
    self.total = total
  }
}
