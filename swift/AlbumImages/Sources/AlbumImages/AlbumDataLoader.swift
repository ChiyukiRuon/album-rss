import AlbumCore
import Foundation
import Nuke
import Synchronization

/// 演示：是否模拟图片加载耗时（设置页的“原型调试”）
public final class LatencySwitch: Sendable {
  private let value = Mutex(false)

  public init() {}

  public var isOn: Bool {
    get { value.withLock { $0 } }
    set { value.withLock { $0 = newValue } }
  }
}

/// 图片数据的唯一来源：演示地址在本地绘制，不会发出请求；其他地址走网络，不带 cookie 与来源信息
public final class AlbumDataLoader: DataLoading, Sendable {
  private let network: DataLoader
  private let latency: LatencySwitch

  public init(latency: LatencySwitch) {
    let configuration = URLSessionConfiguration.default
    // 原图由 Nuke 的磁盘缓存保存，不再经过 URLCache
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.timeoutIntervalForRequest = 30
    configuration.httpMaximumConnectionsPerHost = 6
    network = DataLoader(configuration: configuration)
    self.latency = latency
  }

  public func loadData(
    with request: URLRequest,
    didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
    completion: @escaping @Sendable (Error?) -> Void
  ) -> any Cancellable {
    guard let url = request.url, DemoArt.isDemo(url) else {
      return network.loadData(with: request, didReceiveData: didReceiveData, completion: completion)
    }
    let simulate = latency.isOn
    let task = Task.detached(priority: .userInitiated) {
      if simulate { try? await Task.sleep(for: DemoArt.simulatedDelay(for: url)) }
      if Task.isCancelled {
        completion(URLError(.cancelled))
        return
      }
      do {
        let data = try DemoArt.render(url)
        let response = HTTPURLResponse(
          url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/jpeg"])!
        didReceiveData(data, response)
        completion(nil)
      } catch {
        completion(error)
      }
    }
    return TaskCancellable(task: task)
  }
}

private struct TaskCancellable: Cancellable {
  let task: Task<Void, Never>

  func cancel() {
    task.cancel()
  }
}
