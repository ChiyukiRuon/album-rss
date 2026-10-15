import Foundation

/// 同一服务的请求排队：同时最多 concurrency 个，相邻两次开始至少间隔 interval。
/// 服务限流时整体暂停，避免连续请求触发服务或前置代理的风控。
public actor RequestGate {
  private let concurrency: Int
  private let interval: Duration
  private let clock = ContinuousClock()
  private var active = 0
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private var readyAt: ContinuousClock.Instant

  public init(concurrency: Int = 2, interval: Duration = .milliseconds(150)) {
    self.concurrency = max(1, concurrency)
    self.interval = interval
    readyAt = clock.now
  }

  public func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
    await acquire()
    defer { release() }
    return try await operation()
  }

  /// 在这段时间内不再开始新的请求
  public func pause(_ duration: Duration) {
    readyAt = max(readyAt, clock.now + duration)
  }

  private func acquire() async {
    if active >= concurrency || !waiting.isEmpty {
      // 名额由 release() 直接转交，active 不变
      await withCheckedContinuation { waiting.append($0) }
    } else {
      active += 1
    }
    while true {
      let now = clock.now
      if now >= readyAt {
        readyAt = now + interval
        return
      }
      try? await clock.sleep(until: readyAt)
    }
  }

  private func release() {
    if waiting.isEmpty {
      active -= 1
    } else {
      waiting.removeFirst().resume()
    }
  }
}
