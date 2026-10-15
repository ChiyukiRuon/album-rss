import AlbumCore
import AlbumImages
import SwiftUI

/// 没有端点时是连接页；端点的第一页还没读完时是等待页；之后是四个页签
struct RootView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.scenePhase) private var scenePhase
  @Namespace private var hero

  var body: some View {
    @Bindable var app = app
    @Bindable var viewer = app.viewer
    let store = app.store
    Group {
      if store.endpoint == nil {
        ConnectView()
      } else if !store.loaded {
        LoadingView(title: "正在同步订阅和图集…", description: "正在读取订阅和最新一页文章，更早的文章会在浏览时按需读取。")
      } else {
        MainTabView()
      }
    }
    .environment(\.heroNamespace, hero)
    .environment(\.imagePipeline, app.pipeline)
    .overlay(alignment: .bottom) {
      ToastStack()
        .padding(.bottom, store.endpoint == nil || !store.loaded ? 24 : 92)
    }
    .fullScreenCover(item: $viewer.session) { _ in
      ViewerView()
        .environment(\.imagePipeline, app.pipeline)
        .modifier(ZoomTransition(sourceID: app.viewer.cardKey, namespace: hero))
    }
    .sheet(item: $app.endpointSheet) { route in
      EndpointSheetView(route: route)
    }
    .sheet(item: $app.webPage) { page in
      SafariView(url: page.url).ignoresSafeArea()
    }
    .tint(Color.ink)
    .preferredColorScheme(colorScheme)
    .task { await app.start() }
    .onChange(of: store.endpoint?.id) { app.endpointChanged() }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active: store.didBecomeActive()
      case .background: store.didEnterBackground()
      default: break
      }
    }
  }

  private var colorScheme: ColorScheme? {
    if let forced = app.forcedColorScheme { return forced }
    switch app.store.settings.theme {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }
}

/// 卡片与查看器之间的缩放过渡（iOS 18 起）：关闭时缩回最后看的那张卡片
private struct ZoomTransition: ViewModifier {
  let sourceID: String?
  let namespace: Namespace.ID

  func body(content: Content) -> some View {
    if let sourceID {
      content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
    } else {
      content
    }
  }
}

struct MainTabView: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    @Bindable var app = app
    TabView(selection: $app.selectedTab) {
      Tab("浏览", systemImage: "square.grid.2x2", value: AppTab.browse) {
        NavigationStack(path: $app.browsePath) {
          BrowseView().feedDestinations()
        }
      }
      .badge(app.store.sync.pendingIDs.count)

      Tab("收藏", systemImage: "star", value: AppTab.starred) {
        NavigationStack(path: $app.starredPath) {
          StarredView().feedDestinations()
        }
      }

      Tab("订阅", systemImage: "dot.radiowaves.up.forward", value: AppTab.feeds) {
        NavigationStack(path: $app.feedsPath) {
          FeedsView().feedDestinations()
        }
      }

      Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
        NavigationStack(path: $app.settingsPath) {
          SettingsView().feedDestinations()
        }
      }
    }
    .minimizesTabBarOnScroll()
  }
}

extension View {
  func feedDestinations() -> some View {
    navigationDestination(for: FeedRoute.self) { route in
      FeedView(feedID: route.feedID)
    }
  }

  /// 页签首页的标题
  func tabPageTitle(_ title: String) -> some View {
    modifier(TabPageTitle(title: title))
  }
}

/// iPhone 上大号标题与右上角的按钮放在同一行；iPad 顶部的一行是页签栏，
/// 标题放不进去会被隐藏，仍用大标题显示在页签栏下方（要写明 .large，.automatic 在这里也会隐藏标题）
private struct TabPageTitle: ViewModifier {
  let title: String
  @Environment(\.horizontalSizeClass) private var sizeClass

  func body(content: Content) -> some View {
    content
      .navigationTitle(title)
      .toolbarTitleDisplayMode(sizeClass == .compact ? .inlineLarge : .large)
  }
}
