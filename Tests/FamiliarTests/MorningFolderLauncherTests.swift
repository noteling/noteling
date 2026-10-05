import AppKit
import Foundation
import Testing
@testable import Familiar

/// The little Morning folder on the screen can be put away: from its own right-click menu, the menu bar or Settings,
/// and the choice is remembered.
@Suite @MainActor
struct MorningFolderLauncherTests {
    @Test func theFoldersRightClickMenuOffersOpenWhosWhoAndHide() throws {
        var ran: [String] = []
        let menu = try #require(WindowDragHandle.menu([("Open Morning Files", { ran.append("open") }),
                                                       ("Who’s Who", { ran.append("people") }),
                                                       ("Hide Morning folder", { ran.append("hide") })]))
        #expect(menu.items.map(\.title) == ["Open Morning Files", "Who’s Who", "Hide Morning folder"])
        try #require(menu.items[2] as? WindowDragHandle.ClosureMenuItem).runAction()
        #expect(ran == ["hide"])
        #expect(WindowDragHandle.menu([]) == nil)   // nothing to offer, no menu
    }

    @Test func theChoiceIsRememberedAndShownInSettings() throws {
        #expect(Config().showMorningFolder)
        let earlier = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(earlier.showMorningFolder)   // a config from before the switch shows the folder

        var config = Config()
        config.showMorningFolder = false
        let reread = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(!reread.showMorningFolder)

        let model = SettingsModel()
        model.load(config: reread, packs: [])
        #expect(!model.showMorningFolder)
        model.showMorningFolder = true
        #expect(model.save(into: reread).showMorningFolder)
    }
}
