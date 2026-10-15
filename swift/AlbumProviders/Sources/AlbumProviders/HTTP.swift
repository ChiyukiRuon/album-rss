import AlbumCore
import Foundation

/// 发出一个 HTTP 请求。测试里换成假的实现，不访问网络
public protocol HTTPClient: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// 默认实现：不读写 cookie、不缓存、不跟随重定向（重定向响应原样返回，由调用方报错）
public final class URLSessionHTTPClient: HTTPClient {
  private let session: URLSession

  public init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 30
    configuration.waitsForConnectivity = false
    session = URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
  }

  deinit {
    session.invalidateAndCancel()
  }

  public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    return (data, http)
  }
}

private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    nil
  }
}

/// application/x-www-form-urlencoded，与 URLSearchParams.toString() 相同：空格写成 +，只保留字母数字和 *-._
enum FormEncoding {
  static func encode(_ pairs: [(String, String)]) -> String {
    pairs.map { escape($0.0) + "=" + escape($0.1) }.joined(separator: "&")
  }

  static func escape(_ value: String) -> String {
    var out = ""
    for byte in value.utf8 {
      switch byte {
      case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2A, 0x2D, 0x2E, 0x5F:
        out.unicodeScalars.append(Unicode.Scalar(byte))
      case 0x20:
        out += "+"
      default:
        out += String(format: "%%%02X", byte)
      }
    }
    return out
  }

  static func decode(_ query: String) -> [(String, String)] {
    query.split(separator: "&", omittingEmptySubsequences: true).map { pair in
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      func unescape(_ value: Substring) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(value)
      }
      return (unescape(parts[0]), parts.count > 1 ? unescape(parts[1]) : "")
    }
  }
}

/// encodeURIComponent：保留字母数字和 -_.!~*'()
enum URIComponent {
  static func encode(_ value: String) -> String {
    var out = ""
    for byte in value.utf8 {
      switch byte {
      case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x5F, 0x2E, 0x21, 0x7E, 0x2A, 0x27, 0x28, 0x29:
        out.unicodeScalars.append(Unicode.Scalar(byte))
      default:
        out += String(format: "%%%02X", byte)
      }
    }
    return out
  }
}

/// JSON 的动态读取：服务返回的字段类型不一定可靠，按 JS 的宽松方式逐项取值
enum JSONValue: Decodable, Sendable, Equatable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  subscript(key: String) -> JSONValue? {
    if case .object(let object) = self { return object[key] }
    return nil
  }

  var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  var number: Double? {
    if case .number(let value) = self { return value }
    return nil
  }

  var bool: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }

  var array: [JSONValue]? {
    if case .array(let value) = self { return value }
    return nil
  }

  var object: [String: JSONValue]? {
    if case .object(let value) = self { return value }
    return nil
  }

  /// JS 模板字符串 `${value}` 的效果：数字去掉无意义的 .0
  var text: String? {
    switch self {
    case .string(let value): value
    case .number(let value): value.rounded() == value && abs(value) < 1e21 ? String(Int64(value)) : String(value)
    case .bool(let value): String(value)
    default: nil
    }
  }

  /// Number(value) || 0
  var numberOrZero: Double {
    switch self {
    case .number(let value): value.isFinite ? value : 0
    case .string(let value): Double(value.trimmingCharacters(in: .whitespaces)) ?? 0
    case .bool(let value): value ? 1 : 0
    default: 0
    }
  }
}
