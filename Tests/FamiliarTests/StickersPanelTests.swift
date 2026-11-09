import AppKit
import Foundation
import Testing
@testable import Familiar

/// The deck's panel itself: which card its right-click menu is about, what choosing from it does, what its keys mean,
/// and what it tells the app to remember. The panel is made but never shown.
@Suite @MainActor struct StickersPanelTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func matter(_ id: String, _ text: String, action: Bool = false) -> Matter {
        let ref = FindingRef(job: "team/pages", id: id)
        let view = MatterView(headline: "Pages", text: text, action: action ? MatterView.Action(finding: ref, run: "nudge", label: "Nudge warehouse") : nil, tone: .calm)
        var matter = Matter(id: id, findings: [ref], state: .open, view: view, jobName: "Pages up", byline: nil, createdAt: at, updatedAt: at)
        matter.writtenAt = at
        return matter
    }

    private func deck(_ matters: Matters) -> DeckModel {
        let model = DeckModel(matters: matters)
        model.clock = { self.at }
        model.stampSeconds = 0
        return model
    }

    @Test func theMenuIsAboutTheCardOnTopWhileItIsStillThere() {
        let matters = Matters(directory: nil)
        matters.clock = { self.at }
        matters.save(matter("m-1", "One.", action: true))
        matters.save(matter("m-2", "Two."))
        let model = deck(matters)
        var opened: [String] = []
        model.open = { opened.append($0) }
        let panel = StickersPanel(model: model, look: StickersLook(), home: nil, hideFromScreenShare: false)
        let top = model.card!.id
        panel.point(top, inside: true)
        let menu = panel.contextMenu()
        let titles = menu.items.map(\.title)
        #expect(titles.count == 9 && titles[0] == "Open" && titles[2] == "Mine" && titles[3] == "Not now" && titles.last == "Hide stickers")
        #expect(titles[1] == (top == "m-1" ? "Nudge warehouse" : "Mine") || titles[1] == "Mine" || titles[1] == "Nudge warehouse")
        #expect(menu.items[4].isSeparatorItem && menu.items[7].isSeparatorItem)
        panel.choose(.open(top))
        #expect(opened == [top])

        // Put away for real, the card is off the deck: the next card is on top, and the menu is about that one.
        panel.choose(.putAway(top))
        #expect(matters.matter(id: top)?.state == .quiet && model.count == 1)
        panel.point(top, inside: false)
        #expect(panel.contextMenu().items.map(\.title) == ["Bigger", "Smaller", "", "Hide stickers"])
        let next = model.card!.id
        panel.point(next, inside: true)
        #expect(panel.contextMenu().items.first?.title == "Open")
    }

    @Test func theKeysMeanTheVerbsOnTheCardOnTop() {
        let withAction = Sticker(id: "m-1", title: "Pages up", text: "One.", byline: nil, at: at, urgent: false,
                                 action: MatterView.Action(finding: FindingRef(job: "team/pages", id: "1"), run: "nudge", label: "Nudge"))
        let without = Sticker(id: "m-2", title: "Pages up", text: "Two.", byline: nil, at: at, urgent: false)
        #expect(StickersPanel.key(123, card: withAction) == .doIt("m-1") && StickersPanel.key(123, card: without) == nil)
        // No action but a next step: ← takes it, and the menu offers it where the action would be.
        let withNext = Sticker(id: "m-3", title: "Mail", text: "Three.", byline: nil, at: at, urgent: false, next: "Reply to Lena")
        #expect(StickersPanel.key(123, card: withNext) == .next("m-3"))
        #expect(StickersPanel.menu(pointing: withNext, detached: false, scale: 1).compactMap { $0?.title }.prefix(3) == ["Open", "Reply to Lena", "Mine"])
        #expect(StickersPanel.key(124, card: withAction) == .mine("m-1") && StickersPanel.key(126, card: withAction) == .putAway("m-1"))
        #expect(StickersPanel.key(36, card: withAction) == .open("m-1") && StickersPanel.key(76, card: without) == .open("m-2"))
        #expect(StickersPanel.key(53, card: withAction) == .close && StickersPanel.key(53, card: nil) == .close)
        #expect(StickersPanel.key(49, card: withAction) == nil && StickersPanel.key(123, card: nil) == nil)
    }

    @Test func theMenuBarListsEveryCardByItsHeadline() {
        var card = Sticker(id: "m-1", title: "Pages up", headline: "Checkout is down", text: "Two steps are down.", byline: "Yang", at: at, urgent: true)
        let items = StickersPanel.menuBar(stickers: [card], hidden: false, detached: false)
        #expect(items.map { $0?.title ?? "" } == ["Open the Deck (1)", "", "Checkout is down", "", "Hide Stickers"])
        card.headline = nil
        #expect(StickersPanel.menuLine(card) == "Two steps are down.")
        #expect(StickersPanel.menuBar(stickers: [], hidden: false, detached: true).map { $0?.title ?? "" } == ["No stickers", "", "Hide Stickers", "Put back beside Noteling"])
        #expect(StickersPanel.menuBar(stickers: [card], hidden: true, detached: false).map { $0?.title ?? "" } == ["Show Stickers (1)"])
        #expect(StickersPanel.menuBarTitle(count: 2, hidden: true) == "Stickers (2, hidden)" && StickersPanel.menuBarTitle(count: 0, hidden: false) == "Stickers")
        #expect(card.line(now: at) == "Pages up · shared by Yang · " + JobWords.time(at, now: at))
    }

    @Test func hidingResizingAndReattachingAreRememberedThroughTheApp() async throws {
        let matters = Matters(directory: nil)
        matters.save(matter("m-1", "One."))
        var changes = 0, hides = 0
        let panel = StickersPanel(model: deck(matters), look: StickersLook(scale: 1.4), home: NSPoint(x: 300, y: 100), hideFromScreenShare: false)
        panel.onChange = { changes += 1 }
        panel.onHide = { hides += 1 }
        var closes = 0
        panel.onClose = { closes += 1 }
        panel.choose(.close)
        #expect(closes == 1)
        #expect(panel.isDetached && panel.home == NSPoint(x: 300, y: 100) && !panel.hidden)
        #expect(panel.contextMenu().items.map(\.title) == ["Bigger", "Smaller", "", "Put back beside Noteling", "Hide stickers"])

        panel.choose(.hide)
        #expect(panel.hidden && changes == 1 && hides == 1)

        panel.choose(.attach)
        #expect(!panel.isDetached && panel.home == nil && changes == 2)
        #expect(panel.contextMenu().items.map(\.title) == ["Bigger", "Smaller", "", "Hide stickers"])

        // The size steps, and the app hears of it once the deck has redrawn.
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
