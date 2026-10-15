import Foundation

struct ChangeKey: Hashable, Sendable {
  var endpointID: String
  var entryID: String
  var field: EntryField
}

/// 已读、收藏的待发送队列：本地先更新，再按“期望值”串行写入服务。
/// 同一文章同一字段的连续操作合并成最后的目标值；目标值等于服务端已确认的值时直接丢弃。
struct WriteQueue {
  /// 还没确认写入服务的改动
  var changes: [ChangeKey: (change: PendingChange, revision: Int)] = [:]
  /// 每次本地操作的序号；同步结果只在它之后才会覆盖本地值
  var revision = 0
  var lastChanges: [ChangeKey: Int] = [:]
  /// 正在发送的改动及发送时的序号
  var inFlight: [ChangeKey: Int] = [:]
  /// 凭据失效而暂停的端点
  var paused: Set<String> = []
  /// 网络问题后各端点的连续失败次数与下次重试时间：一个端点暂时不可用，不影响其他端点的写入
  var failures: [String: Int] = [:]
  var retryAt: [String: ContinuousClock.Instant] = [:]
  /// 二分定位出错文章时，先发送这些批次
  var split: [[ChangeKey]] = []
  /// 发送循环；为空表示没有在发送
  var flushTask: Task<Void, Never>?
  /// 正在发送的那一批，以及它属于哪个端点
  var sending: Task<Void, Never>?
  var sendingEndpoint: String?

  func change(_ key: ChangeKey) -> PendingChange? { changes[key]?.change }

  mutating func forget(endpointID: String) {
    changes = changes.filter { $0.key.endpointID != endpointID }
    lastChanges = lastChanges.filter { $0.key.endpointID != endpointID }
    inFlight = inFlight.filter { $0.key.endpointID != endpointID }
    split = split.map { $0.filter { $0.endpointID != endpointID } }.filter { !$0.isEmpty }
    paused.remove(endpointID)
    failures[endpointID] = nil
    retryAt[endpointID] = nil
  }
}

extension AlbumStore {
  public func setRead(_ ids: [String], _ read: Bool) {
    mutate(ids, .read, read)
  }

  public func setStarred(_ id: String, _ starred: Bool) {
    mutate([id], .starred, starred)
  }

  func mutate(_ ids: [String], _ field: EntryField, _ value: Bool) {
    guard let endpoint else { return }
    queue.revision += 1
    let serial = queue.revision
    var upserts: [PendingChange] = []
    var deletes: [(entryID: String, field: EntryField)] = []
    for id in ids {
      let key = ChangeKey(endpointID: endpoint.id, entryID: id, field: field)
      let current = entries[id]?[field] ?? false
      var change = queue.change(key)
        ?? PendingChange(entryID: id, field: field, value: value, confirmed: current, feedID: entries[id]?.feedId ?? "")
      change.value = value
      queue.lastChanges[key] = serial
      if change.value == change.confirmed && queue.inFlight[key] == nil {
        queue.changes[key] = nil
        deletes.append((id, field))
      } else {
        queue.changes[key] = (change, serial)
        upserts.append(change)
      }
    }
    patchEntries(ids, field, value)
    if persists(endpoint), let database = environment.database {
      let endpointID = endpoint.id
      Task { try? await database.saveChanges(endpointID, upsert: upserts, delete: deletes) }
    }
    updatePendingCount()
    schedulePersist()
    flushWrites()
  }

  /// 改动文章；已读状态变化时一并调整未读计数
  static func patch(
    entries: inout [String: Entry],
    unread: inout [String: Int]?,
    _ ids: [String],
    _ field: EntryField,
    _ value: Bool
  ) {
    for id in ids {
      guard var entry = entries[id], entry[field] != value else { continue }
      entry[field] = value
      entries[id] = entry
      if field == .read, var counts = unread {
        counts[entry.feedId] = max(0, (counts[entry.feedId] ?? 0) + (value ? -1 : 1))
        unread = counts
      }
    }
  }

  func patchEntries(_ ids: [String], _ field: EntryField, _ value: Bool) {
    var nextEntries = entries
    var nextUnread = unread
    Self.patch(entries: &nextEntries, unread: &nextUnread, ids, field, value)
    if nextEntries != entries { entries = nextEntries }
    if nextUnread != unread { unread = nextUnread }
  }

  /// 改动某个端点的文章：正在使用时改页面状态，否则改它的缓存
  func patchEndpoint(_ endpointID: String, _ ids: [String], _ field: EntryField, _ value: Bool) {
    if endpoint?.id == endpointID {
      patchEntries(ids, field, value)
    } else if var data = cache[endpointID] {
      Self.patch(entries: &data.entries, unread: &data.unread, ids, field, value)
      cache[endpointID] = data
    }
  }

  /// 服务端的未读计数还不包含待发送的已读改动，按改动修正
  func adjustedUnread(_ counts: [String: Int]?, endpointID: String) -> [String: Int]? {
    guard var counts else { return nil }
    for (key, item) in queue.changes where key.endpointID == endpointID && key.field == .read {
      let change = item.change
      guard change.value != change.confirmed else { continue }
      counts[change.feedID] = max(0, (counts[change.feedID] ?? 0) + (change.value ? -1 : 1))
    }
    return counts
  }

  func updatePendingCount() {
    let id = endpoint?.id
    let count = queue.changes.keys.count { $0.endpointID == id }
    if pendingWrites != count { pendingWrites = count }
  }

  /// 启动时读回各端点未发送的改动
  func restoreChanges() async {
    guard let database = environment.database else { return }
    for endpoint in endpoints where endpoint.remember {
      guard let changes = try? await database.loadChanges(endpoint.id) else { continue }
      for change in changes {
        queue.revision += 1
        queue.changes[ChangeKey(endpointID: endpoint.id, entryID: change.entryID, field: change.field)] = (
          change, queue.revision
        )
      }
    }
    updatePendingCount()
  }

  /// 开始（或继续）发送；回到前台、网络恢复、重新连接后都会调用
  public func flushWrites() {
    guard queue.flushTask == nil else { return }
    queue.flushTask = Task { [weak self] in
      await self?.flushLoop()
      self?.queue.flushTask = nil
    }
  }

  /// 立即重试积压的写入（回到前台、网络可能已经恢复），不再等待退避时间
  public func retryWrites() {
    queue.failures = [:]
    queue.retryAt = [:]
    flushWrites()
  }

  /// 这个端点正在发送的那一批；同步只等它，不等整个积压，也不等其他端点
  func waitForInFlightWrite(endpointID: String) async {
    guard queue.sendingEndpoint == endpointID else { return }
    await queue.sending?.value
  }

  private func flushLoop() async {
    while let batch = nextBatch() {
      guard let target = endpointFor(batch.endpointID) else {
        queue.forget(endpointID: batch.endpointID)
        continue
      }
      for key in batch.keys { queue.inFlight[key] = queue.changes[key]?.revision ?? queue.revision }
      let sent = batch.keys.compactMap { key in queue.inFlight[key].map { (key, $0) } }
      let sending = Task { () -> (any Error)? in
        do {
          let provider = try self.provider(for: target)
          let ids = batch.keys.map(\.entryID)
          if batch.field == .read {
            try await provider.setRead(ids, read: batch.value)
          } else {
            for id in ids { try await provider.setStarred(id, starred: batch.value) }
          }
          return nil
        } catch {
          return error
        }
      }
      queue.sending = Task { _ = await sending.value }
      queue.sendingEndpoint = target.id
      let failure = await sending.value
      queue.sending = nil
      queue.sendingEndpoint = nil
      for (key, _) in sent { queue.inFlight[key] = nil }
      let proceed: Bool
      if let failure {
        proceed = handleFailure(failure, batch: batch, sent: sent, target: target)
      } else {
        confirm(batch, sent: sent, endpointID: target.id)
        proceed = true
      }
      dropSettled(sent.map(\.0), endpoint: target)
      if !proceed { break }
    }
  }

  /// 发送期间又改回了服务端的值：这项改动已经没有意义
  private func dropSettled(_ keys: [ChangeKey], endpoint target: Endpoint) {
    var deletes: [(entryID: String, field: EntryField)] = []
    for key in keys {
      guard let item = queue.changes[key], queue.inFlight[key] == nil, item.change.value == item.change.confirmed else {
        continue
      }
      queue.changes[key] = nil
      deletes.append((key.entryID, key.field))
    }
    guard !deletes.isEmpty else { return }
    if persists(target), let database = environment.database {
      let id = target.id
      Task { try? await database.saveChanges(id, upsert: [], delete: deletes) }
    }
    updatePendingCount()
  }

  private struct Batch {
    var endpointID: String
    var field: EntryField
    var value: Bool
    var keys: [ChangeKey]
  }

  private func endpointFor(_ id: String) -> Endpoint? {
    if id == Endpoint.demoID { return endpoint?.isDemo == true ? endpoint : nil }
    return endpoints.first { $0.id == id }
  }

  /// 下一批：先发二分出来的批次；否则按“端点 + 字段 + 目标值”分组，已读每批最多 500 篇，收藏每次一篇
  private func nextBatch() -> Batch? {
    while let keys = queue.split.first {
      queue.split.removeFirst()
      let live = keys.filter { queue.changes[$0] != nil && queue.inFlight[$0] == nil }
      if let first = live.first, let change = queue.change(first) {
        return Batch(endpointID: first.endpointID, field: first.field, value: change.value, keys: live)
      }
    }
    let now = ContinuousClock.now
    let candidates = queue.changes
      .filter { item in
        let id = item.key.endpointID
        return queue.inFlight[item.key] == nil && !queue.paused.contains(id) && (queue.retryAt[id].map { $0 <= now } ?? true)
      }
      .sorted { $0.value.revision < $1.value.revision }
    guard let first = candidates.first else { return nil }
    let key = first.key
    let value = first.value.change.value
    if key.field == .starred {
      return Batch(endpointID: key.endpointID, field: .starred, value: value, keys: [key])
    }
    let keys = candidates.lazy
      .filter { $0.key.endpointID == key.endpointID && $0.key.field == .read && $0.value.change.value == value }
      .prefix(500).map(\.key)
    return Batch(endpointID: key.endpointID, field: .read, value: value, keys: Array(keys))
  }

  private func confirm(_ batch: Batch, sent: [(ChangeKey, Int)], endpointID: String) {
    queue.failures[endpointID] = nil
    queue.retryAt[endpointID] = nil
    // 服务刚确认的值比进行中的同步可能读到的旧值更新：记下序号，合并时保留本地值
    queue.revision += 1
    for (key, _) in sent { queue.lastChanges[key] = queue.revision }
    var upserts: [PendingChange] = []
    var deletes: [(entryID: String, field: EntryField)] = []
    for (key, revision) in sent {
      guard var item = queue.changes[key] else { continue }
      item.change.confirmed = batch.value
      if item.revision == revision || item.change.value == item.change.confirmed {
        queue.changes[key] = nil
        deletes.append((key.entryID, key.field))
      } else {
        // 发送期间又改了：服务端现在是发送的值，新目标值稍后再发
        queue.changes[key] = item
        upserts.append(item.change)
      }
    }
    if let target = endpointFor(endpointID), persists(target), let database = environment.database {
      Task { try? await database.saveChanges(endpointID, upsert: upserts, delete: deletes) }
    }
    updatePendingCount()
  }

  /// 返回是否继续发送后面的批次
  private func handleFailure(_ error: any Error, batch: Batch, sent: [(ChangeKey, Int)], target: Endpoint) -> Bool {
    let api = error as? APIError
    if error is CancellationError { return false }
    if api?.isTransient == true {
      // 网络或服务暂时不可用：保留改动，这个端点退避后重试，其他端点照常发送
      let id = target.id
      let failures = (queue.failures[id] ?? 0) + 1
      queue.failures[id] = failures
      let delay = min(120.0, 5.0 * pow(2.0, Double(failures - 1)))
      queue.retryAt[id] = ContinuousClock.now + .seconds(delay)
      Task { [weak self, sleep = environment.sleep] in
        try? await sleep(.seconds(delay))
        guard let self, let retry = self.queue.retryAt[id], retry <= ContinuousClock.now else { return }
        self.queue.retryAt[id] = nil
        self.flushWrites()
      }
      return true
    }
    if api?.isUnauthorized == true {
      queue.paused.insert(target.id)
      writeErrors[target.id] = api?.message ?? errorMessage(error)
      return true
    }
    if batch.keys.count > 1 {
      // 先二分定位被拒绝的文章，其余的照常写入
      let half = batch.keys.count / 2
      queue.split.insert(contentsOf: [Array(batch.keys[..<half]), Array(batch.keys[half...])], at: 0)
      return true
    }
    reject(sent, endpoint: target, value: batch.value, field: batch.field, error: error)
    return true
  }

  /// 服务拒绝了这项改动：恢复最后确认的状态并提示
  private func reject(_ sent: [(ChangeKey, Int)], endpoint target: Endpoint, value: Bool, field: EntryField, error: any Error) {
    // 端点在发送期间被删除：改动随端点一起放弃，不再写入它的数据库或提示
    guard endpointFor(target.id) != nil else { return }
    var deletes: [(entryID: String, field: EntryField)] = []
    var reverted: [String] = []
    for (key, revision) in sent {
      guard let item = queue.changes[key] else { continue }
      if item.revision == revision {
        queue.changes[key] = nil
        deletes.append((key.entryID, key.field))
        patchEndpoint(target.id, [key.entryID], field, item.change.confirmed)
        reverted.append(key.entryID)
      }
    }
    if persists(target), let database = environment.database {
      let id = target.id
      Task { try? await database.saveChanges(id, upsert: [], delete: deletes) }
    }
    updatePendingCount()
    let active = endpoint?.id == target.id
    if active { listVersion += 1 }
    toasts.show(
      active ? "状态未能保存到服务器" : "「\(target.label)」的状态未能保存",
      detail: errorMessage(error),
      tone: .warning,
      action: active && !reverted.isEmpty
        ? ToastCenter.Action(label: "重试") { [weak self] in self?.mutate(reverted, field, value) } : nil
    )
  }
}
