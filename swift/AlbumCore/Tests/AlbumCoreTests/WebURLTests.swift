import Testing

@testable import AlbumCore

/// 期望值按 WHATWG URL 标准（即浏览器的 new URL）给出
@Suite struct WebURLTests {
  @Test(arguments: [
    ("https://Example.COM:443/a/./b/../c?x=1 2#f g", "https://example.com/a/c?x=1%202#f%20g"),
    ("http://example.com", "http://example.com/"),
    ("http://example.com:80/", "http://example.com/"),
    ("http://example.com:8080", "http://example.com:8080/"),
    ("HTTPS://EXAMPLE.com/A", "https://example.com/A"),
    ("https:\\\\example.com\\a\\b", "https://example.com/a/b"),
    ("  https://example.com/a b  ", "https://example.com/a%20b"),
    ("https://exa\nmple.com/a\tb", "https://example.com/ab"),
    ("https://example.com/路径/图.jpg", "https://example.com/%E8%B7%AF%E5%BE%84/%E5%9B%BE.jpg"),
    ("https://例え.jp/", "https://xn--r8jz45g.jp/"),
    ("https://example.com/a?q='x'", "https://example.com/a?q=%27x%27"),
    ("https://example.com/a|b{c}", "https://example.com/a|b%7Bc%7D"),
    ("https://example.com/%zz", "https://example.com/%zz"),
    ("https://example.com/a/%2e%2E/b", "https://example.com/b"),
    ("http://0x7f.1/", "http://127.0.0.1/"),
    ("http://192.168.001.010/", "http://192.168.1.8/"),
    ("https:example.com", "https://example.com/"),
    ("https://example.com./x", "https://example.com./x"),
    ("https://@example.com/", "https://example.com/"),
  ])
  func absoluteAddresses(input: String, expected: String) {
    #expect(httpURL(input) == expected)
  }

  @Test(arguments: [
    ("/cover.jpg", "https://example.com/post/1", "https://example.com/cover.jpg"),
    ("cover.jpg", "https://example.com/post/1", "https://example.com/post/cover.jpg"),
    ("../img/a.png", "https://example.com/a/b/c.html", "https://example.com/a/img/a.png"),
    ("//cdn.example.com/x.jpg", "https://example.com/", "https://cdn.example.com/x.jpg"),
    ("?x=1", "https://example.com/a/b?y#z", "https://example.com/a/b?x=1"),
    ("#top", "https://example.com/a?y", "https://example.com/a?y#top"),
    ("http:img.jpg", "http://example.com/a/b", "http://example.com/a/img.jpg"),
    (".", "http://example.com/a/b.jpg", "http://example.com/a/"),
    ("..", "http://example.com/a/b/c", "http://example.com/a/"),
  ])
  func relativeAddresses(input: String, base: String, expected: String) {
    #expect(httpURL(input, base: base) == expected)
  }

  @Test(arguments: [
    "", "   ", "javascript:alert(1)", "data:image/png;base64,AAAA", "mailto:a@example.com",
    "https://user:pass@example.com/", "https://user@example.com/", "relative.jpg",
    "https://example.com:65536/", "http:///", "https://exa mple.com/", "http://1.2.3.4.5/",
  ])
  func rejectedAddresses(input: String) {
    #expect(httpURL(input) == "")
  }

  @Test func invalidBaseFailsLikeTheURLConstructor() {
    #expect(httpURL("https://example.com/a.jpg", base: "not a url") == "")
  }

  @Test func originAndSearch() throws {
    let url = try #require(WebURL("https://Example.com:8443/a?"))
    #expect(url.origin == "https://example.com:8443")
    #expect(url.search == "")
    #expect(url.href == "https://example.com:8443/a?")
  }

  @Test func proxyImagesAreMappedToTheConnectedServer() {
    let mapped = mediaURL(
      "https://miniflux.example.com/proxy/abc/def?x=1",
      base: "https://post.example.com/1",
      server: "http://localhost:8880/rss/",
      mediaOrigin: "https://miniflux.example.com"
    )
    #expect(mapped == "http://localhost:8880/rss/proxy/abc/def?x=1")
  }

  @Test func otherPathsAndOriginsAreLeftAlone() {
    let other = mediaURL(
      "https://miniflux.example.com/other.jpg", base: "https://p.example.com/",
      server: "http://localhost:8880", mediaOrigin: "https://miniflux.example.com")
    #expect(other == "https://miniflux.example.com/other.jpg")
    let thirdParty = mediaURL(
      "https://cdn.example.com/proxy/a.jpg", base: "https://p.example.com/",
      server: "http://localhost:8880", mediaOrigin: "https://miniflux.example.com")
    #expect(thirdParty == "https://cdn.example.com/proxy/a.jpg")
  }
}
