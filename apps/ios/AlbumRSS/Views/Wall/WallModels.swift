import AlbumCore
import CoreGraphics
import AlbumImages
import Foundation

/// 瀑布流里的一张卡片：图集模式一篇文章一张，图片流里一张图一张
struct WallItem: Identifiable {
  let entry: Entry
  /// 图片流里的图片序号；图集模式为 nil
  let index: Int?

  var key: String { Self.key(entryID: entry.id, index: index) }
  var id: String { key }
  var cover: ImageAsset? { entry.images.indices.contains(index ?? 0) ? entry.images[index ?? 0] : nil }

  static func key(entryID: String, index: Int?) -> String {
    index.map { "\(entryID):\($0)" } ?? entryID
  }
}

/// 卡片在布局里的比例：来自已知宽高、测量结果，或测量失败 / 超时时的占位比例
nonisolated struct ResolvedTile: Equatable, Sendable {
  var ratio: Double
  var long: Bool
  var cropped: Bool
  /// 尺寸测量时图片就加载失败了
  var failed: Bool

  static let text = ResolvedTile(ratio: 1.05, long: false, cropped: false, failed: false)

  init(ratio: Double, long: Bool, cropped: Bool, failed: Bool) {
    self.ratio = ratio
    self.long = long
    self.cropped = cropped
    self.failed = failed
  }

  init(_ display: WallLayout.DisplayRatio) {
    self.init(ratio: display.ratio, long: display.long, cropped: display.cropped, failed: false)
  }

  @MainActor
  static func resolve(_ item: WallItem, probe: ImageSizeProbe) -> ResolvedTile? {
    guard let cover = item.cover else { return .text }
    if cover.isVideo { return ResolvedTile(WallLayout.displayRatio(width: cover.width ?? 16, height: cover.height ?? 9)) }
    if let width = cover.width, let height = cover.height {
      return ResolvedTile(WallLayout.displayRatio(width: width, height: height))
    }
    switch probe.result(for: cover.url) {
    case .size(let width, let height):
      return ResolvedTile(WallLayout.displayRatio(width: width, height: height))
    case .failed:
      return ResolvedTile(ratio: WallLayout.fallbackRatio, long: false, cropped: true, failed: true)
    case .timeout:
      return ResolvedTile(ratio: WallLayout.fallbackRatio, long: false, cropped: true, failed: false)
    case nil:
      return nil
    }
  }
}

/// 视口在瀑布流坐标里的上下边界，按 160pt 分档：滚动时不必每帧重新排版
nonisolated struct VisibleWindow: Equatable, Sendable {
  static let bucket: Double = 160

  var top: Double = 0
  var bottom: Double = 1600
  var height: Double = 900

  init() {}

  init(_ rect: CGRect) {
    top = (rect.minY / Self.bucket).rounded(.down) * Self.bucket
    bottom = (rect.maxY / Self.bucket).rounded(.up) * Self.bucket
    height = max(1, rect.height)
  }
}

/// 视图保存的、不触发重绘的中间结果（列表快照、已放下的卡片），与 Web 端 useState 的“上一次结果”对应
final class WallMemory {
  var snapshot: ListSnapshot?
  var layoutKey = ""
  var placed: [String] = []
  var pages = 1
  var stallLength = -1
  var misses = 0
  var viewerLoadsLength = -1
  var viewerLoads = 0
  /// 精确的可见区域（瀑布流坐标）：只在跟随查看器时读取，滚动时更新它不会触发重绘
  var visibleRect = CGRect.zero
}
