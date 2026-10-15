import AlbumCore
import Foundation

/// 限流或网关暂时不可用时重试；超过这个等待时间就直接报错，交给用户稍后再试
let retryStatuses: Set<Int> = [429, 502, 503, 504]
let maxRetries = 3
let maxRetryWait: TimeInterval = 30

/// 重试前的等待：优先使用 Retry-After（秒数或 HTTP 日期），否则 1、2、4 秒
func retryDelay(_ response: HTTPURLResponse, attempt: Int, now: Date = Date()) -> TimeInterval {
  if let header = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces),
    !header.isEmpty
  {
    if let seconds = Double(header), seconds.isFinite { return max(0, seconds) }
    if let date = httpDate(header) { return max(0, date.timeIntervalSince(now)) }
  }
  return pow(2, Double(attempt))
}

private func httpDate(_ value: String) -> Date? {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(identifier: "GMT")
  for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
    formatter.dateFormat = format
    if let date = formatter.date(from: value) { return date }
  }
  return nil
}

/// 同一端点的请求：排队、超时、重试，并把失败换成给用户看的说明（不包含响应正文）
struct Transport: Sendable {
  let server: String
  let client: any HTTPClient
  let gate: RequestGate
  /// 测试里替换掉，避免真的等待
  var sleep: @Sendable (TimeInterval) async throws -> Void = { seconds in
    try await Task.sleep(for: .seconds(seconds))
  }

  init(server: String, client: any HTTPClient, gate: RequestGate) {
    self.server = server
    self.client = client
    self.gate = gate
  }

  func send(
    _ path: String,
    method: String = "GET",
    headers: [String: String] = [:],
    body: Data? = nil
  ) async throws -> (Data, HTTPURLResponse) {
    guard let url = URL(string: server + path) else { throw APIError("服务地址无效，请编辑这个端点") }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 30
    request.httpShouldHandleCookies = false
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
    request.httpBody = body
    let attemptRequest = request
    return try await gate.run {
      var attempt = 0
      while true {
        let data: Data
        let response: HTTPURLResponse
        do {
          (data, response) = try await client.data(for: attemptRequest)
        } catch {
          if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
          throw APIError("请求未完成，请检查网络连接、服务地址和证书后重试", isNetwork: true)
        }
        let status = response.statusCode
        if (200..<300).contains(status) { return (data, response) }
        let wait = retryDelay(response, attempt: attempt)
        if retryStatuses.contains(status), attempt < maxRetries, wait <= maxRetryWait {
          await gate.pause(.milliseconds(Int(wait * 1000)))
          try await sleep(wait)
          attempt += 1
          continue
        }
        throw Self.error(status: status, wait: wait)
      }
    }
  }

  static func error(status: Int, wait: TimeInterval) -> APIError {
    switch status {
    case 401, 403:
      return APIError("凭据无效或已过期，请编辑这个端点后重新连接", status: status)
    case 429:
      let when = wait > maxRetryWait ? "约 \(Int(wait.rounded(.up))) 秒后" : "稍后"
      return APIError("服务限制了请求频率，请\(when)再试", status: status)
    case 300..<400:
      return APIError("服务地址发生了重定向（HTTP \(status)），请填写重定向后的完整地址", status: status)
    default:
      return APIError("服务返回 HTTP \(status)，请稍后重试", status: status)
    }
  }

  func json(_ path: String, headers: [String: String] = [:]) async throws -> JSONValue {
    let (data, _) = try await send(path, headers: headers)
    return try Self.decode(data)
  }

  static func decode(_ data: Data) throws -> JSONValue {
    do {
      return try JSONDecoder().decode(JSONValue.self, from: data)
    } catch {
      throw APIError("服务没有返回有效的 JSON 数据，请检查服务类型和 API 地址")
    }
  }

  func text(_ path: String, method: String = "GET", headers: [String: String] = [:], body: Data? = nil)
    async throws -> String
  {
    let (data, _) = try await send(path, method: method, headers: headers, body: body)
    return String(decoding: data, as: UTF8.self)
  }
}

/// 可选接口：服务没有实现时返回 nil，认证和网络错误照常抛出
func optional<T: Sendable>(_ read: () async throws -> T?) async throws -> T? {
  do {
    return try await read()
  } catch let error as APIError where [400, 404, 405, 501].contains(error.status) {
    return nil
  }
}

/// Date.parse 对 RFC 3339 时间的解析：小数秒位数不固定，可能是 Go 的零时间；没有时区时按本地时间
func parseTimestamp(_ value: String?) -> Date? {
  guard let value else { return nil }
  let pattern = #/^(\d{4})-(\d{2})-(\d{2})(?:[Tt ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?)?\s*([Zz]|[+-]\d{2}(?::?\d{2})?)?$/#
  guard let match = value.trimmingCharacters(in: .whitespaces).wholeMatch(of: pattern),
    let year = Int(match.1), let month = Int(match.2), let day = Int(match.3),
    (1...12).contains(month), (1...31).contains(day)
  else { return nil }
  let hour = match.4.flatMap { Int($0) } ?? 0
  let minute = match.5.flatMap { Int($0) } ?? 0
  let second = match.6.flatMap { Int($0) } ?? 0
  guard hour <= 24, minute <= 59, second <= 59 else { return nil }
  // JS 使用前推格里历；Foundation 的公历在 1582 年之前换成儒略历，Go 的零时间会差两天，所以直接计算
  let days = daysFromCivil(year: year, month: month, day: day)
  var seconds = Double(days * 86_400 + hour * 3_600 + minute * 60 + second)
  // 与 JS 一致只保留到毫秒
  seconds += match.7.map { Double("0." + $0.prefix(3)) ?? 0 } ?? 0
  if let zone = match.8 {
    if zone != "Z" && zone != "z" {
      let sign = zone.hasPrefix("-") ? -1.0 : 1.0
      let digits = zone.dropFirst().replacingOccurrences(of: ":", with: "")
      let offset = Double((Int(digits.prefix(2)) ?? 0) * 3_600 + (Int(digits.dropFirst(2)) ?? 0) * 60)
      seconds -= sign * offset
    }
  } else if match.4 != nil {
    // 带时刻但没有时区时，JS 按本地时间解析；只有日期时按 UTC
    let guess = Date(timeIntervalSince1970: seconds)
    seconds -= Double(TimeZone.current.secondsFromGMT(for: guess))
  }
  return Date(timeIntervalSince1970: seconds)
}

/// 公历日期到 1970-01-01 的天数（Howard Hinnant 的 days_from_civil）
private func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
  let y = month <= 2 ? year - 1 : year
  let era = (y >= 0 ? y : y - 399) / 400
  let yearOfEra = y - era * 400
  let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
  let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
  return era * 146_097 + dayOfEra - 719_468
}
