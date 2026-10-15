import SwiftUI
import UIKit

/// 网点底纹。凡是“还不是一张图”的状态——加载中、尺寸未知、加载失败、没有图片——
/// 都用它来呈现，像漫画原稿上的网点纸。两层 45° 点阵：大点集中在左上，小点在中段，右下留白。
/// 等待中时网点缓慢移动（与 Web 端 `components/tone` 相同）。
struct ToneView<Content: View>: View {
  var loading = false
  var background = Color.toneBackground
  var dot = Color.toneDot
  @ViewBuilder var content: () -> Content

  @State private var phase = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      ZStack {
        background
        dots(size: size, pattern: .large, stops: [
          .init(color: .black, location: 0), .init(color: .black.opacity(0.7), location: 0.22),
          .init(color: .clear, location: 0.55),
        ])
        dots(size: size, pattern: .small, stops: [
          .init(color: .clear, location: 0.25), .init(color: .black, location: 0.52),
          .init(color: .clear, location: 0.88),
        ])
        content()
      }
    }
    .clipped()
    .onAppear {
      // 不用 withAnimation：同一次更新里的其他布局变化（例如导航栏高度变化）会被一起卷进循环动画，
      // 整页内容跟着来回浮动。循环动画只作用在遮罩的位移上，见 dots(size:pattern:stops:)
      guard loading, !reduceMotion else { return }
      phase = true
    }
  }

  /// 点阵用平铺的图案填充，再用 155° 的渐变遮罩控制每个区域的点有多明显
  private func dots(size: CGSize, pattern: TonePattern, stops: [Gradient.Stop]) -> some View {
    // 等待中时遮罩放大到 2.6 倍，从左上扫到右下
    let factor: CGFloat = loading ? 2.6 : 1
    let maskSize = CGSize(width: size.width * factor, height: size.height * factor)
    let travel = CGSize(width: maskSize.width - size.width, height: maskSize.height - size.height)
    return Rectangle()
      .fill(dot)
      .mask(Rectangle().fill(ImagePaint(image: pattern.image, scale: 1 / pattern.scale)))
      .mask(alignment: .topLeading) {
        LinearGradient(stops: stops, startPoint: UnitPoint(x: 0.29, y: 0.05), endPoint: UnitPoint(x: 0.71, y: 0.95))
          .frame(width: maskSize.width, height: maskSize.height)
          .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { content in
            content.modifier(ToneSweep(progress: phase ? 1 : 0, travel: travel))
          }
      }
  }
}

/// 遮罩的扫动按进度（0…1）计算位移：尺寸变化时只换算新的距离，动画从当前进度继续
private struct ToneSweep: ViewModifier, Animatable {
  var progress: CGFloat
  var travel: CGSize

  nonisolated var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    content.offset(x: -travel.width * progress, y: -travel.height * progress)
  }
}

extension ToneView where Content == EmptyView {
  init(loading: Bool = false, background: Color = .toneBackground, dot: Color = .toneDot) {
    self.init(loading: loading, background: background, dot: dot) { EmptyView() }
  }
}

/// 9pt 一格、错位排列的圆点，只画一次，之后平铺
enum TonePattern {
  case large
  case small

  var scale: CGFloat { 3 }

  var image: Image { Image(uiImage: self == .large ? Self.largeTile : Self.smallTile) }

  private static let largeTile = tile(radius: 1.85)
  private static let smallTile = tile(radius: 1.1)

  private static func tile(radius: CGFloat) -> UIImage {
    let spacing: CGFloat = 9
    let format = UIGraphicsImageRendererFormat()
    format.scale = 3
    format.opaque = false
    return UIGraphicsImageRenderer(size: CGSize(width: spacing, height: spacing), format: format).image { context in
      UIColor.black.setFill()
      for center in [CGPoint(x: spacing / 4, y: spacing / 4), CGPoint(x: spacing * 3 / 4, y: spacing * 3 / 4)] {
        context.cgContext.fillEllipse(
          in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
      }
    }
  }
}
