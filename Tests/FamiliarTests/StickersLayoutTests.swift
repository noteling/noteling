import AppKit
import Foundation
import Testing
@testable import Familiar

/// Where the stickers' panel goes, beside the orb or where the person put it; when it is on the screen at all; its
/// sizes; its right-click menu; and the small words on a sticker. Pure frames and words; no panel is made.
@Suite struct StickersLayoutTests {
    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let width = StickersPanel.width(1)

    @Test func thePanelSitsLeftOfTheOrbWithTheirBottomsLevel() {
        let orb = NSRect(x: 1332, y: 24, width: 84, height: 84)
        let frame = StickersPanel.frame(contentHeight: 180, width: width, orb: orb, visible: visible)
        #expect(frame == NSRect(x: 1332 - width - 4, y: 24, width: width, height: 180))
        #expect(frame.maxX == orb.minX - 4)
        #expect(frame.minY == orb.minY)
    }

    @Test func itMovesToTheOrbsRightWhenTheLeftWouldLeaveTheScreen() {
        let orb = NSRect(x: 10, y: 24, width: 84, height: 84)
        let frame = StickersPanel.frame(contentHeight: 180, width: width, orb: orb, visible: visible)
        #expect(frame.minX == orb.maxX + 4)
        #expect(frame.minY == 24)
        #expect(frame.size == NSSize(width: width, height: 180))
    }

    @Test func itStaysOnTheScreenWhenTheOrbIsNearTheTop() {
        let orb = NSRect(x: 1332, y: 820, width: 84, height: 84)
        let frame = StickersPanel.frame(contentHeight: 300, width: width, orb: orb, visible: visible)
        #expect(frame.maxY == visible.maxY)
        #expect(frame.minY == 575)
        #expect(frame.minX == 1332 - width - 4)
    }

    @Test func itStaysOnTheScreenWhenTheOrbIsBelowItOrOffItsLeft() {
        let low = StickersPanel.frame(contentHeight: 100, width: width, orb: NSRect(x: 600, y: -30, width: 84, height: 84), visible: visible)
        #expect(low.minY == visible.minY)
        let wide = NSRect(x: 100, y: 0, width: 400, height: 875)   // a screen narrower than the orb and its panel
        let squeezed = StickersPanel.frame(contentHeight: 100, width: width, orb: NSRect(x: 110, y: 24, width: 380, height: 84), visible: wide)
        #expect(squeezed.minX == wide.maxX - width)
    }

    /// Once the person has dragged the stack somewhere, its bottom-left corner stays there and it grows upward; near
    /// the top or an edge it is kept on the screen.
    @Test func aMovedStackKeepsItsCornerAndGrowsUpwardOnTheScreen() {
        let home = NSPoint(x: 300, y: 100)
        let short = StickersPanel.frame(contentHeight: 120, width: width, home: home, visible: visible)
        let tall = StickersPanel.frame(contentHeight: 300, width: width, home: home, visible: visible)
        #expect(short.origin == home && tall.origin == home)
        #expect(short.size == NSSize(width: width, height: 120) && tall.height == 300)
        let nearTop = StickersPanel.frame(contentHeight: 300, width: width, home: NSPoint(x: 300, y: 800), visible: visible)
        #expect(nearTop.maxY == visible.maxY && nearTop.minX == 300)
        let offLeft = StickersPanel.frame(contentHeight: 100, width: width, home: NSPoint(x: -50, y: -10), visible: visible)
        #expect(offLeft.origin == NSPoint(x: 0, y: 0))
        let offRight = StickersPanel.frame(contentHeight: 100, width: width, home: NSPoint(x: 2000, y: 100), visible: visible)
        #expect(offRight.maxX == visible.maxX && offRight.minY == 100)
        let wider = StickersPanel.frame(contentHeight: 100, width: StickersPanel.width(1.6), home: NSPoint(x: 1300, y: 100), visible: visible)
        #expect(wider.maxX == visible.maxX && wider.width == StickersPanel.width(1.6))
    }

    /// Beside the orb only while the bubble is collapsed and fully there and no crane is flying; at the person's own
    /// spot whatever the bubble does. Never without a matter to show, while hidden, or while Noteling works in front.
    @Test func theStickersShowBesideACollapsedBubbleOrAtTheirOwnSpot() {
        func beside(bubbleVisible: Bool = true, alpha: CGFloat = 1, expanded: Bool = false, flying: Bool = false, count: Int = 1,
                    hidden: Bool = false, controlling: Bool = false) -> Bool {
            StickersPanel.shows(count: count, opened: true, hidden: hidden, controlling: controlling, detached: false,
                                bubbleVisible: bubbleVisible, alpha: alpha, expanded: expanded, flying: flying)
        }
        #expect(beside())
        #expect(!beside(bubbleVisible: false))   // hidden bubble
        #expect(!beside(alpha: 0.4))             // flying off to the menu bar
        #expect(!beside(expanded: true))         // the pad is open
        #expect(!beside(flying: true))           // the crane is out
        #expect(!beside(count: 0))               // nothing to show
        #expect(!beside(hidden: true))           // Hide stickers
        #expect(!beside(controlling: true))      // Noteling is working in front of the person

        func own(bubbleVisible: Bool = false, alpha: CGFloat = 0, expanded: Bool = true, flying: Bool = true, count: Int = 1,
                 hidden: Bool = false, controlling: Bool = false) -> Bool {
            StickersPanel.shows(count: count, opened: true, hidden: hidden, controlling: controlling, detached: true,
                                bubbleVisible: bubbleVisible, alpha: alpha, expanded: expanded, flying: flying)
        }
        #expect(own())                           // the bubble is away, the pad open, a crane flying: the stack stays
        #expect(!own(count: 0))
        #expect(!own(hidden: true))
        #expect(!own(controlling: true))
    }

    /// Bigger and Smaller move through five steps, from a little smaller than designed to a good deal bigger, and a
    /// remembered size outside them is brought back in.
    @Test func theDeckShowsOnlyOnceOpenedFromTheLampAndTheLampFollowsTheDeck() {
        #expect(!StickersPanel.shows(count: 2, opened: false, hidden: false, controlling: false, detached: true, bubbleVisible: true, alpha: 1, expanded: false, flying: false))
        #expect(StickersPanel.shows(count: 2, opened: true, hidden: false, controlling: false, detached: true, bubbleVisible: false, alpha: 0, expanded: true, flying: true))
        #expect(LampState.of(count: 0, urgent: false) == .off && LampState.of(count: 2, urgent: false) == .warm && LampState.of(count: 1, urgent: true) == .hot)
        #expect(LampState.words(count: 0, urgent: false) == "Nothing needs you" && LampState.words(count: 1, urgent: false) == "1 needs you")
        #expect(LampState.words(count: 3, urgent: false) == "3 need you" && LampState.words(count: 3, urgent: true) == "3 need you, one can't wait")
        #expect(LampState.words(count: 1, urgent: true) == "1 needs you, and can't wait")
        #expect(AppDelegate.statusImage(lamp: .off)?.isTemplate == true && AppDelegate.statusImage(lamp: .hot)?.isTemplate == false)
    }

    @Test func theSizeMovesInStepsAndTheWidthFollows() {
        #expect(StickersLook.steps == [0.85, 1, 1.2, 1.4, 1.6])
        #expect(StickersLook.bigger(than: 1) == 1.2 && StickersLook.smaller(than: 1) == 0.85)
        #expect(StickersLook.bigger(than: 1.6) == nil && StickersLook.smaller(than: 0.85) == nil)
        #expect(StickersLook.bigger(than: 1.1) == 1.2 && StickersLook.smaller(than: 1.1) == 1)   // a hand-edited value still steps
        #expect(StickersLook.clamped(3) == 1.6 && StickersLook.clamped(0.1) == 0.85 && StickersLook.clamped(.nan) == 1 && StickersLook.clamped(1.2) == 1.2)
        #expect(StickersPanel.width(1) == 312 && StickersPanel.width(1.2) == 368 && StickersPanel.width(1.6) == 480)
        #expect(StickersPanel.designWidth == PaperLook.cardWidth + 2 * PaperLook.margin)
    }

    /// Over a sticker the menu starts with Open and Put away; the size is always there, Bigger and Smaller greyed at
    /// the ends; Put back beside Noteling only once the stack was moved; Hide stickers last.
    @Test func theRightClickMenuFitsWhatIsUnderThePointer() {
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let action = MatterView.Action(finding: FindingRef(job: "team/pages", id: "1"), run: "nudge", label: "Nudge warehouse")
        let card = Sticker(id: "m-1", title: "Pages up", text: "Down.", byline: nil, at: at, urgent: false, action: action)
        let onCard = StickersPanel.menu(pointing: card, detached: false, scale: 1)
        #expect(onCard.map { $0?.title } == ["Open", "Nudge warehouse", "Mine", "Not now", nil, "Bigger", "Smaller", nil, "Hide stickers"])
        #expect(onCard[0]?.choice == .open("m-1") && onCard[1]?.choice == .doIt("m-1") && onCard[2]?.choice == .mine("m-1") && onCard[3]?.choice == .putAway("m-1"))
        let plain = Sticker(id: "m-2", title: "Pages up", text: "Down.", byline: nil, at: at, urgent: false)
        #expect(StickersPanel.menu(pointing: plain, detached: false, scale: 1).map { $0?.title } == ["Open", "Mine", "Not now", nil, "Bigger", "Smaller", nil, "Hide stickers"])
        let moved = StickersPanel.menu(pointing: nil, detached: true, scale: 1.6)
        #expect(moved.map { $0?.title } == ["Bigger", "Smaller", nil, "Put back beside Noteling", "Hide stickers"])
        #expect(moved[0]?.enabled == false && moved[1]?.enabled == true)
        #expect(StickersPanel.menu(pointing: nil, detached: false, scale: 0.85)[1]?.enabled == false)
    }

    @Test func theMenuBarSubmenuOpensHidesShowsAndPutsBack() {
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let lena = Sticker(id: "m-1", title: "Mail", text: "Lena asks for\nthe deck by 3.", byline: nil, at: at, urgent: true)
        let long = Sticker(id: "m-2", title: "GM", headline: String(repeating: "x", count: 80), text: "Short.", byline: "Yang", at: at, urgent: false)
        let shown = StickersPanel.menuBar(stickers: [lena, long], hidden: false, detached: false)
        #expect(shown.map { $0?.title } == ["Open the Deck (2)", nil, "Lena asks for the deck by 3.", String(repeating: "x", count: 60) + "…", nil, "Hide Stickers"])
        #expect(shown[0]?.choice == .show && shown[2]?.choice == .open("m-1") && shown[3]?.choice == .open("m-2") && shown[5]?.choice == .hide)
        let none = StickersPanel.menuBar(stickers: [], hidden: false, detached: true)
        #expect(none.map { $0?.title } == ["No stickers", nil, "Hide Stickers", "Put back beside Noteling"])
        #expect(none[0]?.enabled == false && none[2]?.enabled == false)
        let hidden = StickersPanel.menuBar(stickers: [lena], hidden: true, detached: false)
        #expect(hidden.map { $0?.title } == ["Show Stickers (1)"] && hidden[0]?.choice == .show)
        #expect(StickersPanel.menuBar(stickers: [], hidden: true, detached: false).map { $0?.title } == ["Show Stickers"])
        #expect(StickersPanel.menuBarTitle(count: 0, hidden: false) == "Stickers")
        #expect(StickersPanel.menuBarTitle(count: 2, hidden: false) == "Stickers (2)")
        #expect(StickersPanel.menuBarTitle(count: 2, hidden: true) == "Stickers (2, hidden)")
        #expect(StickersPanel.menuBarTitle(count: 0, hidden: true) == "Stickers (hidden)")
    }

    @Test func theSpotAndTheSizeAreRememberedInTheConfig() throws {
        let fresh = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(fresh.stickersX == nil && fresh.stickersY == nil && fresh.stickerScale == 1)
        var config = Config()
        config.stickersX = 300
        config.stickersY = 100.5
        config.stickerScale = 1.4
        let restored = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(restored.stickersX == 300 && restored.stickersY == 100.5 && restored.stickerScale == 1.4)
    }

    @Test func aCardSaysWhereItCameFromAndWhen() {
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let time = JobWords.time(at, now: at)
        let shared = Sticker(id: "m-1", title: "Pages up", text: "3 pages are down.", byline: "Yang", at: at, urgent: false)
        #expect(shared.line(now: at) == "Pages up · shared by Yang · " + time)
        let own = Sticker(id: "m-2", title: "Orders stuck", text: "2 orders waited over an hour.", byline: nil, at: at, urgent: false)
        #expect(own.line(now: at) == "Orders stuck · " + time)
        #expect(StickersView.moreWords(2) == "2 more")
    }
}
