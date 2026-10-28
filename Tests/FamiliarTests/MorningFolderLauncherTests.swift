import AppKit
import Foundation
import Testing
@testable import Familiar

/// The little Morning folder stays off the screen unless asked for, from the menu bar or Settings; on, it can be put
/// away again from its own right-click menu, and the choice is remembered.
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
        #expect(!Config().morningFolderOnScreen)
        let earlier = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(!earlier.morningFolderOnScreen)   // a config from before the switch keeps the folder off the screen
        // Every install from before had the old key written as true on every launch; it no longer counts.
        let old = try JSONDecoder().decode(Config.self, from: Data(#"{"showMorningFolder": true}"#.utf8))
        #expect(!old.morningFolderOnScreen)

        var config = Config()
        config.morningFolderOnScreen = true
        let reread = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(reread.morningFolderOnScreen)

        let model = SettingsModel()
        model.load(config: reread, packs: [])
        #expect(model.morningFolderOnScreen)
        model.morningFolderOnScreen = false
        #expect(!model.save(into: reread).morningFolderOnScreen)
    }

    @Test func theFolderStaysOffTheScreenUnlessAskedFor() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("launcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let panel = MorningPanelController(store: MorningStore(directory: folder), hideFromScreenShare: true)
        defer { panel.close() }
        panel.setHiddenForForegroundGrant(true)   // nothing comes on screen in a test
        #expect(!panel.launcherShown)   // so the menu bar says "Show Morning Folder" at launch
        var remembered: [Bool] = []
        panel.onLauncherShownChanged = { remembered.append($0) }
        panel.setLauncherShown(true)
        #expect(panel.launcherShown)
        panel.setLauncherShown(false, notify: false)   // Settings saved: already written, not remembered twice
        #expect(!panel.launcherShown)
        #expect(remembered == [true])
    }
}
