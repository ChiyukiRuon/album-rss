import Foundation
import SwiftSoup

/// 把服务返回的正文解析成图片和段落，规则与 Web 端 `apps/web/src/lib/parseEntry.ts` 逐条对应，
/// 两端用 `contracts/fixtures/media` 里的同一组样例校验。正文不会被执行或渲染。
public enum EntryParser {
  /// 提取规则变化时递增；本地缓存的文章版本较旧时会重新解析
  public static let version = 2

  /// 解析时整体忽略的元素：它们的图片和文字都不算
  private static let removedTags: Set<String> = [
    "script", "style", "iframe", "object", "embed", "svg", "noscript",
    // 浏览器里 template 的内容不在文档树中，querySelectorAll 与 textContent 都碰不到
    "template",
  ]
  /// 末尾补一个换行、各自成段的元素
  private static let blockTags: Set<String> = [
    "p", "div", "li", "blockquote", "h1", "h2", "h3", "figcaption",
  ]

  @concurrent
  public static func parseAll(_ remotes: [RemoteEntry], server: String, mediaOrigin: String?) async -> [Entry] {
    remotes.map { parse($0, server: server, mediaOrigin: mediaOrigin) }
  }

  public static func parse(_ remote: RemoteEntry, server: String, mediaOrigin: String?) -> Entry {
    var images: [ImageAsset] = []
    var seen = Set<String>()
    let base = remote.url.isEmpty ? server : remote.url

    func add(_ value: String, width: Double? = nil, height: Double? = nil, alt: String? = nil, kind: String? = nil, poster: String? = nil) {
      let url = mediaURL(value, base: base, server: server, mediaOrigin: mediaOrigin)
      if url.isEmpty || seen.contains(url) { return }
      // 追踪像素：宽高都已知且都不超过 2。不记入 seen，之后同一地址的正常图片仍然保留
      if let width, let height, width <= 2, height <= 2 { return }
      seen.insert(url)
      images.append(ImageAsset(key: url, url: url, width: width, height: height, alt: alt, kind: kind, poster: poster))
    }

    var text = ""
    // HTML 解析前，浏览器会把 \r\n 和单独的 \r 统一成 \n
    let html = remote.content
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    if !html.isEmpty, let body = try? SwiftSoup.parseBodyFragment(html).body() {
      var ancestors: [Element] = []
      walk(body, ancestors: &ancestors, text: &text) { image, ancestors in
        if image.tagNameNormal() == "video" {
          let sources = (try? image.select("source").array()) ?? []
          let candidates = [attribute(image, "src"), attribute(image, "data-src")] + sources.map { attribute($0, "src") }
          if let value = candidates.first(where: { !mediaURL($0, base: base, server: server, mediaOrigin: mediaOrigin).isEmpty }) {
            let poster = mediaURL(attribute(image, "poster"), base: base, server: server, mediaOrigin: mediaOrigin)
            add(value, width: dimension(attribute(image, "width")), height: dimension(attribute(image, "height")),
              kind: "video", poster: poster.isEmpty ? nil : poster)
          }
          return
        }
        let picture = ancestors.last { $0.tagNameNormal() == "picture" }
        let source = picture.flatMap { firstDescendant(of: $0) { $0.tagNameNormal() == "source" && $0.hasAttr("srcset") } }
        let value = firstNonEmpty([
          attribute(image, "data-original"),
          attribute(image, "data-src"),
          attribute(image, "data-lazy-src"),
          bestSrcset(attribute(image, "data-srcset")),
          bestSrcset(attribute(image, "srcset")),
          bestSrcset(source.map { attribute($0, "srcset") } ?? ""),
          attribute(image, "src"),
        ])
        let figure = ancestors.last { $0.tagNameNormal() == "figure" }
        let caption = figure.flatMap { firstDescendant(of: $0) { $0.tagNameNormal() == "figcaption" } }
        let alt = firstNonEmpty([attribute(image, "alt"), caption.map(textContent) ?? ""])
        add(
          value,
          width: dimension(attribute(image, "width")),
          height: dimension(attribute(image, "height")),
          alt: alt.isEmpty ? nil : alt
        )
      }
    }
    for enclosure in remote.enclosures {
      if enclosure.mimeType.lowercased().hasPrefix("image/") { add(enclosure.url) }
      if enclosure.mimeType.lowercased().hasPrefix("video/") { add(enclosure.url, kind: "video") }
    }

    let paragraphs = text.unicodeScalars
      .split(separator: "\n")
      .map { JSText.trim(String(String.UnicodeScalarView($0))) }
      .filter { !$0.isEmpty }

    return Entry(
      id: remote.id,
      feedId: remote.feedId,
      title: remote.title,
      author: remote.author,
      url: remote.url,
      publishedAt: remote.publishedAt,
      paragraphs: paragraphs,
      tags: remote.tags,
      images: images,
      parseState: images.isEmpty ? .none : .ready,
      read: remote.read,
      starred: remote.starred
    )
  }

  /// 按文档顺序遍历：遇到 img 时回调，同时拼出 Web 端修改后（br 换行、块元素补换行）的 textContent
  private static func walk(
    _ node: Node,
    ancestors: inout [Element],
    text: inout String,
    onImage: (Element, [Element]) -> Void
  ) {
    for child in node.getChildNodes() {
      if let textNode = child as? TextNode {
        text += textNode.getWholeText()
        continue
      }
      guard let element = child as? Element else { continue }
      let tag = element.tagNameNormal()
      if removedTags.contains(tag) { continue }
      if tag == "br" {
        text += "\n"
        continue
      }
      if tag == "img" || tag == "video" { onImage(element, ancestors) }
      ancestors.append(element)
      walk(element, ancestors: &ancestors, text: &text, onImage: onImage)
      ancestors.removeLast()
      if blockTags.contains(tag) { text += "\n" }
    }
  }

  /// 原始的 textContent：不规整空白，跳过被忽略的元素
  private static func textContent(_ node: Node) -> String {
    var out = ""
    for child in node.getChildNodes() {
      if let textNode = child as? TextNode {
        out += textNode.getWholeText()
      } else if let element = child as? Element, !removedTags.contains(element.tagNameNormal()) {
        out += textContent(element)
      }
    }
    return out
  }

  private static func firstDescendant(of element: Element, where match: (Element) -> Bool) -> Element? {
    for child in element.getChildNodes() {
      guard let child = child as? Element, !removedTags.contains(child.tagNameNormal()) else { continue }
      if match(child) { return child }
      if let found = firstDescendant(of: child, where: match) { return found }
    }
    return nil
  }

  private static func attribute(_ element: Element, _ name: String) -> String {
    (try? element.attr(name)) ?? ""
  }

  /// JS 的 `a || b || c`：取第一个非空串
  private static func firstNonEmpty(_ values: [String]) -> String {
    values.first { !$0.isEmpty } ?? ""
  }

  /// srcset 里描述值最大的地址（"800w" 与 "2x" 都按数字比较），并列时取靠前的
  static func bestSrcset(_ value: String) -> String {
    var best: (url: String, size: Double)?
    for item in value.split(separator: ",", omittingEmptySubsequences: false) {
      let parts = JSText.splitWhitespace(JSText.trim(String(item)))
      let url = parts.first ?? ""
      let size = parts.count > 1 ? (JSText.parseFloat(parts[1]) ?? 0) : 0
      let normalized = size.isNaN ? 0 : size
      if best == nil || normalized > best!.size { best = (url, normalized) }
    }
    return best?.url ?? ""
  }

  private static func dimension(_ value: String) -> Double? {
    guard let number = JSText.number(value), number.isFinite, number > 0 else { return nil }
    return number
  }
}
