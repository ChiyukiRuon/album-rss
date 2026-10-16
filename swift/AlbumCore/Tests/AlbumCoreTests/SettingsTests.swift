import Foundation
import Testing
@testable import AlbumCore

struct SettingsTests {
  @Test func oldSettingsKeepAutoplayDisabled() throws {
    let settings = try JSONDecoder().decode(Settings.self, from: Data("{\"autoRead\":false}".utf8))
    #expect(settings.videoEndBehavior == .pause)
    #expect(!settings.videoAutoplay)
    #expect(!settings.videoAutoplayCellular)
    #expect(!settings.autoRead)
  }

  @Test(arguments: VideoEndBehavior.allCases)
  func preservesVideoEndBehavior(_ behavior: VideoEndBehavior) throws {
    var settings = Settings()
    settings.videoEndBehavior = behavior
    let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    #expect(restored.videoEndBehavior == behavior)
  }

  @Test func unknownVideoEndBehaviorFallsBackToPause() throws {
    let settings = try JSONDecoder().decode(Settings.self, from: Data("{\"videoEndBehavior\":\"unknown\"}".utf8))
    #expect(settings.videoEndBehavior == .pause)
  }

  @Test func retainsCellularPreferenceWhenAutoplayIsDisabled() throws {
    var settings = Settings()
    settings.videoAutoplay = false
    settings.videoAutoplayCellular = true
    let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    #expect(!restored.videoAutoplay)
    #expect(restored.videoAutoplayCellular)
  }
}
