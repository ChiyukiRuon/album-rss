import AlbumCore
import AlbumImages
import NukeUI
import SwiftUI

/// 瀑布流里的一张卡片：封面 + 一行作者信息
struct GalleryCard: View {
  let entry: Entry
  let feed: Feed?
  /// 订阅所属的分类名；不需要显示时为空
  let category: String?
  /// 图片流里这张卡片对应的图片序号；图集模式为 nil
  let imageIndex: Int?
  let tile: ResolvedTile
  let placement: WallLayout.Placement
  let footer: Double
  let position: Int
  let setSize: Int
  /// 已读：在列表里变暗
  let dimmed: Bool
  let open: () -> Void

  @Environment(AppModel.self) private var app
  @Environment(\.heroNamespace) private var namespace

  private var index: Int { imageIndex ?? 0 }
  private var image: ImageAsset? { entry.images.indices.contains(index) ? entry.images[index] : nil }
  private var author: String { feed?.author ?? entry.author }
  private var key: String { WallItem.key(entryID: entry.id, index: imageIndex) }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      media
        .frame(width: placement.width, height: placement.mediaHeight)
      footerRow
        .frame(height: footer)
    }
  }

  @ViewBuilder
  private var media: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
    if let image {
      Button(action: open) {
        MediaCover(
          asset: image,
          size: CGSize(width: placement.width, height: placement.mediaHeight),
          long: tile.long,
          failedEarlier: tile.failed,
          dimmed: dimmed
        )
        .clipShape(shape)
        .overlay(alignment: .topLeading) { if entry.starred { starBadge } }
        .overlay(alignment: .topTrailing) { badges }
        .contentShape(shape)
      }
      .buttonStyle(CardPressStyle())
      .modifier(HeroSource(id: key, namespace: namespace))
      .contextMenu { menu(image) } preview: {
        MediaCover(
          asset: image, size: CGSize(width: placement.width * 1.6, height: placement.mediaHeight * 1.6), long: false,
          failedEarlier: false, dimmed: false
        )
        .frame(width: placement.width * 1.6, height: placement.mediaHeight * 1.6)
      }
      .accessibilityLabel(accessibilityLabel)
      .accessibilityHint("打开查看器")
    } else {
      TextCard(entry: entry)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { app.open(entry.url) }
        .contextMenu { readToggle }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }
  }

  private var accessibilityLabel: String {
    let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = title.isEmpty ? "无标题" : title
    let count = entry.images.count
    var parts = imageIndex != nil ? "\(author)：\(name)，第 \(index + 1) 张，共 \(count) 张" : "\(author)：\(name)，\(count) 张图片"
    if entry.starred { parts += "，已收藏" }
    if entry.read { parts += "，已读" }
    return parts
  }

  private var starBadge: some View {
    Image(systemName: "star.fill")
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(Color.spot)
      .frame(width: 24, height: 24)
      .background(Circle().fill(.white).shadow(color: .black.opacity(0.18), radius: 1.5, y: 1))
      .padding(8)
      .accessibilityHidden(true)
  }

  /// 角标都在右上角：张数（或图片流里的序号）在最右，“长图”在它左边
  private var badges: some View {
    let count = entry.images.count
    return HStack(spacing: 4) {
      if image?.isVideo == true { Badge(text: "视频", systemImage: "play.fill") }
      if tile.long { Badge(text: "长图") }
      if imageIndex != nil {
        if count > 1 { Badge(text: "\(index + 1)/\(count)") }
      } else if count > 1 {
        Badge(text: "\(count)", systemImage: "square.stack.fill")
      }
    }
    .padding(8)
    .accessibilityHidden(true)
  }

  private var footerRow: some View {
    HStack(spacing: 2) {
      Button {
        app.openFeed(entry.feedId)
      } label: {
        HStack(spacing: 7) {
          AvatarView(url: feed?.iconURL, name: author, size: 20)
          ViewThatFits(in: .horizontal) {
            if let category, placement.width > 170 {
              HStack(spacing: 7) {
                authorName
                Text(category)
                  .font(.system(size: 12))
                  .foregroundStyle(Color.ink3)
                  .lineLimit(1)
                  .fixedSize()
              }
            }
            authorName
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("查看\(author)的订阅")
      if image != nil {
        DownloadButton(
          downloadKey: key,
          entry: entry,
          images: imageIndex == nil ? entry.images : [entry.images[index]],
          fallbackOpen: open
        )
      }
    }
    .padding(.leading, 2)
  }

  private var authorName: some View {
    Text(author)
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(Color.ink)
      .lineLimit(1)
  }

  @ViewBuilder
  private func menu(_ image: ImageAsset) -> some View {
    readToggle
    Button(entry.starred ? "取消收藏" : "收藏", systemImage: entry.starred ? "star.slash" : "star") {
      app.store.setStarred(entry.id, !entry.starred)
    }
    let targets = (imageIndex == nil ? entry.images : [image]).filter { !$0.isVideo }
    if !targets.isEmpty {
      Button(targets.count > 1 ? "保存图集（\(targets.count) 张）" : "保存图片", systemImage: "square.and.arrow.down") {
        Task { await app.store.download(key: key, entry: entry, images: targets, fallback: nil) }
      }
    }
    Divider()
    Button("查看「\(author)」", systemImage: "person.crop.square") { app.openFeed(entry.feedId) }
    if !entry.url.isEmpty, let url = URL(string: entry.url) {
      Button("查看原文", systemImage: "safari") { app.open(entry.url) }
      ShareLink(item: url) { Label("分享原文链接", systemImage: "square.and.arrow.up") }
    }
  }

  private var readToggle: some View {
    Button(entry.read ? "标为未读" : "标为已读", systemImage: entry.read ? "eye.slash" : "eye") {
      app.store.setRead([entry.id], !entry.read)
    }
  }
}

/// 卡片作为缩放过渡的起点（iOS 18 起）
struct HeroSource: ViewModifier {
  let id: String
  let namespace: Namespace.ID?

  func body(content: Content) -> some View {
    if let namespace {
      content.matchedTransitionSource(id: id, in: namespace)
    } else {
      content
    }
  }
}

private struct CardPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.spring(duration: 0.2), value: configuration.isPressed)
  }
}

private struct Badge: View {
  let text: String
  var systemImage: String?

  var body: some View {
    HStack(spacing: 3) {
      if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .bold)) }
      Text(text).font(.system(size: 12, weight: .semibold)).monospacedDigit()
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 7)
    .frame(height: 22)
    .background(Capsule().fill(Color(hex: 0x16161A, opacity: 0.58)))
  }
}

/// 卡片封面：按显示框解码缩略图；加载中是网点，失败时可以重试。长图从顶部裁切并在底边渐隐
struct CardImage: View {
  let url: String
  let size: CGSize
  let long: Bool
  /// 尺寸测量时就失败了：先显示失败，点重试再加载
  let failedEarlier: Bool
  let dimmed: Bool

  @Environment(\.imagePipeline) private var pipeline
  @State private var attempt = 0

  var body: some View {
    ZStack {
      Color.toneBackground
      if failedEarlier && attempt == 0 {
        failure
      } else {
        LazyImage(request: ImageRequests.thumbnail(url, size: size), transaction: Transaction(animation: .easeOut(duration: 0.26))) { state in
          if let image = state.image {
            image
              .resizable()
              .scaledToFill()
              .frame(width: size.width, height: size.height, alignment: long ? .top : .center)
              .clipped()
              .mask {
                if long {
                  LinearGradient(
                    stops: [.init(color: .black, location: 0.78), .init(color: .clear, location: 1)], startPoint: .top,
                    endPoint: .bottom)
                } else {
                  Rectangle()
                }
              }
              .opacity(dimmed ? 0.45 : 1)
          } else if state.error != nil {
            failure
          } else {
            ToneView(loading: true)
              .opacity(dimmed ? 0.45 : 1)
          }
        }
        .pipeline(pipeline)
        .id(attempt)
      }
    }
    .frame(width: size.width, height: size.height)
  }

  private var failure: some View {
    ToneView {
      VStack(spacing: 6) {
        Image(systemName: "photo.badge.exclamationmark")
          .font(.system(size: 24))
        Text("图片加载失败")
          .font(.system(size: 12, weight: .semibold))
        Button("重新加载", systemImage: "arrow.clockwise") { attempt += 1 }
          .labelStyle(.iconOnly)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.ink)
          .frame(width: 32, height: 32)
          .glassBackground(in: Circle(), interactive: true)
          .padding(.top, 2)
      }
      .foregroundStyle(Color.ink3)
    }
    .opacity(dimmed ? 0.45 : 1)
  }
}

/// 没有图片的文章（显示无图文章时）：标题、摘要和原文入口
private struct TextCard: View {
  let entry: Entry

  var body: some View {
    ToneView {
      VStack(alignment: .leading, spacing: 0) {
        Label(entry.parseState == .pending ? "图片待解析" : "没有图片", systemImage: entry.parseState == .pending ? "hourglass" : "text.alignleft")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.ink2)
          .padding(.horizontal, 9)
          .frame(height: 24)
          .background(Capsule().fill(Color.paper))
        Spacer(minLength: 8)
        VStack(alignment: .leading, spacing: 6) {
          Text(entry.title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.ink)
            .lineLimit(4)
          if let excerpt = entry.paragraphs.first {
            Text(excerpt)
              .font(.system(size: 13))
              .foregroundStyle(Color.ink2)
              .lineLimit(2)
          }
          Label("原文", systemImage: "arrow.up.forward.square")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.ink3)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }
}

/// 保存到相册：进行中显示进度环，完成打勾，失败给出提示
struct DownloadButton: View {
  let downloadKey: String
  let entry: Entry
  let images: [ImageAsset]
  private var photos: [ImageAsset] { images.filter { !$0.isVideo } }
  var dark = false
  var fallbackOpen: (() -> Void)?

  @Environment(AppModel.self) private var app

  var body: some View {
    let state = app.store.downloads[downloadKey]
    if !photos.isEmpty {
      Button {
        let fallback = fallbackOpen.map { open in ToastCenter.Action(label: "在查看器中打开") { open() } }
        Task { await app.store.download(key: downloadKey, entry: entry, images: photos, fallback: fallback) }
      } label: {
        Group {
          switch state?.status {
          case .running:
            ProgressRing(progress: state.map { Double($0.done) / Double(max(1, $0.total)) } ?? 0, dark: dark)
          case .done:
            Image(systemName: "checkmark").foregroundStyle(Color.ok)
          case .blocked:
            Image(systemName: "exclamationmark.circle").foregroundStyle(dark ? Color.viewerSecondary : Color.ink3)
          case nil:
            Image(systemName: "arrow.down.to.line")
          }
        }
        .font(.system(size: dark ? 17 : 14, weight: .semibold))
        .foregroundStyle(dark ? Color.viewerForeground : Color.ink2)
        .frame(width: dark ? 44 : 32, height: dark ? 44 : 32)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(label(state))
    }
  }

  private func label(_ state: DownloadState?) -> String {
    switch state?.status {
    case .running: "正在保存 \(state?.done ?? 0)/\(state?.total ?? 0)"
    case .done: "已保存"
    case .blocked: photos.count > 1 ? "这些图片没能保存" : "这张图片没能保存"
    case nil: photos.count > 1 ? "保存图集（\(photos.count) 张）" : "保存图片"
    }
  }
}

private struct ProgressRing: View {
  let progress: Double
  var dark = false

  var body: some View {
    ZStack {
      Circle().stroke(dark ? Color.viewerSurface2 : Color.paper3, lineWidth: 2.2)
      Circle()
        .trim(from: 0, to: max(progress, 0.08))
        .stroke(dark ? Color.viewerForeground : Color.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .animation(.easeOut(duration: 0.2), value: progress)
    }
    .frame(width: 16, height: 16)
  }
}

/// 视频使用 poster；没有封面时保留播放占位，不向图片管线发送视频地址。
struct MediaCover: View {
  let asset: ImageAsset
  let size: CGSize
  let long: Bool
  let failedEarlier: Bool
  let dimmed: Bool

  var body: some View {
    ZStack {
      if !asset.isVideo || asset.poster != nil {
        CardImage(url: asset.isVideo ? asset.poster! : asset.url, size: size,
          long: long, failedEarlier: failedEarlier, dimmed: dimmed)
      } else {
        Color.toneBackground
      }
      if asset.isVideo {
        Image(systemName: "play.circle.fill")
          .font(.system(size: min(40, size.width * 0.5)))
          .foregroundStyle(.white)
          .shadow(radius: 4)
      }
    }
    .frame(width: size.width, height: size.height)
  }
}
