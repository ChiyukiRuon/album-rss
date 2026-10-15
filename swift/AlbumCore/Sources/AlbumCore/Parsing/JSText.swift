import Foundation

/// 与 JavaScript 字符串函数一致的小工具。Web 端的解析结果是两端对照的基准，
/// Swift 自带的空白字符集与 JS 不同（例如 U+0085、U+FEFF），这里按 ECMAScript 的定义实现。
enum JSText {
  /// ECMAScript 的 WhiteSpace 与 LineTerminator
  static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F,
      0x205F, 0x3000, 0xFEFF:
      return true
    default:
      return false
    }
  }

  static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
    scalar.value >= 0x30 && scalar.value <= 0x39
  }

  /// String.prototype.trim
  static func trim(_ value: String) -> String {
    let scalars = value.unicodeScalars
    guard let start = scalars.firstIndex(where: { !isWhitespace($0) }) else { return "" }
    let end = scalars.lastIndex(where: { !isWhitespace($0) })!
    return String(scalars[start...end])
  }

  /// Number(value)：只用于宽高属性。空串为 0，无法解析时为 nil（相当于 NaN）
  static func number(_ value: String) -> Double? {
    let text = trim(value)
    if text.isEmpty { return 0 }
    let lower = text.lowercased()
    for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where lower.hasPrefix(prefix) {
      return Int(lower.dropFirst(2), radix: radix).map(Double.init)
    }
    // JS 只认 Infinity 这一种写法；Swift 的 Double(_:) 还接受 inf、nan 和十六进制浮点
    switch text {
    case "Infinity", "+Infinity": return .infinity
    case "-Infinity": return -.infinity
    default: break
    }
    guard text.unicodeScalars.allSatisfy({ isDigit($0) || "+-.eE".unicodeScalars.contains($0) }) else {
      return nil
    }
    return Double(text)
  }

  /// Number.parseFloat：读取开头能解析的最长部分（"800w" → 800），完全无法解析时为 nil
  static func parseFloat(_ value: String) -> Double? {
    let s = Array(value.unicodeScalars.drop(while: isWhitespace))
    var i = 0
    var text = ""
    if i < s.count, s[i] == "+" || s[i] == "-" {
      text.unicodeScalars.append(s[i])
      i += 1
    }
    if String(String.UnicodeScalarView(s[i...])).hasPrefix("Infinity") {
      return text == "-" ? -.infinity : .infinity
    }
    let integerStart = i
    while i < s.count, isDigit(s[i]) { i += 1 }
    var mantissa = String(String.UnicodeScalarView(s[integerStart..<i]))
    if i < s.count, s[i] == "." {
      var j = i + 1
      while j < s.count, isDigit(s[j]) { j += 1 }
      // "5." 与 ".5" 都合法，单独一个 "." 不合法
      if !mantissa.isEmpty || j > i + 1 {
        mantissa += String(String.UnicodeScalarView(s[i..<j]))
        i = j
      }
    }
    guard mantissa.contains(where: \.isNumber) else { return nil }
    text += mantissa
    if i < s.count, s[i] == "e" || s[i] == "E" {
      var j = i + 1
      if j < s.count, s[j] == "+" || s[j] == "-" { j += 1 }
      let digitsStart = j
      while j < s.count, isDigit(s[j]) { j += 1 }
      if j > digitsStart { text += "e" + String(String.UnicodeScalarView(s[(i + 1)..<j])) }
    }
    return Double(text)
  }

  /// value.split(/\s+/)：按连续空白切分，保留首尾空串（与 JS 一致）
  static func splitWhitespace(_ value: String) -> [String] {
    var parts: [String] = []
    var current = String.UnicodeScalarView()
    var inSpace = false
    for scalar in value.unicodeScalars {
      if isWhitespace(scalar) {
        if !inSpace {
          parts.append(String(current))
          current = String.UnicodeScalarView()
          inSpace = true
        }
      } else {
        current.append(scalar)
        inSpace = false
      }
    }
    parts.append(String(current))
    return parts
  }
}
