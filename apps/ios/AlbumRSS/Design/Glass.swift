import SwiftUI

/// 液态玻璃：iOS 26 起用系统的 glassEffect，iOS 18 退回半透明材质。
/// 只用于浮在内容之上的控件（查看器按钮、新内容提示、轻提示、卡片角标），不用于内容本身。
extension View {
  /// 玻璃胶囊或圆形背景；interactive 时按下有液态反馈
  @ViewBuilder
  func glassBackground<S: Shape>(
    in shape: S,
    tint: Color? = nil,
    interactive: Bool = false,
    fallback: Material = .ultraThinMaterial
  ) -> some View {
    if #available(iOS 26.0, *) {
      self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
    } else if let tint {
      self.background(tint, in: shape)
    } else {
      self.background(fallback, in: shape)
    }
  }

  /// 把相邻的玻璃控件放进同一个容器，靠近时会融合
  @ViewBuilder
  func glassGroup(spacing: CGFloat = 8) -> some View {
    if #available(iOS 26.0, *) {
      GlassEffectContainer(spacing: spacing) { self }
    } else {
      self
    }
  }

  /// 页签栏随向下滚动收起（iOS 26）
  @ViewBuilder
  func minimizesTabBarOnScroll() -> some View {
    if #available(iOS 26.0, *) {
      self.tabBarMinimizeBehavior(.onScrollDown)
    } else {
      self
    }
  }
}

/// 查看器里的圆形玻璃按钮
struct ViewerButtonStyle: ButtonStyle {
  var active = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 17, weight: .semibold))
      .foregroundStyle(active ? Color.spot : Color.viewerForeground)
      .frame(width: 44, height: 44)
      .contentShape(Circle())
      .glassBackground(in: Circle(), interactive: true, fallback: .ultraThinMaterial)
      .opacity(configuration.isPressed ? 0.75 : 1)
      .environment(\.colorScheme, .dark)
  }
}
