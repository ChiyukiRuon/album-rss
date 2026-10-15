import XCTest

/// 用演示数据走一遍主要流程，并在每一步留下截图（xcresult 附件）
final class DemoFlowTests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["--reset", "--demo"]
  }

  private func snapshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func waitForBrowse() {
    XCTAssertTrue(app.navigationBars["浏览"].waitForExistence(timeout: 20))
    // 等待瀑布流放下第一批卡片
    XCTAssertTrue(firstCard.waitForExistence(timeout: 20))
  }

  /// iPhone 的页签栏在底部；iPad 上页签在顶部，不是 TabBar 元素
  private func openTab(_ name: String) {
    let tab = app.tabBars.buttons[name]
    if tab.exists { tab.tap() } else { app.buttons[name].firstMatch.tap() }
  }

  private var firstCard: XCUIElement {
    app.buttons.matching(NSPredicate(format: "label CONTAINS '张图片'")).firstMatch
  }

  @MainActor
  func testBrowseAndViewer() throws {
    app.launch()
    waitForBrowse()
    sleep(2)
    snapshot("01-browse")

    firstCard.tap()
    let close = app.buttons["viewer-close"]
    XCTAssertTrue(close.waitForExistence(timeout: 10))
    sleep(2)
    snapshot("02-viewer")

    // 连续向后翻，跨进下一组
    for _ in 0..<3 {
      app.swipeLeft()
      sleep(1)
    }
    snapshot("03-viewer-next")

    app.buttons["viewer-star"].tap()
    sleep(1)
    snapshot("04-viewer-starred")

    app.buttons["文章信息"].tap()
    sleep(2)
    snapshot("05-info")
    app.swipeDown(velocity: .fast)
    sleep(1)

    // 单击隐藏界面
    app.tap()
    sleep(1)
    snapshot("06-viewer-immersive")
    app.tap()
    sleep(1)

    app.buttons["viewer-close"].tap()
    sleep(2)
    snapshot("07-browse-after-viewer")
  }

  /// 缩放过渡：打开时从卡片放大，跨图集翻页后关闭时缩回当前的卡片；下滑也能关闭
  @MainActor
  func testZoomTransitionAndSwipeDown() throws {
    app.launch()
    waitForBrowse()
    sleep(2)
    firstCard.tap()
    for index in 0..<3 { snapshot("80-open-\(index)") }
    let close = app.buttons["viewer-close"]
    XCTAssertTrue(close.waitForExistence(timeout: 10))
    sleep(2)
    app.swipeLeft()
    sleep(1)
    app.swipeLeft()
    sleep(2)
    snapshot("81-before-close")
    close.tap()
    for index in 0..<4 { snapshot("82-close-\(index)") }
    sleep(2)
    snapshot("83-after-close")

    firstCard.tap()
    XCTAssertTrue(close.waitForExistence(timeout: 10))
    sleep(2)
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
    start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
    sleep(2)
    snapshot("84-after-swipe-down")
    XCTAssertFalse(close.exists, "下滑应当关闭查看器")
  }

  /// 不翻页直接关闭：列表应停在原来的位置
  @MainActor
  func testCloseKeepsListPosition() throws {
    app.launch()
    waitForBrowse()
    sleep(2)
    snapshot("90-before-open")
    firstCard.tap()
    let close = app.buttons["viewer-close"]
    XCTAssertTrue(close.waitForExistence(timeout: 10))
    sleep(2)
    close.tap()
    sleep(2)
    snapshot("91-after-close")
  }

  @MainActor
  func testImageStreamAndFolders() throws {
    app.launch()
    waitForBrowse()
    app.buttons["图片流"].tap()
    sleep(3)
    snapshot("10-image-stream")
    app.buttons["全部"].firstMatch.tap()
    sleep(1)
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH '漫画'")).firstMatch.tap()
    sleep(3)
    snapshot("11-comics-all")
  }

  @MainActor
  func testFeedsAndFeedPage() throws {
    app.launch()
    waitForBrowse()
    openTab("订阅")
    XCTAssertTrue(app.navigationBars["订阅"].waitForExistence(timeout: 10))
    sleep(2)
    snapshot("20-feeds")
    app.buttons.matching(NSPredicate(format: "label CONTAINS 'Hoshino Tsumugi'")).firstMatch.tap()
    sleep(3)
    snapshot("21-feed-with-error")
  }

  @MainActor
  func testSettings() throws {
    app.launch()
    waitForBrowse()
    openTab("设置")
    XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 10))
    sleep(1)
    snapshot("30-settings")
    app.swipeUp()
    sleep(1)
    snapshot("31-settings-bottom")
  }

  @MainActor
  func testDarkMode() throws {
    app.launchArguments += ["--appearance", "dark"]
    app.launch()
    waitForBrowse()
    sleep(2)
    snapshot("40-browse-dark")
    openTab("收藏")
    sleep(3)
    snapshot("41-starred-dark")
    openTab("设置")
    XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 10))
    // 深色模式下的开关：打开时是浅色轨道和深色滑块
    XCTAssertEqual(app.switches.firstMatch.value as? String, "1")
    sleep(1)
    snapshot("42-settings-dark")
  }
}
