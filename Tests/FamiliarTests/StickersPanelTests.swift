import AppKit
import Foundation
import Testing
@testable import Familiar

/// The stickers' panel itself: which sticker its right-click menu is about, what choosing from it does, and what it
/// tells the app to remember. The panel is made but never shown.
@Suite @MainActor struct StickersPanelTests {
    private func matter(_ id: String, _ text: String) -> Matter {
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        return Matter(id: id, findings: [FindingRef(job: "team/pages", id: id)], state: .open, view: MatterView(text: text, tone: .calm),
                      jobName: "Pages up", byline: nil, createdAt: at, updatedAt: at)
    }

    @Test func theMenuIsAboutTheStickerUnderThePointerWhileItIsStillThere() {
        let model = Matters(directory: nil)
        model.save(matter("m-1", "One."))
        model.save(matter("m-2", "Two."))
        var opened: [String] = [], putAway: [String] = []
        let panel = StickersPanel(model: model, look: StickersLook(), home: nil, hideFromScreenShare: false,
                                  open: { opened.append($0) }, more: {}, putAway: { putAway.append($0) })
        // Onto one, onto the next, then the first one's leaving arrives late: the menu is about the second.
        panel.point("m-1", inside: true)
        panel.point("m-2", inside: true)
        panel.point("m-1", inside: false)
        let menu = panel.contextMenu()
        #expect(menu.items.map(\.title) == ["Open", "Put away", "", "Bigger", "Smaller", "", "Hide stickers"])
        #expect(menu.items[2].isSeparatorItem && menu.items[5].isSeparatorItem)
        let allEnabled = menu.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.isEnabled }
        #expect(allEnabled)
        panel.choose(.open("m-2"))
        panel.choose(.putAway("m-2"))
        #expect(opened == ["m-2"] && putAway == ["m-2"])

        // Put away for real, the sticker is off the screen: the menu is about the stack, not it.
        model.putAway("m-2")
        #expect(panel.contextMenu().items.map(\.title) == ["Bigger", "Smaller", "", "Hide stickers"])
        panel.point("m-2", inside: false)
        panel.point("m-1", inside: true)
        #expect(panel.contextMenu().items.first?.title == "Open")
    }

    @Test func hidingResizingAndReattachingAreRememberedThroughTheApp() async throws {
        let model = Matters(directory: nil)
        model.save(matter("m-1", "One."))
        var changes = 0, hides = 0
        let panel = StickersPanel(model: model, look: StickersLook(scale: 1.4), home: NSPoint(x: 300, y: 100), hideFromScreenShare: false,
                                  open: { _ in }, more: {}, putAway: { _ in })
        panel.onChange = { changes += 1 }
        panel.onHide = { hides += 1 }
        #expect(panel.isDetached && panel.home == NSPoint(x: 300, y: 100) && !panel.hidden)
        #expect(panel.contextMenu().items.map(\.title) == ["Bigger", "Smaller", "", "Put back beside Noteling", "Hide stickers"])

        panel.choose(.hide)
        #expect(panel.hidden && changes == 1 && hides == 1)

        panel.choose(.attach)
        #expect(!panel.isDetached && panel.home == nil && changes == 2)
        #expect(panel.contextMenu().items.map(\.title) == ["Bigger", "Smaller", "", "Hide stickers"])

        // The size steps, and the app hears of it once the stickers have redrawn.
        panel.choose(.bigger)
        #expect(panel.look.scale == 1.6 && changes == 2)
        try await Task.sleep(for: .milliseconds(50))
        #expect(changes == 3)
        panel.choose(.bigger)   // at the biggest already: nothing
        try await Task.sleep(for: .milliseconds(50))
        #expect(panel.look.scale == 1.6 && changes == 3)
        #expect(panel.contextMenu().items.first?.isEnabled == false)
        panel.choose(.smaller)
        try await Task.sleep(for: .milliseconds(50))
        #expect(panel.look.scale == 1.4 && changes == 4)
    }
}
