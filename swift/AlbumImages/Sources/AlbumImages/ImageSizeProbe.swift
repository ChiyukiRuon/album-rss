import AlbumCore
import Foundation
import Nuke
import Observation

/// 封面尺寸测量。真实订阅里绝大多数图片没有宽高，瀑布流采用“先测量再入列”：
/// 卡片在拿到尺寸（或等待超时）之后才放进布局，放下以后不再因为图片加载而移动。
/// 与 Web 端 `lib/imageProbe.ts` 一致：同时最多测量 6 张，按请求顺序排队；
/// 等待上限从请求时算起，超时的卡片按固定比例放置，之后在框内裁切显示。
@MainActor @Observable
public final class ImageSizeProbe {
  public enum Result: Equatable, Sendable {
    case size(width: Double, height: Double)
    case failed
    case timeout
  }

  public static let timeout: Duration = .seconds(3)
  static let maxConcurrent = 6

  /// 测量结果的版本号；同一轮里的多次完成合并为一次通知
  public private(set) var version = 0

  @ObservationIgnored private var results: [String: Result] = [:]
  @ObservationIgnored private var waiting: [String] = []
  @ObservationIgnored private var pending: Set<String> = []
  @ObservationIgnored private var running = 0
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var bumpScheduled = false
  @ObservationIgnored private var pipeline: ImagePipeline
  /// 测量到新尺寸时调用，用于写入本地数据库
  @ObservationIgnored public var onMeasured: ((String, StoredImageSize) -> Void)?

  public init(pipeline: ImagePipeline = .shared) {
    self.pipeline = pipeline
  }

  /// 换端点时重置；known 为本地保存的测量结果
  public func reset(pipeline: ImagePipeline, known: [String: StoredImageSize] = [:]) {
    generation += 1
    self.pipeline = pipeline
    waiting = []
    pending = []
    running = 0
    results = known.mapValues { $0.failed ? .failed : .size(width: $0.width, height: $0.height) }
    bump()
  }

  /// 补充本地保存的结果（异步读取完成后）
  public func merge(known: [String: StoredImageSize]) {
    for (url, size) in known where results[url] == nil {
      results[url] = size.failed ? .failed : .size(width: size.width, height: size.height)
    }
    bump()
  }

  public func result(for url: String) -> Result? {
    results[url]
  }

  /// 按顺序请求测量；已经有结果或正在测量的会跳过
  public func request(_ urls: [String]) {
    let epoch = generation
    for url in urls where results[url] == nil && !pending.contains(url) {
      pending.insert(url)
      waiting.append(url)
      // 等待上限从请求时算起：排队期间超时的直接放弃
      Task { [weak self] in
        try? await Task.sleep(for: Self.timeout)
        guard let self, epoch == self.generation else { return }
        self.settle(url, .timeout)
      }
    }
    pump()
  }

  private func pump() {
    while running < Self.maxConcurrent, !waiting.isEmpty {
      let url = waiting.removeFirst()
      guard results[url] == nil else { continue }
      running += 1
      let epoch = generation
      let pipeline = pipeline
      Task { [weak self] in
        let result = await Self.measure(url, pipeline: pipeline)
        guard let self, epoch == self.generation else { return }
        self.running -= 1
        self.settle(url, result)
        self.pump()
      }
    }
  }

  @concurrent
  private nonisolated static func measure(_ url: String, pipeline: ImagePipeline) async -> Result {
    guard let request = ImageRequests.original(url) else { return .failed }
    do {
      let (data, _) = try await pipeline.data(for: request)
      guard let size = ImageMetrics.pixelSize(of: data) else { return .failed }
      return .size(width: size.width, height: size.height)
    } catch {
      return .failed
    }
  }

  private func settle(_ url: String, _ result: Result) {
    pending.remove(url)
    guard results[url] == nil else { return }
    results[url] = result
    // 只保存测量到的尺寸：失败可能只是暂时离线，只在本次运行里有效
    if case .size(let width, let height) = result {
      onMeasured?(url, StoredImageSize(width: width, height: height, failed: false))
    }
    bump()
  }

  private func bump() {
    guard !bumpScheduled else { return }
    bumpScheduled = true
    Task { [weak self] in
      await Task.yield()
      guard let self else { return }
      self.bumpScheduled = false
      self.version += 1
    }
  }
}
