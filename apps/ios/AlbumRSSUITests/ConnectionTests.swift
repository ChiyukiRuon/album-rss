import XCTest

/// 连接本机的假服务（scripts/stub-rss-server.py），走一遍真实的网络路径。
/// 假服务没有运行时跳过。
final class ConnectionTests: XCTestCase {
  private var app: XCUIApplication!
  private static let server = "http://127.0.0.1:8787"

  override func setUpWithError() throws {
    continueAfterFailure = false
    let reachable = XCTestExpectation(description: "stub")
    var ok = false
    var request = URLRequest(url: URL(string: "\(Self.server)/v1/me")!, timeoutInterval: 3)
    request.setValue("stub-token", forHTTPHeaderField: "X-Auth-Token")
    URLSession.shared.dataTask(with: request) { _, response, _ in
      ok = (response as? HTTPURLResponse)?.statusCode == 200
      reachable.fulfill()
    }.resume()
    wait(for: [reachable], timeout: 5)
    try XCTSkipUnless(ok, "本机假服务没有运行：python3 scripts/stub-rss-server.py")
    app = XCUIApplication()
  }

  private func snapshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func type(_ text: String, into field: XCUIElement) {
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText(text)
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
  func testMinifluxConnectionReadingAndWrites() throws {
    app.launchArguments = ["--reset"]
    app.launch()
    type(Self.server, into: app.textFields["endpoint-server"])
    // 在密钥框里按“前往”直接连接
    type("stub-token\n", into: app.secureTextFields["endpoint-secret"])
    XCTAssertTrue(app.navigationBars["浏览"].waitForExistence(timeout: 30))
    XCTAssertTrue(firstCard.waitForExistence(timeout: 30))
    sleep(2)
    snapshot("50-miniflux-browse")

    firstCard.tap()
    XCTAssertTrue(app.buttons["viewer-close"].waitForExistence(timeout: 10))
    sleep(2)
    app.buttons["viewer-star"].tap()
    sleep(1)
    snapshot("51-miniflux-viewer")
    app.buttons["viewer-close"].tap()
    sleep(2)

    openTab("订阅")
    sleep(2)
    snapshot("52-miniflux-feeds")
    openTab("收藏")
    sleep(3)
    snapshot("53-miniflux-starred")
  }

  @MainActor
  func testGoogleReaderConnection() throws {
    app.launchArguments = ["--reset"]
    app.launch()
    let service = app.buttons["Google Reader 兼容"]
    XCTAssertTrue(service.waitForExistence(timeout: 10))
    service.tap()
    type("\(Self.server)/api/greader.php", into: app.textFields["endpoint-server"])
    type("reader", into: app.textFields["endpoint-username"])
    type("secret\n", into: app.secureTextFields["endpoint-secret"])
    XCTAssertTrue(app.navigationBars["浏览"].waitForExistence(timeout: 30))
    XCTAssertTrue(firstCard.waitForExistence(timeout: 30))
    sleep(2)
    snapshot("60-greader-browse")
    firstCard.tap()
    XCTAssertTrue(app.buttons["viewer-close"].waitForExistence(timeout: 10))
    sleep(2)
    app.buttons["viewer-star"].tap()
    sleep(1)
    app.buttons["viewer-close"].tap()
    sleep(1)
  }

  @MainActor
  func testWrongCredentialsExplainTheFailure() throws {
    app.launchArguments = ["--reset"]
    app.launch()
    type(Self.server, into: app.textFields["endpoint-server"])
    type("wrong-token\n", into: app.secureTextFields["endpoint-secret"])
    let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '凭据无效或已过期'")).firstMatch
    XCTAssertTrue(message.waitForExistence(timeout: 20))
    XCTAssertTrue(message.isHittable)
    snapshot("70-connect-failure")
  }
}
