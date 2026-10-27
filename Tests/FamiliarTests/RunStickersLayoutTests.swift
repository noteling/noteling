import AppKit
import Foundation
import Testing
@testable import Familiar

/// Where the stickers' panel goes beside the orb, and the small words on a sticker. Pure frames and words; no panel
/// is made.
@Suite struct RunStickersLayoutTests {
    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let width = RunStickersPanel.width

    @Test func thePanelSitsLeftOfTheOrbWithTheirBottomsLevel() {
        let orb = NSRect(x: 1332, y: 24, width: 84, height: 84)
        let frame = RunStickersPanel.frame(contentHeight: 180, orb: orb, visible: visible)
        #expect(frame == NSRect(x: 1332 - width - 4, y: 24, width: width, height: 180))
        #expect(frame.maxX == orb.minX - 4)
        #expect(frame.minY == orb.minY)
    }

    @Test func itMovesToTheOrbsRightWhenTheLeftWouldLeaveTheScreen() {
        let orb = NSRect(x: 10, y: 24, width: 84, height: 84)
        let frame = RunStickersPanel.frame(contentHeight: 180, orb: orb, visible: visible)
        #expect(frame.minX == orb.maxX + 4)
        #expect(frame.minY == 24)
        #expect(frame.size == NSSize(width: width, height: 180))
    }

    @Test func itStaysOnTheScreenWhenTheOrbIsNearTheTop() {
        let orb = NSRect(x: 1332, y: 820, width: 84, height: 84)
        let frame = RunStickersPanel.frame(contentHeight: 300, orb: orb, visible: visible)
        #expect(frame.maxY == visible.maxY)
        #expect(frame.minY == 575)
        #expect(frame.minX == 1332 - width - 4)
    }

    @Test func itStaysOnTheScreenWhenTheOrbIsBelowItOrOffItsLeft() {
        let low = RunStickersPanel.frame(contentHeight: 100, orb: NSRect(x: 600, y: -30, width: 84, height: 84), visible: visible)
        #expect(low.minY == visible.minY)
        let wide = NSRect(x: 100, y: 0, width: 400, height: 875)   // a screen narrower than the orb and its panel
        let squeezed = RunStickersPanel.frame(contentHeight: 100, orb: NSRect(x: 110, y: 24, width: 380, height: 84), visible: wide)
        #expect(squeezed.minX == wide.maxX - width)
    }

    @Test func aStickerSaysWhoSharedItAndWhen() {
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let time = JobWords.clock(at)
        let shared = RunSticker(id: UUID(), jobName: "Pages up", byline: "Yang", said: "3 pages are down.", at: at, digest: "a")
        #expect(RunStickerView.byline(shared) == "Yang · " + time)
        let own = RunSticker(id: UUID(), jobName: "Orders stuck", byline: nil, said: "2 orders waited over an hour.", at: at, digest: "b")
        #expect(RunStickerView.byline(own) == time)
    }

    @Test func stickersLeanALittleEitherWayDownTheStack() {
        #expect([0, 1, 2].map(RunStickerView.tilt) == [-1.2, 0.8, -0.6])
        #expect(RunStickerView.tilt(3) == RunStickerView.tilt(0))
        #expect(RunStickerView.width == RunStickersPanel.width - 16)
        #expect(RunStickersView.moreWords(2) == "and 2 more")
    }
}
