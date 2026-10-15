import Foundation

/// 按 WHATWG URL 标准解析 http / https 地址，结果与浏览器的 `new URL(value, base)` 一致。
/// 图片的去重键、缓存键都来自这里，所以不用 Foundation 的 RFC 3986 规则（两者在反斜杠、
/// 默认端口、主机大小写、百分号编码集合上都不同）。其他协议一律视为无效。
public struct WebURL: Hashable, Sendable, CustomStringConvertible {
  public fileprivate(set) var scheme: String
  public fileprivate(set) var username: String = ""
  public fileprivate(set) var password: String = ""
  public fileprivate(set) var host: String = ""
  /// 默认端口（http 80、https 443）不记录
  public fileprivate(set) var port: Int?
  /// 路径段；序列化时每段前加 "/"
  var segments: [String] = []
  public var query: String?
  public var fragment: String?

  public init?(_ input: String, base: WebURL? = nil) {
    guard let url = WebURLParser.parse(input, base: base) else { return nil }
    self = url
  }

  init(scheme: String) {
    self.scheme = scheme
  }

  public var path: String { segments.map { "/" + $0 }.joined() }
  public var origin: String { scheme + "://" + host + (port.map { ":\($0)" } ?? "") }
  public var hasCredentials: Bool { !username.isEmpty || !password.isEmpty }
  /// 与 location.search 相同：没有查询或查询为空时是空串
  public var search: String { query.map { $0.isEmpty ? "" : "?" + $0 } ?? "" }

  public var href: String {
    var out = scheme + "://"
    if hasCredentials {
      out += username
      if !password.isEmpty { out += ":" + password }
      out += "@"
    }
    out += host
    if let port { out += ":\(port)" }
    out += path
    if let query { out += "?" + query }
    if let fragment { out += "#" + fragment }
    return out
  }

  public var description: String { href }

  /// 交给 URLSession 的地址。href 已经是规范化的 ASCII，Foundation 能原样解析
  public var foundationURL: URL? { URL(string: href) }

  fileprivate static func defaultPort(for scheme: String) -> Int { scheme == "https" ? 443 : 80 }

  fileprivate mutating func copyAuthority(from base: WebURL) {
    username = base.username
    password = base.password
    host = base.host
    port = base.port
  }

  fileprivate mutating func setPort(_ value: Int?) {
    port = value == WebURL.defaultPort(for: scheme) ? nil : value
  }
}

/// `httpUrl`：解析为 http(s) 地址并去掉不安全的写法；带用户名或密码的地址视为无效，返回空串
public func httpURL(_ value: String, base: String? = nil) -> String {
  guard !JSText.trim(value).isEmpty else { return "" }
  var baseURL: WebURL?
  if let base {
    // 与 new URL(value, base) 一致：base 无效时整个解析失败
    guard let parsed = WebURL(base) else { return "" }
    baseURL = parsed
  }
  guard let url = WebURL(value, base: baseURL), !url.hasCredentials else { return "" }
  return url.href
}

/// 规范化服务地址：只接受不含用户名和密码的 http(s) 地址，去掉查询、片段和末尾的斜杠
public func normalizeServer(_ value: String) throws -> String {
  let href = httpURL(value.trimmingCharacters(in: .whitespacesAndNewlines))
  guard !href.isEmpty, var url = WebURL(href) else {
    throw APIError("请输入不含用户名和密码的 HTTP 或 HTTPS 服务地址")
  }
  url.query = nil
  url.fragment = nil
  var result = url.href
  while result.hasSuffix("/") { result.removeLast() }
  return result
}

/// 图片地址：解析相对地址，并把服务公开地址下的 Miniflux /proxy/ 图片映射到当前连接的服务
public func mediaURL(_ value: String, base: String, server: String, mediaOrigin: String?) -> String {
  let resolved = httpURL(value, base: base)
  guard !resolved.isEmpty, let url = WebURL(resolved) else { return "" }
  if let mediaOrigin, !mediaOrigin.isEmpty, let origin = WebURL(mediaOrigin),
    url.origin == origin.origin, url.path.hasPrefix("/proxy/"), let target = WebURL(server)
  {
    var prefix = target.path
    if prefix.hasSuffix("/") { prefix.removeLast() }
    return target.origin + prefix + url.path + url.search
  }
  return resolved
}

// MARK: - 解析

private enum WebURLParser {
  typealias Scalars = ArraySlice<Unicode.Scalar>

  static func parse(_ input: String, base: WebURL?) -> WebURL? {
    var scalars = Array(input.unicodeScalars)
    // 去掉首尾的 C0 控制字符与空格，再去掉所有制表符和换行
    let start = scalars.firstIndex { $0.value > 0x20 } ?? scalars.endIndex
    let end = (scalars.lastIndex { $0.value > 0x20 }).map { $0 + 1 } ?? start
    scalars = Array(scalars[start..<max(start, end)])
    scalars.removeAll { $0 == "\t" || $0 == "\n" || $0 == "\r" }
    let s = scalars[...]

    if let colon = schemeEnd(s) {
      let scheme = String(String.UnicodeScalarView(s[..<colon])).lowercased()
      guard scheme == "http" || scheme == "https" else { return nil }
      let rest = s[(colon + 1)...]
      if let base, base.scheme == scheme, !(rest.first.map(isSlash) ?? false) {
        return relative(rest, base: base)
      }
      return authority(rest.drop(while: isSlash), scheme: scheme)
    }
    guard let base else { return nil }
    return relative(s, base: base)
  }

  static func isSlash(_ c: Unicode.Scalar) -> Bool { c == "/" || c == "\\" }

  static func isASCIIAlpha(_ c: Unicode.Scalar) -> Bool {
    (c.value >= 0x41 && c.value <= 0x5A) || (c.value >= 0x61 && c.value <= 0x7A)
  }

  static func isHexDigit(_ c: Unicode.Scalar) -> Bool {
    JSText.isDigit(c) || (c.value >= 0x41 && c.value <= 0x46) || (c.value >= 0x61 && c.value <= 0x66)
  }

  /// 协议结束处（冒号）的位置；不是“字母开头、后接字母数字 + - .、再接冒号”时为 nil
  static func schemeEnd(_ s: Scalars) -> Int? {
    guard let first = s.first, isASCIIAlpha(first) else { return nil }
    var i = s.startIndex + 1
    while i < s.endIndex {
      let c = s[i]
      if c == ":" { return i }
      guard isASCIIAlpha(c) || JSText.isDigit(c) || c == "+" || c == "-" || c == "." else { return nil }
      i += 1
    }
    return nil
  }

  static func relative(_ s: Scalars, base: WebURL) -> WebURL? {
    var url = WebURL(scheme: base.scheme)
    guard let c = s.first else {
      url.copyAuthority(from: base)
      url.segments = base.segments
      url.query = base.query
      return url
    }
    if isSlash(c) {
      let next = s.dropFirst()
      if let second = next.first, isSlash(second) {
        return authority(s.drop(while: isSlash), scheme: base.scheme)
      }
      url.copyAuthority(from: base)
      return path(next, into: url)
    }
    url.copyAuthority(from: base)
    if c == "?" {
      url.segments = base.segments
      return queryAndFragment(s, into: url)
    }
    if c == "#" {
      url.segments = base.segments
      url.query = base.query
      url.fragment = percentEncode(s.dropFirst(), set: .fragment)
      return url
    }
    url.segments = Array(base.segments.dropLast())
    return path(s, into: url)
  }

  static func authority(_ s: Scalars, scheme: String) -> WebURL? {
    var url = WebURL(scheme: scheme)
    let end = s.firstIndex { isSlash($0) || $0 == "?" || $0 == "#" } ?? s.endIndex
    var hostPort = s[s.startIndex..<end]
    if let at = hostPort.lastIndex(of: "@") {
      let userinfo = hostPort[hostPort.startIndex..<at]
      if let colon = userinfo.firstIndex(of: ":") {
        url.username = percentEncode(userinfo[userinfo.startIndex..<colon], set: .userinfo)
        url.password = percentEncode(userinfo[(colon + 1)...], set: .userinfo)
      } else {
        url.username = percentEncode(userinfo, set: .userinfo)
      }
      hostPort = hostPort[(at + 1)...]
      if hostPort.isEmpty { return nil }
    }
    // 端口在最后一个不在方括号内的冒号之后
    var hostPart = hostPort
    var portPart: Scalars?
    var inBrackets = false
    for i in hostPort.indices {
      let c = hostPort[i]
      if c == "[" { inBrackets = true }
      if c == "]" { inBrackets = false }
      if c == ":", !inBrackets {
        hostPart = hostPort[hostPort.startIndex..<i]
        portPart = hostPort[(i + 1)...]
        break
      }
    }
    guard let host = parseHost(hostPart) else { return nil }
    url.host = host
    if let portPart, !portPart.isEmpty {
      guard portPart.allSatisfy(JSText.isDigit) else { return nil }
      let digits = String(String.UnicodeScalarView(portPart)).drop { $0 == "0" }
      guard digits.count <= 5, let value = Int(digits.isEmpty ? "0" : String(digits)), value <= 65535 else {
        return nil
      }
      url.setPort(value)
    }
    let rest = s[end...]
    if let first = rest.first, isSlash(first) {
      return path(rest.dropFirst(), into: url)
    }
    return path(rest, into: url)
  }

  /// 路径状态：按 / 与 \ 切段，处理 . 和 ..，再接查询和片段
  static func path(_ s: Scalars, into initial: WebURL) -> WebURL? {
    var url = initial
    var buffer = String.UnicodeScalarView()
    var i = s.startIndex
    while true {
      let c: Unicode.Scalar? = i < s.endIndex ? s[i] : nil
      if c == nil || isSlash(c!) || c == "?" || c == "#" {
        let segment = String(buffer)
        let atSlash = c.map(isSlash) ?? false
        if isDoubleDot(segment) {
          if !url.segments.isEmpty { url.segments.removeLast() }
          if !atSlash { url.segments.append("") }
        } else if isSingleDot(segment) {
          if !atSlash { url.segments.append("") }
        } else {
          url.segments.append(percentEncode(buffer, set: .path))
        }
        buffer = String.UnicodeScalarView()
        guard let c else { return url }
        if c == "?" || c == "#" { return queryAndFragment(s[i...], into: url) }
      } else {
        buffer.append(c!)
      }
      i += 1
    }
  }

  /// s 以 "?" 或 "#" 开头
  static func queryAndFragment(_ s: Scalars, into initial: WebURL) -> WebURL? {
    var url = initial
    var rest = s
    if rest.first == "?" {
      let end = rest.firstIndex(of: "#") ?? rest.endIndex
      url.query = percentEncode(rest[(rest.startIndex + 1)..<end], set: .specialQuery)
      rest = rest[end...]
    }
    if rest.first == "#" {
      url.fragment = percentEncode(rest.dropFirst(), set: .fragment)
    }
    return url
  }

  static func isSingleDot(_ segment: String) -> Bool {
    let lower = segment.lowercased()
    return lower == "." || lower == "%2e"
  }

  static func isDoubleDot(_ segment: String) -> Bool {
    switch segment.lowercased() {
    case "..", ".%2e", "%2e.", "%2e%2e": return true
    default: return false
    }
  }

  // MARK: 百分号编码

  enum EncodeSet {
    case path, specialQuery, fragment, userinfo

    func contains(_ c: Unicode.Scalar) -> Bool {
      let v = c.value
      if v < 0x20 || v > 0x7E { return true }
      switch self {
      case .fragment:
        return [0x20, 0x22, 0x3C, 0x3E, 0x60].contains(v)
      case .specialQuery:
        return [0x20, 0x22, 0x23, 0x3C, 0x3E, 0x27].contains(v)
      case .path:
        return [0x20, 0x22, 0x23, 0x3C, 0x3E, 0x3F, 0x60, 0x7B, 0x7D].contains(v)
      case .userinfo:
        return [
          0x20, 0x22, 0x23, 0x3C, 0x3E, 0x3F, 0x60, 0x7B, 0x7D, 0x2F, 0x3A, 0x3B, 0x3D, 0x40, 0x5B, 0x5C,
          0x5D, 0x5E, 0x7C,
        ].contains(v)
      }
    }
  }

  static func percentEncode(_ s: some Sequence<Unicode.Scalar>, set: EncodeSet) -> String {
    var out = ""
    for c in s {
      if set.contains(c) {
        for byte in String(c).utf8 { out += String(format: "%%%02X", byte) }
      } else {
        out.unicodeScalars.append(c)
      }
    }
    return out
  }

  static func percentDecode(_ s: Scalars) -> String {
    func hexValue(_ byte: UInt8) -> UInt8? {
      switch byte {
      case 0x30...0x39: byte - 0x30
      case 0x41...0x46: byte - 0x41 + 10
      case 0x61...0x66: byte - 0x61 + 10
      default: nil
      }
    }
    let utf8 = Array(String(String.UnicodeScalarView(s)).utf8)
    var bytes: [UInt8] = []
    var i = 0
    while i < utf8.count {
      if utf8[i] == 0x25, i + 2 < utf8.count, let high = hexValue(utf8[i + 1]), let low = hexValue(utf8[i + 2]) {
        bytes.append(high << 4 | low)
        i += 3
      } else {
        bytes.append(utf8[i])
        i += 1
      }
    }
    return String(decoding: bytes, as: UTF8.self)
  }

  // MARK: 主机

  static func parseHost(_ s: Scalars) -> String? {
    if s.first == "[" {
      guard s.last == "]" else { return nil }
      let inner = s.dropFirst().dropLast()
      guard !inner.isEmpty, inner.allSatisfy({ isHexDigit($0) || $0 == ":" || $0 == "." }) else { return nil }
      return "[" + String(String.UnicodeScalarView(inner)).lowercased() + "]"
    }
    let decoded = percentDecode(s)
    guard let ascii = domainToASCII(decoded), !ascii.isEmpty else { return nil }
    for c in ascii.unicodeScalars where isForbiddenDomainCodePoint(c) { return nil }
    if endsInNumber(ascii) { return parseIPv4(ascii) }
    return ascii
  }

  static func isForbiddenDomainCodePoint(_ c: Unicode.Scalar) -> Bool {
    let v = c.value
    if v <= 0x20 || v == 0x7F { return true }
    return [0x23, 0x25, 0x2F, 0x3A, 0x3C, 0x3E, 0x3F, 0x40, 0x5B, 0x5C, 0x5D, 0x5E, 0x7C].contains(v)
  }

  /// UTS #46 的近似：NFKC、小写、全角句点换成 "."，非 ASCII 的标签转为 Punycode
  static func domainToASCII(_ domain: String) -> String? {
    if domain.unicodeScalars.allSatisfy(\.isASCII) { return domain.lowercased() }
    let mapped = domain.precomposedStringWithCompatibilityMapping.lowercased()
      .replacingOccurrences(of: "。", with: ".")
      .replacingOccurrences(of: "｡", with: ".")
    var labels: [String] = []
    for label in mapped.split(separator: ".", omittingEmptySubsequences: false) {
      if label.unicodeScalars.allSatisfy(\.isASCII) {
        labels.append(String(label))
      } else {
        guard let encoded = punycode(String(label)) else { return nil }
        labels.append("xn--" + encoded)
      }
    }
    return labels.joined(separator: ".")
  }

  /// RFC 3492 编码
  static func punycode(_ input: String) -> String? {
    let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700
    let points = input.unicodeScalars.map { Int($0.value) }
    var output = String(String.UnicodeScalarView(input.unicodeScalars.filter(\.isASCII)))
    let basicCount = output.unicodeScalars.count
    var handled = basicCount
    if basicCount > 0 { output += "-" }
    var n = 128
    var delta = 0
    var bias = 72

    func digit(_ d: Int) -> Character {
      Character(Unicode.Scalar(UInt8(d < 26 ? 0x61 + d : 0x30 + d - 26)))
    }
    func adapt(_ delta: Int, _ count: Int, _ first: Bool) -> Int {
      var delta = first ? delta / damp : delta / 2
      delta += delta / count
      var k = 0
      while delta > ((base - tMin) * tMax) / 2 {
        delta /= base - tMin
        k += base
      }
      return k + (base - tMin + 1) * delta / (delta + skew)
    }

    while handled < points.count {
      guard let m = points.filter({ $0 >= n }).min() else { return nil }
      let (product, overflow) = (m - n).multipliedReportingOverflow(by: handled + 1)
      guard !overflow else { return nil }
      delta += product
      n = m
      for c in points {
        if c < n { delta += 1 }
        if c == n {
          var q = delta
          var k = base
          while true {
            let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
            if q < t { break }
            output.append(digit(t + (q - t) % (base - t)))
            q = (q - t) / (base - t)
            k += base
          }
          output.append(digit(q))
          bias = adapt(delta, handled + 1, handled == basicCount)
          delta = 0
          handled += 1
        }
      }
      delta += 1
      n += 1
    }
    return output
  }

  // MARK: IPv4

  static func endsInNumber(_ host: String) -> Bool {
    var parts = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    if parts.last == "" {
      if parts.count == 1 { return false }
      parts.removeLast()
    }
    guard let last = parts.last, !last.isEmpty else { return false }
    if last.unicodeScalars.allSatisfy(JSText.isDigit) { return true }
    return ipv4Number(last) != nil
  }

  static func ipv4Number(_ part: String) -> Int? {
    guard !part.isEmpty else { return nil }
    var text = Substring(part)
    var radix = 10
    if text.count >= 2, text.lowercased().hasPrefix("0x") {
      text = text.dropFirst(2)
      radix = 16
    } else if text.count >= 2, text.hasPrefix("0") {
      text = text.dropFirst()
      radix = 8
    }
    if text.isEmpty { return 0 }
    return Int(text, radix: radix)
  }

  static func parseIPv4(_ host: String) -> String? {
    var parts = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    if parts.last == "", parts.count > 1 { parts.removeLast() }
    guard parts.count <= 4 else { return nil }
    var numbers: [Int] = []
    for part in parts {
      guard let value = ipv4Number(part) else { return nil }
      numbers.append(value)
    }
    for value in numbers.dropLast() where value > 255 { return nil }
    let last = numbers.last ?? 0
    guard last < Int(pow(256.0, Double(5 - numbers.count))) else { return nil }
    var address = last
    for (index, value) in numbers.dropLast().enumerated() {
      address += value * Int(pow(256.0, Double(3 - index)))
    }
    return (0..<4).map { String((address >> (8 * (3 - $0))) & 0xFF) }.joined(separator: ".")
  }
}
