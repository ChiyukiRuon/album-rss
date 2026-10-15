import AlbumCore
import SwiftUI

/// 浏览：未读 / 全部、图集 / 图片流、按分类筛选
struct BrowseView: View {
  @Environment(AppModel.self) private var app
  @State private var statusOverride: ListStatus?
  @State private var mode: WallMode = .albums
  @State private var folderID: String?

  private var status: ListStatus { statusOverride ?? app.store.settings.defaultStatus }

  var body: some View {
    let store = app.store
    // 找不到的分类（例如切换端点后）当作全部
    let folder = store.folders.first { $0.id == folderID }
    let query = ListQuery(listStatus: status, folderId: folder?.id)
    let counts = Selectors.unreadCounts(
      entries: store.entries, feeds: store.feeds, serverCounts: store.unread, showImageless: store.settings.showImageless)
    let unread = folder.map { counts.byFolder[$0.id] ?? 0 } ?? counts.total
    EntryWall(
      query: query,
      mode: mode,
      label: folder.map { "\($0.title)中的图集" } ?? "图集",
      dimRead: true,
      showsNewItems: true
    ) {
      VStack(alignment: .leading, spacing: 12) {
        TimelineView(.periodic(from: .now, by: 30)) { context in
          PageSubtitle(text: subtitle(folder: folder, unread: unread, query: query, now: context.date))
        }
        SyncBanners()
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 10) { pickers(unread: unread) }
          VStack(alignment: .leading, spacing: 10) { pickers(unread: unread) }
        }
        // 分类来自 RSS 服务；只有一个分类时筛选没有意义，不显示
        if store.folders.count > 1 {
          FolderChips(
            chips: store.folders.map { FolderChip(id: $0.id, title: $0.title, count: counts.byFolder[$0.id]) },
            selection: $folderID
          )
        }
      }
      .padding(.top, 4)
    } empty: {
      emptyState
    }
    .tabPageTitle("浏览")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { SyncToolbarButton() }
    }
  }

  @ViewBuilder
  private func pickers(unread: Int) -> some View {
    StatusPicker(status: Binding(get: { status }, set: { statusOverride = $0 }), unread: unread)
    ModePicker(mode: $mode)
  }

  private func syncedText(_ now: Date) -> String {
    let sync = app.store.sync
    if sync.status == .syncing { return "正在同步…" }
    if sync.lastSyncedAt == .distantPast { return "尚未同步" }
    return "\(Formatting.relativeTime(sync.lastSyncedAt, now: now))同步"
  }

  private func subtitle(folder: Folder?, unread: Int, query: ListQuery, now: Date) -> String {
    let store = app.store
    var parts: [String] = []
    if let folder { parts.append(folder.title) }
    if status == .unread {
      parts.append("\(unread) 个未读图集")
    } else {
      let scope = store.scopes[query]
      let count = scope?.ids.count { Selectors.isVisible(store.entries[$0], in: query, showImageless: store.settings.showImageless) } ?? 0
      parts.append("\(count)\(scope?.done == false ? "+" : "") 个图集")
    }
    parts.append(syncedText(now))
    return parts.joined(separator: " · ")
  }

  @ViewBuilder
  private var emptyState: some View {
    if status == .unread {
      EmptyStateView(
        systemImage: "checkmark.circle",
        title: "未读的图集都看完了",
        description: "\(syncedText(.now))。可以再同步一次看看有没有新的，或者回顾全部图集。"
      ) {
        Button("同步", systemImage: "arrow.clockwise") { Task { await app.store.sync(explicit: true) } }
          .buttonStyle(InkButtonStyle(prominent: true))
        Button("查看全部") { statusOverride = .all }
          .buttonStyle(InkButtonStyle())
      }
    } else {
      EmptyStateView(
        systemImage: "arrow.clockwise",
        title: "这里还没有图集",
        description: "订阅里还没有包含图片的文章。同步完成后，新的图集会出现在这里。"
      ) {
        Button("同步") { Task { await app.store.sync(explicit: true) } }
          .buttonStyle(InkButtonStyle(prominent: true))
      }
    }
  }
}
