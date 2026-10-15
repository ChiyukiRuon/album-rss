import Foundation
import Testing

@testable import AlbumCore

@Suite struct SelectorsTests {
  let folders = [Folder(id: "1", title: "插画"), Folder(id: "2", title: "漫画")]

  @Test func showsTheFolderName() {
    #expect(Selectors.categoryLabel(["2"], folders: folders) == "漫画")
  }

  @Test func joinsMultipleLabelsAndIgnoresMissingOnes() {
    #expect(Selectors.categoryLabel(["1", "missing", "2"], folders: folders) == "插画、漫画")
  }

  @Test func hiddenWithoutFolders() {
    #expect(Selectors.categoryLabel([], folders: folders) == nil)
  }

  @Test func hiddenWhenTheAccountHasOneFolder() {
    #expect(Selectors.categoryLabel(["1"], folders: [Folder(id: "1", title: "All")]) == nil)
  }

  func entry(_ id: String, feed: String = "f", read: Bool = false, starred: Bool = false, images: Int = 1) -> Entry {
    Entry(
      id: id, feedId: feed, title: "", author: "", url: "", publishedAt: Date(timeIntervalSince1970: 0),
      images: (0..<images).map { ImageAsset(key: "\(id)-\($0)", url: "https://e.com/\(id)/\($0).jpg") },
      parseState: images > 0 ? .ready : .none, read: read, starred: starred)
  }

  @Test func visibilityFollowsStatusAndImages() {
    let unread = ListQuery(status: .unread)
    #expect(Selectors.isVisible(entry("1"), in: unread, showImageless: false))
    #expect(!Selectors.isVisible(entry("1", read: true), in: unread, showImageless: false))
    #expect(!Selectors.isVisible(entry("1", images: 0), in: unread, showImageless: false))
    #expect(Selectors.isVisible(entry("1", images: 0), in: unread, showImageless: true))
    #expect(!Selectors.isVisible(entry("1"), in: ListQuery(status: .starred), showImageless: false))
    #expect(!Selectors.isVisible(nil, in: unread, showImageless: true))
  }

  @Test func countsUseServerNumbersWhenAvailable() {
    let feeds = [Feed(id: "f", title: "F", author: "F", folderIds: ["1"])]
    let counts = Selectors.unreadCounts(
      entries: ["1": entry("1")], feeds: feeds, serverCounts: ["f": 7], showImageless: false)
    #expect(counts == .init(total: 7, byFeed: ["f": 7], byFolder: ["1": 7]))
  }

  @Test func countsFallBackToLoadedEntriesAndRespectImageless() {
    let feeds = [Feed(id: "f", title: "F", author: "F")]
    let entries = ["1": entry("1"), "2": entry("2", read: true), "3": entry("3", images: 0)]
    #expect(Selectors.unreadCounts(entries: entries, feeds: feeds, serverCounts: nil, showImageless: false).total == 1)
    #expect(Selectors.unreadCounts(entries: entries, feeds: feeds, serverCounts: nil, showImageless: true).total == 2)
  }

  @Test func orderIsNewestFirstWithNumericTiebreak() {
    var a = entry("9")
    var b = entry("10")
    var c = entry("3")
    a.publishedAt = Date(timeIntervalSince1970: 100)
    b.publishedAt = Date(timeIntervalSince1970: 100)
    c.publishedAt = Date(timeIntervalSince1970: 200)
    #expect(Selectors.sortOrder(["9": a, "10": b, "3": c]) == ["3", "10", "9"])
  }
}
