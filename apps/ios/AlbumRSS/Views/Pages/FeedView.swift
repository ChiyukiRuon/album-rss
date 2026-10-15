import AlbumCore
import SwiftUI

/// 单个订阅（画师）的页面：刷新、全部标为已读、抓取错误
struct FeedView: View {
  let feedID: String

  @Environment(AppModel.self) private var app
  @State private var statusOverride: ListStatus?
  @State private var mode: WallMode = .albums
  @State private var confirmingMarkRead = false

  private var status: ListStatus { statusOverride ?? app.store.settings.defaultStatus }

  var body: some View {
    let store = app.store
    if let feed = store.feeds.first(where: { $0.id == feedID }) {
      let counts = Selectors.unreadCounts(
        entries: store.entries, feeds: store.feeds, serverCounts: store.unread, showImageless: store.settings.showImageless)
      let unread = counts.byFeed[feed.id] ?? 0
      EntryWall(query: ListQuery(listStatus: status, feedId: feed.id), mode: mode, label: "\(feed.author)的图集") {
        header(feed, unread: unread)
      } empty: {
        EmptyStateView(
          systemImage: "checkmark.circle",
          title: status == .unread ? "「\(feed.author)」没有未读图集" : "还没有图集",
          description: status == .unread ? "新作品同步到之后会出现在这里。" : "这个订阅里还没有包含图片的文章。"
        ) {
          if status == .unread {
            Button("查看全部") { statusOverride = .all }.buttonStyle(InkButtonStyle())
          }
        }
      }
      .navigationTitle(feed.author)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          if store.canRefreshFeeds {
            Button {
              Task { await store.refreshFeed(feed.id) }
            } label: {
              if store.refreshingFeeds.contains(feed.id) { ProgressView() } else { Image(systemName: "arrow.clockwise") }
            }
            .disabled(store.refreshingFeeds.contains(feed.id))
            .accessibilityLabel("刷新订阅")
          }
          Button("全部标为已读", systemImage: "checkmark.circle") { confirmingMarkRead = true }
            .disabled(unread == 0)
        }
      }
      .confirmationDialog(
        "将「\(feed.author)」的 \(unread) 个未读图集标为已读？之后可以撤销。",
        isPresented: $confirmingMarkRead,
        titleVisibility: .visible
      ) {
        Button("标为已读") { Task { await store.markFeedRead(feed) } }
        Button("取消", role: .cancel) {}
      }
    } else {
      EmptyStateView(systemImage: "dot.radiowaves.up.forward", title: "找不到这个订阅", description: "它可能已在 RSS 服务里被删除。")
    }
  }

  @ViewBuilder
  private func header(_ feed: Feed, unread: Int) -> some View {
    let store = app.store
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 14) {
        AvatarView(url: feed.iconURL, name: feed.author, size: 64)
          .overlay { Circle().strokeBorder(Color.line) }
        VStack(alignment: .leading, spacing: 4) {
          Text(feed.author)
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(Color.ink)
            .lineLimit(2)
          TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(details(feed, now: context.date))
              .font(.system(size: 13))
              .foregroundStyle(Color.ink2)
          }
          let site = Formatting.siteName(feed.siteURL)
          if !site.isEmpty {
            Button {
              app.open(feed.siteURL)
            } label: {
              Label("在 \(site) 查看", systemImage: "arrow.up.forward.square")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink2)
            }
            .buttonStyle(.plain)
          }
        }
      }
      if feed.parsingErrorCount > 0 {
        Banner(
          title: "最近 \(feed.parsingErrorCount) 次抓取失败",
          message: "\(feed.parsingError ?? "订阅源暂时无法抓取")。下面是之前同步到的内容，RSS 服务会继续按计划重试。"
        ) {
          if store.canRefreshFeeds {
            Button("重试") { Task { await store.refreshFeed(feed.id) } }
              .buttonStyle(InkButtonStyle(prominent: true))
              .disabled(store.refreshingFeeds.contains(feed.id))
          }
        }
      }
      SyncBanners()
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) { pickers(unread: unread) }
        VStack(alignment: .leading, spacing: 10) { pickers(unread: unread) }
      }
    }
    .padding(.top, 8)
  }

  @ViewBuilder
  private func pickers(unread: Int) -> some View {
    StatusPicker(status: Binding(get: { status }, set: { statusOverride = $0 }), unread: unread)
    ModePicker(mode: $mode)
  }

  /// 分类 · 订阅标题（与名字相同时省略）· 抓取时间
  private func details(_ feed: Feed, now: Date) -> String {
    let store = app.store
    var parts: [String] = []
    if let category = Selectors.categoryLabel(feed.folderIds, folders: store.folders) { parts.append(category) }
    if feed.title != feed.author { parts.append(feed.title) }
    if store.refreshingFeeds.contains(feed.id) {
      parts.append("正在抓取…")
    } else if let checked = feed.checkedAt {
      parts.append("\(Formatting.relativeTime(checked, now: now))抓取")
    }
    return parts.joined(separator: " · ")
  }
}
