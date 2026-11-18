import Foundation
import Testing
@testable import AlbumImages

@Test func extractsChannelAvatarAndResolvesRelativeURL() {
  let base = "https://example.org/feeds/gallery.xml"
  let item = "<item><image><url>article.jpg</url></image></item>"
  let rss = "<rss><channel>\(item)<image><url><![CDATA[../face.jpg?a=1&b=2]]></url></image></channel></rss>"
  #expect(ChannelImageParser.image(in: Data(rss.utf8), base: base) == "https://example.org/face.jpg?a=1&b=2")
  #expect(ChannelImageParser.image(in: Data("<rss><channel>\(item)</channel></rss>".utf8), base: base) == nil)
  let atom = "<feed xmlns='http://www.w3.org/2005/Atom'><icon>small</icon><logo>large</logo></feed>"
  #expect(ChannelImageParser.image(in: Data(atom.utf8), base: base) == "https://example.org/feeds/large")
}
