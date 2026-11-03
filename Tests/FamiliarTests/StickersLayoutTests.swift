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
        #expect(wider.maxX == visible.maxX && wider.width == 346)
    }

    /// Beside the orb only while the bubble is collapsed and fully there and no crane is flying; at the person's own
    /// spot whatever the bubble does. Never without a matter to show, while hidden, or while Noteling works in front.
    @Test func theStickersShowBesideACollapsedBubbleOrAtTheirOwnSpot() {
        func beside(bubbleVisible: Bool = true, alpha: CGFloat = 1, expanded: Bool = false, flying: Bool = false, count: Int = 1,
                    hidden: Bool = false, controlling: Bool = false) -> Bool {
            StickersPanel.shows(count: count, hidden: hidden, controlling: controlling, detached: false,
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
            StickersPanel.shows(count: count, hidden: hidden, controlling: controlling, detached: true,
                                bubbleVisible: bubbleVisible, alpha: alpha, expanded: expanded, flying: flying)
        }
        #expect(own())                           // the bubble is away, the pad open, a crane flying: the stack stays
        #expect(!own(count: 0))
        #expect(!own(hidden: true))
        #expect(!own(controlling: true))
    }

    /// Bigger and Smaller move through five steps, from a little smaller than designed to a good deal bigger, and a
    /// remembered size outside them is brought back in.
    @Test func theSizeMovesInStepsAndTheWidthFollows() {
        #expect(StickersLook.steps == [0.85, 1, 1.2, 1.4, 1.6])
        #expect(StickersLook.bigger(than: 1) == 1.2 && StickersLook.smaller(than: 1) == 0.85)
        #expect(StickersLook.bigger(than: 1.6) == nil && StickersLook.smaller(than: 0.85) == nil)
        #expect(StickersLook.bigger(than: 1.1) == 1.2 && StickersLook.smaller(than: 1.1) == 1)   // a hand-edited value still steps
        #expect(StickersLook.clamped(3) == 1.6 && StickersLook.clamped(0.1) == 0.85 && StickersLook.clamped(.nan) == 1 && StickersLook.clamped(1.2) == 1.2)
        #expect(StickersPanel.width(1) == 216 && StickersPanel.width(1.2) == 259 && StickersPanel.width(1.6) == 346)
        #expect(StickerView.width(1) == 200 && StickerView.width(1.4) == 302 - 16)
    }

    /// Over a sticker the menu starts with Open and Put away; the size is always there, Bigger and Smaller greyed at
    /// the ends; Put back beside Noteling only once the stack was moved; Hide stickers last.
    @Test func theRightClickMenuFitsWhatIsUnderThePointer() {
        let onSticker = StickersPanel.menu(pointing: "m-1", detached: false, scale: 1)
        #expect(onSticker.map { $0?.title } == ["Open", "Put away", nil, "Bigger", "Smaller", nil, "Hide stickers"])
        #expect(onSticker[0]?.choice == .open("m-1") && onSticker[1]?.choice == .putAway("m-1") && onSticker[6]?.choice == .hide)
        let allEnabled = onSticker.compactMap { $0 }.allSatisfy { $0.enabled }
        #expect(allEnabled)

        let moved = StickersPanel.menu(pointing: nil, detached: true, scale: 1.6)
        #expect(moved.map { $0?.title } == ["Bigger", "Smaller", nil, "Put back beside Noteling", "Hide stickers"])
        #expect(moved[0]?.enabled == false && moved[1]?.enabled == true && moved[3]?.choice == .attach)
        #expect(StickersPanel.menu(pointing: nil, detached: false, scale: 0.85)[1]?.enabled == false)
    }

    /// The menu bar's item says which way it goes, and how many stickers wait while they're hidden.
    @Test func theMenuBarItemSaysHideOrShowWithTheCount() {
        #expect(AppDelegate.stickersMenuTitle(hidden: false, count: 3) == "Hide Stickers")
        #expect(AppDelegate.stickersMenuTitle(hidden: true, count: 2) == "Show Stickers (2)")
        #expect(AppDelegate.stickersMenuTitle(hidden: true, count: 0) == "Show Stickers")
    }

    /// The spot and the size are kept in the config; an older file without them means beside the bubble, as designed.
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

    @Test func aStickerSaysWhoSharedItAndWhen() {
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let time = JobWords.clock(at)
        let shared = Sticker(id: "m-1", title: "Pages up", text: "3 pages are down.", byline: "Yang", at: at, urgent: false)
        #expect(StickerView.byline(shared) == "Yang · " + time)
        let own = Sticker(id: "m-2", title: "Orders stuck", text: "2 orders waited over an hour.", byline: nil, at: at, urgent: false)
        #expect(StickerView.byline(own) == time)
    }

    @Test func stickersLeanALittleEitherWayDownTheStack() {
        #expect([0, 1, 2].map(StickerView.tilt) == [-1.2, 0.8, -0.6])
        #expect(StickerView.tilt(3) == StickerView.tilt(0))
        #expect(StickerView.width(1) == StickersPanel.width(1) - 16)
        #expect(StickersView.moreWords(2) == "and 2 more")
    }
}
