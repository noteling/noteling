import AppKit
import Foundation
import Testing
@testable import Familiar

/// R03: a hint the pen kept beside a named neighbour, on a page where that neighbour is scrolled out of view. On the
/// item's name, it goes on this page's item's name when that is in view; any other hint is further down, as it was.
/// Notes come through the pen's paper (`PenSavePathTests`), pages are fixtures.
@Suite @MainActor
struct ItemNameInViewTests {
    typealias P = PenSavePathTests
    typealias Lamp = ItemNameHintTests

    enum Landing: Equatable { case on(CGRect), guessed(CGRect), below, missing }

    static func landing(_ note: StickyNote, on page: PageSnapshot) -> Landing {
        let result = WandController.place([note], page: page, primaryMaxY: P.Pen.top)
        if let there = P.landing(note, on: page) {
            #expect(result.placed.count == 1 && result.below.isEmpty && result.missing.isEmpty)
            return there.predicted ? .guessed(there.frame) : .on(there.frame)
        }
        #expect(result.below.count + result.missing.count == 1)
        return result.below.isEmpty ? .missing : .below
    }

    /// Kept on a control of page A, for pages like it, with the page read in time.
    static func kept(on element: PageElement) async throws -> StickyNote {
        let pen = P.Pen(on: Lamp.urlA, reads: P.Reads(P.pageA))
        try pen.open(element)
        try await pen.pageRead()
        let note = try pen.keep(scope: 1)
        #expect(note.anchor.near?.label == "Add to cart")
        return note
    }

    /// A control of the page, scrolled out of view.
    static func away(_ element: PageElement, y: CGFloat = 2_000) -> PageElement {
        var e = element
        e.visible = false
        e.frame?.origin.y = y
        return e
    }

    static let frameB = P.titleB.frame!

    @Test func theTitleInViewWinsOverTheNeighbourScrolledAway() async throws {
        let note = try await Self.kept(on: P.titleA)
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [P.titleB, P.priceB, Self.away(P.cartB)])) == .on(Self.frameB))
        // The same as the hint with no neighbour.
        var without = note
        without.anchor.near = nil
        #expect(Self.landing(without, on: Lamp.page(Lamp.urlB, [P.titleB, P.priceB, Self.away(P.cartB)])) == .on(Self.frameB))
    }

    /// Of two headings with B's name in view, the nearer to where A's title was, as with no neighbour at all.
    @Test func ofTwoNamesInViewItIsTheNearerToTheSpot() async throws {
        let note = try await Self.kept(on: P.titleA)
        let first = P.pageBTwice.elements[0]
        for names in [[first, P.titleB], [P.titleB, first]] {
            #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, names + [Self.away(P.cartB)])) == .on(first.frame!))
        }
    }

    /// A like item's name further down does not keep the one in view from winning.
    @Test func aLikeNameScrolledAwayDoesNotMatter() async throws {
        let note = try await Self.kept(on: P.titleA)
        let like = P.element("AXHeading", Lamp.titleB, Self.frameB)
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [Self.away(like), P.titleB, Self.away(P.cartB)])) == .on(Self.frameB))
    }

    /// On the hint's own page the title is found by its name, whatever is scrolled away.
    @Test func onItsOwnPageItIsFoundByName() async throws {
        let note = try await Self.kept(on: P.titleA)
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlA, [P.titleA, Self.away(P.cartA)])) == .on(P.titleA.frame!))
    }

    // MARK: as before

    @Test func theNameAlsoScrolledAwayIsFurtherDown() async throws {
        let note = try await Self.kept(on: P.titleA)
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [Self.away(P.titleB, y: -600), P.priceB, Self.away(P.cartB)])) == .below)
        // No heading naming the item at all; and one by its name that is not of the hint's role.
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [P.priceB, Self.away(P.cartB)])) == .below)
        let link = P.element("AXLink", Lamp.titleB, Self.frameB)
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [link, P.priceB, Self.away(P.cartB)])) == .below)
        // A heading of the hint's role in view that names something else.
        let reviews = P.element("AXHeading", "Customer ratings and reviews", Self.frameB)
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [reviews, P.priceB, Self.away(P.cartB)])) == .below)
    }

    /// Down A's own page, at a carousel of like lamps: the hint's own title is on the page, scrolled away.
    @Test func onItsOwnPageALikeLampsNameIsNotTheTitleScrolledAway() async throws {
        let note = try await Self.kept(on: P.titleA)
        let like = P.element("AXHeading", "Better Homes & Gardens 13 in Pink Velvet Pleated Shade Table Lamp", CGRect(x: 100, y: 300, width: 200, height: 40))
        #expect(NoteAnchor.namesTheItem(like.label, page: PageKey.of(Lamp.urlA)))
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlA, [Self.away(P.titleA, y: -600), Self.away(P.cartA, y: -400), like])) == .below)
    }

    @Test func aPriceIsFurtherDownWithItsNeighbour() async throws {
        let note = try await Self.kept(on: P.priceA)
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [P.titleB, P.priceB, Self.away(P.cartB)])) == .below)
        #expect(Self.landing(note, on: P.pageB) == .on(P.priceB.frame!))
    }

    /// Kept for this page only, the hint is on its own title or none: not on B's, with the pattern taken off.
    @Test func aHintForOnePageIsNotPutOnAnotherName() async throws {
        var note = try await Self.kept(on: P.titleA)
        note.anchor.pattern = nil
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [P.titleB, P.priceB, Self.away(P.cartB)])) == .below)
    }

    @Test func theNeighbourInViewStillPicksTheTitleOfTwo() async throws {
        let note = try await Self.kept(on: P.titleA)
        #expect(Self.landing(note, on: P.pageBTwice) == .on(Self.frameB))
    }

    /// The neighbour in view with nothing of the hint's role beside it: still rescued by the item's name, as #142 has
    /// it, else only guessed.
    @Test func aGuessBesideTheNeighbourIsStillRescuedByTheItemsName() async throws {
        let note = try await Self.kept(on: P.titleA)
        let far = P.element("AXHeading", Lamp.titleB, CGRect(x: 100, y: 100, width: 350, height: 60))
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [far, P.cartB])) == .on(far.frame!))
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [P.cartB])) == .guessed(Self.frameB))
        // ... and further down when that name is scrolled away.
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [Self.away(far), P.cartB])) == .below)
    }
}
