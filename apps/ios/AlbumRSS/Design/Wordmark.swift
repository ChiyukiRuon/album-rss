import SwiftUI

/// 标志：一小块瀑布流，其中一格是品红
struct LogoMark: View {
  var size: CGFloat = 22

  var body: some View {
    Canvas { context, canvas in
      let unit = canvas.width / 22
      func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit), cornerRadius: 2.5 * unit)
      }
      context.fill(block(1, 1, 9, 12), with: .color(.ink))
      context.fill(block(1, 15, 9, 6), with: .color(.ink))
      context.fill(block(12, 1, 9, 7), with: .color(.spot))
      context.fill(block(12, 10, 9, 11), with: .color(.ink))
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

struct Wordmark: View {
  var body: some View {
    HStack(spacing: 9) {
      LogoMark()
      (Text("Album").font(.system(size: 18, weight: .heavy).width(.expanded))
        + Text(" RSS").font(.system(size: 18, weight: .medium)).foregroundColor(.ink3))
        .foregroundStyle(Color.ink)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Album RSS")
  }
}
