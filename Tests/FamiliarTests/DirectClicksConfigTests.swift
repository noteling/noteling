import Foundation
import Testing
@testable import Familiar

@Suite
struct DirectClicksConfigTests {
    @Test func directClicksAreOnByDefaultAndCanBeTurnedOff() throws {
        #expect(Config().backgroundDirectClicks)
        let existing = Data(#"{"allowControl":true,"controlInBackground":true,"backgroundDirectClicks":false}"#.utf8)
        let restored = try JSONDecoder().decode(Config.self, from: existing)
        #expect(restored.allowControl)
        #expect(restored.controlInBackground)
        #expect(!restored.backgroundDirectClicks)
    }

    /// Settings saved while direct clicks were experimental wrote `backgroundPreciseClicks: false` into every file, and
    /// the separate-display experiment left `backgroundVirtualDisplay` behind; neither old key means anything now.
    @Test func oldExperimentalKeysAreIgnored() throws {
        let old = Data(#"{"allowControl":true,"controlInBackground":true,"backgroundPreciseClicks":false,"backgroundVirtualDisplay":true}"#.utf8)
        let restored = try JSONDecoder().decode(Config.self, from: old)
        #expect(restored.backgroundDirectClicks)
        let written = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        #expect(written["backgroundVirtualDisplay"] == nil)
        #expect(written["backgroundPreciseClicks"] == nil)
    }

    @Test @MainActor
    func settingsLoadsAndRefreshesDirectClicks() {
        var config = Config()
        config.connectionMode = "claudeCode" // No API credentials are read for this settings fixture.
        config.backgroundDirectClicks = false
        let model = SettingsModel()
        model.load(config: config, packs: [])
        #expect(!model.backgroundDirectClicks)

        config.backgroundDirectClicks = true
        model.load(config: config, packs: [])
        #expect(model.backgroundDirectClicks)
    }
}
