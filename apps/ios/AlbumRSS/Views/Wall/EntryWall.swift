import AlbumCore
import AlbumImages
import SwiftUI

extension EnvironmentValues {
  /// 卡片与查看器之间缩放过渡的命名空间
  @Entry var heroNamespace: Namespace.ID?
}

/// 瀑布流列表：分页追加、打开查看器、跟随查看器滚动。对应 Web 端的 EntryWall 与 Masonry。
struct EntryWall<Header: View, Empty: View>: View {
  let query: ListQuery
  let mode: WallMode
  let label: String
  /// 已读文章在列表里变暗；收藏页不需要
  var dimRead = true
  /// 浏览页顶部的“有新图集”提示
  var showsNewItems = false
  @ViewBuilder var header: () -> Header
  @ViewBuilder var empty: () -> Empty

  @Environment(AppModel.self) private var app
  @State private var memory = WallMemory()
  @State private var wallID = UUID()
  @State private var width: Double = 0
  /// 左右留白：由容器宽度（内容宽度 + 当前留白）决定，避免留白与宽度互相影响而来回变化
  @State private var padding: Double = 12
  @State private var window = VisibleWindow()
  @State private var pages = 1
  @State private var misses = 0
  @State private var appeared = false

  /// 每次在本地多显示多少卡片
  private var pageSize: Int { mode == .albums ? 36 : 60 }
  /// 连续读到几页都没有可显示的图集时，停止自动翻页，改为让用户点“加载更早的内容”
  private static var autoPages: Int { 3 }
  private static var skeletonRatios: [Double] { [1.333, 1.5, 1, 1.25, 1.6, 1.414, 1.12, 1.78] }
  private static var topAnchor: String { "wall-top" }
  private static var focusAnchor: String { "wall-focus" }

  var body: some View {
    let layout = computeLayout()
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Color.clear.frame(height: 0).id(Self.topAnchor)
          header()
          content(layout)
        }
        .padding(.horizontal, padding)
        .padding(.bottom, 28)
      }
      .scrollIndicators(.visible)
      .refreshable { await app.store.sync(explicit: true) }
      .overlay(alignment: .top) {
        if showsNewItems, !app.store.sync.pendingIDs.isEmpty {
          NewItemsPill(count: app.store.sync.pendingIDs.count) {
            app.store.applyPending()
            withAnimation { proxy.scrollTo(Self.topAnchor, anchor: .top) }
          }
          .padding(.top, 8)
          .transition(.move(edge: .top).combined(with: .opacity))
        }
      }
      .animation(.spring(duration: 0.3), value: app.store.sync.pendingIDs.isEmpty)
      .onChange(of: layout.focusY) { _, focusY in
        // 跟随查看器：目标卡片不完整地在视口内时（顶部留出导航栏），直接把它滚到视口上部
        guard let focusY, let height = layout.focusHeight else { return }
        let visible = memory.visibleRect
        if focusY < visible.minY + 100 || focusY + height > visible.maxY {
          proxy.scrollTo(Self.focusAnchor, anchor: UnitPoint(x: 0, y: 0.22))
        }
      }
    }
    // 还没读过（或换了端点、本地快照里的游标失效被清空）时读第一页
    .task(id: ScopeRequest(query: query, endpointID: app.store.endpoint?.id, loaded: app.store.loaded, missing: app.store.scopes[query] == nil)) {
      if app.store.loaded, app.store.scopes[query] == nil { app.store.loadMore(query) }
    }
    .onAppear {
      appeared = true
      app.store.listAppeared(query)
    }
    .onDisappear {
      appeared = false
      app.store.listDisappeared(query)
    }
    .onChange(of: query) { old, new in
      guard appeared else { return }
      app.store.listDisappeared(old)
      app.store.listAppeared(new)
    }
    .onChange(of: layout.layoutKey) { pages = 1 }
    .onChange(of: layout.itemCount) { misses = 0 }
    .onChange(of: layout.sequence) { _, sequence in app.viewer.extend(sequence, source: wallID) }
    .task(id: layout.probeURLs) {
      if !layout.probeURLs.isEmpty { app.probe.request(layout.probeURLs) }
    }
    .task(id: layout.loadTrigger) { loadMoreIfNeeded(layout) }
  }

  // MARK: 内容

  @ViewBuilder
  private func content(_ layout: Layout) -> some View {
    if layout.items.isEmpty && !layout.fetchMore && !layout.loading {
      if let error = layout.error {
        EmptyStateView(systemImage: "exclamationmark.circle", title: "没能读取这个列表", description: error) {
          Button("重试", systemImage: "arrow.clockwise") { retry() }
            .buttonStyle(InkButtonStyle())
        }
      } else if !layout.remoteMore {
        empty()
      } else {
        canvas(layout)
      }
    } else {
      canvas(layout)
      if !layout.localMore && layout.remoteMore && !layout.loading && (layout.error != nil || !layout.autoLoad) {
        VStack(spacing: 10) {
          if let error = layout.error {
            Text(error).font(.system(size: 13)).foregroundStyle(Color.danger)
          } else if layout.items.isEmpty {
            Text("最近读取的文章里没有可显示的图集。").font(.system(size: 13)).foregroundStyle(Color.ink2)
          }
          Button(layout.error != nil ? "重试" : "加载更早的内容", systemImage: layout.error != nil ? "arrow.clockwise" : "arrow.down") {
            retry()
          }
          .buttonStyle(InkButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
      }
    }
  }

  private func canvas(_ layout: Layout) -> some View {
    ZStack(alignment: .topLeading) {
      Color.clear.frame(height: max(1, layout.contentHeight))
      ForEach(layout.visible) { tile in
        GalleryCard(
          entry: tile.item.entry,
          feed: app.store.feeds.first { $0.id == tile.item.entry.feedId },
          category: category(for: tile.item.entry.feedId),
          imageIndex: tile.item.index,
          tile: tile.tile,
          placement: tile.placement,
          footer: layout.metrics.footer,
          position: tile.position,
          setSize: layout.itemCount,
          dimmed: dimRead && tile.item.entry.read,
          open: { open(tile.item, sequence: layout.sequence) }
        )
        .frame(width: tile.placement.width, height: tile.placement.height)
        .offset(x: tile.placement.x, y: tile.placement.y)
      }
      ForEach(Array(layout.skeletons.enumerated()), id: \.offset) { _, placement in
        SkeletonCard(mediaHeight: placement.mediaHeight, footer: layout.metrics.footer)
          .frame(width: placement.width, height: placement.height)
          .offset(x: placement.x, y: placement.y)
      }
      if let focusY = layout.focusY {
        VStack(spacing: 0) {
          Color.clear.frame(width: 1, height: focusY)
          Color.clear.frame(width: 1, height: 1).id(Self.focusAnchor)
        }
        .allowsHitTesting(false)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .onGeometryChange(for: Double.self) { $0.size.width } action: { measured in
      let container = measured + 2 * padding
      let next: Double = container >= WallLayout.narrowWidth ? 20 : 12
      padding = next
      width = container - 2 * next
    }
    .onGeometryChange(for: VisibleWindow.self) { proxy in
      VisibleWindow(proxy.bounds(of: .scrollView) ?? .zero)
    } action: { window = $0 }
    .onGeometryChange(for: CGRect.self) { proxy in
      proxy.bounds(of: .scrollView) ?? .zero
    } action: { memory.visibleRect = $0 }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
  }

  private func category(for feedID: String) -> String? {
    guard let feed = app.store.feeds.first(where: { $0.id == feedID }) else { return nil }
    return Selectors.categoryLabel(feed.folderIds, folders: app.store.folders)
  }

  private func open(_ item: WallItem, sequence: [String]) {
    app.viewer.open(
      entryID: item.entry.id, index: item.index ?? 0, sequence: sequence, source: wallID, mode: mode)
  }

  private func retry() {
    misses = 0
    app.store.loadMore(query)
  }

  // MARK: 布局

  struct Tile: Identifiable {
    let item: WallItem
    let tile: ResolvedTile
    let placement: WallLayout.Placement
    /// 在列表中的位置（从 1 开始），按文章顺序而不是放置顺序
    let position: Int
    var id: String { item.key }
  }

  struct ScopeRequest: Hashable {
    var query: ListQuery
    var endpointID: String?
    var loaded: Bool
    var missing: Bool
  }

  struct LoadTrigger: Hashable {
    var needsMore: Bool
    var localMore: Bool
    var fetchMore: Bool
    var loading: Bool
    var itemCount: Int
    var pages: Int
    var nearViewerEnd: Bool
  }

  struct Layout {
    var items: [WallItem] = []
    var itemCount = 0
    var layoutKey = ""
    var metrics = WallLayout.metrics(width: 0, density: .standard)
    var visible: [Tile] = []
    var skeletons: [WallLayout.Placement] = []
    var contentHeight: Double = 0
    var sequence: [String] = []
    var localMore = false
    var remoteMore = true
    var fetchMore = true
    var loading = true
    var error: String?
    var autoLoad = true
    var probeURLs: [String] = []
    var focusY: Double?
    var focusHeight: Double?
    var loadTrigger = LoadTrigger(
      needsMore: false, localMore: false, fetchMore: false, loading: true, itemCount: 0, pages: 1, nearViewerEnd: false)
  }

  private func computeLayout() -> Layout {
    let store = app.store
    _ = app.probe.version
    var layout = Layout()
    // 列表快照：只在换了一份列表时重新取数，读到下一页时只在末尾追加
    let snapshot = store.snapshot(for: query, previous: memory.snapshot)
    memory.snapshot = snapshot
    let entries = store.entries

    var items: [WallItem] = []
    for id in snapshot.ids {
      guard let entry = entries[id] else { continue }
      if mode == .albums {
        items.append(WallItem(entry: entry, index: nil))
      } else {
        for index in entry.images.indices { items.append(WallItem(entry: entry, index: index)) }
      }
    }
    layout.itemCount = items.count
    layout.layoutKey = "\(snapshot.layoutID)-\(mode.rawValue)"
    layout.sequence = snapshot.ids.filter { entries[$0]?.hasImages == true }

    let scope = store.scopes[query]
    layout.remoteMore = !(scope?.done ?? false)
    layout.loading = scope?.loading ?? true
    layout.error = scope?.error
    layout.autoLoad = misses < Self.autoPages
    layout.fetchMore = layout.remoteMore && layout.error == nil && layout.autoLoad

    // 查看器翻到还没显示的位置时，列表跟着把那一页也显示出来
    let focusKey = app.viewer.focusKey(for: wallID)
    let focusPosition = focusKey.flatMap { key in items.firstIndex { $0.key == key } } ?? -1
    let visibleCount = max(pages * pageSize, focusPosition + pageSize / 2)
    let shown = Array(items.prefix(visibleCount))
    layout.items = shown
    layout.localMore = visibleCount < items.count

    let metrics = WallLayout.metrics(width: width, density: store.settings.density)
    layout.metrics = metrics
    guard width > 0 else { return layout }
    let windowSize = metrics.columns * 3
    let keys = shown.map(\.key)
    var indexByKey: [String: Int] = [:]
    for (index, key) in keys.enumerated() { indexByKey[key] = index }

    // 先测量再入列：拿到尺寸（或等待超时）的卡片才放进布局，放下后不再移动
    if memory.layoutKey != layout.layoutKey {
      memory.layoutKey = layout.layoutKey
      memory.placed = []
    }
    // 一次放到不能再放为止（与 Web 端反复重渲染的效果相同）：尺寸都已知时不必等滚动
    var placedKeys = memory.placed.filter { indexByKey[$0] != nil }
    while let extended = WallLayout.extendPlacement(
      placedKeys, keys: keys, isReady: { ResolvedTile.resolve(shown[$0], probe: app.probe) != nil }, windowSize: windowSize)
    {
      placedKeys = extended
    }
    memory.placed = placedKeys

    var placedItems: [(item: WallItem, index: Int, tile: ResolvedTile)] = []
    for key in placedKeys {
      guard let index = indexByKey[key], let tile = ResolvedTile.resolve(shown[index], probe: app.probe) else { continue }
      placedItems.append((shown[index], index, tile))
    }
    let (placements, columnHeights) = WallLayout.placeTiles(placedItems.map(\.tile.ratio), metrics: metrics)
    let placedBottom = max(0, (columnHeights.max() ?? 0) - metrics.gap)
    let placedSet = Set(placedKeys)
    let firstUnplaced = keys.firstIndex { !placedSet.contains($0) }
    let allPlaced = firstUnplaced == nil
    let hasMore = layout.localMore || layout.fetchMore || layout.loading
    let waiting = !allPlaced || hasMore
    let skeleton =
      waiting
      ? WallLayout.placeTiles(
        (0..<(metrics.columns * 2)).map { Self.skeletonRatios[$0 % Self.skeletonRatios.count] }, metrics: metrics,
        start: columnHeights)
      : nil
    layout.contentHeight = max(0, ((skeleton?.columnHeights ?? columnHeights).max() ?? 0) - metrics.gap)

    // 只渲染视口上下各一屏内的卡片
    let top = window.top - window.height
    let bottom = window.bottom + window.height
    for (slot, placement) in placements.enumerated() where placement.y + placement.height >= top && placement.y <= bottom {
      let placed = placedItems[slot]
      layout.visible.append(Tile(item: placed.item, tile: placed.tile, placement: placement, position: placed.index + 1))
    }
    layout.skeletons = skeleton?.placements.filter { $0.y <= bottom } ?? []

    let nearEnd = placedBottom - window.bottom < window.height * 1.5
    // 测量：接近底部时为后面几行开始测量；查看器跳到更远的位置时一直测到那里
    if let first = firstUnplaced {
      let target = max(first + (nearEnd ? windowSize + metrics.columns : 1), focusPosition >= 0 ? focusPosition + metrics.columns * 2 : 0)
      layout.probeURLs = shown[first..<min(shown.count, target)].compactMap { item in
        guard let cover = item.cover, cover.width == nil || cover.height == nil else { return nil }
        return cover.url
      }
    }

    if let focusKey, let slot = placedKeys.firstIndex(of: focusKey), slot < placements.count {
      layout.focusY = placements[slot].y
      layout.focusHeight = placements[slot].height
    }
    let nearViewerEnd = focusPosition >= 0 && focusPosition >= items.count - 3
    layout.loadTrigger = LoadTrigger(
      needsMore: allPlaced && hasMore && nearEnd,
      localMore: layout.localMore,
      fetchMore: layout.fetchMore,
      loading: layout.loading,
      itemCount: items.count,
      pages: pages,
      nearViewerEnd: nearViewerEnd
    )
    return layout
  }

  /// 已放下的卡片接近视口底部时追加下一页；查看器翻到末尾附近时也继续读
  private func loadMoreIfNeeded(_ layout: Layout) {
    let trigger = layout.loadTrigger
    if trigger.needsMore {
      if trigger.localMore {
        pages += 1
      } else if trigger.fetchMore && !trigger.loading {
        misses += 1
        app.store.loadMore(query)
      }
      return
    }
    guard trigger.nearViewerEnd, layout.remoteMore, layout.error == nil, !trigger.loading else { return }
    if memory.viewerLoadsLength != trigger.itemCount {
      memory.viewerLoadsLength = trigger.itemCount
      memory.viewerLoads = 0
    }
    guard memory.viewerLoads < Self.autoPages else { return }
    memory.viewerLoads += 1
    app.store.loadMore(query)
  }
}

/// 还在等待的卡片：网点与作者行的占位
struct SkeletonCard: View {
  let mediaHeight: Double
  let footer: Double

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ToneView(loading: true)
        .frame(height: mediaHeight)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
      HStack(spacing: 7) {
        Circle().fill(Color.paper3).frame(width: 20, height: 20)
        Capsule().fill(Color.paper3).frame(width: 64, height: 9)
      }
      .frame(height: footer)
      .padding(.leading, 2)
    }
    .accessibilityHidden(true)
  }
}
