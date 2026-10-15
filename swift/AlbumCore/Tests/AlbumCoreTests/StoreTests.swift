import Foundation
import Testing

@testable import AlbumCore

/// 移植自 Web 端 store.test.ts。写入改为持久化的合并队列后，
/// “连续操作失败”一类用例按新语义调整：只有被服务拒绝的改动才回滚，网络问题保留并重试。
@MainActor
@Suite(.serialized) struct EndpointTests {
  @Test func addsEditsSwitchesAndRemovesEndpointsWhilePersistingOnlyRememberedCredentials() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(with(input) { $0.remember = true; $0.name = "First" })
    let first = try #require(store.endpoint)
    store.setRead(["1"], true)
    try await store.connect(with(input) { $0.server = "https://second.example.com"; $0.name = "Second" })
    let second = try #require(store.endpoint)
    #expect(store.endpoints.count == 2)
    #expect(store.entries["1"]?.read == false)
    let saved = try JSONDecoder().decode(
      [Endpoint].self, from: #require(harness.defaults.data(forKey: AlbumStore.endpointsKey)))
    #expect(saved.map(\.id) == [first.id])
    try await store.connect(with(input) { $0.id = second.id; $0.name = "Edited" })
    #expect(store.endpoints.count == 2)
    #expect(store.endpoint?.name == "Edited")
    try await store.switchEndpoint(first.id)
    #expect(store.endpoint?.id == first.id)
    #expect(store.entries["1"]?.read == true)
    #expect(store.viewerSequence == nil)
    await store.removeEndpoint(second.id)
    #expect(store.endpoints.count == 1)
    await store.removeEndpoint(first.id)
    #expect(store.endpoint == nil)
    #expect(harness.defaults.data(forKey: AlbumStore.activeKey) == nil)
    let remaining = try JSONDecoder().decode(
      [Endpoint].self, from: #require(harness.defaults.data(forKey: AlbumStore.endpointsKey)))
    #expect(remaining.isEmpty)
    #expect(harness.credentials.token(for: first.id) == nil)
  }

  @Test func readsOnlySubscriptionsCountsAndTheFirstPageWhenConnecting() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    #expect(harness.provider.count("authenticate") == 1)
    #expect(harness.provider.count("subscriptions") == 1)
    #expect(harness.provider.count("unreadCounts") == 1)
    #expect(harness.provider.entriesCalls == [.init(scope: EntryScope(unread: true), cursor: nil, limit: 100)])
    #expect(store.order == ["1"])
    #expect(store.unread == ["2": 1])
  }

  @Test func switchesBackToAVisitedEndpointFromItsCacheWithoutRequests() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(with(input) { $0.name = "A" })
    let a = try #require(store.endpoint)
    harness.provider.entriesHandler = { _, _, _ in page(["7"]) }
    try await store.connect(with(input) { $0.server = "https://b.example.com"; $0.name = "B" })
    let b = try #require(store.endpoint)
    harness.provider.reset()
    try await store.switchEndpoint(a.id)
    #expect(store.order == ["1"])
    #expect(harness.provider.count("entries") == 0)
    #expect(harness.provider.count("subscriptions") == 0)
    // 缓存放久了：切回时立即显示，同时在后台检查新内容
    harness.clock.advance(61)
    try await store.switchEndpoint(b.id)
    #expect(store.order == ["7"])
    await waitUntil { harness.provider.count("subscriptions") == 1 }
  }

  @Test func keepsTheActiveEndpointAndPendingWritesWhenAddingAnotherFails() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    let original = store.endpoint
    let writing = Deferred<Void>()
    harness.provider.setReadHandler = { _, _ in try await writing.value() }
    store.setRead(["1"], true)
    await waitUntil { harness.provider.setReadCalls.count == 1 }
    harness.provider.onceEntries { _, _, _ in throw TestError("offline") }
    await #expect(throws: TestError.self) {
      try await store.connect(with(input) { $0.server = "https://offline.example.com" })
    }
    #expect(store.endpoint == original)
    #expect(store.endpoints.count == 1)
    // 服务拒绝写入：回滚到最后确认的状态
    writing.reject(TestError("write failed"))
    await waitUntil { store.entries["1"]?.read == false }
  }

  @Test func stillSendsWritesAfterSwitchingAndRollsFailuresBackIntoTheCachedEndpoint() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(with(input) { $0.name = "A" })
    let a = try #require(store.endpoint)
    let writing = Deferred<Void>()
    harness.provider.setReadHandler = { _, _ in try await writing.value() }
    store.setRead(["1"], true)
    #expect(store.unread == ["2": 0])
    try await store.connect(with(input) { $0.server = "https://b.example.com"; $0.name = "B" })
    await waitUntil { harness.provider.setReadCalls.contains { $0.0 == ["1"] && $0.1 } }
    writing.reject(TestError("write failed"))
    await waitUntil { store.toasts.toasts.contains { $0.message.contains("「A」") } }
    #expect(store.entries["1"]?.read == false)
    try await store.switchEndpoint(a.id)
    #expect(store.entries["1"]?.read == false)
    #expect(store.unread == ["2": 1])
  }

  @Test func switchesToTheNextEndpointWhenTheActiveOneIsRemoved() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(with(input) { $0.name = "A" })
    let a = try #require(store.endpoint)
    try await store.connect(with(input) { $0.server = "https://b.example.com"; $0.name = "B" })
    let b = try #require(store.endpoint)
    await store.removeEndpoint(b.id)
    #expect(store.endpoint?.id == a.id)
    #expect(store.endpoints.map(\.id) == [a.id])
  }

  @Test func restoresRememberedEndpointsOnRelaunch() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(with(input) { $0.remember = true })
    let firstID = store.endpoint?.id
    try await store.connect(with(input) { $0.remember = true; $0.server = "https://second.example.com" })
    let restored = harness.makeStore()
    #expect(restored.endpoints.count == 2)
    #expect(restored.endpoints.first?.id == firstID)
    #expect(restored.endpoint?.server == "https://second.example.com")
    #expect(restored.loaded == false)
  }

  @Test func persistsOnlyTheRememberedTokenAndNeverThePassword() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    #expect(try JSONDecoder().decode([Endpoint].self, from: #require(harness.defaults.data(forKey: AlbumStore.endpointsKey))).isEmpty)
    try await store.connect(with(input) { $0.remember = true })
    let raw = try #require(harness.defaults.data(forKey: AlbumStore.endpointsKey))
    let saved = try JSONDecoder().decode([Endpoint].self, from: raw)
    #expect(saved.first?.server == "https://example.com/rss")
    #expect(saved.first?.username == "reader")
    #expect(saved.first?.token == nil)
    let text = String(decoding: raw, as: UTF8.self)
    #expect(!text.contains(input.password))
    #expect(!text.contains("\"token\""))
    #expect(harness.credentials.token(for: try #require(saved.first?.id)) == "token")
    let restored = harness.makeStore()
    #expect(restored.endpoints.count == 1)
    await restored.removeEndpoint(try #require(store.endpoint?.id))
    #expect(restored.endpoint == nil)
    restored.enterDemo()
    await waitUntil { restored.order.count > 1 }
    #expect(restored.endpoint?.isDemo == true)
  }

  @Test func doesNotEstablishAnEndpointAfterAFailedInitialRead() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    harness.provider.onceEntries { _, _, _ in throw TestError("offline") }
    await #expect(throws: TestError.self) { try await store.connect(input) }
    #expect(store.endpoint == nil)
    #expect(harness.defaults.data(forKey: AlbumStore.activeKey) == nil)
  }

  @Test func clearsKeychainItemsLeftByAPreviousInstall() async throws {
    let harness = Harness()
    harness.credentials.setToken("stale", for: "old")
    _ = harness.makeStore()
    #expect(harness.credentials.token(for: "old") == nil)
    // 已安装过：不会再清理
    harness.credentials.setToken("kept", for: "next")
    _ = harness.makeStore()
    #expect(harness.credentials.token(for: "next") == "kept")
  }
}

@MainActor
@Suite(.serialized) struct ListTests {
  @Test func readsOlderPagesOnlyWhenAListAsksForThem() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    harness.provider.onceEntries { _, _, _ in page(["3", "2"], cursor: "2") }
    try await store.connect(input)
    #expect(store.scopes[unreadQuery]?.ids == ["3", "2"])
    #expect(store.scopes[unreadQuery]?.done == false)
    harness.provider.onceEntries { _, _, _ in page(["1"]) }
    await store.loadMore(unreadQuery).value
    #expect(harness.provider.entriesCalls.last == .init(scope: EntryScope(unread: true), cursor: "2", limit: 100))
    #expect(store.scopes[unreadQuery]?.ids == ["3", "2", "1"])
    #expect(store.scopes[unreadQuery]?.done == true)
    await store.loadMore(unreadQuery).value
    #expect(harness.provider.count("entries") == 2)
    await store.loadMore(ListQuery(status: .all, feedId: "2")).value
    #expect(harness.provider.entriesCalls.last == .init(scope: EntryScope(feedId: "2"), cursor: nil, limit: 100))
  }

  @Test func dropsAPageThatArrivesAfterTheListWasRefreshed() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    harness.provider.onceEntries { _, _, _ in page(["3"], cursor: "3") }
    try await store.connect(input)
    let older = Deferred<EntryPage>()
    harness.provider.onceEntries { _, _, _ in try await older.value() }
    let loading = store.loadMore(unreadQuery)
    await waitUntil { harness.provider.count("entries") == 2 }
    harness.provider.onceEntries { _, _, _ in page(["4", "3"], cursor: "3") }
    await store.sync(explicit: true)
    older.resolve(page(["2"]))
    await loading.value
    #expect(store.scopes[unreadQuery]?.ids == ["4", "3"])
  }

  @Test func countsNewArticlesInTheBackgroundUntilTheyAreApplied() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    harness.provider.onceEntries { _, _, _ in page(["9", "1"]) }
    await store.sync(explicit: false)
    #expect(store.sync.pendingIDs == ["9"])
    #expect(store.scopes[unreadQuery]?.ids == ["1"])
    store.applyPending()
    #expect(store.sync.pendingIDs.isEmpty)
    #expect(store.scopes[unreadQuery]?.ids == ["9", "1"])
  }

  @Test func marksEveryUnreadArticleOfAFeedIncludingUnloadedOnesWithUndo() async throws {
    let harness = Harness()
    harness.provider.unreadHandler = { ["2": 3] }
    let store = harness.makeStore()
    try await store.connect(input)
    harness.provider.onceEntries { _, _, _ in page(["1", "5"], cursor: "5") }
    harness.provider.onceEntries { _, _, _ in page(["6"]) }
    await store.markFeedRead(try #require(store.feeds.first))
    #expect(harness.provider.entriesCalls.last == .init(scope: EntryScope(feedId: "2", unread: true), cursor: "5", limit: 500))
    #expect(store.unread == ["2": 0])
    await waitUntil { harness.provider.setReadCalls.contains { Set($0.0) == ["1", "5", "6"] && $0.1 } }
    await waitUntil { store.pendingWrites == 0 }
    store.toasts.toasts.last?.action?.run()
    await waitUntil { harness.provider.setReadCalls.contains { Set($0.0) == ["1", "5", "6"] && !$0.1 } }
    #expect(store.unread == ["2": 3])
  }

  @Test func snapshotsAppendNewPagesAndIgnoreReadStateUntilReset() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    harness.provider.onceEntries { _, _, _ in page(["3", "2"], cursor: "2") }
    try await store.connect(input)
    var snapshot = store.snapshot(for: unreadQuery, previous: nil)
    #expect(snapshot.ids == ["3", "2"])
    store.setRead(["3"], true)
    let layout = snapshot.layoutID
    snapshot = store.snapshot(for: unreadQuery, previous: snapshot)
    // 看过的文章留在列表里，直到换了一份列表
    #expect(snapshot.ids == ["3", "2"])
    harness.provider.onceEntries { _, _, _ in page(["1"]) }
    await store.loadMore(unreadQuery).value
    snapshot = store.snapshot(for: unreadQuery, previous: snapshot)
    #expect(snapshot.ids == ["3", "2", "1"])
    #expect(snapshot.layoutID == layout)
    harness.provider.onceEntries { _, _, _ in page(["2", "1"]) }
    await store.sync(explicit: true)
    snapshot = store.snapshot(for: unreadQuery, previous: snapshot)
    #expect(snapshot.ids == ["2", "1"])
    #expect(snapshot.layoutID != layout)
  }
}

@MainActor
@Suite(.serialized) struct SyncTests {
  @Test func ignoresAPreviousEndpointResponseEvenWhenBothServicesUseTheSameIDs() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    let reading = Deferred<EntryPage>()
    harness.provider.onceEntries { _, _, _ in try await reading.value() }
    async let syncing: Void = store.sync(explicit: true)
    await waitUntil { harness.provider.count("entries") == 2 }
    try await store.connect(with(input) { $0.server = "https://second.example.com" })
    reading.resolve(EntryPage(entries: [remote("1", read: true)], cursor: nil))
    await syncing
    #expect(store.entries["1"]?.read == false)
    #expect(store.sync.status == .idle)
  }

  @Test func rapidOppositeWritesCoalesceIntoNothing() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    store.setRead(["1"], true)
    store.setRead(["1"], false)
    await store.sync(explicit: true)
    try await Task.sleep(for: .milliseconds(50))
    #expect(harness.provider.setReadCalls.isEmpty)
    #expect(store.entries["1"]?.read == false)
    #expect(store.pendingWrites == 0)
  }

  @Test func aChangeMadeWhileTheWriteIsInFlightIsSentAfterwards() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    let first = Deferred<Void>()
    harness.provider.setStarredHandler = { _, _ in try await first.value() }
    store.setStarred("1", true)
    await waitUntil { harness.provider.setStarredCalls.count == 1 }
    harness.provider.setStarredHandler = { _, _ in }
    store.setStarred("1", false)
    first.resolve(())
    await waitUntil { harness.provider.setStarredCalls.count == 2 }
    #expect(harness.provider.setStarredCalls.map(\.1) == [true, false])
    await waitUntil { store.pendingWrites == 0 }
    #expect(store.entries["1"]?.starred == false)
  }

  @Test func rejectedWritesRollBackButNetworkFailuresAreKeptForRetry() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    harness.provider.setReadHandler = { _, _ in throw APIError("offline", isNetwork: true) }
    store.setRead(["1"], true)
    await waitUntil { harness.provider.setReadCalls.count == 1 }
    try await Task.sleep(for: .milliseconds(30))
    #expect(store.entries["1"]?.read == true)
    #expect(store.pendingWrites == 1)
    // 网络恢复后（例如回到前台）继续发送
    harness.provider.setReadHandler = { _, _ in }
    store.retryWrites()
    await waitUntil { store.pendingWrites == 0 }
    #expect(harness.provider.setReadCalls.count == 2)
    #expect(store.entries["1"]?.read == true)
  }

  @Test func unauthorizedWritesPauseTheQueueUntilTheEndpointIsEdited() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    let endpoint = try #require(store.endpoint)
    harness.provider.setReadHandler = { _, _ in throw APIError("凭据无效", status: 401) }
    store.setRead(["1"], true)
    await waitUntil { store.writeErrors[endpoint.id] != nil }
    #expect(store.entries["1"]?.read == true)
    harness.provider.setReadHandler = { _, _ in }
    try await store.connect(with(input) { $0.id = endpoint.id })
    await waitUntil { store.pendingWrites == 0 }
    #expect(store.writeErrors[endpoint.id] == nil)
  }

  @Test func aRejectedBatchIsBisectedSoOnlyTheBadEntryRollsBack() async throws {
    let harness = Harness()
    harness.provider.entriesHandler = { _, _, _ in page(["1", "2", "3", "4"]) }
    let store = harness.makeStore()
    try await store.connect(input)
    harness.provider.setReadHandler = { ids, _ in if ids.contains("3") { throw APIError("not found", status: 404) } }
    store.setRead(["1", "2", "3", "4"], true)
    await waitUntil { store.pendingWrites == 0 }
    #expect(store.entries["3"]?.read == false)
    #expect(["1", "2", "4"].allSatisfy { store.entries[$0]?.read == true })
  }

  @Test func keepsALocalChangeMadeWhileASyncIsInFlight() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    let reading = Deferred<EntryPage>()
    harness.provider.onceEntries { _, _, _ in try await reading.value() }
    async let syncing: Void = store.sync(explicit: true)
    await waitUntil { harness.provider.count("entries") == 2 }
    store.setStarred("1", true)
    await waitUntil { harness.provider.setStarredCalls.count == 1 }
    reading.resolve(page(["1"]))
    await syncing
    #expect(store.entries["1"]?.starred == true)
  }

  @Test func ignoresStaleSyncResponsesAfterTheEndpointIsRemoved() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    let reading = Deferred<EntryPage>()
    harness.provider.onceEntries { _, _, _ in try await reading.value() }
    async let syncing: Void = store.sync(explicit: true)
    await waitUntil { harness.provider.count("entries") == 2 }
    await store.removeEndpoint(try #require(store.endpoint?.id))
    reading.resolve(page(["8"]))
    await syncing
    #expect(store.endpoint == nil)
    #expect(store.entries["8"] == nil)
  }

  @Test func retainsEarlierDataWhenSyncFailsAndClearsTheErrorOnRetry() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    harness.provider.onceEntries { _, _, _ in throw TestError("offline") }
    await store.sync(explicit: true)
    #expect(store.order == ["1"])
    #expect(store.sync.error == "offline")
    await store.sync(explicit: true)
    #expect(store.sync.error == nil)
  }

  @Test func doesNotMixAPendingDemoSyncIntoANewlyConnectedEndpoint() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    store.enterDemo()
    try await store.connect(input)
    try await Task.sleep(for: .milliseconds(50))
    #expect(store.order == ["1"])
    #expect(store.endpoint?.kind == .connected)
  }

  @Test func anExplicitSyncDuringABackgroundSyncRunsAfterIt() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    let reading = Deferred<EntryPage>()
    harness.provider.onceEntries { _, _, _ in try await reading.value() }
    async let background: Void = store.sync(explicit: false)
    await waitUntil { harness.provider.count("entries") == 2 }
    harness.provider.onceEntries { _, _, _ in page(["5", "1"]) }
    async let explicit: Void = store.sync(explicit: true)
    reading.resolve(page(["1"]))
    await background
    await explicit
    #expect(store.scopes[unreadQuery]?.ids == ["5", "1"])
  }
}

@MainActor
@Suite(.serialized) struct DownloadTests {
  let image = ImageAsset(key: "image", url: "https://example.com/image.png")

  @Test func marksSuccessfulDownloadsReadByDefaultAndWritesTheState() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    #expect(store.settings.downloadRead)
    await store.download(key: "download", entry: try #require(store.entries["1"]), images: [image])
    #expect(store.entries["1"]?.read == true)
    await waitUntil { harness.provider.setReadCalls.contains { $0.0 == ["1"] && $0.1 } }
  }

  @Test func persistsTheDisabledPreferenceAndLeavesDownloadsUnread() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    store.updateSettings { $0.downloadRead = false }
    await store.download(key: "download", entry: try #require(store.entries["1"]), images: [image])
    #expect(store.entries["1"]?.read == false)
    #expect(harness.provider.setReadCalls.isEmpty)
    let saved = try JSONDecoder().decode(Settings.self, from: #require(harness.defaults.data(forKey: AlbumStore.settingsKey)))
    #expect(saved.downloadRead == false)
    #expect(harness.makeStore().settings.downloadRead == false)
  }

  @Test func leavesPartialFailedAndEmptyDownloadsUnread() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    let entry = try #require(store.entries["1"])
    harness.saver.handler = { _ in throw TestError("offline") }
    await store.download(key: "failed", entry: entry, images: [image])
    #expect(store.downloads["failed"]?.status == .blocked)
    let attempts = Counter()
    harness.saver.handler = { _ in if attempts.increment() > 1 { throw TestError("offline") } }
    await store.download(key: "partial", entry: entry, images: [image, image])
    #expect(store.downloads["partial"] == DownloadState(status: .blocked, done: 1, total: 2))
    await store.download(key: "empty", entry: entry, images: [])
    #expect(store.entries["1"]?.read == false)
    #expect(harness.provider.setReadCalls.isEmpty)
  }

  @Test func doesNotMarkTheNewEndpointReadWhenAnOldDownloadFinishes() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    let saving = Deferred<Void>()
    harness.saver.handler = { _ in try await saving.value() }
    let entry = try #require(store.entries["1"])
    async let downloading: Void = store.download(key: "old", entry: entry, images: [image])
    try await Task.sleep(for: .milliseconds(20))
    try await store.connect(with(input) { $0.server = "https://second.example.com" })
    saving.resolve(())
    await downloading
    #expect(store.entries["1"]?.read == false)
    #expect(store.downloads.isEmpty)
    #expect(harness.provider.setReadCalls.isEmpty)
  }
}

@MainActor
@Suite(.serialized) struct PersistenceTests {
  @Test func showsTheLocalSnapshotFirstAndSyncsInTheBackground() async throws {
    var harness = Harness()
    harness.database = try AlbumDatabase(directory: nil)
    let store = harness.makeStore()
    harness.provider.onceEntries { _, _, _ in page(["3", "2"], cursor: "2") }
    try await store.connect(with(input) { $0.remember = true })
    store.setStarred("2", true)
    await waitUntil { store.pendingWrites == 0 }
    store.persistNow()
    try await Task.sleep(for: .milliseconds(100))
    harness.provider.reset()
    let entriesGate = Deferred<EntryPage>()
    harness.provider.onceEntries { _, _, _ in try await entriesGate.value() }
    let relaunched = harness.makeStore()
    async let starting: Void = relaunched.start()
    await waitUntil { relaunched.loaded }
    #expect(relaunched.order == ["3", "2"])
    #expect(relaunched.entries["2"]?.starred == true)
    #expect(relaunched.scopes[unreadQuery]?.cursor == "2")
    entriesGate.resolve(page(["4", "3"]))
    await starting
    await waitUntil { relaunched.sync.pendingIDs == ["4"] }
  }

  @Test func pendingWritesSurviveARelaunch() async throws {
    var harness = Harness()
    harness.database = try AlbumDatabase(directory: nil)
    let store = harness.makeStore()
    try await store.connect(with(input) { $0.remember = true })
    harness.provider.setReadHandler = { _, _ in throw APIError("offline", isNetwork: true) }
    store.setRead(["1"], true)
    await waitUntil { harness.provider.setReadCalls.count == 1 }
    store.persistNow()
    try await Task.sleep(for: .milliseconds(100))
    harness.provider.setReadHandler = { _, _ in }
    let relaunched = harness.makeStore()
    await relaunched.start()
    #expect(relaunched.entries["1"]?.read == true)
    await waitUntil { harness.provider.setReadCalls.count == 2 && relaunched.pendingWrites == 0 }
  }

  @Test func listsAreTruncatedToTheirFirstPagesWhenSaved() async throws {
    var harness = Harness()
    harness.database = try AlbumDatabase(directory: nil)
    let store = harness.makeStore()
    harness.provider.entriesHandler = { _, cursor, _ in
      let start = Int(cursor ?? "100") ?? 100
      return page((0..<2).map { String(start - $0) }, cursor: String(start - 2))
    }
    try await store.connect(with(input) { $0.remember = true })
    for _ in 0..<4 { await store.loadMore(unreadQuery).value }
    #expect(store.scopes[unreadQuery]?.ids.count == 10)
    store.persistNow()
    try await Task.sleep(for: .milliseconds(100))
    let relaunched = harness.makeStore()
    await relaunched.start()
    #expect(relaunched.scopes[unreadQuery]?.ids.count ?? 0 >= 6)
  }
}

final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func increment() -> Int {
    lock.withLock {
      value += 1
      return value
    }
  }
}

@MainActor
@Suite(.serialized) struct ReviewRegressionTests {
  @Test func aRestoredListKeepsItsContentWhenTheNextPageFailsOffline() async throws {
    var harness = Harness()
    harness.database = try AlbumDatabase(directory: nil)
    let store = harness.makeStore()
    harness.provider.entriesHandler = { _, cursor, _ in
      let start = Int(cursor ?? "100") ?? 100
      return page((0..<2).map { String(start - $0) }, cursor: String(start - 2))
    }
    try await store.connect(with(input) { $0.remember = true })
    await store.loadMore(unreadQuery).value
    store.persistNow()
    try await Task.sleep(for: .milliseconds(100))
    let relaunched = harness.makeStore()
    await relaunched.start()
    let restored = try #require(relaunched.scopes[unreadQuery])
    #expect(restored.restored)
    harness.provider.entriesHandler = { _, _, _ in throw APIError("offline", isNetwork: true) }
    await relaunched.loadMore(unreadQuery).value
    let after = try #require(relaunched.scopes[unreadQuery])
    #expect(after.ids == restored.ids)
    #expect(after.error == "offline")
  }

  @Test func aRestoredCursorThatTheServiceRejectsStartsTheListAgain() async throws {
    var harness = Harness()
    harness.database = try AlbumDatabase(directory: nil)
    let store = harness.makeStore()
    harness.provider.onceEntries { _, _, _ in page(["3", "2"], cursor: "2") }
    try await store.connect(with(input) { $0.remember = true })
    store.persistNow()
    try await Task.sleep(for: .milliseconds(100))
    let relaunched = harness.makeStore()
    let before = harness.provider.count("subscriptions")
    await relaunched.start()
    // 等启动后的后台同步结束，再让下一页的请求被服务拒绝
    await waitUntil { harness.provider.count("subscriptions") > before && relaunched.sync.status == .idle }
    #expect(relaunched.scopes[unreadQuery]?.restored == true)
    harness.provider.onceEntries { _, _, _ in throw APIError("服务未正确推进文章分页") }
    await relaunched.loadMore(unreadQuery).value
    #expect(relaunched.scopes[unreadQuery] == nil)
  }

  @Test func oneUnreachableEndpointDoesNotBlockAnothersWrites() async throws {
    let harness = Harness()
    let reachable = MockProvider()
    let unreachable = MockProvider()
    unreachable.setReadHandler = { _, _ in throw APIError("offline", isNetwork: true) }
    var environment = harness.environment
    environment.makeProvider = { endpoint in endpoint.server.contains("lan") ? unreachable : reachable }
    let store = AlbumStore(environment: environment)
    try await store.connect(with(input) { $0.server = "http://lan.example.com" })
    store.setRead(["1"], true)
    await waitUntil { unreachable.setReadCalls.count == 1 }
    try await store.connect(with(input) { $0.server = "https://cloud.example.com" })
    store.setRead(["1"], true)
    await waitUntil { reachable.setReadCalls.count == 1 }
    #expect(unreachable.setReadCalls.count == 1)
  }

  @Test func newItemsWaitingForThePillAreNotPrunedFromTheDatabase() async throws {
    let database = try AlbumDatabase(directory: nil)
    let entry = Entry(id: "9", feedId: "2", title: "New", author: "", url: "", publishedAt: Date(timeIntervalSince1970: 9))
    try await database.upsertEntries("e", items: [(remote("9"), entry)])
    try await database.saveState(
      "e",
      StoredState(folders: [], feeds: [], scopes: [], unread: nil, lastSyncedAt: Date(), states: [], keep: ["9"]))
    let snapshot = try #require(try await database.loadSnapshot("e", server: "https://example.com", mediaOrigin: nil, nextToken: { 1 }))
    #expect(snapshot.entries.map(\.id) == ["9"])
  }

  @Test func aBackgroundSyncRequestedDuringAStaleSyncRunsForTheNewEndpoint() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(with(input) { $0.name = "A" })
    let reading = Deferred<EntryPage>()
    harness.provider.onceEntries { _, _, _ in try await reading.value() }
    async let stale: Void = store.sync(explicit: false)
    await waitUntil { harness.provider.count("entries") == 2 }
    try await store.connect(with(input) { $0.server = "https://b.example.com"; $0.name = "B" })
    let before = harness.provider.count("subscriptions")
    async let current: Void = store.sync(explicit: false)
    reading.resolve(page(["1"]))
    await stale
    await current
    #expect(harness.provider.count("subscriptions") == before + 1)
  }

  @Test func anExplicitSyncOfAnotherListKeepsThePendingNewItems() async throws {
    let harness = Harness()
    let store = harness.makeStore()
    try await store.connect(input)
    harness.provider.onceEntries { _, _, _ in page(["9", "1"]) }
    await store.sync(explicit: false)
    #expect(store.sync.pendingIDs == ["9"])
    store.listAppeared(ListQuery(status: .starred))
    await store.sync(explicit: true)
    #expect(store.sync.pendingIDs == ["9"])
    store.applyPending()
    #expect(store.scopes[unreadQuery]?.ids == ["9", "1"])
  }
}
