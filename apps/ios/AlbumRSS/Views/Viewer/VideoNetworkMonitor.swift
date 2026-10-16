import Network
import Observation

/// 未确认网络前不自动播放；蜂窝网络和个人热点均按数据流量处理。
@MainActor @Observable
final class VideoNetworkMonitor {
  static let shared = VideoNetworkMonitor()
  private(set) var unmetered = false
  private(set) var connected = false
  private let monitor = NWPathMonitor()

  private init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let connected = path.status == .satisfied
      let unmetered = connected && !path.isExpensive && !path.usesInterfaceType(.cellular)
      Task { @MainActor [weak self] in
        self?.connected = connected
        self?.unmetered = unmetered
      }
    }
    monitor.start(queue: DispatchQueue(label: "album.video-network"))
  }
}
