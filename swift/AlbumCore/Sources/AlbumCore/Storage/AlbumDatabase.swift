import Foundation
import GRDB
import Synchronization

/// 已读或收藏这两个可以写回服务的字段
public enum EntryField: String, Codable, Sendable, CaseIterable {
  case read
  case starred
}

extension Entry {
  public subscript(field: EntryField) -> Bool {
    get { field == .read ? read : starred }
    set {
      if field == .read { read = newValue } else { starred = newValue }
    }
  }
}

/// 一条还没确认写入服务的本地改动：记录期望值，而不是“切换”
public struct PendingChange: Codable, Equatable, Sendable {
  public var entryID: String
  public var field: EntryField
  public var value: Bool
  /// 最后一次确认的服务端值；放弃改动时恢复成它
  public var confirmed: Bool
  /// 用来在同步后修正未读计数
  public var feedID: String

  public init(entryID: String, field: EntryField, value: Bool, confirmed: Bool, feedID: String) {
    self.entryID = entryID
    self.field = field
    self.value = value
    self.confirmed = confirmed
    self.feedID = feedID
  }
}

/// 图片尺寸测量结果，重启后瀑布流可以直接放置卡片
public struct StoredImageSize: Codable, Equatable, Sendable {
  public var width: Double
  public var height: Double
  public var failed: Bool

  public init(width: Double, height: Double, failed: Bool) {
    self.width = width
    self.height = height
    self.failed = failed
  }
}

/// 一个端点保存在本地的内容
struct StoredSnapshot: Sendable {
  var folders: [Folder]
  var feeds: [Feed]
  var entries: [Entry]
  var scopes: [ScopeState]
  var unread: [String: Int]?
  var lastSyncedAt: Date
}

/// 写入时的端点状态：分类、订阅、列表、计数，以及各文章的已读与收藏
struct StoredState: Sendable {
  var folders: [Folder]
  var feeds: [Feed]
  var scopes: [ScopeState]
  var unread: [String: Int]?
  var lastSyncedAt: Date
  var states: [(id: String, read: Bool, starred: Bool)]
  /// 不在列表里但需要保留的文章（后台同步拿到、还没放进列表的新文章）
  var keep: [String] = []
}

/// 本地数据库：每个端点一个 SQLite 文件，删除端点时整个文件一起删掉
public final class AlbumDatabase: Sendable {
  /// 每个列表最多保存的页数；更早的内容重启后按需重新读取
  static let persistedPages = 3

  private let directory: URL?
  private let queues = Mutex<[String: DatabaseQueue]>([:])

  /// directory 为 nil 时使用内存数据库（测试）
  public init(directory: URL?) throws {
    self.directory = directory
    if let directory {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
  }

  private func fileURL(_ endpointID: String) -> URL? {
    let safe = endpointID.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" ? String($0) : "_" }
      .joined()
    return directory?.appending(path: "\(safe).sqlite")
  }

  func queue(_ endpointID: String) throws -> DatabaseQueue {
    try queues.withLock { queues in
      if let queue = queues[endpointID] { return queue }
      var configuration = Configuration()
      configuration.label = "album-rss.\(endpointID)"
      let queue: DatabaseQueue
      if let url = fileURL(endpointID) {
        queue = try DatabaseQueue(path: url.path, configuration: configuration)
      } else {
        queue = try DatabaseQueue(configuration: configuration)
      }
      try Self.migrator.migrate(queue)
      queues[endpointID] = queue
      return queue
    }
  }

  /// 删除端点的全部本地数据
  public func removeEndpoint(_ endpointID: String) {
    _ = queues.withLock { $0.removeValue(forKey: endpointID) }
    guard let url = fileURL(endpointID) else { return }
    for suffix in ["", "-wal", "-shm"] {
      try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
    }
  }

  /// 清理不再对应任何端点的数据库文件（例如连接中途取消、或上一次安装遗留的）
  public func removeUnknownEndpoints(keeping ids: Set<String>) {
    guard let directory,
      let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    else { return }
    let keep = Set(ids.compactMap { fileURL($0)?.lastPathComponent })
    for file in files where file.pathExtension == "sqlite" && !keep.contains(file.lastPathComponent) {
      let path = file.path
      for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
    }
  }

  private static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1") { db in
      try db.create(table: "meta") { t in
        t.primaryKey("key", .text)
        t.column("value", .blob)
      }
      try db.create(table: "folder") { t in
        t.primaryKey("id", .text)
        t.column("position", .integer).notNull()
        t.column("data", .blob).notNull()
      }
      try db.create(table: "feed") { t in
        t.primaryKey("id", .text)
        t.column("position", .integer).notNull()
        t.column("data", .blob).notNull()
      }
      try db.create(table: "entry") { t in
        t.primaryKey("id", .text)
        t.column("feedID", .text).notNull()
        t.column("read", .boolean).notNull()
        t.column("starred", .boolean).notNull()
        t.column("parserVersion", .integer).notNull()
        // 原始正文：解析规则变化时据此重新解析，不必重新请求
        t.column("remote", .blob).notNull()
        t.column("parsed", .blob).notNull()
      }
      try db.create(table: "scope") { t in
        t.primaryKey("key", .text)
        t.column("position", .integer).notNull()
        t.column("data", .blob).notNull()
      }
      try db.create(table: "change") { t in
        t.column("entryID", .text).notNull()
        t.column("field", .text).notNull()
        t.column("data", .blob).notNull()
        t.primaryKey(["entryID", "field"])
      }
      try db.create(table: "imageSize") { t in
        t.primaryKey("url", .text)
        t.column("data", .blob).notNull()
      }
    }
    return migrator
  }

  // MARK: 快照

  private struct StoredScope: Codable {
    var query: ListQuery
    var ids: [String]
    var cursor: String?
    var done: Bool
    var pages: [PageMark]
  }

  private struct Meta: Codable {
    var unread: [String: Int]?
    var lastSyncedAt: Date
  }

  /// 文章原文与解析结果；在合并服务端数据时写入
  func upsertEntries(_ endpointID: String, items: [(remote: RemoteEntry, entry: Entry)]) async throws {
    guard !items.isEmpty else { return }
    let encoder = JSONEncoder()
    let rows = try items.map { item in
      (
        item.entry.id, item.entry.feedId, item.entry.read, item.entry.starred,
        try encoder.encode(item.remote), try encoder.encode(item.entry)
      )
    }
    try await queue(endpointID).write { db in
      for row in rows {
        try db.execute(
          sql: """
            INSERT INTO entry (id, feedID, read, starred, parserVersion, remote, parsed)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET feedID = excluded.feedID, read = excluded.read,
              starred = excluded.starred, parserVersion = excluded.parserVersion,
              remote = excluded.remote, parsed = excluded.parsed
            """,
          arguments: [row.0, row.1, row.2, row.3, EntryParser.version, row.4, row.5]
        )
      }
    }
  }

  /// 写入端点状态；列表只保留前几页，之后删除不再被引用、也没有收藏或待发送改动的文章
  func saveState(_ endpointID: String, _ state: StoredState) async throws {
    let encoder = JSONEncoder()
    let folders = try state.folders.map { ($0.id, try encoder.encode($0)) }
    let feeds = try state.feeds.map { ($0.id, try encoder.encode($0)) }
    let scopes = try state.scopes.map { scope -> (String, Data, [String]) in
      let stored = Self.truncate(scope)
      return (scope.query.storageKey, try encoder.encode(stored), stored.ids)
    }
    let meta = try encoder.encode(Meta(unread: state.unread, lastSyncedAt: state.lastSyncedAt))
    let states = state.states
    let keep = Set(scopes.flatMap(\.2)).union(state.keep)
    try await queue(endpointID).write { db in
      try db.execute(sql: "DELETE FROM folder")
      for (index, folder) in folders.enumerated() {
        try db.execute(sql: "INSERT INTO folder (id, position, data) VALUES (?, ?, ?)", arguments: [folder.0, index, folder.1])
      }
      try db.execute(sql: "DELETE FROM feed")
      for (index, feed) in feeds.enumerated() {
        try db.execute(sql: "INSERT INTO feed (id, position, data) VALUES (?, ?, ?)", arguments: [feed.0, index, feed.1])
      }
      try db.execute(sql: "DELETE FROM scope")
      for (index, scope) in scopes.enumerated() {
        try db.execute(sql: "INSERT INTO scope (key, position, data) VALUES (?, ?, ?)", arguments: [scope.0, index, scope.1])
      }
      try db.execute(
        sql: "INSERT INTO meta (key, value) VALUES ('state', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        arguments: [meta]
      )
      for item in states {
        try db.execute(sql: "UPDATE entry SET read = ?, starred = ? WHERE id = ?", arguments: [item.read, item.starred, item.id])
      }
      // 只保留仍在列表里、已收藏或有待发送改动的文章
      try db.execute(sql: "CREATE TEMP TABLE IF NOT EXISTS keep (id TEXT PRIMARY KEY)")
      try db.execute(sql: "DELETE FROM keep")
      for id in keep {
        try db.execute(sql: "INSERT OR IGNORE INTO keep (id) VALUES (?)", arguments: [id])
      }
      try db.execute(
        sql: """
          DELETE FROM entry WHERE starred = 0
            AND id NOT IN (SELECT id FROM keep)
            AND id NOT IN (SELECT entryID FROM change)
          """
      )
    }
  }

  private static func truncate(_ scope: ScopeState) -> StoredScope {
    guard scope.pages.count > persistedPages, let mark = scope.pages.dropLast(scope.pages.count - persistedPages).last else {
      return StoredScope(query: scope.query, ids: scope.ids, cursor: scope.cursor, done: scope.done, pages: scope.pages)
    }
    return StoredScope(
      query: scope.query,
      ids: Array(scope.ids.prefix(mark.count)),
      cursor: mark.cursor,
      done: mark.cursor == nil,
      pages: Array(scope.pages.prefix(persistedPages))
    )
  }

  /// 读取端点的快照；解析器版本较旧的文章按原文重新解析
  func loadSnapshot(_ endpointID: String, server: String, mediaOrigin: String?, nextToken: @Sendable () -> Int)
    async throws -> StoredSnapshot?
  {
    let decoder = JSONDecoder()
    typealias StoredEntryRow = (read: Bool, starred: Bool, version: Int, remote: Data, parsed: Data)
    let raw = try await queue(endpointID).read { db -> (Data?, [Data], [Data], [Data], [StoredEntryRow]) in
      let meta = try Data.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'state'")
      let folders = try Data.fetchAll(db, sql: "SELECT data FROM folder ORDER BY position")
      let feeds = try Data.fetchAll(db, sql: "SELECT data FROM feed ORDER BY position")
      let scopes = try Data.fetchAll(db, sql: "SELECT data FROM scope ORDER BY position")
      let entries = try Row.fetchAll(db, sql: "SELECT read, starred, parserVersion, remote, parsed FROM entry").map {
        row -> StoredEntryRow in
        (row["read"], row["starred"], row["parserVersion"], row["remote"], row["parsed"])
      }
      return (meta, folders, feeds, scopes, entries)
    }
    guard let metaData = raw.0, let meta = try? decoder.decode(Meta.self, from: metaData) else { return nil }
    var outdated: [(remote: RemoteEntry, entry: Entry)] = []
    var entries: [Entry] = []
    for row in raw.4 {
      var entry: Entry
      if row.version == EntryParser.version, let parsed = try? decoder.decode(Entry.self, from: row.parsed) {
        entry = parsed
      } else if let remote = try? decoder.decode(RemoteEntry.self, from: row.remote) {
        entry = EntryParser.parse(remote, server: server, mediaOrigin: mediaOrigin)
        outdated.append((remote, entry))
      } else {
        continue
      }
      entry.read = row.read
      entry.starred = row.starred
      entries.append(entry)
    }
    if !outdated.isEmpty { try await upsertEntries(endpointID, items: outdated) }
    let scopes = raw.3.compactMap { try? decoder.decode(StoredScope.self, from: $0) }.map {
      ScopeState(
        query: $0.query, ids: $0.ids, cursor: $0.cursor, done: $0.done, token: nextToken(), pages: $0.pages,
        restored: true)
    }
    return StoredSnapshot(
      folders: raw.1.compactMap { try? decoder.decode(Folder.self, from: $0) },
      feeds: raw.2.compactMap { try? decoder.decode(Feed.self, from: $0) },
      entries: entries,
      scopes: scopes,
      unread: meta.unread,
      lastSyncedAt: meta.lastSyncedAt
    )
  }

  // MARK: 待发送改动

  func loadChanges(_ endpointID: String) async throws -> [PendingChange] {
    let decoder = JSONDecoder()
    return try await queue(endpointID).read { db in
      try Data.fetchAll(db, sql: "SELECT data FROM change").compactMap { try? decoder.decode(PendingChange.self, from: $0) }
    }
  }

  func saveChanges(_ endpointID: String, upsert: [PendingChange], delete: [(entryID: String, field: EntryField)])
    async throws
  {
    let encoder = JSONEncoder()
    let rows = try upsert.map { ($0.entryID, $0.field.rawValue, try encoder.encode($0)) }
    try await queue(endpointID).write { db in
      for key in delete {
        try db.execute(sql: "DELETE FROM change WHERE entryID = ? AND field = ?", arguments: [key.entryID, key.field.rawValue])
      }
      for row in rows {
        try db.execute(
          sql: """
            INSERT INTO change (entryID, field, data) VALUES (?, ?, ?)
            ON CONFLICT(entryID, field) DO UPDATE SET data = excluded.data
            """,
          arguments: [row.0, row.1, row.2]
        )
      }
    }
  }

  // MARK: 图片尺寸

  public func imageSizes(_ endpointID: String) async throws -> [String: StoredImageSize] {
    let decoder = JSONDecoder()
    let rows = try await queue(endpointID).read { db in
      try Row.fetchAll(db, sql: "SELECT url, data FROM imageSize").map { row -> (String, Data) in (row["url"], row["data"]) }
    }
    var sizes: [String: StoredImageSize] = [:]
    for (url, data) in rows {
      if let size = try? decoder.decode(StoredImageSize.self, from: data) { sizes[url] = size }
    }
    return sizes
  }

  public func saveImageSizes(_ endpointID: String, _ sizes: [String: StoredImageSize]) async throws {
    guard !sizes.isEmpty else { return }
    let encoder = JSONEncoder()
    let rows = try sizes.map { ($0.key, try encoder.encode($0.value)) }
    try await queue(endpointID).write { db in
      for row in rows {
        try db.execute(
          sql: "INSERT INTO imageSize (url, data) VALUES (?, ?) ON CONFLICT(url) DO UPDATE SET data = excluded.data",
          arguments: [row.0, row.1]
        )
      }
      // 只保留最近的一部分，避免无限增长
      try db.execute(sql: "DELETE FROM imageSize WHERE rowid NOT IN (SELECT rowid FROM imageSize ORDER BY rowid DESC LIMIT 20000)")
    }
  }
}
