import Foundation

/// 瀑布流的纯计算部分，与 Web 端 `components/masonry/layout.ts` 一致
public enum WallLayout {
  /// 高宽比超过它的图按长图处理：限高、从顶部裁切并标“长图”
  public static let maxRatio = 1.8
  /// 很宽的图最多压到 2:1，左右裁切
  public static let minRatio = 0.5
  /// 尺寸测量超时或失败时使用的占位比例
  public static let fallbackRatio = 4.0 / 3.0
  /// 窄屏与宽屏的分界
  public static let narrowWidth = 600.0

  public struct Metrics: Equatable, Sendable {
    public var columns: Int
    public var gap: Double
    /// 卡片下方作者行的高度
    public var footer: Double
    public var columnWidth: Double

    public init(columns: Int, gap: Double, footer: Double, columnWidth: Double) {
      self.columns = columns
      self.gap = gap
      self.footer = footer
      self.columnWidth = columnWidth
    }
  }

  public static func metrics(width: Double, density: Density) -> Metrics {
    let narrow = width < narrowWidth
    let gap = narrow ? 8.0 : 16.0
    let footer = narrow ? 38.0 : 44.0
    let columns =
      narrow
      ? density.narrowColumns
      : max(2, Int(((width + gap) / (density.targetColumnWidth + gap)).rounded(.down)))
    let columnWidth = max(0, (width - gap * Double(columns - 1)) / Double(columns))
    return Metrics(columns: columns, gap: gap, footer: footer, columnWidth: columnWidth)
  }

  public struct DisplayRatio: Equatable, Sendable {
    /// 显示用的高宽比，已限制在 minRatio 与 maxRatio 之间
    public var ratio: Double
    /// 原图比显示框更长，从顶部裁切
    public var long: Bool
    /// 显示框与原图比例不同，需要按填充方式裁切
    public var cropped: Bool

    public init(ratio: Double, long: Bool, cropped: Bool) {
      self.ratio = ratio
      self.long = long
      self.cropped = cropped
    }
  }

  public static func displayRatio(width: Double, height: Double) -> DisplayRatio {
    let raw = height / width
    let ratio = min(maxRatio, max(minRatio, raw))
    return DisplayRatio(ratio: ratio, long: raw > maxRatio, cropped: ratio != raw)
  }

  public struct Placement: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var mediaHeight: Double

    public init(x: Double, y: Double, width: Double, height: Double, mediaHeight: Double) {
      self.x = x
      self.y = y
      self.width = width
      self.height = height
      self.mediaHeight = mediaHeight
    }
  }

  /// 依次放进当前最矮的一列；高度相同时靠左。结果只取决于输入，便于测试
  public static func placeTiles(
    _ ratios: [Double],
    metrics: Metrics,
    start: [Double]? = nil
  ) -> (placements: [Placement], columnHeights: [Double]) {
    var heights = start ?? Array(repeating: 0, count: metrics.columns)
    let placements = ratios.map { ratio -> Placement in
      var column = 0
      for c in 1..<max(1, metrics.columns) where heights[c] < heights[column] - 0.5 {
        column = c
      }
      let y = heights[column]
      // 与 JS 的 Math.round 一致：.5 向正无穷取整
      let mediaHeight = (metrics.columnWidth * ratio + 0.5).rounded(.down)
      let height = mediaHeight + metrics.footer
      heights[column] = y + height + metrics.gap
      return Placement(
        x: Double(column) * (metrics.columnWidth + metrics.gap),
        y: y,
        width: metrics.columnWidth,
        height: height,
        mediaHeight: mediaHeight
      )
    }
    return (placements, heights)
  }

  /// 入列顺序：在第一张还没放下的卡片之后的一个窗口内，谁先测量完谁先放下。
  /// 一张慢图不会挡住后面所有卡片，乱序也不会超过一个窗口；已经放下的卡片顺序不再改变。
  /// 没有新卡片可放时返回 nil，调用方据此判断是否需要更新。
  public static func extendPlacement(
    _ placed: [String],
    keys: [String],
    isReady: (Int) -> Bool,
    windowSize: Int
  ) -> [String]? {
    let placedSet = Set(placed)
    guard let first = keys.firstIndex(where: { !placedSet.contains($0) }) else { return nil }
    var additions: [String] = []
    let end = min(keys.count, first + windowSize)
    for i in first..<end where !placedSet.contains(keys[i]) && isReady(i) {
      additions.append(keys[i])
    }
    return additions.isEmpty ? nil : placed + additions
  }
}
