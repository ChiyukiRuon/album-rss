import Foundation
import Testing

@testable import AlbumCore

/// 由测试控制何时完成的结果，用来构造请求之间的先后顺序
final class Deferred<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var result: Result<T, any Error>?
  private var waiters: [CheckedContinuation<T, any Error>] = []

  func value() async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      if let result {
        lock.unlock()
        continuation.resume(with: result)
      } else {
        waiters.append(continuation)
        lock.unlock()
      }
    }
  }

  func resolve(_ value: T) { finish(.success(value)) }
  func reject(_ error: any Error) { finish(.failure(error)) }

  private func finish(_ result: Result<T, any Error>) {
    lock.lock()
    self.result = result
    let waiting = waiters
    waiters = []
    lock.unlock()
    waiting.forEach { $0.resume(with: result) }
  }
}

struct TestError: Error, LocalizedError {
  var message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

/// 可编程的假服务：每个方法可以替换实现，并记录调用
final class MockProvider: RSSProvider, @unchecked Sendable {
  struct EntriesCall: Equatable {
    var scope: EntryScope
    var cursor: String?
    var limit: Int
  }

  private let lock = NSLock()
  private var _entriesCalls: [EntriesCall] = []
  private var _setReadCalls: [([String], Bool)] = []
  private var _setStarredCalls: [(String, Bool)] = []
  private var _counts: [String: Int] = [:]
  private var queued: [@Sendable (EntryScope, String?, Int) async throws -> EntryPage] = []

  var authenticateHandler: @Sendable () async throws -> String = { "reader" }
  var subscriptionsHandler: @Sendable () async throws -> Subscriptions = {
    Subscriptions(folders: [], feeds: [Feed(id: "2", title: "Photos", author: "Photos")])
  }
  var unreadHandler: @Sendable () async throws -> [String: Int]? = { ["2": 1] }
  var entriesHandler: @Sendable (EntryScope, String?, Int) async throws -> EntryPage = { _, _, _ in
    EntryPage(entries: [remote("1")], cursor: nil)
  }
  var setReadHandler: @Sendable ([String], Bool) async throws -> Void = { _, _ in }
  var setStarredHandler: @Sendable (String, Bool) async throws -> Void = { _, _ in }

  func count(_ name: String) -> Int { lock.withLock { _counts[name] ?? 0 } }
  var entriesCalls: [EntriesCall] { lock.withLock { _entriesCalls } }
  var setReadCalls: [([String], Bool)] { lock.withLock { _setReadCalls } }
  var setStarredCalls: [(String, Bool)] { lock.withLock { _setStarredCalls } }

  /// 下一次 entries 调用使用这个实现（之后恢复默认）
  func onceEntries(_ handler: @escaping @Sendable (EntryScope, String?, Int) async throws -> EntryPage) {
    lock.withLock { queued.append(handler) }
  }

  func reset() {
    lock.withLock {
      _counts = [:]
      _entriesCalls = []
      _setReadCalls = []
      _setStarredCalls = []
    }
  }

  private func record(_ name: String) {
    lock.withLock { _counts[name, default: 0] += 1 }
  }

  func authenticate() async throws -> String {
    record("authenticate")
    return try await authenticateHandler()
  }

  func subscriptions() async throws -> Subscriptions {
    record("subscriptions")
    return try await subscriptionsHandler()
  }

  func unreadCounts() async throws -> [String: Int]? {
    record("unreadCounts")
    return try await unreadHandler()
  }

  func entries(_ scope: EntryScope, cursor: String?, limit: Int) async throws -> EntryPage {
    let handler = lock.withLock { () -> (@Sendable (EntryScope, String?, Int) async throws -> EntryPage)? in
      _counts["entries", default: 0] += 1
      _entriesCalls.append(EntriesCall(scope: scope, cursor: cursor, limit: limit))
      return queued.isEmpty ? nil : queued.removeFirst()
    }
    return try await (handler ?? entriesHandler)(scope, cursor, limit)
  }

  func setRead(_ ids: [String], read: Bool) async throws {
    lock.withLock { _setReadCalls.append((ids, read)) }
    try await setReadHandler(ids, read)
  }

  func setStarred(_ id: String, starred: Bool) async throws {
    lock.withLock { _setStarredCalls.append((id, starred)) }
    try await setStarredHandler(id, starred)
  }
}

func remote(_ id: String, read: Bool = false, starred: Bool = false) -> RemoteEntry {
  RemoteEntry(
    id: id, feedId: "2", title: "Article", url: "https://example.com/post",
    publishedAt: Date(timeIntervalSince1970: Double(id) ?? 0), content: "<img src=\"/\(id).jpg\">",
    read: read, starred: starred)
}

func page(_ ids: [String], cursor: String? = nil) -> EntryPage {
  EntryPage(entries: ids.map { remote($0) }, cursor: cursor)
}

final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Date(timeIntervalSince1970: 1_760_486_400)
  var now: Date { lock.withLock { value } }
  func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
}

final class MockSaver: ImageSaver, @unchecked Sendable {
  private let lock = NSLock()
  var handler: @Sendable (ImageAsset) async throws -> Void = { _ in }
  private var _saved = 0
  var saved: Int { lock.withLock { _saved } }

  func save(_ images: [ImageAsset], endpoint: Endpoint, progress: @escaping @Sendable (Int) -> Void) async throws {
    for (index, image) in images.enumerated() {
      try await handler(image)
      lock.withLock { _saved += 1 }
      progress(index + 1)
    }
  }
}

/// 一套测试环境：同一个假服务、内存里的凭据与设置，可选数据库
struct Harness {
  let provider = MockProvider()
  let credentials = MemoryCredentialStore()
  let defaults = MemoryKeyValueStore()
  let clock = TestClock()
  let saver = MockSaver()
  var database: AlbumDatabase?

  var environment: StoreEnvironment {
    let provider = provider
    let clock = clock
    return StoreEnvironment(
      makeProvider: { _ in provider },
      login: { _, _, _ in "token" },
      credentials: credentials,
      defaults: defaults,
      database: database,
      imageSaver: saver,
      now: { clock.now },
      demoLatency: .zero
    )
  }

  @MainActor func makeStore() -> AlbumStore {
    AlbumStore(environment: environment)
  }
}

let input = ConnectInput(
  service: .miniflux,
  server: "https://example.com/rss/",
  username: "",
  remember: false,
  apiKey: "token",
  password: "never-persist-this"
)

func with(_ input: ConnectInput, _ change: (inout ConnectInput) -> Void) -> ConnectInput {
  var copy = input
  change(&copy)
  return copy
}

let unreadQuery = ListQuery(status: .unread)

/// 轮询直到条件成立（相当于 vi.waitFor）
@MainActor
func waitUntil(
  _ condition: @MainActor () -> Bool,
  timeout: Duration = .seconds(3),
  sourceLocation: SourceLocation = #_sourceLocation
) async {
  let clock = ContinuousClock()
  let deadline = clock.now + timeout
  while !condition() {
    if clock.now > deadline {
      Issue.record("条件在超时前没有成立", sourceLocation: sourceLocation)
      return
    }
    try? await Task.sleep(for: .milliseconds(5))
  }
}
