import AlbumCore
import AlbumImages
import Nuke
import NukeUI
import SwiftUI
import UIKit

/// 沉浸查看器：深色全屏、左右翻页、缩放、缩略图条，文章信息按需展开
struct ViewerView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.imagePipeline) private var pipeline
  @State private var chromeHidden = false
  @State private var infoOpen = false
  @State private var webPage: WebPage?
  @State private var sharing: ShareFile?
  @State private var preparingShare = false

  var body: some View {
    let store = app.store
    ZStack {
      Color.viewerBackground.ignoresSafeArea()
      if let session = app.viewer.session, let entry = store.entries[session.entryID], !entry.images.isEmpty {
        let index = min(max(0, session.index), entry.images.count - 1)
        let page = makePage(entry, index)
        ImagePager(
          current: page,
          pipeline: pipeline,
          autoplay: store.settings.videoAutoplay && VideoNetworkMonitor.shared.connected
            && (store.settings.videoAutoplayCellular || VideoNetworkMonitor.shared.unmetered),
          endBehavior: store.settings.videoEndBehavior,
          onVideoEnded: { ended in
            guard let current = app.viewer.session, current.entryID == ended.entryID, current.index == ended.index,
              let next = nextEntry(after: entry, session: current) else { return }
            go(entryID: next.id, index: 0)
          },
          neighbor: neighbor,
          order: order,
          onChange: { go(entryID: $0.entryID, index: $0.index) },
          onShown: { markShown($0.entryID) },
          onTap: { withAnimation(.easeInOut(duration: 0.2)) { chromeHidden.toggle() } },
          onOpenOriginal: { open($0.url) }
        )
        .ignoresSafeArea()
        .accessibilityLabel("第 \(index + 1) 张，共 \(entry.images.count) 张")
        if !chromeHidden || page.isVideo {
          chrome(entry: entry, index: index, session: session)
            .transition(.opacity)
        }
        notice
      } else {
        missing
      }
    }
    .environment(\.colorScheme, .dark)
    .statusBarHidden(chromeHidden)
    .persistentSystemOverlays(chromeHidden ? .hidden : .automatic)
    .overlay(alignment: .bottom) { ToastStack().padding(.bottom, 132) }
    .sheet(isPresented: $infoOpen) {
      if let session = app.viewer.session, let entry = store.entries[session.entryID] {
        InfoSheet(entry: entry, index: min(session.index, max(0, entry.images.count - 1)), open: open)
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
          .presentationBackground(Color(hex: 0x141418))
      }
    }
    .sheet(item: $webPage) { SafariView(url: $0.url).ignoresSafeArea() }
    .sheet(item: $sharing) { ActivityView(items: $0.items).presentationDetents([.medium, .large]) }
  }

  // MARK: 翻页顺序

  private func makePage(_ entry: Entry, _ index: Int) -> ViewerPage {
    let image = entry.images[index]
    var size: CGSize?
    if let width = image.width, let height = image.height {
      size = CGSize(width: width, height: height)
    } else if case .size(let width, let height) = app.probe.result(for: image.url) {
      size = CGSize(width: width, height: height)
    }
    return ViewerPage(entryID: entry.id, index: index, url: image.url, size: size, isVideo: image.isVideo)
  }

  /// 看完当前图集后继续翻页，直接进入相邻的图集；向前翻进入上一组的最后一张
  private func neighbor(_ page: ViewerPage, _ direction: ImagePager.Direction) -> ViewerPage? {
    let entries = app.store.entries
    guard let session = app.viewer.session, let entry = entries[page.entryID] else { return nil }
    switch direction {
    case .after:
      if page.index + 1 < entry.images.count { return makePage(entry, page.index + 1) }
      guard let position = session.sequence.firstIndex(of: entry.id) else { return nil }
      for id in session.sequence.dropFirst(position + 1) {
        if let next = entries[id], next.hasImages { return makePage(next, 0) }
      }
    case .before:
      if page.index > 0 { return makePage(entry, page.index - 1) }
      guard let position = session.sequence.firstIndex(of: entry.id) else { return nil }
      for id in session.sequence.prefix(position).reversed() {
        if let previous = entries[id], previous.hasImages { return makePage(previous, previous.images.count - 1) }
      }
    }
    return nil
  }

  private func order(_ page: ViewerPage) -> [Int] {
    [app.viewer.session?.sequence.firstIndex(of: page.entryID) ?? 0, page.index]
  }

  /// 翻页与缩略图条的跳转。多于两张的图集向后翻到最后一张时预告下一组，往回翻到第一张时预告上一组；
  /// 一两张的图集翻得快，不再每组都提示
  private func go(entryID: String, index: Int) {
    let viewer = app.viewer
    guard let session = viewer.session else { return }
    if entryID == session.entryID, let entry = app.store.entries[entryID], entry.images.count > 2 {
      if index > session.index, index == entry.images.count - 1, let next = nextEntry(after: entry, session: session) {
        viewer.notice = ViewerController.Notice(kind: .next, entryID: next.id)
      } else if index < session.index, index == 0, let previous = previousEntry(before: entry, session: session) {
        viewer.notice = ViewerController.Notice(kind: .previous, entryID: previous.id)
      }
    }
    viewer.go(entryID: entryID, index: index)
  }

  /// 至少一张图片显示成功后标为已读（可在设置中关闭）
  private func markShown(_ entryID: String) {
    let store = app.store
    if store.settings.autoRead, store.entries[entryID]?.read == false { store.setRead([entryID], true) }
  }

  private func open(_ address: String) {
    guard let url = URL(string: address), url.scheme == "http" || url.scheme == "https" else { return }
    webPage = WebPage(url: url)
  }

  // MARK: 界面

  private func chrome(entry: Entry, index: Int, session: ViewerController.Session) -> some View {
    let feed = app.store.feeds.first { $0.id == entry.feedId }
    let next = nextEntry(after: entry, session: session)
    return VStack(spacing: 0) {
      topBar(entry: entry, feed: feed, index: index)
      Spacer(minLength: 0)
      VStack(spacing: 10) {
        if entry.images.count > 1 || next != nil {
          ThumbnailStrip(entry: entry, index: index, next: next) { entryID, index in
            go(entryID: entryID, index: index)
          }
        }
        actionBar(entry: entry, index: index)
      }
      .padding(.bottom, 8)
      .background(alignment: .bottom) {
        LinearGradient(colors: [.black.opacity(0.62), .clear], startPoint: .bottom, endPoint: .top)
          .ignoresSafeArea()
          .allowsHitTesting(false)
      }
    }
  }

  private func topBar(entry: Entry, feed: Feed?, index: Int) -> some View {
    let author = feed?.author ?? entry.author
    let category = feed.flatMap { Selectors.categoryLabel($0.folderIds, folders: app.store.folders) }
    return HStack(spacing: 8) {
      Button("关闭", systemImage: "xmark") { app.viewer.close() }
        .labelStyle(.iconOnly)
        .buttonStyle(ViewerButtonStyle())
        .accessibilityIdentifier("viewer-close")
      Button {
        app.openFeed(entry.feedId)
      } label: {
        HStack(spacing: 10) {
          AvatarView(url: feed?.iconURL, name: author, size: 32, dark: true)
          VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text(author).font(.system(size: 14, weight: .semibold))
              if let category { Text(category).font(.system(size: 12)).foregroundStyle(Color.viewerSecondary) }
            }
            .lineLimit(1)
            TimelineView(.periodic(from: .now, by: 60)) { context in
              Text((entry.title.isEmpty ? "" : "\(entry.title) · ") + Formatting.relativeTime(entry.publishedAt, now: context.date))
                .font(.system(size: 12))
                .foregroundStyle(Color.viewerSecondary)
                .lineLimit(1)
            }
          }
        }
        .foregroundStyle(Color.viewerForeground)
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .glassBackground(in: Capsule(), interactive: true)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(author)，查看订阅")
      Spacer(minLength: 0)
      (Text("\(index + 1)") + Text(" / ").foregroundColor(.viewerSecondary) + Text("\(entry.images.count)"))
        .font(.counter(15))
        .foregroundStyle(Color.viewerForeground)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .glassBackground(in: Capsule())
        .accessibilityLabel("第 \(index + 1) 张，共 \(entry.images.count) 张")
    }
    .padding(.horizontal, 12)
    .padding(.top, 4)
    .background(alignment: .top) {
      LinearGradient(colors: [.black.opacity(0.62), .clear], startPoint: .top, endPoint: .bottom)
        .frame(height: 140)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
  }

  private func actionBar(entry: Entry, index: Int) -> some View {
    let image = entry.images[index]
    return HStack(spacing: 12) {
      Button(entry.starred ? "取消收藏" : "收藏", systemImage: entry.starred ? "star.fill" : "star") {
        app.store.setStarred(entry.id, !entry.starred)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
      }
      .labelStyle(.iconOnly)
      .buttonStyle(ViewerButtonStyle(active: entry.starred))
      .accessibilityIdentifier("viewer-star")

      DownloadButton(downloadKey: "\(entry.id):\(index)", entry: entry, images: [image], dark: true)
        .glassBackground(in: Circle(), interactive: true)

      Button("文章信息", systemImage: "info.circle") { infoOpen = true }
        .labelStyle(.iconOnly)
        .buttonStyle(ViewerButtonStyle())

      Menu {
        Button(image.isVideo ? "打开视频" : "打开原图", systemImage: "arrow.up.forward.square") { open(image.url) }
          .disabled(DemoArt.isDemo(URL(string: image.url) ?? URL(fileURLWithPath: "/")))
        if !entry.url.isEmpty {
          Button("查看原文", systemImage: "safari") { open(entry.url) }
        }
        Button("复制媒体地址", systemImage: "link") {
          UIPasteboard.general.string = image.url
          app.store.toasts.show("已复制媒体地址", tone: .success)
        }
        if image.isVideo, let url = URL(string: image.url) {
          ShareLink(item: url) { Label("分享视频链接", systemImage: "square.and.arrow.up") }
        } else {
          Button("分享图片…", systemImage: "square.and.arrow.up") { share(image, entry: entry) }
            .disabled(preparingShare)
        }
        Divider()
        Button(entry.read ? "标为未读" : "标为已读", systemImage: entry.read ? "eye.slash" : "eye") {
          app.store.setRead([entry.id], !entry.read)
        }
      } label: {
        Image(systemName: "ellipsis")
      }
      .buttonStyle(ViewerButtonStyle())
      .accessibilityLabel("更多操作")
    }
    .glassGroup(spacing: 12)
    .padding(.horizontal, 12)
  }

  /// 分享图片本身：先取原始数据（通常已在缓存里），写成临时文件交给系统分享
  private func share(_ image: ImageAsset, entry: Entry) {
    guard let request = ImageRequests.original(image.url) else { return }
    preparingShare = true
    let pipeline = pipeline
    Task {
      defer { preparingShare = false }
      do {
        let (data, _) = try await pipeline.data(for: request)
        let file = try ShareFile.write(data, name: "album-\(entry.id)-\(image.key.hashValue & 0xFFFF)")
        var items: [Any] = [file]
        if let url = URL(string: entry.url), !entry.url.isEmpty { items.append(url) }
        sharing = ShareFile(items: items)
      } catch {
        app.store.toasts.show("无法分享这张图片", detail: errorMessage(error), tone: .warning)
      }
    }
  }

  private func nextEntry(after entry: Entry, session: ViewerController.Session) -> Entry? {
    guard let position = session.sequence.firstIndex(of: entry.id) else { return nil }
    for id in session.sequence.dropFirst(position + 1) {
      if let next = app.store.entries[id], next.hasImages { return next }
    }
    return nil
  }

  private func previousEntry(before entry: Entry, session: ViewerController.Session) -> Entry? {
    guard let position = session.sequence.firstIndex(of: entry.id) else { return nil }
    for id in session.sequence.prefix(position).reversed() {
      if let previous = app.store.entries[id], previous.hasImages { return previous }
    }
    return nil
  }

  @ViewBuilder
  private var notice: some View {
    if let notice = app.viewer.notice, let entry = app.store.entries[notice.entryID] {
      let feed = app.store.feeds.first { $0.id == entry.feedId }
      VStack {
        HStack(spacing: 8) {
          AvatarView(url: feed?.iconURL, name: entry.author, size: 22, dark: true)
          Text(notice.kind == .next ? "下一组" : "上一组").foregroundStyle(Color.viewerSecondary)
          Text(feed?.author ?? entry.author).fontWeight(.bold)
          Text("\(entry.images.count) 张").foregroundStyle(Color.viewerSecondary)
        }
        .font(.system(size: 14))
        .foregroundStyle(Color.viewerForeground)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .glassBackground(in: Capsule())
        .padding(.top, chromeHidden ? 12 : 64)
        Spacer()
      }
      .allowsHitTesting(false)
      .transition(.move(edge: .top).combined(with: .opacity))
      .task(id: notice.id) {
        try? await Task.sleep(for: .milliseconds(1600))
        withAnimation { app.viewer.notice = nil }
      }
      .accessibilityElement(children: .combine)
    }
  }

  private var missing: some View {
    VStack(spacing: 12) {
      Text("这个图集不在本地了").font(.system(size: 18, weight: .bold))
      Text("它可能已被服务器删除，或者还没有同步到这台设备。")
        .font(.system(size: 14))
        .foregroundStyle(Color.viewerSecondary)
      Button("返回列表") { app.viewer.close() }
        .buttonStyle(.bordered)
    }
    .foregroundStyle(Color.viewerForeground)
    .padding(32)
  }
}

/// 缩略图条：当前图集的每一张，末尾是下一组的入口
private struct ThumbnailStrip: View {
  let entry: Entry
  let index: Int
  let next: Entry?
  let go: (String, Int) -> Void

  @Environment(\.horizontalSizeClass) private var sizeClass

  var body: some View {
    let side: CGFloat = sizeClass == .regular ? 48 : 40
    ScrollViewReader { proxy in
      ScrollView(.horizontal) {
        HStack(spacing: 6) {
          ForEach(Array(entry.images.enumerated()), id: \.offset) { offset, image in
            Button {
              go(entry.id, offset)
            } label: {
              MediaCover(asset: image, size: CGSize(width: side, height: side), long: false, failedEarlier: false, dimmed: false)
                .environment(\.colorScheme, .dark)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                  RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.viewerForeground, lineWidth: offset == index ? 2 : 0)
                }
                .opacity(offset == index ? 1 : 0.55)
            }
            .buttonStyle(.plain)
            .id(offset)
            .accessibilityLabel("第 \(offset + 1) 张")
            .accessibilityAddTraits(offset == index ? .isSelected : [])
          }
          if let next {
            Divider().frame(height: side * 0.6).overlay(Color.white.opacity(0.2)).padding(.horizontal, 4)
            Button {
              go(next.id, 0)
            } label: {
              HStack(spacing: 10) {
                if let cover = next.images.first {
                  MediaCover(asset: cover, size: CGSize(width: side, height: side), long: false, failedEarlier: false, dimmed: false)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                  Text("下一组").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.viewerForeground.opacity(0.75))
                  Text(next.author).font(.system(size: 13, weight: .semibold)).lineLimit(1).frame(maxWidth: 120, alignment: .leading)
                }
              }
              .foregroundStyle(Color.viewerForeground)
              .padding(.trailing, 12)
              .glassBackground(in: RoundedRectangle(cornerRadius: 8, style: .continuous), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一组：\(next.author)，\(next.images.count) 张")
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
      }
      .scrollIndicators(.hidden)
      .onAppear { proxy.scrollTo(index, anchor: .center) }
      .onChange(of: "\(entry.id):\(index)") { withAnimation { proxy.scrollTo(index, anchor: .center) } }
    }
  }
}

/// 文章信息：标题、正文段落、标签、图片说明和发布信息
private struct InfoSheet: View {
  let entry: Entry
  let index: Int
  let open: (String) -> Void

  @Environment(AppModel.self) private var app

  var body: some View {
    let store = app.store
    let feed = store.feeds.first { $0.id == entry.feedId }
    let author = feed?.author ?? entry.author
    let category = feed.flatMap { Selectors.categoryLabel($0.folderIds, folders: store.folders) }
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          HStack(spacing: 12) {
            AvatarView(url: feed?.iconURL, name: author, size: 40, dark: true)
            VStack(alignment: .leading, spacing: 2) {
              Text(author).font(.system(size: 16, weight: .semibold))
              Text((category.map { "\($0) · " } ?? "") + Formatting.relativeTime(entry.publishedAt, now: .now))
                .font(.system(size: 12))
                .foregroundStyle(Color.viewerSecondary)
            }
          }
          Text(entry.title.isEmpty ? "无标题" : entry.title)
            .font(.system(size: 20, weight: .bold))
            .textSelection(.enabled)
          ForEach(Array(entry.paragraphs.enumerated()), id: \.offset) { _, paragraph in
            Text(paragraph).font(.system(size: 15)).lineSpacing(3).textSelection(.enabled)
          }
          if !entry.tags.isEmpty {
            FlowTags(tags: entry.tags)
          }
          if entry.images.indices.contains(index), let alt = entry.images[index].alt, !Self.collapse(alt).isEmpty {
            Text("图 \(index + 1)：\(Self.collapse(alt))")
              .font(.system(size: 13))
              .foregroundStyle(Color.viewerSecondary)
          }
          VStack(spacing: 0) {
            fact("发布时间", Formatting.fullTime(entry.publishedAt))
            fact("来自订阅", feed?.title ?? "未知订阅")
            fact("媒体", "\(entry.images.filter { !$0.isVideo }.count) 张图片 · \(entry.images.filter { $0.isVideo }.count) 个视频")
          }
          .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.viewerSurface))
          HStack(spacing: 10) {
            Button(entry.starred ? "已收藏" : "收藏", systemImage: entry.starred ? "star.fill" : "star") {
              store.setStarred(entry.id, !entry.starred)
            }
            .tint(entry.starred ? Color.spot : .white)
            Button(entry.read ? "标为未读" : "标为已读", systemImage: entry.read ? "eye.slash" : "eye") {
              store.setRead([entry.id], !entry.read)
            }
            .tint(.white)
            if !entry.url.isEmpty {
              Button("查看原文", systemImage: "safari") { open(entry.url) }
                .tint(.white)
            }
          }
          .buttonStyle(.bordered)
          .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(Color.viewerForeground)
        .padding(20)
      }
      .navigationTitle("文章信息")
      .navigationBarTitleDisplayMode(.inline)
    }
    .environment(\.colorScheme, .dark)
  }

  private func fact(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label).foregroundStyle(Color.viewerSecondary)
      Spacer()
      Text(value).multilineTextAlignment(.trailing)
    }
    .font(.system(size: 14))
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }

  /// 图片说明取自 figcaption 的原始文本：按网页显示的方式合并空白
  static func collapse(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  }
}

private struct FlowTags: View {
  let tags: [String]

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 6) { chips }
      ScrollView(.horizontal) { HStack(spacing: 6) { chips } }.scrollIndicators(.hidden)
    }
  }

  private var chips: some View {
    ForEach(tags, id: \.self) { tag in
      Text("#\(tag)")
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(Color.viewerSurface2))
    }
  }
}

/// 交给系统分享的临时文件
struct ShareFile: Identifiable {
  let id = UUID()
  let items: [Any]

  static func write(_ data: Data, name: String) throws -> URL {
    let ext: String
    switch data.first {
    case 0x89: ext = "png"
    case 0x47: ext = "gif"
    case 0x52: ext = "webp"
    default: ext = "jpg"
    }
    let url = FileManager.default.temporaryDirectory.appending(path: "\(name).\(ext)")
    try data.write(to: url, options: .atomic)
    return url
  }
}

struct ActivityView: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
