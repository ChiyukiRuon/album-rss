import AlbumCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 演示用占位插画：按地址里的种子在本地绘制，不访问任何图片站点。
/// 移植自 Web 端 `prototype/art.ts`（那里输出 SVG），随机数调用顺序一致，画面构成相同。
/// 地址形如 `https://demo.album-rss.invalid/art/{配色}/{种子}/{宽}x{高}`；`/broken/{n}` 注定加载失败。
public enum DemoArt {
  public enum Failure: Error {
    case broken
    case invalidAddress
  }

  /// 每组：背景起点、背景终点、高光、深色、点缀
  static let palettes: [String: [UInt32]] = [
    "dusk": [0xF9CDBF, 0x9B8BD8, 0xFFF1E4, 0x4F3F86, 0xF48FA0],
    "sea": [0xC4E9F3, 0x3F7DB4, 0xEFFAF7, 0x1C4672, 0x7FD3C8],
    "citrus": [0xFFF3B0, 0x93CF6A, 0xFFFBE6, 0x3F8F37, 0xFFA26E],
    "ink": [0xF6F6F4, 0xD6D6D6, 0xFFFFFF, 0x141414, 0x7A7A7A],
    "sakura": [0xFFE4EE, 0xF39ABB, 0xFFFAF6, 0xB74F78, 0xFCD2C9],
    "autumn": [0xF7D9A8, 0xC76A3B, 0xFDF0DC, 0x6F3726, 0xEAA65A],
    "night": [0x22306A, 0x6D5AA8, 0xF4C4D5, 0x0D1230, 0x8DB4EA],
    "mint": [0xDFF7EF, 0x78C6AE, 0xF8FCFA, 0x2A7865, 0xB6E2F0],
  ]

  public static func isDemo(_ url: URL) -> Bool {
    url.host() == DemoContent.host
  }

  /// 地址里带着的原始尺寸（演示数据的“原图”尺寸）
  public static func size(of url: URL) -> CGSize? {
    let parts = url.pathComponents
    guard parts.count >= 5, parts[1] == "art" else { return nil }
    let size = parts[4].split(separator: "x").compactMap { Double($0) }
    return size.count == 2 ? CGSize(width: size[0], height: size[1]) : nil
  }

  /// 绘制成 JPEG。为了速度按 maxDimension 缩小绘制，宽高比与原图一致
  public static func render(_ url: URL, maxDimension: Double = 1400) throws -> Data {
    let parts = url.pathComponents
    if parts.count >= 2, parts[1] == "broken" { throw Failure.broken }
    guard parts.count >= 5, parts[1] == "art", let palette = palettes[parts[2]], let seed = Int(parts[3]),
      let size = size(of: url), size.width > 0, size.height > 0
    else { throw Failure.invalidAddress }
    let scale = min(1, maxDimension / max(size.width, size.height))
    let pixelWidth = max(1, Int((size.width * scale).rounded()))
    let pixelHeight = max(1, Int((size.height * scale).rounded()))
    guard
      let context = CGContext(
        data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw Failure.invalidAddress }
    // 翻转成 SVG 的坐标系（原点在左上），再按原图尺寸绘制
    context.translateBy(x: 0, y: CGFloat(pixelHeight))
    context.scaleBy(x: CGFloat(pixelWidth) / size.width, y: -CGFloat(pixelHeight) / size.height)
    var rng = Mulberry32(seed: seed)
    let painter = Painter(context: context, width: size.width, height: size.height)
    if parts[2] == "ink" {
      painter.manga(&rng)
    } else {
      painter.illustration(&rng, palette.map { color($0) })
    }
    guard let image = context.makeImage() else { throw Failure.invalidAddress }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
      throw Failure.invalidAddress
    }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw Failure.invalidAddress }
    return data as Data
  }

  /// 按地址固定的加载耗时：多数很快，少数较慢，约 4% 超过尺寸测量的等待上限
  public static func simulatedDelay(for url: URL) -> Duration {
    let roll = Double(hashString(url.absoluteString) % 1000) / 1000
    let milliseconds = roll < 0.04 ? 4200 + roll * 20000 : roll < 0.3 ? 700 + roll * 3000 : 120 + roll * 900
    return .milliseconds(Int(milliseconds))
  }

  static func color(_ hex: UInt32, alpha: Double = 1) -> CGColor {
    CGColor(
      srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255, alpha: alpha)
  }
}

/// SVG 坐标里的 Math.round 与 toFixed(2)
private func n(_ value: Double) -> Double { (value + 0.5).rounded(.down) }
private func f(_ value: Double) -> Double { (value * 100).rounded() / 100 }

private struct Painter {
  let context: CGContext
  let width: Double
  let height: Double

  func illustration(_ rng: inout Mulberry32, _ p: [CGColor]) {
    let w = width
    let h = height
    let m = min(w, h)
    let angle = n(rng.next() * 360)
    // 背景渐变：在 objectBoundingBox 坐标里绕中心旋转，再映射到画布（与 SVG 的 gradientTransform 相同）
    context.saveGState()
    context.scaleBy(x: w, y: h)
    let radians = angle * .pi / 180
    func rotate(_ x: Double, _ y: Double) -> CGPoint {
      let dx = x - 0.5
      let dy = y - 0.5
      return CGPoint(x: 0.5 + dx * cos(radians) - dy * sin(radians), y: 0.5 + dx * sin(radians) + dy * cos(radians))
    }
    let background = CGGradient(colorsSpace: nil, colors: [p[0], p[1]] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(
      background, start: rotate(0, 0), end: rotate(1, 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()

    // 柔和的色块，像插画背景里的光和氛围
    let blobs = rng.intBetween(4, 7)
    for _ in 0..<blobs {
      let color = rng.pick(p)
      let rx = m * rng.between(0.25, 0.7)
      let ry = rx * rng.between(0.55, 1.4)
      let opacity = f(rng.between(0.5, 0.95))
      let cx = n(rng.next() * w)
      let cy = n(rng.next() * h)
      let gradient = CGGradient(
        colorsSpace: nil, colors: [color.copy(alpha: opacity)!, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
      context.saveGState()
      context.translateBy(x: cx, y: cy)
      context.scaleBy(x: n(rx), y: n(ry))
      context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
      context.restoreGState()
    }

    // 地平线
    if rng.next() < 0.6 {
      let y = h * rng.between(0.62, 0.84)
      let bend = h * rng.between(-0.08, 0.08)
      let opacity = f(rng.between(0.16, 0.32))
      let path = CGMutablePath()
      path.move(to: CGPoint(x: 0, y: n(y)))
      path.addQuadCurve(to: CGPoint(x: w, y: n(y - bend)), control: CGPoint(x: n(w / 2), y: n(y + bend)))
      path.addLine(to: CGPoint(x: w, y: h))
      path.addLine(to: CGPoint(x: 0, y: h))
      path.closeSubpath()
      context.addPath(path)
      context.setFillColor(p[3].copy(alpha: opacity)!)
      context.fillPath()
    }

    // 人物剪影：头与肩，暗示这是一张角色插画
    if rng.next() < 0.72 {
      let cx = w * rng.between(0.34, 0.66)
      let r = m * rng.between(0.085, 0.13)
      let headY = h * rng.between(0.4, 0.56)
      let half = r * rng.between(1.7, 2.2)
      let top = headY + r * 2.1
      let opacity = f(rng.between(0.5, 0.78))
      // 两个形状在同一个 <g fill-opacity> 里：分别填充，重叠处会更深，与 SVG 一致
      context.setFillColor(p[3].copy(alpha: opacity)!)
      context.fillEllipse(in: CGRect(x: n(cx) - n(r), y: n(headY) - n(r), width: n(r) * 2, height: n(r) * 2))
      let shoulders = CGMutablePath()
      shoulders.move(to: CGPoint(x: n(cx - half), y: h))
      shoulders.addCurve(
        to: CGPoint(x: n(cx + half), y: h), control1: CGPoint(x: n(cx - half), y: n(top)),
        control2: CGPoint(x: n(cx + half), y: n(top)))
      shoulders.closeSubpath()
      context.addPath(shoulders)
      context.fillPath()
    }

    // 光点
    let dots = rng.intBetween(6, 16)
    for _ in 0..<dots {
      let cx = n(rng.next() * w)
      let cy = n(rng.next() * h)
      let r = n(m * rng.between(0.004, 0.018))
      let opacity = f(rng.between(0.45, 0.95))
      context.setFillColor(p[2].copy(alpha: opacity)!)
      context.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }
  }

  /// 黑白漫画页：分格、网点和速度线；长图时排成条漫
  func manga(_ rng: inout Mulberry32) {
    let w = width
    let h = height
    let m = min(w, h)
    let margin = m * 0.06
    let gutter = m * 0.03
    let stroke = max(2, m * 0.006)
    context.setFillColor(DemoArt.color(0xFBFBF9))
    context.fill(CGRect(x: 0, y: 0, width: w, height: h))

    let strip = h / w > 2.2
    let rows = strip ? max(3, Int(n((h / w) * 1.4))) : rng.intBetween(3, 4)
    let weights = (0..<rows).map { _ in rng.between(0.7, 1.3) }
    let total = weights.reduce(0, +)
    let rowGap = strip ? gutter * 4 : gutter
    let usable = h - margin * 2 - rowGap * Double(rows - 1)
    var y = margin
    for weight in weights {
      let rowH = (usable * weight) / total
      let split = !strip && rng.next() < 0.55 ? 2 : 1
      let ratio = split == 2 ? rng.between(0.35, 0.65) : 1
      let shares = split == 2 ? [ratio, 1 - ratio] : [1.0]
      var x = margin
      let rowW = w - margin * 2 - gutter * Double(split - 1)
      for share in shares {
        let pw = rowW * share
        let frame = CGRect(x: x, y: y, width: pw, height: rowH)
        context.saveGState()
        context.clip(to: frame)
        panel(&rng, frame, m)
        context.restoreGState()
        context.setStrokeColor(DemoArt.color(0x141414))
        context.setLineWidth(stroke)
        context.stroke(frame)
        x += pw + gutter
      }
      y += rowH + rowGap
    }
  }

  private func panel(_ rng: inout Mulberry32, _ frame: CGRect, _ m: Double) {
    let x = frame.minX
    let y = frame.minY
    let w = frame.width
    let h = frame.height
    let kind = rng.pick(["tone", "speed", "fade", "plain"])
    if kind == "tone" {
      // 45° 旋转的网点
      let dot = m * 0.016
      context.saveGState()
      context.setFillColor(DemoArt.color(0x1A1A1A, alpha: 0.55))
      let reach = hypot(w, h)
      let center = CGPoint(x: frame.midX, y: frame.midY)
      context.translateBy(x: center.x, y: center.y)
      context.rotate(by: .pi / 4)
      let count = Int(reach / dot) + 2
      for row in -count...count {
        for column in -count...count {
          let px = Double(column) * dot
          let py = Double(row) * dot
          context.addEllipse(in: CGRect(x: px - dot * 0.27, y: py - dot * 0.27, width: dot * 0.54, height: dot * 0.54))
        }
      }
      context.fillPath()
      context.restoreGState()
    }
    if kind == "fade" {
      let gradient = CGGradient(
        colorsSpace: nil,
        colors: [DemoArt.color(0x2A2A2A, alpha: 0.4), DemoArt.color(0x2A2A2A, alpha: 0)] as CFArray,
        locations: [0, 1])!
      context.saveGState()
      context.clip(to: CGRect(x: x, y: y, width: w, height: h * 0.6))
      context.drawLinearGradient(gradient, start: CGPoint(x: x, y: y), end: CGPoint(x: x, y: y + h * 0.6), options: [])
      context.restoreGState()
    }
    if kind == "speed" {
      let cx = x + w * rng.between(0.3, 0.7)
      let cy = y + h * rng.between(0.3, 0.7)
      let reach = hypot(w, h)
      context.saveGState()
      context.setStrokeColor(DemoArt.color(0x1A1A1A, alpha: 0.7))
      context.setLineWidth(max(1, m * 0.0025))
      for i in 0..<36 {
        let a = Double(i) / 36 * .pi * 2 + rng.next() * 0.08
        let inner = reach * rng.between(0.12, 0.22)
        context.move(to: CGPoint(x: cx + cos(a) * inner, y: cy + sin(a) * inner))
        context.addLine(to: CGPoint(x: cx + cos(a) * reach, y: cy + sin(a) * reach))
      }
      context.strokePath()
      context.restoreGState()
    }
    // 部分分格里放一个角色轮廓
    if rng.next() < 0.55 {
      let r = min(w, h) * rng.between(0.14, 0.22)
      let cx = x + w * rng.between(0.3, 0.7)
      let cy = y + h * rng.between(0.35, 0.6)
      let line = max(2, m * 0.005)
      context.setFillColor(DemoArt.color(0xFFFFFF))
      context.setStrokeColor(DemoArt.color(0x141414))
      context.setLineWidth(line)
      context.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
      context.drawPath(using: .fillStroke)
      let body = CGMutablePath()
      body.move(to: CGPoint(x: cx - r * 1.9, y: y + h))
      body.addCurve(
        to: CGPoint(x: cx + r * 1.9, y: y + h), control1: CGPoint(x: cx - r * 1.9, y: cy + r * 1.6),
        control2: CGPoint(x: cx + r * 1.9, y: cy + r * 1.6))
      body.closeSubpath()
      context.addPath(body)
      context.drawPath(using: .fillStroke)
    }
  }
}
