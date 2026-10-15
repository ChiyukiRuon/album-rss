import AlbumCore
import Foundation

/// Miniflux 原生 REST API，使用 API 密钥（X-Auth-Token）
struct MinifluxProvider: RSSProvider {
  let transport: Transport
  let token: String

  private var headers: [String: String] { ["X-Auth-Token": token] }

  var supportsRefresh: Bool { true }

  private func get(_ path: String) async throws -> JSONValue {
    try await transport.json(path, headers: headers)
  }

  private func put(_ path: String, body: [String: Any]? = nil) async throws {
    var headers = headers
    var data: Data?
    if let body {
      headers["Content-Type"] = "application/json"
      data = try JSONSerialization.data(withJSONObject: body)
    }
    _ = try await transport.send(path, method: "PUT", headers: headers, body: data)
  }

  func authenticate() async throws -> String {
    let me = try await get("/v1/me")
    guard let username = me["username"]?.string else {
      throw APIError("服务类型不匹配：未返回 Miniflux 用户信息")
    }
    return username
  }

  func subscriptions() async throws -> Subscriptions {
    async let rawFeeds = get("/v1/feeds")
    async let rawCategories = get("/v1/categories")
    let feeds = try await rawFeeds.array ?? []
    let categories = try await rawCategories.array ?? []
    return Subscriptions(
      folders: categories.map { Folder(id: $0["id"]?.text ?? "", title: $0["title"]?.string ?? "") },
      feeds: feeds.map { feed in
        let title = feed["title"]?.string ?? ""
        let error = feed["parsing_error_message"]?.string ?? ""
        return Feed(
          id: feed["id"]?.text ?? "",
          title: title,
          author: title,
          siteURL: httpURL(feed["site_url"]?.string ?? ""),
          iconURL: "",
          folderIds: feed["category"]?["id"]?.text.map { [$0] } ?? [],
          checkedAt: parseTimestamp(feed["checked_at"]?.string),
          parsingErrorCount: Int(feed["parsing_error_count"]?.numberOrZero ?? 0),
          parsingError: error.isEmpty ? nil : error
        )
      }
    )
  }

  func unreadCounts() async throws -> [String: Int]? {
    try await optional {
      let counters = try await get("/v1/feeds/counters")
      guard counters.object != nil else { return nil }
      var counts: [String: Int] = [:]
      for (id, count) in counters["unreads"]?.object ?? [:] { counts[id] = Int(count.numberOrZero) }
      return counts
    }
  }

  func entries(_ scope: EntryScope, cursor: String?, limit: Int) async throws -> EntryPage {
    // 使用 ID 游标，避免翻页期间新增或读完的文章导致 offset 偏移
    var params: [(String, String)] = [("limit", String(limit)), ("order", "id"), ("direction", "desc")]
    if scope.unread {
      params.append(("status", "unread"))
    } else {
      params.append(("status", "read"))
      params.append(("status", "unread"))
    }
    if scope.starred { params.append(("starred", "true")) }
    if let cursor { params.append(("before_entry_id", cursor)) }
    let path: String
    if let feedId = scope.feedId {
      path = "/v1/feeds/\(try numericID(feedId))/entries"
    } else if let folderId = scope.folderId {
      path = "/v1/categories/\(try numericID(folderId))/entries"
    } else {
      path = "/v1/entries"
    }
    let page = try await get("\(path)?\(FormEncoding.encode(params))")
    let entries = try (page["entries"]?.array ?? []).map(entry)
    if entries.count < limit { return EntryPage(entries: entries, cursor: nil) }
    let next = entries.compactMap { Int64($0.id) }.min().map(String.init) ?? ""
    if let cursor, let nextValue = Int64(next), let cursorValue = Int64(cursor), nextValue >= cursorValue {
      throw APIError("服务未正确推进文章分页")
    }
    return EntryPage(entries: entries, cursor: next)
  }

  func setRead(_ ids: [String], read: Bool) async throws {
    for offset in stride(from: 0, to: ids.count, by: 250) {
      let batch = try ids[offset..<min(ids.count, offset + 250)].map(numericID)
      try await put("/v1/entries", body: ["entry_ids": batch, "status": read ? "read" : "unread"])
    }
  }

  func setStarred(_ id: String, starred: Bool) async throws {
    // 旧版 Miniflux 只有切换接口，先读取再写入期望状态，最后回读校验
    let number = try numericID(id)
    let current = try await get("/v1/entries/\(number)")
    if (current["starred"]?.bool ?? false) != starred {
      try await put("/v1/entries/\(number)/bookmark")
    }
    let verified = try await get("/v1/entries/\(number)")
    if (verified["starred"]?.bool ?? false) != starred {
      throw APIError("收藏状态校验失败，请同步后重试")
    }
  }

  func refreshFeed(_ id: String) async throws {
    try await put("/v1/feeds/\(try numericID(id))/refresh")
  }

  private func entry(_ value: JSONValue) throws -> RemoteEntry {
    RemoteEntry(
      id: String(try numericID(value["id"]?.text ?? "")),
      feedId: value["feed_id"]?.text ?? "",
      title: value["title"]?.string ?? "",
      author: value["author"]?.string ?? "",
      url: httpURL(value["url"]?.string ?? ""),
      publishedAt: parseTimestamp(value["published_at"]?.string) ?? Date(timeIntervalSince1970: 0),
      content: value["content"]?.string ?? "",
      enclosures: (value["enclosures"]?.array ?? []).map {
        Enclosure(url: $0["url"]?.string ?? "", mimeType: $0["mime_type"]?.string ?? "")
      },
      tags: [],
      read: value["status"]?.string == "read",
      starred: value["starred"]?.bool ?? false
    )
  }
}

/// Miniflux 的 ID 都是正整数，超出 JS 安全整数范围的一律拒绝（与 Web 端一致）
func numericID(_ id: String) throws -> Int64 {
  let maxSafe: Double = 9_007_199_254_740_991
  guard let value = Double(id.trimmingCharacters(in: .whitespaces)), value.rounded() == value, value > 0,
    value <= maxSafe
  else {
    throw APIError("服务返回了不支持的 ID")
  }
  return Int64(value)
}
