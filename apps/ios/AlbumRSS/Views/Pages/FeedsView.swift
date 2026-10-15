import AlbumCore
import AlbumImages
import NukeUI
import SwiftUI

/// 订阅：按分类分组的画师卡片（最近三张封面、未读数、抓取错误）
struct FeedsView: View {
  @Environment(AppModel.self) private var app
  @State private var folderID: String?

  private struct Group: Identifiable {
    var id: String
    var title: String
    var feeds: [Feed]
  }

  var body: some View {
    let store = app.store
    let counts = Selectors.unreadCounts(
      entries: store.entries, feeds: store.feeds, serverCounts: store.unread, showImageless: store.settings.showImageless)
    // Miniflux 每个订阅只有一个分类；数据模型允许多对多，以兼容支持多个标签的 Google Reader 服务
    let groups = (store.folders.map { folder in
      Group(id: folder.id, title: folder.title, feeds: store.feeds.filter { $0.folderIds.contains(folder.id) })
    } + [Group(id: "none", title: "未分类", feeds: store.feeds.filter(\.folderIds.isEmpty))])
      .filter { !$0.feeds.isEmpty }
    let active = groups.first { $0.id == folderID }
    let covers = coverMap()

    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        PageSubtitle(
          text: active.map { "\($0.title) · \($0.feeds.count) 个订阅" }
            ?? "\(store.feeds.count) 个订阅 · \(store.folders.count) 个分类")
        SyncBanners()
        if store.folders.count > 1 {
          FolderChips(
            chips: groups.map { FolderChip(id: $0.id, title: $0.title, count: $0.feeds.count) },
            selection: $folderID
          )
        }
        if groups.isEmpty {
          EmptyStateView(systemImage: "dot.radiowaves.up.forward", title: "还没有订阅", description: "在 RSS 服务里添加订阅后，同步一次就会出现在这里。")
        }
        ForEach(active.map { [$0] } ?? groups) { group in
          VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
              Text(group.title).font(.system(size: 17, weight: .bold)).foregroundStyle(Color.ink)
              Text("\(group.feeds.count)").font(.counter(13, weight: .medium)).foregroundStyle(Color.ink3)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
              ForEach(group.feeds) { feed in
                NavigationLink(value: FeedRoute(feedID: feed.id)) {
                  FeedTile(feed: feed, unread: counts.byFeed[feed.id] ?? 0, covers: covers[feed.id] ?? [])
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 4)
      .padding(.bottom, 28)
    }
    .refreshable { await store.sync(explicit: true) }
    .tabPageTitle("订阅")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { SyncToolbarButton() }
    }
  }

  /// 每个订阅最近的三张封面（只来自已读取的文章）
  private func coverMap() -> [String: [ImageAsset]] {
    var map: [String: [ImageAsset]] = [:]
    for id in app.store.order {
      guard let entry = app.store.entries[id], entry.hasImages, let cover = entry.images.first else { continue }
      if map[entry.feedId, default: []].count < 3 { map[entry.feedId, default: []].append(cover) }
    }
    return map
  }
}

private struct FeedTile: View {
  let feed: Feed
  let unread: Int
  let covers: [ImageAsset]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      GeometryReader { proxy in
        let side = (proxy.size.width - 4) / 3
        HStack(spacing: 2) {
          ForEach(0..<3, id: \.self) { index in
            if index < covers.count {
              CardImage(url: covers[index].url, size: CGSize(width: side, height: side), long: false, failedEarlier: false, dimmed: false)
            } else {
              ToneView().frame(width: side, height: side)
            }
          }
        }
      }
      .aspectRatio(3, contentMode: .fit)
      HStack(spacing: 12) {
        AvatarView(url: feed.iconURL, name: feed.author, size: 44)
          .overlay { Circle().strokeBorder(Color.paper, lineWidth: 3) }
          .padding(.top, -26)
        VStack(alignment: .leading, spacing: 2) {
          Text(feed.author)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.ink)
            .lineLimit(1)
          TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(meta(now: context.date))
              .font(.system(size: 12))
              .foregroundStyle(Color.ink3)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 0)
        if unread > 0 {
          Text("\(unread)")
            .font(.counter(12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(minWidth: 24, minHeight: 22)
            .background(Capsule().fill(Color.spot))
            .accessibilityLabel("\(unread) 个未读")
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      if feed.parsingErrorCount > 0 {
        Label("最近 \(feed.parsingErrorCount) 次抓取失败", systemImage: "exclamationmark.circle.fill")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.danger)
          .padding(.horizontal, 12)
          .padding(.bottom, 10)
      }
    }
    .background(Color.paper)
    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.line) }
    .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
  }

  private func meta(now: Date) -> String {
    // 这一页已按分类分组，卡片里不再重复分类
    if let checked = feed.checkedAt { return "\(Formatting.relativeTime(checked, now: now))抓取" }
    let site = Formatting.siteName(feed.siteURL)
    return site.isEmpty ? "抓取时间未知" : site
  }
}
