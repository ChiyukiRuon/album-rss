import AlbumCore
import Foundation
import Synchronization
import Testing

@testable import AlbumProviders

/// 假的 HTTP：记录每个请求，由测试决定响应
final class StubHTTP: HTTPClient {
  typealias Handler = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
  private let handler: Handler
  private let log = Mutex<[URLRequest]>([])

  init(_ handler: @escaping Handler) {
    self.handler = handler
  }

  var requests: [URLRequest] { log.withLock { $0 } }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    log.withLock { $0.append(request) }
    return try await handler(request)
  }
}

func respond(
  _ request: URLRequest,
  json: Any? = nil,
  text: String? = nil,
  status: Int = 200,
  headers: [String: String] = [:]
) -> (Data, HTTPURLResponse) {
  let data: Data
  if let json { data = try! JSONSerialization.data(withJSONObject: json, options: [.fragmentsAllowed]) } else {
    data = Data((text ?? "").utf8)
  }
  let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
  return (data, response)
}

func entry(_ id: Int, starred: Bool = false) -> [String: Any] {
  [
    "id": id, "feed_id": 1, "title": "Album", "author": "Artist", "url": "https://example.com/post",
    "content": "<img src=\"/cover.jpg\">", "published_at": "2026-10-15T00:00:00Z", "status": "unread",
    "starred": starred,
  ]
}

extension URLRequest {
  var path: String { url?.path(percentEncoded: true) ?? "" }
  var query: [(String, String)] { FormEncoding.decode(url?.query(percentEncoded: true) ?? "") }
  func params(_ name: String) -> [String] { query.filter { $0.0 == name }.map(\.1) }
  var bodyText: String { httpBody.map { String(decoding: $0, as: UTF8.self) } ?? "" }
}

/// 测试里不等待请求间隔
func fastGate() -> RequestGate { RequestGate(interval: .zero) }

@Suite struct MinifluxTests {
  @Test func preservesSubpathsAndPagesWithAnIDCursor() async throws {
    let http = StubHTTP { request in
      #expect(request.value(forHTTPHeaderField: "X-Auth-Token") == "secret")
      #expect(request.httpShouldHandleCookies == false)
      let path = request.path
      if path.hasSuffix("/me") { return respond(request, json: ["username": "reader"]) }
      if path.hasSuffix("/feeds") {
        return respond(request, json: [["id": 1, "title": "Photos", "site_url": "https://example.com", "category": ["id": 2]]])
      }
      if path.hasSuffix("/categories") { return respond(request, json: [["id": 2, "title": "Art"]]) }
      let before = request.params("before_entry_id").first
      let entries = before == nil ? [entry(3), entry(2)] : before == "2" ? [entry(1)] : []
      return respond(request, json: ["entries": entries])
    }
    let provider = try makeProvider(
      service: .miniflux, server: "https://rss.example.com/rss/", token: "secret", client: http, gate: fastGate())
    #expect(try await provider.authenticate() == "reader")
    let subscriptions = try await provider.subscriptions()
    #expect(subscriptions.feeds.first?.folderIds == ["2"])
    #expect(subscriptions.folders == [Folder(id: "2", title: "Art")])
    let first = try await provider.entries(EntryScope(), cursor: nil, limit: 2)
    #expect(first.entries.map(\.id) == ["3", "2"])
    #expect(first.cursor == "2")
    let last = try await provider.entries(EntryScope(), cursor: first.cursor, limit: 2)
    #expect(last.entries.map(\.id) == ["1"])
    #expect(last.cursor == nil)
    let pages = http.requests.filter { $0.path.hasSuffix("/v1/entries") }
    #expect(pages.count == 2)
    #expect(pages[0].params("status") == ["read", "unread"])
    #expect(pages[0].params("limit") == ["2"])
    #expect(http.requests.allSatisfy { $0.url!.absoluteString.hasPrefix("https://rss.example.com/rss/v1/") })
  }

  @Test func mapsScopesToFeedCategoryUnreadAndStarredQueries() async throws {
    let http = StubHTTP { respond($0, json: ["entries": []]) }
    let provider = try makeProvider(service: .miniflux, server: "https://example.com", token: "secret", client: http, gate: fastGate())
    _ = try await provider.entries(EntryScope(feedId: "7", unread: true), cursor: nil, limit: 100)
    _ = try await provider.entries(EntryScope(folderId: "3"), cursor: "50", limit: 100)
    _ = try await provider.entries(EntryScope(starred: true), cursor: nil, limit: 100)
    let requests = http.requests
    #expect(requests.map(\.path) == ["/v1/feeds/7/entries", "/v1/categories/3/entries", "/v1/entries"])
    #expect(requests[0].params("status") == ["unread"])
    #expect(requests[1].params("before_entry_id") == ["50"])
    #expect(requests[2].params("starred") == ["true"])
  }

  @Test func readsUnreadCountersAndTreatsAMissingEndpointAsUnsupported() async throws {
    func provider(_ status: Int) throws -> any RSSProvider {
      let http = StubHTTP { request in
        status == 200
          ? respond(request, json: ["reads": ["1": 4], "unreads": ["1": 2, "5": 9]])
          : respond(request, status: status)
      }
      return try makeProvider(service: .miniflux, server: "https://example.com", token: "t", client: http, gate: fastGate())
    }
    #expect(try await provider(200).unreadCounts() == ["1": 2, "5": 9])
    #expect(try await provider(404).unreadCounts() == nil)
    await #expect(throws: APIError("凭据无效或已过期，请编辑这个端点后重新连接", status: 401)) {
      try await provider(401).unreadCounts()
    }
  }

  @Test func writesReadStateInBulkAndMakesBookmarkingIdempotent() async throws {
    let starred = Mutex(false)
    let http = StubHTTP { request in
      if request.httpMethod == "PUT" {
        if request.path.hasSuffix("/bookmark") { starred.withLock { $0.toggle() } }
        return respond(request, status: 204)
      }
      return respond(request, json: entry(1, starred: starred.withLock { $0 }))
    }
    let provider = try makeProvider(service: .miniflux, server: "https://example.com", token: "t", client: http, gate: fastGate())
    try await provider.setRead(["1", "2"], read: true)
    try await provider.setStarred("1", starred: true)
    try await provider.setStarred("1", starred: true)
    let writes = http.requests.filter { $0.httpMethod == "PUT" }
    #expect(writes.map { $0.url!.absoluteString } == ["https://example.com/v1/entries", "https://example.com/v1/entries/1/bookmark"])
    let body = try JSONSerialization.jsonObject(with: writes[0].httpBody!) as! [String: Any]
    #expect(body["entry_ids"] as? [Int] == [1, 2])
    #expect(body["status"] as? String == "read")
    #expect(writes[1].httpBody == nil)
  }

  @Test func batchesReadWritesBy250() async throws {
    let http = StubHTTP { respond($0, status: 204) }
    let provider = try makeProvider(service: .miniflux, server: "https://example.com", token: "t", client: http, gate: fastGate())
    try await provider.setRead((1...501).map(String.init), read: false)
    #expect(http.requests.count == 3)
  }

  @Test func reportsAuthenticationErrorsWithoutTheResponseBody() async throws {
    let http = StubHTTP { respond($0, text: "private data", status: 401) }
    let provider = try makeProvider(service: .miniflux, server: "https://example.com", token: "t", client: http, gate: fastGate())
    do {
      _ = try await provider.authenticate()
      Issue.record("should fail")
    } catch let error as APIError {
      #expect(error.status == 401)
      #expect(error.isUnauthorized)
      #expect(!error.message.contains("private data"))
    }
  }

  @Test func stopsIfTheServiceRepeatsAPage() async throws {
    let http = StubHTTP { respond($0, json: ["entries": [entry(2), entry(1)]]) }
    let provider = try makeProvider(service: .miniflux, server: "https://example.com", token: "t", client: http, gate: fastGate())
    let first = try await provider.entries(EntryScope(), cursor: nil, limit: 2)
    await #expect(throws: APIError("服务未正确推进文章分页")) {
      try await provider.entries(EntryScope(), cursor: first.cursor, limit: 2)
    }
  }

  @Test func refusesRedirectsWithAClearMessage() async throws {
    let http = StubHTTP { respond($0, status: 302, headers: ["Location": "https://elsewhere.example.com/"]) }
    let provider = try makeProvider(service: .miniflux, server: "http://example.com", token: "t", client: http, gate: fastGate())
    await #expect(throws: APIError("服务地址发生了重定向（HTTP 302），请填写重定向后的完整地址", status: 302)) {
      try await provider.authenticate()
    }
  }

  @Test func networkFailuresAreMarkedRetryable() async throws {
    let http = StubHTTP { _ in throw URLError(.notConnectedToInternet) }
    let provider = try makeProvider(service: .miniflux, server: "https://example.com", token: "t", client: http, gate: fastGate())
    do {
      _ = try await provider.authenticate()
      Issue.record("should fail")
    } catch let error as APIError {
      #expect(error.isNetwork)
      #expect(error.isTransient)
    }
  }

  @Test func parsesMinifluxTimestamps() throws {
    let expected = Date(timeIntervalSince1970: 1_760_486_400)  // 2025-10-15T00:00:00Z
    #expect(parseTimestamp("2025-10-15T00:00:00Z") == expected)
    #expect(parseTimestamp("2025-10-15T08:00:00+08:00") == expected)
    let fractional = try #require(parseTimestamp("2025-10-15T00:00:00.123456789Z"))
    #expect(abs(fractional.timeIntervalSince(expected) - 0.123) < 0.0005)
    #expect(parseTimestamp("0001-01-01T00:00:00Z") == Date(timeIntervalSince1970: -62_135_596_800))
    #expect(parseTimestamp("not a date") == nil)
  }
}

@Suite struct RateLimitTests {
  @Test func backsOffOn429UsingRetryAfterAndPausesTheWholeQueue() async throws {
    let calls = Mutex(0)
    let starts = Mutex<[ContinuousClock.Instant]>([])
    let http = StubHTTP { request in
      starts.withLock { $0.append(ContinuousClock.now) }
      if request.path.hasSuffix("/me"), calls.withLock({ (value: inout Int) -> Int in value += 1; return value }) == 1 {
        return respond(request, status: 429, headers: ["Retry-After": "1"])
      }
      return respond(request, json: request.path.hasSuffix("/me") ? ["username": "reader"] : [])
    }
    let provider = try makeProvider(service: .miniflux, server: "https://example.com", token: "t", client: http, gate: fastGate())
    async let auth = provider.authenticate()
    try await Task.sleep(for: .milliseconds(50))
    async let feeds = provider.subscriptions()
    #expect(try await auth == "reader")
    _ = try await feeds
    let times = starts.withLock { $0 }
    #expect(times.count == 4)
    #expect(times.dropFirst().allSatisfy { $0 - times[0] >= .milliseconds(950) })
  }

  @Test func givesUpWhenTheServiceAsksToWaitTooLong() async throws {
    let http = StubHTTP { respond($0, status: 429, headers: ["Retry-After": "120"]) }
    let provider = try makeProvider(service: .miniflux, server: "https://example.com", token: "t", client: http, gate: fastGate())
    await #expect(throws: APIError("服务限制了请求频率，请约 120 秒后再试", status: 429)) {
      try await provider.authenticate()
    }
  }

  @Test func retryAfterAcceptsSecondsAndHTTPDates() {
    let url = URL(string: "https://example.com")!
    let now = Date(timeIntervalSince1970: 1_760_486_400)
    func delay(_ header: String?, attempt: Int = 0) -> TimeInterval {
      let response = HTTPURLResponse(
        url: url, statusCode: 429, httpVersion: nil, headerFields: header.map { ["Retry-After": $0] } ?? [:])!
      return retryDelay(response, attempt: attempt, now: now)
    }
    #expect(delay("3") == 3)
    #expect(delay("Wed, 15 Oct 2025 00:00:10 GMT") == 10)
    #expect(delay(nil, attempt: 2) == 4)
  }

  @Test func limitsConcurrencyAndSpacesOutRequestStarts() async throws {
    let gate = RequestGate(concurrency: 2, interval: .milliseconds(60))
    let state = Mutex((active: 0, peak: 0, starts: [ContinuousClock.Instant]()))
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<4 {
        group.addTask {
          try await gate.run {
            state.withLock {
              $0.active += 1
              $0.peak = max($0.peak, $0.active)
              $0.starts.append(ContinuousClock.now)
            }
            try await Task.sleep(for: .milliseconds(200))
            state.withLock { $0.active -= 1 }
          }
        }
      }
      try await group.waitForAll()
    }
    let result = state.withLock { $0 }
    #expect(result.peak == 2)
    let starts = result.starts.sorted()
    for i in 1..<starts.count { #expect(starts[i] - starts[i - 1] >= .milliseconds(55)) }
  }
}

@Suite struct GoogleReaderTests {
  @Test func exchangesAPasswordForATokenWithFormEncoding() async throws {
    let http = StubHTTP { request in
      #expect(request.url!.absoluteString == "https://example.com/api/greader.php/accounts/ClientLogin")
      #expect(request.bodyText == "Email=user&Passwd=p%26ss")
      return respond(request, text: "SID=x\nAuth=access-token\n")
    }
    let token = try await loginGoogleReader(
      server: "https://example.com/api/greader.php/", username: "user", password: "p&ss", client: http)
    #expect(token == "access-token")
  }

  @Test func preserves64BitStringIDsAndFollowsContinuations() async throws {
    let id = "tag:google.com,2005:reader/item/ffffffffffffffff"
    let http = StubHTTP { request in
      if !request.params("c").isEmpty { return respond(request, json: ["items": []]) }
      return respond(
        request,
        json: [
          "continuation": "next+/=",
          "items": [
            [
              "id": id, "origin": ["streamId": "feed/1"], "categories": ["user/1/state/com.google/starred"],
              "summary": ["content": "<p>Photo</p>"],
            ]
          ],
        ])
    }
    let provider = try makeProvider(service: .greader, server: "https://example.com", token: "token", client: http, gate: fastGate())
    let first = try await provider.entries(EntryScope(), cursor: nil, limit: 100)
    #expect(first.entries.first?.id == id)
    #expect(first.entries.first?.feedId == "feed/1")
    #expect(first.entries.first?.starred == true)
    #expect(first.cursor == "next+/=")
    let second = try await provider.entries(EntryScope(), cursor: first.cursor, limit: 100)
    #expect(second == EntryPage(entries: [], cursor: nil))
    // + 与 / 必须编码，否则服务会把 + 读成空格
    #expect(http.requests[1].url!.absoluteString.contains("c=next%2B%2F%3D"))
    #expect(http.requests[1].params("c") == ["next+/="])
  }

  @Test func readsFeedsLabelsStarredAndUnreadFromTheirOwnStreams() async throws {
    let http = StubHTTP { respond($0, json: ["items": []]) }
    let provider = try makeProvider(
      service: .greader, server: "https://example.com/api/greader.php", token: "token", client: http, gate: fastGate())
    _ = try await provider.entries(EntryScope(feedId: "feed/1", unread: true), cursor: nil, limit: 50)
    _ = try await provider.entries(EntryScope(folderId: "user/-/label/插画 Art"), cursor: "c1", limit: 50)
    _ = try await provider.entries(EntryScope(starred: true), cursor: nil, limit: 50)
    let requests = http.requests
    #expect(requests.map { $0.url!.path(percentEncoded: false) } == [
      "/api/greader.php/reader/api/0/stream/contents/feed/1",
      "/api/greader.php/reader/api/0/stream/contents/user/-/label/插画 Art",
      "/api/greader.php/reader/api/0/stream/contents/user/-/state/com.google/starred",
    ])
    #expect(requests[0].params("xt") == ["user/-/state/com.google/read"])
    #expect(requests[1].params("c") == ["c1"])
    #expect(requests[2].params("n") == ["50"])
  }

  @Test func readsPerFeedUnreadCountsAndToleratesServicesWithoutThem() async throws {
    func provider(_ body: Any?, status: Int = 200) throws -> any RSSProvider {
      let text = body.map { String(decoding: try! JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
      let http = StubHTTP { request in
        status == 200 ? respond(request, text: text) : respond(request, status: status)
      }
      return try makeProvider(service: .greader, server: "https://example.com", token: "t", client: http, gate: fastGate())
    }
    let counts = try await provider([
      "unreadcounts": [
        ["id": "feed/1", "count": 3], ["id": "user/-/label/Art", "count": 3],
        ["id": "user/-/state/com.google/reading-list", "count": 3],
      ]
    ]).unreadCounts()
    #expect(counts == ["feed/1": 3])
    #expect(try await provider(nil, status: 404).unreadCounts() == nil)
  }

  @Test func writesDesiredStateTagsWithAFreshWriteToken() async throws {
    let http = StubHTTP { request in
      if request.path.hasSuffix("/token") { return respond(request, text: "csrf") }
      let body = FormEncoding.decode(request.bodyText)
      #expect(body.first { $0.0 == "T" }?.1 == "csrf")
      #expect(body.first { $0.0 == "r" }?.1 == "user/-/state/com.google/starred")
      #expect(body.first { $0.0 == "i" }?.1 == "tag:google.com,2005:reader/item/ffffffffffffffff")
      return respond(request, text: "OK")
    }
    let provider = try makeProvider(service: .greader, server: "https://example.com", token: "token", client: http, gate: fastGate())
    try await provider.setStarred("tag:google.com,2005:reader/item/ffffffffffffffff", starred: false)
    #expect(http.requests.count == 2)
  }

  @Test func foldersKeepFirstPositionAndLastLabel() async throws {
    let http = StubHTTP { request in
      respond(
        request,
        json: [
          "subscriptions": [
            ["id": "feed/1", "title": "A", "categories": [["id": "user/-/label/x", "label": "Old"]]],
            ["id": "feed/2", "title": "B", "categories": [["id": "user/-/label/y", "label": "Y"], ["id": "user/-/label/x", "label": "New"]]],
          ]
        ])
    }
    let provider = try makeProvider(service: .greader, server: "https://example.com", token: "t", client: http, gate: fastGate())
    let subscriptions = try await provider.subscriptions()
    #expect(subscriptions.folders == [Folder(id: "user/-/label/x", title: "New"), Folder(id: "user/-/label/y", title: "Y")])
    #expect(subscriptions.feeds.map(\.folderIds) == [["user/-/label/x"], ["user/-/label/y", "user/-/label/x"]])
  }
}

@Suite struct ServerAddressTests {
  @Test func rejectsEmbeddedCredentialsAndUnsafeSchemes() throws {
    #expect(throws: APIError.self) { try normalizeServer("https://user:password@example.com") }
    #expect(throws: APIError.self) { try normalizeServer("javascript:alert(1)") }
    #expect(try normalizeServer("https://example.com/rss/?q=1#hash") == "https://example.com/rss")
    #expect(try normalizeServer(" http://LOCALHOST:8880/ ") == "http://localhost:8880")
  }

  @Test func formAndComponentEncodingMatchJavaScript() {
    #expect(FormEncoding.escape("a b+c/d=e&f*-._~") == "a+b%2Bc%2Fd%3De%26f*-._%7E")
    #expect(URIComponent.encode("插画 Art!~*'()") == "%E6%8F%92%E7%94%BB%20Art!~*'()")
    #expect(streamPath("user/-/label/插画 Art") == "user/-/label/%E6%8F%92%E7%94%BB%20Art")
  }
}
