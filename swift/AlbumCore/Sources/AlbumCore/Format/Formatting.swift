import Foundation

/// 时间与地址的显示格式，与 Web 端 `lib/format.ts` 一致
public enum Formatting {
  private static let minute: TimeInterval = 60
  private static let hour: TimeInterval = 60 * minute
  private static let day: TimeInterval = 24 * hour

  private static func pad(_ value: Int) -> String {
    value < 10 ? "0\(value)" : "\(value)"
  }

  /// 相对时间：刚刚 / 5 分钟前 / 3 小时前 / 昨天 21:04 / 10月3日 / 2025年10月3日
  public static func relativeTime(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
    let diff = now.timeIntervalSince(date)
    if diff < minute { return "刚刚" }
    if diff < hour { return "\(Int((diff / minute).rounded(.down))) 分钟前" }
    let startOfToday = calendar.startOfDay(for: now)
    if date >= startOfToday { return "\(Int((diff / hour).rounded(.down))) 小时前" }
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    if date >= startOfToday.addingTimeInterval(-day) {
      return "昨天 \(pad(parts.hour ?? 0)):\(pad(parts.minute ?? 0))"
    }
    let month = parts.month ?? 1
    let dayOfMonth = parts.day ?? 1
    if parts.year == calendar.component(.year, from: now) { return "\(month)月\(dayOfMonth)日" }
    return "\(parts.year ?? 0)年\(month)月\(dayOfMonth)日"
  }

  public static func fullTime(_ date: Date, calendar: Calendar = .current) -> String {
    let p = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    return "\(p.year ?? 0)年\(p.month ?? 1)月\(p.day ?? 1)日 \(pad(p.hour ?? 0)):\(pad(p.minute ?? 0))"
  }

  /// 网站的显示名：去掉 www. 的主机名（含端口）；地址无效时为空
  public static func siteName(_ url: String) -> String {
    guard let parsed = WebURL(url) else { return "" }
    let host = parsed.host + (parsed.port.map { ":\($0)" } ?? "")
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }

  public static func hostOf(_ url: String) -> String {
    guard let parsed = WebURL(url) else { return url }
    return parsed.host + (parsed.port.map { ":\($0)" } ?? "")
  }
}
