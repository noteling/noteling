import Foundation
import Testing
@testable import Familiar

@Suite
struct BackgroundDisplayConfigTests {
    @Test func separateDisplayIsOptInForNewAndExistingConfigurations() throws {
        #expect(!Config().backgroundVirtualDisplay)
        let existing = Data(#"{"allowControl":true,"controlInBackground":true,"backgroundDirectClicks":false}"#.utf8)
        let restored = try JSONDecoder().decode(Config.self, from: existing)

        #expect(!restored.backgroundVirtualDisplay)
        #expect(restored.allowControl)
        #expect(restored.controlInBackground)
        #expect(!restored.backgroundDirectClicks)
    }

    /// Settings saved while direct clicks were experimental wrote `backgroundPreciseClicks: false` into every file; that
    /// old key must not keep the proven path off now that it is the default.
    @Test func directClicksStayOnDespiteTheOldExperimentalKey() throws {
        #expect(Config().backgroundDirectClicks)
        let old = Data(#"{"allowControl":true,"controlInBackground":true,"backgroundPreciseClicks":false,"backgroundVirtualDisplay":true}"#.utf8)
        let restored = try JSONDecoder().decode(Config.self, from: old)
        #expect(restored.backgroundDirectClicks)
        #expect(restored.backgroundVirtualDisplay)
    }

    @Test(arguments: [false, true])
    func separateDisplayPreferenceSurvivesPersistence(_ enabled: Bool) throws {
        var config = Config()
        config.backgroundVirtualDisplay = enabled
        config.allowControl = true
        config.controlInBackground = true

        let data = try JSONEncoder().encode(config)
        let restored = try JSONDecoder().decode(Config.self, from: data)

        #expect(restored.backgroundVirtualDisplay == enabled)
        #expect(restored.allowControl)
        #expect(restored.controlInBackground)
    }

    @Test @MainActor
    func settingsLoadsAndRefreshesSeparateDisplayPreference() {
        var config = Config()
        config.connectionMode = "claudeCode" // No API credentials are read for this settings fixture.
        config.backgroundVirtualDisplay = true
        let model = SettingsModel()
        model.load(config: config, packs: [])
        #expect(model.backgroundVirtualDisplay)

        config.backgroundVirtualDisplay = false
        model.load(config: config, packs: [])
        #expect(!model.backgroundVirtualDisplay)
    }
}
