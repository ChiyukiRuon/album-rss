import Foundation
import Observation

/// 屏幕底部的轻提示：同时最多三条，旧的先出；带操作或说明的停留更久
@MainActor @Observable
public final class ToastCenter {
  public enum Tone: Sendable {
    case neutral
    case success
    case warning
  }

  public struct Action {
    public var label: String
    public var run: @MainActor () -> Void

    public init(label: String, run: @escaping @MainActor () -> Void) {
      self.label = label
      self.run = run
    }
  }

  public struct Toast: Identifiable {
    public let id: Int
    public var message: String
    public var detail: String?
    public var tone: Tone
    public var action: Action?
  }

  public private(set) var toasts: [Toast] = []
  @ObservationIgnored private var nextID = 1
  @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

  public init(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
    self.sleep = sleep
  }

  @discardableResult
  public func show(_ message: String, detail: String? = nil, tone: Tone = .neutral, action: Action? = nil) -> Int {
    let id = nextID
    nextID += 1
    toasts = Array(toasts.suffix(2)) + [Toast(id: id, message: message, detail: detail, tone: tone, action: action)]
    let lifetime: Duration = action != nil || detail != nil ? .milliseconds(6500) : .milliseconds(3200)
    Task { [weak self, sleep] in
      try? await sleep(lifetime)
      self?.dismiss(id)
    }
    return id
  }

  public func dismiss(_ id: Int) {
    toasts.removeAll { $0.id == id }
  }

  public func clear() {
    toasts = []
  }
}
