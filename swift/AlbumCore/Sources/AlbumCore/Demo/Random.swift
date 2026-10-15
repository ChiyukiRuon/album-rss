import Foundation

/// 可复现的伪随机数，与 Web 端 `prototype/random.ts` 的 mulberry32 逐位一致：
/// 演示数据每次生成都一样，截图和对比才稳定。
public struct Mulberry32: Sendable {
  private var state: UInt32

  public init(seed: Int) {
    state = UInt32(truncatingIfNeeded: seed)
  }

  public mutating func next() -> Double {
    state = state &+ 0x6D2B_79F5
    var t = (state ^ (state >> 15)) &* (1 | state)
    t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
    return Double(t ^ (t >> 14)) / 4_294_967_296
  }

  public mutating func pick<T>(_ items: [T]) -> T {
    items[Int((next() * Double(items.count)).rounded(.down))]
  }

  public mutating func between(_ min: Double, _ max: Double) -> Double {
    min + next() * (max - min)
  }

  public mutating func intBetween(_ min: Int, _ max: Int) -> Int {
    Int(between(Double(min), Double(max + 1)).rounded(.down))
  }

  public mutating func weighted<T>(_ options: [(T, Double)]) -> T {
    let total = options.reduce(0) { $0 + $1.1 }
    var roll = next() * total
    for (value, weight) in options {
      roll -= weight
      if roll < 0 { return value }
    }
    return options[options.count - 1].0
  }
}

/// FNV-1a，按 UTF-16 码元计算（与 JS 的 charCodeAt 一致）
public func hashString(_ value: String) -> UInt32 {
  var hash: UInt32 = 2_166_136_261
  for unit in value.utf16 {
    hash ^= UInt32(unit)
    hash = hash &* 16_777_619
  }
  return hash
}
