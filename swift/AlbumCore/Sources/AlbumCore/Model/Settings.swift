import Foundation

public enum Theme: String, Codable, Sendable, CaseIterable {
  case system
  case light
  case dark
}

/// 卡片大小：窄屏上分别是三列、两列和一列
public enum Density: String, Codable, Sendable, CaseIterable {
  case compact
  case standard
  case roomy

  /// 宽屏时的目标列宽
  var targetColumnWidth: Double {
    switch self {
    case .compact: 168
    case .standard: 208
    case .roomy: 288
    }
  }

  var narrowColumns: Int {
    switch self {
    case .compact: 3
    case .standard: 2
    case .roomy: 1
    }
  }
}

public enum ListStatus: String, Codable, Sendable, CaseIterable {
  case unread
  case all
}

/// 展示方式：每篇文章一张卡片，或展开成每张图片一张卡片
public enum WallMode: String, Codable, Sendable, CaseIterable {
  case albums
  case images
}

public struct Settings: Codable, Equatable, Sendable {
  /// 进入图集且至少一张图片显示成功后标记已读
  public var autoRead = true
  /// 保存到相册全部成功后标记已读
  public var downloadRead = true
  /// 显示没有图片或图片待解析的文章
  public var showImageless = false
  public var defaultStatus: ListStatus = .unread
  public var density: Density = .standard
  public var theme: Theme = .system
  /// 图片缓存的容量上限（字节）
  public var imageCacheLimit = 1_000_000_000
  /// 演示：模拟图片加载耗时，用来查看占位与测量过程
  public var simulateLatency = true

  public init() {}

  /// 逐项读取：旧版本保存的设置缺少新字段时使用默认值
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Settings()
    autoRead = (try? container.decode(Bool.self, forKey: .autoRead)) ?? defaults.autoRead
    downloadRead = (try? container.decode(Bool.self, forKey: .downloadRead)) ?? defaults.downloadRead
    showImageless = (try? container.decode(Bool.self, forKey: .showImageless)) ?? defaults.showImageless
    defaultStatus = (try? container.decode(ListStatus.self, forKey: .defaultStatus)) ?? defaults.defaultStatus
    density = (try? container.decode(Density.self, forKey: .density)) ?? defaults.density
    theme = (try? container.decode(Theme.self, forKey: .theme)) ?? defaults.theme
    imageCacheLimit = (try? container.decode(Int.self, forKey: .imageCacheLimit)) ?? defaults.imageCacheLimit
    simulateLatency = (try? container.decode(Bool.self, forKey: .simulateLatency)) ?? defaults.simulateLatency
  }
}
