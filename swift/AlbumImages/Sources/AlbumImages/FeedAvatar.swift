import AlbumCore
import Foundation

/// 同一订阅的多个头像视图共用一次 RSS 请求；短期缓存也包含取不到头像的情况。
public actor FeedAvatar {
  public static let shared = FeedAvatar()
  private var cache: [String: (until: Date, task: Task<String?, Never>)] = [:]
  private let session: URLSession

  private init() {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.httpShouldSetCookies = false
    config.urlCredentialStorage = nil
    config.timeoutIntervalForResource = 10
    session = URLSession(configuration: config)
  }

  public func originalURL(for source: String) async -> String? {
    guard !httpURL(source).isEmpty, let url = URL(string: source) else { return nil }
    let now = Date()
    if let cached = cache[source], cached.until > now { return await cached.task.value }
    cache = cache.filter { $0.value.until > now }
    let task = Task<String?, Never> { [session] in
      guard let (data, response) = try? await session.data(from: url),
        let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
      else { return nil }
      return ChannelImageParser.image(in: data, base: response.url?.absoluteString ?? source)
    }
    cache[source] = (now.addingTimeInterval(900), task)
    return await task.value
  }
}

final class ChannelImageParser: NSObject, XMLParserDelegate {
  private var path: [String] = []
  private var text = ""
  private var image = ""
  private var icon = ""

  static func image(in data: Data, base: String) -> String? {
    let parser = XMLParser(data: data)
    let reader = ChannelImageParser()
    parser.delegate = reader
    parser.shouldProcessNamespaces = true
    parser.shouldResolveExternalEntities = false
    guard parser.parse() else { return nil }
    let result = httpURL(reader.image.isEmpty ? reader.icon : reader.image, base: base)
    return result.isEmpty ? nil : result
  }

  func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
    path.append(elementName)
    text = ""
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if isImageElement { text += string }
  }

  func parser(_ parser: XMLParser, foundCDATA data: Data) {
    if isImageElement { text += String(decoding: data, as: UTF8.self) }
  }

  private var isImageElement: Bool {
    path == ["rss", "channel", "image", "url"] || path == ["feed", "logo"] || path == ["feed", "icon"]
  }

  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
    if isImageElement {
      let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if elementName == "icon" { icon = value } else { image = value }
    }
    path.removeLast()
  }
}
