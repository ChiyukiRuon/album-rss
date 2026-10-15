import Foundation

/// 服务类型：Miniflux 原生 API，或 Google Reader 兼容协议
public enum ServiceKind: String, Codable, Sendable, CaseIterable {
  case miniflux
  case greader
}

public struct Folder: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var title: String

  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}

public struct Feed: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var title: String
  /// 订阅的显示名（画师名）；服务没有单独的作者字段，与标题相同
  public var author: String
  /// 网站地址；无效时为空字符串
  public var siteURL: String
  public var iconURL: String
  public var folderIds: [String]
  /// 最近一次抓取时间；服务不提供时为空
  public var checkedAt: Date?
  public var parsingErrorCount: Int
  public var parsingError: String?

  public init(
    id: String,
    title: String,
    author: String,
    siteURL: String = "",
    iconURL: String = "",
    folderIds: [String] = [],
    checkedAt: Date? = nil,
    parsingErrorCount: Int = 0,
    parsingError: String? = nil
  ) {
    self.id = id
    self.title = title
    self.author = author
    self.siteURL = siteURL
    self.iconURL = iconURL
    self.folderIds = folderIds
    self.checkedAt = checkedAt
    self.parsingErrorCount = parsingErrorCount
    self.parsingError = parsingError
  }
}

public struct ImageAsset: Codable, Hashable, Sendable, Identifiable {
  /// 去重与缓存用的键，目前就是规范化后的地址
  public var key: String
  public var url: String
  public var width: Double?
  public var height: Double?
  public var alt: String?

  public var id: String { key }

  public init(key: String, url: String, width: Double? = nil, height: Double? = nil, alt: String? = nil) {
    self.key = key
    self.url = url
    self.width = width
    self.height = height
    self.alt = alt
  }
}

/// 图片解析状态：有图、确认无图、尚未解析
public enum ImageParseState: String, Codable, Sendable {
  case ready
  case none
  case pending
}

public struct Entry: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var feedId: String
  public var title: String
  public var author: String
  public var url: String
  public var publishedAt: Date
  public var paragraphs: [String]
  public var tags: [String]
  public var images: [ImageAsset]
  public var parseState: ImageParseState
  public var read: Bool
  public var starred: Bool

  public init(
    id: String,
    feedId: String,
    title: String,
    author: String,
    url: String,
    publishedAt: Date,
    paragraphs: [String] = [],
    tags: [String] = [],
    images: [ImageAsset] = [],
    parseState: ImageParseState = .none,
    read: Bool = false,
    starred: Bool = false
  ) {
    self.id = id
    self.feedId = feedId
    self.title = title
    self.author = author
    self.url = url
    self.publishedAt = publishedAt
    self.paragraphs = paragraphs
    self.tags = tags
    self.images = images
    self.parseState = parseState
    self.read = read
    self.starred = starred
  }

  /// 有可显示的图片（列表默认只显示这类文章）
  public var hasImages: Bool { parseState == .ready && !images.isEmpty }
}

public struct Enclosure: Codable, Hashable, Sendable {
  public var url: String
  public var mimeType: String

  public init(url: String, mimeType: String) {
    self.url = url
    self.mimeType = mimeType
  }
}

/// 服务返回的文章：正文还没解析成图片和段落
public struct RemoteEntry: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var feedId: String
  public var title: String
  public var author: String
  public var url: String
  public var publishedAt: Date
  public var content: String
  public var enclosures: [Enclosure]
  public var tags: [String]
  public var read: Bool
  public var starred: Bool

  public init(
    id: String,
    feedId: String,
    title: String = "",
    author: String = "",
    url: String = "",
    publishedAt: Date = Date(timeIntervalSince1970: 0),
    content: String = "",
    enclosures: [Enclosure] = [],
    tags: [String] = [],
    read: Bool = false,
    starred: Bool = false
  ) {
    self.id = id
    self.feedId = feedId
    self.title = title
    self.author = author
    self.url = url
    self.publishedAt = publishedAt
    self.content = content
    self.enclosures = enclosures
    self.tags = tags
    self.read = read
    self.starred = starred
  }
}

public struct Subscriptions: Sendable, Equatable {
  public var folders: [Folder]
  public var feeds: [Feed]

  public init(folders: [Folder], feeds: [Feed]) {
    self.folders = folders
    self.feeds = feeds
  }
}

/// 文章列表的查询范围；不带条件即全部订阅的全部文章
public struct EntryScope: Hashable, Sendable {
  public var feedId: String?
  public var folderId: String?
  public var unread: Bool
  public var starred: Bool

  public init(feedId: String? = nil, folderId: String? = nil, unread: Bool = false, starred: Bool = false) {
    self.feedId = feedId
    self.folderId = folderId
    self.unread = unread
    self.starred = starred
  }
}

/// 一页文章，新的在前；cursor 为 nil 表示已经到底
public struct EntryPage: Sendable, Equatable {
  public var entries: [RemoteEntry]
  public var cursor: String?

  public init(entries: [RemoteEntry], cursor: String?) {
    self.entries = entries
    self.cursor = cursor
  }
}
