import Foundation

/// 服务请求失败。message 直接显示给用户，不包含响应正文
public struct APIError: Error, Equatable, Sendable, LocalizedError {
  public var message: String
  /// HTTP 状态码；网络错误等没有状态码时为 0
  public var status: Int
  /// 请求没有到达服务（离线、超时、证书等），之后可以重试
  public var isNetwork: Bool

  public init(_ message: String, status: Int = 0, isNetwork: Bool = false) {
    self.message = message
    self.status = status
    self.isNetwork = isNetwork
  }

  public var errorDescription: String? { message }

  public var isUnauthorized: Bool { status == 401 || status == 403 }

  /// 稍后重试可能成功：网络问题、限流、服务暂时不可用
  public var isTransient: Bool {
    isNetwork || status == 429 || status >= 500
  }

  public static let cancelled = APIError("连接已取消")
}

/// 一个 RSS 服务的读写操作。UI 与 store 不直接依赖远端路径或字段
public protocol RSSProvider: Sendable {
  /// 验证凭据和服务类型；返回服务端的用户名（没有时为空串）
  func authenticate() async throws -> String
  func subscriptions() async throws -> Subscriptions
  /// 各订阅的未读文章数，键为订阅 ID；服务不提供计数接口时为 nil
  func unreadCounts() async throws -> [String: Int]?
  /// 按范围分页读取文章，新的在前；cursor 来自上一页
  func entries(_ scope: EntryScope, cursor: String?, limit: Int) async throws -> EntryPage
  func setRead(_ ids: [String], read: Bool) async throws
  func setStarred(_ id: String, starred: Bool) async throws
  /// 请求服务立即抓取订阅；不支持时 supportsRefresh 为 false
  func refreshFeed(_ id: String) async throws
  var supportsRefresh: Bool { get }
}

extension RSSProvider {
  public var supportsRefresh: Bool { false }

  public func refreshFeed(_ id: String) async throws {
    throw APIError("当前服务不支持手动抓取，请在 RSS 服务中刷新后同步")
  }
}

/// 把任意错误变成给用户看的说明
public func errorMessage(_ error: any Error) -> String {
  if let api = error as? APIError { return api.message }
  if error is CancellationError { return APIError.cancelled.message }
  return (error as? LocalizedError)?.errorDescription ?? "请求失败，请稍后重试"
}
