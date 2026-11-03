import AppKit
import Foundation
import Testing
@testable import Familiar

/// Where the stickers' panel goes beside the orb, when it is on the screen at all, and the small words on a sticker.
/// Pure frames and words; no panel is made.
@Suite struct StickersLayoutTests {
    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let width = StickersPanel.width

    @Test func thePanelSitsLeftOfTheOrbWithTheirBottomsLevel() {
        let orb = NSRect(x: 1332, y: 24, width: 84, height: 84)
        let frame = StickersPanel.frame(contentHeight: 180, orb: orb, visible: visible)
        #expect(frame == NSRect(x: 1332 - width - 4, y: 24, width: width, height: 180))
        #expect(frame.maxX == orb.minX - 4)
        #expect(frame.minY == orb.minY)
    }

    @Test func itMovesToTheOrbsRightWhenTheLeftWouldLeaveTheScreen() {
        let orb = NSRect(x: 10, y: 24, width: 84, height: 84)
        let frame = StickersPanel.frame(contentHeight: 180, orb: orb, visible: visible)
        #expect(frame.minX == orb.maxX + 4)
        #expect(frame.minY == 24)
        #expect(frame.size == NSSize(width: width, height: 180))
    }

    @Test func itStaysOnTheScreenWhenTheOrbIsNearTheTop() {
        let orb = NSRect(x: 1332, y: 820, width: 84, height: 84)
        let frame = StickersPanel.frame(contentHeight: 300, orb: orb, visible: visible)
        #expect(frame.maxY == visible.maxY)
        #expect(frame.minY == 575)
        #expect(frame.minX == 1332 - width - 4)
    }

    @Test func itStaysOnTheScreenWhenTheOrbIsBelowItOrOffItsLeft() {
        let low = StickersPanel.frame(contentHeight: 100, orb: NSRect(x: 600, y: -30, width: 84, height: 84), visible: visible)
        #expect(low.minY == visible.minY)
        let wide = NSRect(x: 100, y: 0, width: 400, height: 875)   // a screen narrower than the orb and its panel
        let squeezed = StickersPanel.frame(contentHeight: 100, orb: NSRect(x: 110, y: 24, width: 380, height: 84), visible: wide)
        #expect(squeezed.minX == wide.maxX - width)
    }

    /// Beside the orb only while the bubble is collapsed and fully there, no crane is flying, and a matter has something
    /// to show.
    @Test func theStickersShowOnlyBesideACollapsedBubbleThatIsThere() {
        #expect(StickersPanel.shows(bubbleVisible: true, alpha: 1, expanded: false, flying: false, count: 1))
        #expect(!StickersPanel.shows(bubbleVisible: false, alpha: 1, expanded: false, flying: false, count: 1))   // hidden bubble
        #expect(!StickersPanel.shows(bubbleVisible: true, alpha: 0.4, expanded: false, flying: false, count: 1))  // flying off to the menu bar
        #expect(!StickersPanel.shows(bubbleVisible: true, alpha: 1, expanded: true, flying: false, count: 1))     // the pad is open
        #expect(!StickersPanel.shows(bubbleVisible: true, alpha: 1, expanded: false, flying: true, count: 1))     // the crane is out
        #expect(!StickersPanel.shows(bubbleVisible: true, alpha: 1, expanded: false, flying: false, count: 0))    // nothing to show
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
        #expect(StickerView.width == StickersPanel.width - 16)
        #expect(StickersView.moreWords(2) == "and 2 more")
    }
}
