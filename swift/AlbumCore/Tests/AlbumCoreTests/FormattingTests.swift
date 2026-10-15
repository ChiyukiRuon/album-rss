import Foundation
import Testing

@testable import AlbumCore

@Suite struct FormattingTests {
  /// 固定时区，结果不随运行测试的机器变化
  let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
  }()

  func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  var now: Date { at(2026, 10, 15, 14, 30) }

  @Test func justNowWithinAMinute() {
    #expect(Formatting.relativeTime(now.addingTimeInterval(-20), now: now, calendar: calendar) == "刚刚")
  }

  @Test func minutesWithinAnHourThenHoursToday() {
    #expect(Formatting.relativeTime(now.addingTimeInterval(-5 * 60), now: now, calendar: calendar) == "5 分钟前")
    #expect(Formatting.relativeTime(at(2026, 10, 15, 9, 0), now: now, calendar: calendar) == "5 小时前")
  }

  @Test func yesterdayThisYearAndEarlier() {
    #expect(Formatting.relativeTime(at(2026, 10, 14, 21, 4), now: now, calendar: calendar) == "昨天 21:04")
    #expect(Formatting.relativeTime(at(2026, 3, 3, 8, 0), now: now, calendar: calendar) == "3月3日")
    #expect(Formatting.relativeTime(at(2025, 10, 3, 8, 0), now: now, calendar: calendar) == "2025年10月3日")
  }

  @Test func fullTimeIncludesMinutes() {
    #expect(Formatting.fullTime(at(2026, 1, 5, 7, 3), calendar: calendar) == "2026年1月5日 07:03")
  }

  @Test func siteNameDropsWWW() {
    #expect(Formatting.siteName("https://www.pixiv.net/users/1") == "pixiv.net")
    #expect(Formatting.siteName("https://space.bilibili.com/2/dynamic") == "space.bilibili.com")
    #expect(Formatting.siteName("http://localhost:8880/") == "localhost:8880")
  }

  @Test func siteNameIsEmptyForInvalidAddresses() {
    #expect(Formatting.siteName("") == "")
    #expect(Formatting.siteName("not a url") == "")
  }
}
