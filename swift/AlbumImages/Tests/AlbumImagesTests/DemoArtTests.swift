import AlbumCore
import Foundation
import Testing

@testable import AlbumImages

@Suite struct DemoArtTests {
  @Test func rendersIllustrationsAndMangaWithTheRequestedAspectRatio() throws {
    for path in ["art/dusk/123/1200x1800", "art/ink/77/2048x2896", "art/autumn/5/800x4000"] {
      let url = try #require(URL(string: "\(DemoContent.server)/\(path)"))
      let data = try DemoArt.render(url)
      let size = try #require(ImageMetrics.pixelSize(of: data))
      let expected = try #require(DemoArt.size(of: url))
      #expect(abs(size.width / size.height - expected.width / expected.height) < 0.01)
      #expect(max(size.width, size.height) <= 1400)
    }
  }

  @Test func brokenAddressesFail() throws {
    let url = try #require(URL(string: "\(DemoContent.server)/broken/1"))
    #expect(throws: DemoArt.Failure.self) { try DemoArt.render(url) }
  }

  @Test func renderingIsDeterministic() throws {
    let url = try #require(URL(string: "\(DemoContent.server)/art/sea/42/600x600"))
    #expect(try DemoArt.render(url) == DemoArt.render(url))
  }

  @Test func onlyTheDemoHostIsRenderedLocally() throws {
    #expect(DemoArt.isDemo(try #require(URL(string: "\(DemoContent.server)/art/sea/1/10x10"))))
    #expect(!DemoArt.isDemo(try #require(URL(string: "https://example.com/art/sea/1/10x10"))))
  }

  @Test func viewerDecodeSizeIsCappedByPixelCount() {
    #expect(ImageMetrics.viewerMaxPixelSize(for: CGSize(width: 1000, height: 1000)) == 1000)
    let strip = ImageMetrics.viewerMaxPixelSize(for: CGSize(width: 1000, height: 20000))
    #expect(strip < 20000 && strip > 17000)
  }
}

@MainActor
@Suite struct ImageSizeProbeTests {
  @Test func measuresDemoImagesThroughThePipeline() async throws {
    let service = ImageService(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), limit: 1 << 26)
    let probe = ImageSizeProbe(pipeline: service.pipeline(for: .demo))
    let url = "\(DemoContent.server)/art/mint/9/1600x900"
    probe.request([url])
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(5)
    while probe.result(for: url) == nil, clock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    guard case .size(let width, let height) = probe.result(for: url) else {
      Issue.record("没有测量到尺寸")
      return
    }
    #expect(abs(width / height - 1600.0 / 900) < 0.01)
  }

  @Test func brokenImagesSettleAsFailed() async throws {
    let service = ImageService(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), limit: 1 << 26)
    let probe = ImageSizeProbe(pipeline: service.pipeline(for: .demo))
    let url = "\(DemoContent.server)/broken/3"
    probe.request([url])
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(5)
    while probe.result(for: url) == nil, clock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    #expect(probe.result(for: url) == .failed)
  }
}
