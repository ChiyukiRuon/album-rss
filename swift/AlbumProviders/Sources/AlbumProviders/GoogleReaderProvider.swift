import AlbumCore
import Foundation

private let readingList = "user/-/state/com.google/reading-list"
private let starredStream = "user/-/state/com.google/starred"
private let readState = "user/-/state/com.google/read"

/// 流 ID 放在路径里：保留分隔的斜杠，其余字符（如标签里的空格、中文、+）逐段编码
func streamPath(_ stream: String) -> String {
  stream.split(separator: "/", omittingEmptySubsequences: false).map { URIComponent.encode(String($0)) }
    .joined(separator: "/")
}

/// Google Reader 兼容协议（FreshRSS、Miniflux 的兼容接口等），使用 ClientLogin 换取的令牌
struct GoogleReaderProvider: RSSProvider {
  let transport: Transport
  let token: String

  private var headers: [String: String] { ["Authorization": "GoogleLogin auth=\(token)"] }

  private func get(_ path: String) async throws -> JSONValue {
    try await transport.json("/reader/api/0/\(path)", headers: headers)
  }

  func authenticate() async throws -> String {
    let data = try await get("subscription/list?output=json")
    guard data["subscriptions"]?.array != nil else { throw APIError("服务类型不匹配：未返回订阅列表") }
    return ""
  }

  func subscriptions() async throws -> Subscriptions {
    let data = try await get("subscription/list?output=json")
    guard let subscriptions = data["subscriptions"]?.array else {
      throw APIError("服务类型不匹配：未返回订阅列表")
    }
    // 同一分类在多个订阅里出现：位置取第一次出现，名称取最后一次（与 JS Map.set 相同）
    var folderOrder: [String] = []
    var folderTitles: [String: String] = [:]
    let feeds = subscriptions.map { item -> Feed in
      let categories = item["categories"]?.array ?? []
      for category in categories {
        let id = category["id"]?.text ?? ""
        if folderTitles[id] == nil { folderOrder.append(id) }
        folderTitles[id] = category["label"]?.string ?? ""
      }
      let title = item["title"]?.string ?? ""
      return Feed(
        id: item["id"]?.text ?? "",
        title: title,
        author: title,
        siteURL: httpURL(item["htmlUrl"]?.string ?? ""),
        iconURL: httpURL(item["iconUrl"]?.string ?? ""),
        folderIds: categories.map { $0["id"]?.text ?? "" },
        checkedAt: nil,
        parsingErrorCount: 0
      )
    }
    return Subscriptions(
      folders: folderOrder.map { Folder(id: $0, title: folderTitles[$0] ?? "") },
      feeds: feeds
    )
  }

  func unreadCounts() async throws -> [String: Int]? {
    try await optional {
      let data = try await get("unread-count?output=json")
      guard let items = data["unreadcounts"]?.array else { return nil }
      var counts: [String: Int] = [:]
      for item in items {
        if let id = item["id"]?.string, id.hasPrefix("feed/") {
          counts[id] = Int(item["count"]?.numberOrZero ?? 0)
        }
      }
      return counts
    }
  }

  func entries(_ scope: EntryScope, cursor: String?, limit: Int) async throws -> EntryPage {
    let stream = scope.feedId ?? scope.folderId ?? (scope.starred ? starredStream : readingList)
    var params: [(String, String)] = [("output", "json"), ("n", String(limit))]
    if scope.unread { params.append(("xt", readState)) }
    if let cursor { params.append(("c", cursor)) }
    let page = try await get("stream/contents/\(streamPath(stream))?\(FormEncoding.encode(params))")
    guard let items = page["items"]?.array else { throw APIError("服务未返回有效的文章列表") }
    let continuation = page["continuation"]?.text ?? ""
    let next = continuation.isEmpty ? nil : continuation
    if let next, next == cursor { throw APIError("服务未正确推进文章分页") }
    return EntryPage(entries: try items.map(entry), cursor: next)
  }

  func setRead(_ ids: [String], read: Bool) async throws {
    try await edit(ids, tag: "read", value: read)
  }

  func setStarred(_ id: String, starred: Bool) async throws {
    try await edit([id], tag: "starred", value: starred)
  }

  /// 写入期望状态（a 添加、r 移除），每次先取新的写入令牌
  private func edit(_ ids: [String], tag: String, value: Bool) async throws {
    let csrf = try await transport.text("/reader/api/0/token", headers: headers)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if csrf.isEmpty || csrf.hasPrefix("<") { throw APIError("服务未返回有效的写入令牌") }
    var formHeaders = headers
    formHeaders["Content-Type"] = "application/x-www-form-urlencoded;charset=UTF-8"
    for offset in stride(from: 0, to: ids.count, by: 100) {
      var body: [(String, String)] = [("T", csrf), (value ? "a" : "r", "user/-/state/com.google/\(tag)")]
      for id in ids[offset..<min(ids.count, offset + 100)] { body.append(("i", id)) }
      let reply = try await transport.text(
        "/reader/api/0/edit-tag",
        method: "POST",
        headers: formHeaders,
        body: Data(FormEncoding.encode(body).utf8)
      )
      if reply.trimmingCharacters(in: .whitespacesAndNewlines) != "OK" {
        throw APIError("服务没有确认状态写入成功")
      }
    }
  }

  private func entry(_ value: JSONValue) throws -> RemoteEntry {
    guard let id = value["id"]?.string else { throw APIError("服务返回了不安全的 Google Reader ID") }
    let categories = (value["categories"]?.array ?? []).compactMap(\.string)
    let link = value["canonical"]?.array?.first?["href"]?.string ?? value["alternate"]?.array?.first?["href"]?.string
    return RemoteEntry(
      id: id,
      feedId: value["origin"]?["streamId"]?.string ?? "",
      title: value["title"]?.string ?? "",
      author: value["author"]?.string ?? "",
      url: httpURL(link ?? ""),
      publishedAt: Date(timeIntervalSince1970: value["published"]?.numberOrZero ?? 0),
      content: value["content"]?["content"]?.string ?? value["summary"]?["content"]?.string ?? "",
      enclosures: (value["enclosure"]?.array ?? []).map {
        Enclosure(url: $0["href"]?.string ?? "", mimeType: $0["type"]?.string ?? "")
      },
      tags: categories.filter { $0.contains("/label/") }.map { category in
        category.components(separatedBy: "/label/").dropFirst().first ?? category
      },
      read: categories.contains { $0.hasSuffix("/state/com.google/read") },
      starred: categories.contains { $0.hasSuffix("/state/com.google/starred") }
    )
  }
}

/// 用用户名和密码换取 Google Reader 访问令牌；密码只用于这一次请求
public func loginGoogleReader(
  server: String,
  username: String,
  password: String,
  client: any HTTPClient = URLSessionHTTPClient()
) async throws -> String {
  let transport = Transport(server: try normalizeServer(server), client: client, gate: RequestGate())
  let text = try await transport.text(
    "/accounts/ClientLogin",
    method: "POST",
    headers: ["Content-Type": "application/x-www-form-urlencoded;charset=UTF-8"],
    body: Data(FormEncoding.encode([("Email", username), ("Passwd", password)]).utf8)
  )
  for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("Auth=") {
    let token = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
    if !token.isEmpty { return token }
  }
  throw APIError("登录失败：服务未返回 Google Reader 访问令牌")
}

/// 创建适配器。同一端点的请求共用一个队列
public func makeProvider(
  service: ServiceKind,
  server: String,
  token: String,
  client: any HTTPClient = URLSessionHTTPClient(),
  gate: RequestGate = RequestGate()
) throws -> any RSSProvider {
  let transport = Transport(server: try normalizeServer(server), client: client, gate: gate)
  switch service {
  case .miniflux: return MinifluxProvider(transport: transport, token: token)
  case .greader: return GoogleReaderProvider(transport: transport, token: token)
  }
}
