import AppKit
import Foundation
import Testing
@testable import Familiar

/// A hint's neighbour is gone by only for a control with no name and for the item's own name. A title's hint changed
/// from pages like this to this page (or the whole site) still carries one; it is on its title or on nothing.
@Suite @MainActor
struct NeighbourUseTests {
    typealias P = PenSavePathTests
    typealias Lamp = ItemNameHintTests
    typealias V = ItemNameInViewTests

    static let titleGone = Lamp.page(Lamp.urlA, [P.priceA, P.cartA])
    static let titleAway = Lamp.page(Lamp.urlA, [V.away(P.titleA, y: -300), P.priceA, P.cartA])

    /// Kept on A's title for pages like it, then changed on the pen's paper to be met elsewhere.
    static func changed(to scope: Int) async throws -> (first: StickyNote, changed: StickyNote, pen: P.Pen) {
        let pen = P.Pen(on: Lamp.urlA, reads: P.Reads(P.pageA))
        try pen.open(P.titleA)
        try await pen.pageRead()
        let first = try pen.keep(scope: 1)
        #expect(first.anchor.near == P.nearA && first.anchor.pattern != nil)
        try pen.open(P.titleA)
        let changed = try pen.keep(scope: scope)
        #expect(changed.id == first.id && changed.anchor.pattern == nil && changed.anchor.near == P.nearA)
        return (first, changed, pen)
    }

    @Test func aTitlesHintChangedToThisPageIsOnItsTitleOrFurtherDown() async throws {
        let note = try await Self.changed(to: 0).changed
        #expect(note.anchor.scope == .page)
        #expect(V.landing(note, on: P.pageA) == .on(P.titleA.frame!))
        #expect(V.landing(note, on: Self.titleAway) == .below)
        #expect(V.landing(note, on: Self.titleGone) == .missing)
    }

    @Test func aTitlesHintChangedToTheSiteIsNotPutBesideEveryPagesButton() async throws {
        let note = try await Self.changed(to: 2).changed
        #expect(note.anchor.scope == .site)
        #expect(V.landing(note, on: P.pageA) == .on(P.titleA.frame!))
        #expect(V.landing(note, on: Self.titleAway) == .below)
        #expect(V.landing(note, on: P.pageB) == .missing)
    }

    /// The neighbour it carries is there for when it is changed back, though no page is read then.
    @Test func changedBackToPagesLikeThisItHasItsNeighbourAgain() async throws {
        let (first, _, pen) = try await Self.changed(to: 0)
        try pen.open(P.titleA)
        let back = try pen.keep(scope: 1)
        #expect(back.id == first.id && back.anchor == first.anchor)
        #expect(V.landing(back, on: P.pageBTwice) == .on(P.titleB.frame!))
    }

    /// A control named as any other control is, carrying a neighbour from a file: on itself or on nothing.
    @Test func aNamedControlsNeighbourIsNotGoneBy() {
        var anchor = NoteStore.sceneAnchor(bundleID: "com.google.Chrome", windowTitle: "Walmart", url: Lamp.urlA)
        anchor.role = "AXButton"
        anchor.label = "Specifications"
        anchor.rect = [0.5, 0.2, 0.4, 0.05]
        anchor.near = P.nearA
        anchor.pattern = PagePattern.of(anchor.page!).description
        let note = StickyNote(id: "n", anchor: anchor, kind: "tip", text: "t", by: "x", at: "2026-11-16", confirmed: "2026-11-16")
        #expect(V.landing(note, on: P.pageB) == .missing)
    }

    /// A price has no name: its neighbour is how it is found, on this page as on pages like it.
    @Test(arguments: [0, 1]) func aPriceIsStillFoundByItsNeighbour(_ scope: Int) async throws {
        let pen = P.Pen(on: Lamp.urlA, reads: P.Reads(P.pageA))
        try pen.open(P.priceA)
        try await pen.pageRead()
        let note = try pen.keep("Per lamp", scope: scope)
        let near = try #require(note.anchor.near)
        #expect(near.label == "Add to cart")
        let lower = Lamp.page(Lamp.urlA, [P.element("AXStaticText", "$31.50", CGRect(x: 500, y: 350, width: 80, height: 30)),
                                          P.element("AXButton", "Add to cart", CGRect(x: 500, y: 500, width: 200, height: 44))])
        #expect(V.landing(note, on: lower) == .on(CGRect(x: 500, y: 350, width: 80, height: 30)))
        #expect(V.landing(note, on: Lamp.page(Lamp.urlA, [V.away(P.cartA)])) == .below)
    }
}
