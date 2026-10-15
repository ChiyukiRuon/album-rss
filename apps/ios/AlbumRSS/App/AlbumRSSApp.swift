import SwiftUI
import UIKit

@main
struct AlbumRSSApp: App {
  @State private var app = AppModel()

  init() {
    // 打开的开关轨道是墨色，深色模式下接近白色，系统默认的白色滑块会融进去；
    // 与 Web 端一样，滑块用“墨上的颜色”（浅色模式白色，深色模式近黑）
    UISwitch.appearance().thumbTintColor = UIColor(Color.onInk)
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(app)
    }
  }
}
