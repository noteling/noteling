import AppKit
import Foundation
import Testing
@testable import Familiar

/// R03, the pen's half: a hint's neighbour is measured only from its control's own frame. Changed from a sticker at
/// the window's edge, or from a mark placed by a guess, a hint gets no neighbour and keeps the one it has. The mouse
/// goes through the view in a window that is never ordered in; pages are fixtures (`PenSavePathTests`).
@Suite @MainActor
struct NearFromFoundTests {
    typealias P = PenSavePathTests
    typealias Lamp = ItemNameHintTests

    /// The pen picked up again over a page, with the hints on it drawn as it has placed them.
    @MainActor final class Again {
        let pen: P.Pen
        let reads: P.Reads
        private let host: NSWindow

        init(_ note: StickyNote, on url: String, page: PageSnapshot, _ marks: [WandController.PlacedNote]) {
            reads = P.Reads(page)
            pen = P.Pen(on: url, reads: reads)
            pen.controller.notesProvider = { _ in [note] }
            pen.controller.takeScene()
            let window = P.Pen.appKit(Lamp.window)
            host = NSWindow(contentRect: window, styleMask: [.borderless], backing: .buffered, defer: true)
            host.isReleasedWhenClosed = false
            host.contentView = pen.view
            pen.view.showStickers(marks)
        }

        /// Right-click on the hint's sticker, at a point where it is drawn.
        func rightClick(_ mark: WandController.PlacedNote) throws {
            var at: NSPoint?
            for dx in stride(from: -60, through: 260, by: 8) {
                for dy in stride(from: -160, through: 60, by: 8) where at == nil {
                    let p = NSPoint(x: mark.frame.maxX + CGFloat(dx), y: mark.frame.maxY + CGFloat(dy))
                    if pen.view.sticker(at: p) == mark.note.id { at = p }
                }
            }
            let point = try #require(at)
            func event(_ type: NSEvent.EventType) throws -> NSEvent {
                try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: point.x - host.frame.minX, y: point.y - host.frame.minY),
                                                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            }
            pen.view.rightMouseDown(with: try event(.rightMouseDown))
            pen.view.rightMouseUp(with: try event(.rightMouseUp))
            #expect(pen.view.openPaper != nil)
        }

        /// Changes the hint from its sticker; no page is read for it.
        func changeUnread(_ mark: WandController.PlacedNote, _ text: String = "Changed", scope: Int? = nil) async throws -> StickyNote {
            try rightClick(mark)
            try await P.settle()
            #expect(reads.bundles.isEmpty)
            let changed = try pen.keep(text, scope: scope)
            #expect(changed.id == mark.note.id && changed.text == text)
            return changed
        }
    }

    /// Kept on A before its page was read: no neighbour.
    static func keptEarly(on element: PageElement, scope: Int = 1) throws -> StickyNote {
        let pen = P.Pen(on: Lamp.urlA, reads: P.Reads(nil))
        try pen.open(element)
        let note = try pen.keep(scope: scope)
        #expect(note.anchor.near == nil)
        return note
    }

    static func keptWithNeighbour(on element: PageElement) async throws -> StickyNote {
        let pen = P.Pen(on: Lamp.urlA, reads: P.Reads(P.pageA))
        try pen.open(element)
        try await pen.pageRead()
        let note = try pen.keep(scope: 1)
        #expect(note.anchor.near != nil)
        return note
    }

    static func away(_ element: PageElement, y: CGFloat) -> PageElement {
        var e = element
        e.visible = false
        e.frame?.origin.y = y
        return e
    }

    static func placed(_ note: StickyNote, on page: PageSnapshot) -> (placed: [WandController.PlacedNote], missing: [StickyNote], below: [StickyNote]) {
        WandController.place([note], page: page, primaryMaxY: P.Pen.top)
    }

    static func edge(_ note: StickyNote, below: Bool) throws -> WandController.PlacedNote {
        try #require(WandController.atEdge([note], of: P.Pen.appKit(Lamp.window), below: below ? [note.id] : []).first)
    }

    /// A scrolled down to its reviews: the title out of view, a button in reach of the window's edge.
    static let review = P.element("AXButton", "Write a review", CGRect(x: 720, y: 120, width: 200, height: 44))
    static let scrolledA = Lamp.page(Lamp.urlA, [away(P.titleA, y: -600), review])

    // MARK: at the window's edge

    @Test func changedFromFurtherDownItGetsNoNeighbour() async throws {
        let first = try Self.keptEarly(on: P.titleA)
        #expect(Self.placed(first, on: Self.scrolledA).below.map(\.id) == [first.id])
        let mark = try Self.edge(first, below: true)
        #expect(!mark.found)
        let again = Again(first, on: Lamp.urlA, page: Self.scrolledA, [mark])
        let changed = try await again.changeUnread(mark)
        #expect(changed.anchor.near == nil && changed.anchor.rect == first.anchor.rect)
        // Met on B as before the change: on its title though the button is scrolled away; with no title, where it was.
        let b = Lamp.page(Lamp.urlB, [P.titleB, P.priceB, P.cartB, Self.away(Self.review, y: 2_000)])
        #expect(P.landing(changed, on: b)?.frame == P.titleB.frame)
        let noTitle = Lamp.page(Lamp.urlB, [P.element("AXButton", "Write a review", CGRect(x: 720, y: 600, width: 200, height: 44))])
        #expect(P.landing(changed, on: noTitle)?.frame == P.titleA.frame)
    }

    /// Kept, the hint's sticker stays where it stood; changed again from there, it still has no neighbour.
    @Test func changedTwiceFromTheEdgeItStillGetsNone() async throws {
        let first = try Self.keptEarly(on: P.titleA)
        let mark = try Self.edge(first, below: true)
        let again = Again(first, on: Lamp.urlA, page: Self.scrolledA, [mark])
        _ = try await again.changeUnread(mark)
        let kept = try #require(again.pen.controller.placed.first)
        #expect(kept.frame == mark.frame && !kept.found)
        again.pen.view.showStickers(again.pen.controller.placed)
        #expect(try await again.changeUnread(kept, "Changed again").anchor.near == nil)
    }

    /// A hint for this page whose title the page no longer has, made one for pages like it from its edge sticker.
    @Test func changedFromNotOnYourScreenItGetsNoNeighbour() async throws {
        let first = try Self.keptEarly(on: P.titleA, scope: 0)
        let page = Lamp.page(Lamp.urlA, [Self.review])
        #expect(Self.placed(first, on: page).missing.map(\.id) == [first.id])
        let mark = try Self.edge(first, below: false)
        #expect(mark.note.text.hasPrefix("Not on your screen") && !mark.found)
        let again = Again(first, on: Lamp.urlA, page: page, [mark])
        let changed = try await again.changeUnread(mark, scope: 1)
        #expect(changed.anchor.pattern == "www.walmart.com/ip/*/*" && changed.anchor.near == nil)
    }

    @Test func theNeighbourItHasIsCarriedFromTheEdge() async throws {
        let first = try await Self.keptWithNeighbour(on: P.titleA)
        let page = Lamp.page(Lamp.urlA, [Self.away(P.titleA, y: -600), Self.away(P.cartA, y: -400), Self.review])
        #expect(Self.placed(first, on: page).below.map(\.id) == [first.id])
        let mark = try Self.edge(first, below: true)
        let changed = try await Again(first, on: Lamp.urlA, page: page, [mark]).changeUnread(mark)
        #expect(changed.anchor.near == P.nearA)
    }

    // MARK: a guess

    @Test func changedFromAGuessItGetsNoNeighbour() async throws {
        let first = try Self.keptEarly(on: P.priceA)
        let mark = try #require(Self.placed(first, on: P.pageB).placed.first)
        #expect(mark.predicted && !mark.found && mark.frame == P.Pen.appKit(P.priceA.frame!))
        let again = Again(first, on: Lamp.urlB, page: P.pageB, [mark])
        let changed = try await again.changeUnread(mark)
        #expect(changed.anchor.near == nil && changed.anchor.rect == first.anchor.rect)
        // ... and again, from where it was kept.
        let kept = try #require(again.pen.controller.placed.first)
        #expect(kept.frame == mark.frame && !kept.found)
        again.pen.view.showStickers(again.pen.controller.placed)
        #expect(try await again.changeUnread(kept, "Changed again").anchor.near == nil)
    }

    /// The title's own guess, on a page with no heading naming the item.
    @Test func changedFromATitlesGuessItGetsNoNeighbour() async throws {
        let first = try Self.keptEarly(on: P.titleA), page = Lamp.page(Lamp.urlB, [P.cartB])
        let mark = try #require(Self.placed(first, on: page).placed.first)
        #expect(mark.predicted)
        #expect(try await Again(first, on: Lamp.urlB, page: page, [mark]).changeUnread(mark).anchor.near == nil)
    }

    /// A guess moved onto a control the live page has there is drawn on it, but that control is only like the hint's:
    /// of its role and about its size, here other words where A's price was.
    @Test func aGuessThatPassesItsCheckIsStillNotFound() async throws {
        let first = try Self.keptEarly(on: P.priceA)
        let guess = try #require(Self.placed(first, on: P.pageB).placed.first)
        let words = CGRect(x: 490, y: 245, width: 120, height: 30)
        let mark = try #require(WandController.snapped([guess], bundleID: "com.google.Chrome", primaryMaxY: P.Pen.top) { _, point, role, _, size in
            #expect(point == CGPoint(x: P.priceA.frame!.midX, y: P.priceA.frame!.midY) && role == "AXStaticText" && size == P.priceA.frame!.size)
            return words
        }.first)
        #expect(mark.frame == P.Pen.appKit(words) && !mark.predicted && !mark.found)
        #expect(try await Again(first, on: Lamp.urlB, page: P.pageB, [mark]).changeUnread(mark).anchor.near == nil)
        // One that fails it keeps its place, a guess.
        let stays = WandController.snapped([guess], bundleID: "com.google.Chrome", primaryMaxY: P.Pen.top) { _, _, _, _, _ in nil }
        #expect(stays.first?.frame == guess.frame && stays.first?.predicted == true && stays.first?.found == false)
        // One found needs no check.
        let sure = WandController.PlacedNote(note: first, frame: guess.frame)
        let same = WandController.snapped([sure], bundleID: "com.google.Chrome", primaryMaxY: P.Pen.top) { _, _, _, _, _ in words }
        #expect(same.first?.frame == guess.frame && same.first?.found == true)
    }

    /// Beside a neighbour in view, with nothing of its role there: a guess, and the neighbour it has is carried.
    @Test func theNeighbourItHasIsCarriedFromAGuess() async throws {
        let first = try await Self.keptWithNeighbour(on: P.priceA), page = Lamp.page(Lamp.urlB, [P.titleB, P.cartB])
        let mark = try #require(Self.placed(first, on: page).placed.first)
        #expect(mark.predicted && !mark.found)
        #expect(try await Again(first, on: Lamp.urlB, page: page, [mark]).changeUnread(mark).anchor.near == first.anchor.near)
    }

    // MARK: found

    @Test func changedFromItsStickerOnTheControlItGetsOne() async throws {
        let first = try Self.keptEarly(on: P.titleA)
        let mark = try #require(Self.placed(first, on: P.pageA).placed.first)
        #expect(mark.found)
        let again = Again(first, on: Lamp.urlA, page: P.pageA, [mark])
        try again.rightClick(mark)
        try await again.pen.pageRead()
        let changed = try again.pen.keep()
        #expect(changed.id == first.id && changed.anchor.near == P.nearA)
        #expect(again.pen.controller.placed.first?.found == true)
    }

    /// On the other lamp's title, found by the item's name: beside that page's button.
    @Test func changedFromTheOtherLampsTitleItGetsOne() async throws {
        let first = try Self.keptEarly(on: P.titleA)
        let mark = try #require(Self.placed(first, on: P.pageB).placed.first)
        #expect(mark.found && mark.frame == P.Pen.appKit(P.titleB.frame!))
        let again = Again(first, on: Lamp.urlB, page: P.pageB, [mark])
        try again.rightClick(mark)
        try await again.pen.pageRead()
        #expect(try again.pen.keep().anchor.near == P.nearA)
    }

    /// Opened on the control itself, with the hint's sticker drawn elsewhere.
    @Test func changedOnTheControlItselfItGetsOne() async throws {
        let first = try Self.keptEarly(on: P.titleA)
        let again = Again(first, on: Lamp.urlA, page: P.pageA, [try Self.edge(first, below: true)])
        try again.pen.open(P.titleA)
        try await again.pen.pageRead()
        let changed = try again.pen.keep()
        #expect(changed.id == first.id && changed.anchor.near == P.nearA)
    }
}
