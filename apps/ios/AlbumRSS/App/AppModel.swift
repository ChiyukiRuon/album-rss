import AlbumCore
import AlbumImages
import AlbumProviders
import Foundation
import Nuke
import Observation
import SwiftUI

nonisolated enum AppTab: Hashable, Sendable {
  case browse
  case starred
  case feeds
  case settings
}

/// 单个订阅页的路由
nonisolated struct FeedRoute: Hashable, Sendable {
  var feedID: String
}

/// 添加或编辑端点的弹层
enum EndpointSheet: Identifiable {
  case add
  case edit(String)

  var id: String {
    switch self {
    case .add: "add"
    case .edit(let id): "edit-\(id)"
    }
  }
}

/// 在应用内浏览器打开的网页
struct WebPage: Identifiable {
  let url: URL
  var id: String { url.absoluteString }
}

/// App 的组装：数据（store）、图片管线、尺寸测量、查看器和导航状态
@MainActor @Observable
final class AppModel {
  let store: AlbumStore
  let images: ImageService
  let probe: ImageSizeProbe
  let viewer = ViewerController()
  @ObservationIgnored let database: AlbumDatabase?

  var selectedTab: AppTab = .browse
  var browsePath: [FeedRoute] = []
  var starredPath: [FeedRoute] = []
  var feedsPath: [FeedRoute] = []
  var settingsPath: [FeedRoute] = []
  var endpointSheet: EndpointSheet?
  /// 启动参数 --appearance dark|light 指定的外观（界面测试与截图用），优先于设置
  let forcedColorScheme: ColorScheme? = {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "--appearance"), index + 1 < arguments.count else { return nil }
    return arguments[index + 1] == "dark" ? .dark : arguments[index + 1] == "light" ? .light : nil
  }()
  var webPage: WebPage?

  @ObservationIgnored private var measured: [String: StoredImageSize] = [:]
  @ObservationIgnored private var measuredFlush: Task<Void, Never>?
  @ObservationIgnored private var probeEndpointID: String?

  init() {
    Self.applyLaunchArguments()
    let database = try? AlbumDatabase(
      directory: URL.applicationSupportDirectory.appending(path: "AlbumRSS/Endpoints", directoryHint: .isDirectory))
    let images = ImageService(limit: Settings().imageCacheLimit)
    let environment = StoreEnvironment(
      makeProvider: { endpoint in
        try makeProvider(service: endpoint.service, server: endpoint.server, token: endpoint.token ?? "")
      },
      login: { server, username, password in
        try await loginGoogleReader(server: server, username: username, password: password)
      },
      credentials: KeychainCredentialStore(),
      defaults: UserDefaultsStore(),
      database: database,
      imageSaver: PhotoLibrarySaver(pipeline: { images.pipeline(for: $0) }),
      didRemoveEndpoint: { id in
        Task { @MainActor in images.removeCache(endpointID: id) }
      }
    )
    let store = AlbumStore(environment: environment)
    images.limit = store.settings.imageCacheLimit
    images.latency.isOn = store.settings.simulateLatency
    self.store = store
    self.images = images
    self.database = database
    probe = ImageSizeProbe(pipeline: images.pipeline(for: store.endpoint))
    probe.onMeasured = { [weak self] url, size in self?.remember(url, size) }
  }

  func start() async {
    images.removeUnknownCaches(keeping: Set(store.endpoints.map(\.id)))
    resetProbe()
    await store.start()
    if ProcessInfo.processInfo.arguments.contains("--demo"), store.endpoint == nil { store.enterDemo() }
  }

  /// 开发与界面测试用的启动参数：--reset 清空本地数据，--demo 直接进入演示数据
  private static func applyLaunchArguments() {
    guard ProcessInfo.processInfo.arguments.contains("--reset") else { return }
    if let bundle = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: bundle) }
    KeychainCredentialStore().removeAll()
    try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "AlbumRSS"))
    try? FileManager.default.removeItem(at: ImageService.defaultRoot)
  }

  /// 当前端点的图片管线
  var pipeline: ImagePipeline { images.pipeline(for: store.endpoint) }

  /// 换了端点：尺寸测量、导航和查看器都属于之前的端点
  func endpointChanged() {
    resetProbe()
    viewer.close()
    browsePath = []
    starredPath = []
    feedsPath = []
    settingsPath = []
  }

  private func resetProbe() {
    let endpoint = store.endpoint
    guard probeEndpointID != endpoint?.id else { return }
    flushMeasured()
    probeEndpointID = endpoint?.id
    probe.reset(pipeline: images.pipeline(for: endpoint))
    guard let endpoint, endpoint.kind == .connected, endpoint.remember, let database else { return }
    Task { [weak self] in
      guard let sizes = try? await database.imageSizes(endpoint.id), let self, self.probeEndpointID == endpoint.id else {
        return
      }
      self.probe.merge(known: sizes)
    }
  }

  /// 测量结果攒一会儿再写入，避免每张图一次写入
  private func remember(_ url: String, _ size: StoredImageSize) {
    guard let endpoint = store.endpoint, endpoint.kind == .connected, endpoint.remember else { return }
    measured[url] = size
    guard measuredFlush == nil else { return }
    measuredFlush = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      self?.flushMeasured()
    }
  }

  private func flushMeasured() {
    measuredFlush?.cancel()
    measuredFlush = nil
    guard let id = probeEndpointID, !measured.isEmpty, let database else { return }
    let sizes = measured
    measured = [:]
    Task { try? await database.saveImageSizes(id, sizes) }
  }

  /// 打开订阅页：推进当前页签的导航栈；查看器开着时先关闭
  func openFeed(_ feedID: String) {
    viewer.close()
    let route = FeedRoute(feedID: feedID)
    switch selectedTab {
    case .browse: if browsePath.last != route { browsePath.append(route) }
    case .starred: if starredPath.last != route { starredPath.append(route) }
    case .feeds: if feedsPath.last != route { feedsPath.append(route) }
    case .settings: if settingsPath.last != route { settingsPath.append(route) }
    }
  }

  /// 在应用内浏览器打开（原文、原图、网站）
  func open(_ address: String) {
    guard let url = URL(string: address), url.scheme == "http" || url.scheme == "https" else { return }
    webPage = WebPage(url: url)
  }

  func updateSettings(_ change: (inout Settings) -> Void) {
    store.updateSettings(change)
    images.limit = store.settings.imageCacheLimit
    images.latency.isOn = store.settings.simulateLatency
  }
}
