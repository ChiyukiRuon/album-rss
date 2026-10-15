import SwiftUI
import UIKit

/// 设计变量：白纸、墨、网点。界面本身只用灰阶，把色彩留给插画；
/// 唯一的彩色是印刷品红（spot），只标记“属于你”的状态：收藏、未读计数、新内容提示。
/// 数值与 Web 端 `styles/tokens.css` 相同。
extension Color {
  static let paper = Color(light: 0xFFFFFF, dark: 0x111114)
  static let paper2 = Color(light: 0xF5F5F7, dark: 0x1B1B20)
  static let paper3 = Color(light: 0xECECF0, dark: 0x24242A)
  static let line = Color(light: 0xE7E7EC, dark: 0x2A2A31)
  static let toneBackground = Color(light: 0xF2F2F5, dark: 0x19191E)
  static let toneDot = Color(light: 0xD2D2DA, dark: 0x33333B)

  static let ink = Color(light: 0x16161A, dark: 0xF1F1F4)
  static let ink2 = Color(light: 0x5C5C66, dark: 0xA9A9B3)
  static let ink3 = Color(light: 0x8E8E98, dark: 0x74747E)
  static let onInk = Color(light: 0xFFFFFF, dark: 0x111114)

  static let spot = Color(light: 0xE5007E, dark: 0xFF3D9E)
  static let spotSoft = Color(light: 0xFDE8F3, dark: 0x3A1229)
  static let danger = Color(light: 0xC4321B, dark: 0xFF6B55)
  static let dangerSoft = Color(light: 0xFDEEEB, dark: 0x3A1A15)
  static let ok = Color(light: 0x0F8A5F, dark: 0x3CCF94)

  /// 查看器始终是深色，不随主题变化
  static let viewerBackground = Color(hex: 0x0D0D0F)
  static let viewerForeground = Color(hex: 0xF3F3F5)
  static let viewerSecondary = Color(hex: 0xA3A3AD)
  static let viewerSurface = Color.white.opacity(0.08)
  static let viewerSurface2 = Color.white.opacity(0.15)
  static let viewerTone = Color(hex: 0x17171B)
  static let viewerToneDot = Color(hex: 0x2C2C33)

  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255, opacity: opacity)
  }

  init(light: UInt32, dark: UInt32) {
    self.init(
      uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
      })
  }
}

extension UIColor {
  convenience init(hex: UInt32, alpha: CGFloat = 1) {
    self.init(
      red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
  }
}

extension Font {
  /// 计数与标志用加宽字形（Web 端的 font-stretch）
  static func counter(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: weight).width(.expanded).monospacedDigit()
  }
}

enum Radius {
  static let card: CGFloat = 14
  static let medium: CGFloat = 10
  static let small: CGFloat = 8
}
