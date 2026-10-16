import Foundation
import Testing

@testable import AlbumCore

/// 跨端样例：contracts/fixtures/media 下的每个用例，Web 端的 parseEntry.test.ts 也读取同一组文件
struct MediaCase: Decodable, Sendable, CustomTestStringConvertible {
  struct Input: Decodable, Sendable {
    let content: String
    let url: String
    let server: String
    let mediaOrigin: String?
    let enclosures: [Enclosure]?
  }

  struct Image: Decodable, Equatable, Sendable {
    let url: String
    let width: Double?
    let height: Double?
    let alt: String?
    let kind: String?
    let poster: String?
  }

  struct Expected: Decodable, Sendable {
    let images: [Image]
    let paragraphs: [String]
  }

  let name: String
  let input: Input
  let expected: Expected

  var testDescription: String { name }

  static let all: [MediaCase] = {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // AlbumCoreTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // AlbumCore
      .deletingLastPathComponent()  // swift
      .deletingLastPathComponent()  // 仓库根目录
    let folder = root.appending(path: "contracts/fixtures/media")
    let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    struct File: Decodable { let cases: [MediaCase] }
    return files.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }.flatMap { file in
      (try? JSONDecoder().decode(File.self, from: Data(contentsOf: file)).cases) ?? []
    }
  }()
}

@Suite struct EntryParserTests {
  @Test func fixturesAreFound() {
    #expect(MediaCase.all.count >= 15)
  }

  @Test(arguments: MediaCase.all)
  func matchesTheSharedFixture(_ fixture: MediaCase) {
    let remote = RemoteEntry(
      id: "1",
      feedId: "f",
      title: "Title",
      url: fixture.input.url,
      content: fixture.input.content,
      enclosures: fixture.input.enclosures ?? []
    )
    let entry = EntryParser.parse(remote, server: fixture.input.server, mediaOrigin: fixture.input.mediaOrigin)
    let images = entry.images.map { MediaCase.Image(url: $0.url, width: $0.width, height: $0.height, alt: $0.alt, kind: $0.kind, poster: $0.poster) }
    #expect(images == fixture.expected.images)
    #expect(entry.images.allSatisfy { $0.key == $0.url })
    #expect(entry.paragraphs == fixture.expected.paragraphs)
    #expect(entry.parseState == (fixture.expected.images.isEmpty ? .none : .ready))
  }

  @Test func keepsServerStateAndMetadata() {
    let remote = RemoteEntry(
      id: "tag:google.com,2005:reader/item/ffffffffffffffff", feedId: "feed/1", title: "T", author: "A",
      url: "https://example.com/a", tags: ["Art"], read: true, starred: true)
    let entry = EntryParser.parse(remote, server: "https://rss.example.com", mediaOrigin: nil)
    #expect(entry.id == remote.id)
    #expect(entry.feedId == "feed/1")
    #expect(entry.tags == ["Art"])
    #expect(entry.read && entry.starred)
    #expect(entry.parseState == .none)
  }

  @Test func srcsetPrefersTheFirstOfEqualCandidates() {
    #expect(EntryParser.bestSrcset("a.jpg 2x, b.jpg 2x") == "a.jpg")
    #expect(EntryParser.bestSrcset("a.jpg, b.jpg 1x") == "b.jpg")
    #expect(EntryParser.bestSrcset("") == "")
  }

  @Test func parsesManyEntriesOffTheMainActor() async {
    let remotes = (0..<50).map {
      RemoteEntry(id: "\($0)", feedId: "f", url: "https://example.com/\($0)", content: "<img src=\"\($0).jpg\">")
    }
    let entries = await EntryParser.parseAll(remotes, server: "https://rss.example.com", mediaOrigin: nil)
    #expect(entries.map(\.images.first?.url) == remotes.map { "https://example.com/\($0.id).jpg" })
  }
}
