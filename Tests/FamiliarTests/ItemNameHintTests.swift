import AppKit
import Foundation
import Testing
@testable import Familiar

/// R03: a hint on the item's own name (its title) on one product page, met on another product page of the kind.
@Suite @MainActor
struct ItemNameHintTests {
    static let urlA = "https://www.walmart.com/ip/Better-Homes-Gardens-13-in-Green-Velvet-Pleated-Shade-Portable-Table-Lamp/20087608457"
    static let urlB = "https://www.walmart.com/ip/Home-Decor-Collection-18-in-Ribbed-Ceramic-Table-Lamp-with-Ivory-Pleated-Shade/5395422942"
    static let titleA = "Better Homes & Gardens 13 in Green Velvet Pleated Shade Portable Table Lamp"
    static let titleB = "Home Decor Collection 18 in Ribbed Ceramic Table Lamp with Ivory Pleated Shade"
    static let window = CGRect(x: 0, y: 0, width: 1_000, height: 800)

    static func element(_ role: String, _ label: String, _ frame: CGRect, visible: Bool = true) -> PageElement {
        PageElement(kind: "thing", role: role, label: label, frame: frame, visible: visible, enabled: true, document: 0)
    }

    static func page(_ url: String, _ elements: [PageElement]) -> PageSnapshot {
        PageSnapshot(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: "Walmart",
                     documents: [PageDocument(url: url, frame: window)],
                     elements: elements, selectedText: nil, windowFrame: window, truncated: false, elapsed: 0)
    }

    /// The note the pen keeps on page A's title, scoped to pages like this, as `NoteStore.sceneAnchor` and the
    /// paper make it.
    static func titleNote(near: NoteNear?, rect: [Double]? = [0.5, 0.2, 0.4, 0.05]) -> StickyNote {
        var anchor = NoteStore.sceneAnchor(bundleID: "com.google.Chrome", windowTitle: "Walmart", url: urlA)
        anchor.role = "AXHeading"
        anchor.label = titleA
        anchor.rect = rect
        anchor.pattern = PagePattern.of(anchor.page!).description
        anchor.near = near
        return StickyNote(id: "title", anchor: anchor, kind: "tip", text: "Check the shade size", by: "David", at: "2026-11-16", confirmed: "2026-11-16")
    }

    @Test func davidsTwoLampPagesAreOneKind() throws {
        let a = try #require(PageKey.of(Self.urlA)), b = try #require(PageKey.of(Self.urlB))
        let kind = PagePattern.of(a)
        #expect(kind.description == "www.walmart.com/ip/*/*")
        #expect(kind.matches(a) && kind.matches(b))
        #expect(PagePattern.of(b).description == kind.description)
    }

    @Test func aTitleNamesTheItemAndAButtonDoesNot() throws {
        let a = PageKey.of(Self.urlA), b = PageKey.of(Self.urlB)
        #expect(NoteAnchor.namesTheItem(Self.titleA, page: a))
        #expect(NoteAnchor.namesTheItem(Self.titleB, page: b))
        // Digit-free titles are found by the slug.
        #expect(NoteAnchor.namesTheItem("Great Value Whole Milk", page: PageKey.of("https://www.walmart.com/ip/Great-Value-Whole-Milk-1-Gallon/10450114")))
        for generic in ["Add to cart", "Specifications", "Pickup", "Add to list", "About this item"] {
            #expect(!NoteAnchor.namesTheItem(generic, page: a), "\(generic)")
        }
        #expect(!NoteAnchor.namesTheItem(nil, page: a))
    }

    /// A digit or a price is not the item's name by itself: options, counts, ratings and prices are controls of the
    /// kind's pages, left out where they are not, as before.
    @Test func aCountOrAPriceIsNotTheItemsName() throws {
        let a = PageKey.of(Self.urlA)
        for label in ["Size 10", "Qty 1", "4.5 out of 5 stars", "$24.97", "13 in", "Now $19.88"] {
            #expect(!NoteAnchor.namesTheItem(label, page: a), "\(label)")
        }
        // Nor does one word of the address with a size put to it: short words are not words of a name here.
        for label in ["13 in Lamp", "Lamp 13", "13 in Velvet"] {
            #expect(!NoteAnchor.namesTheItem(label, page: a), "\(label)")
        }
        // Without a page there is no slug to tell by.
        #expect(!NoteAnchor.namesTheItem(Self.titleA, page: nil))
    }

    /// Page B: a different title, the same "Add to cart" button, roughly where A's were.
    static let pageB = page(urlB, [
        element("AXHeading", titleB, CGRect(x: 500, y: 160, width: 400, height: 40)),
        element("AXButton", "Add to cart", CGRect(x: 500, y: 400, width: 200, height: 44)),
    ])

    @Test func onTheOtherLampItSitsBesideTheButton() {
        // Before the fix the pen kept no neighbour for a named control; it should keep "Add to cart" now.
        let near = NoteNear(role: "AXButton", label: "Add to cart", dx: 0, dy: -240, width: 400, height: 40)
        let result = WandController.place([Self.titleNote(near: near)], page: Self.pageB, primaryMaxY: 1_000)
        #expect(result.missing.isEmpty)
        #expect(result.placed.map(\.note.id) == ["title"])
        // The heading where the neighbour says the control should be: B's title, not a predicted spot.
        #expect(result.placed.first?.frame == NSRect(x: 500, y: 1_000 - 200, width: 400, height: 40))
        #expect(result.placed.first?.predicted == false)
    }

    @Test func withNoNeighbourItGoesOnThisItemsTitle() {
        let result = WandController.place([Self.titleNote(near: nil)], page: Self.pageB, primaryMaxY: 1_000)
        #expect(result.missing.isEmpty && result.placed.first?.predicted == false)
        #expect(result.placed.first?.frame == NSRect(x: 500, y: 1_000 - 200, width: 400, height: 40))
    }

    @Test func withNoNeighbourAndNoTitleItGoesWhereItWas() {
        let noTitle = Self.page(Self.urlB, [Self.element("AXButton", "Add to cart", CGRect(x: 500, y: 400, width: 200, height: 44))])
        let result = WandController.place([Self.titleNote(near: nil)], page: noTitle, primaryMaxY: 1_000)
        #expect(result.missing.isEmpty && result.placed.first?.predicted == true)
        #expect(result.placed.first?.frame == NSRect(x: 500, y: 1_000 - 200, width: 400, height: 40))
    }

    @Test func onItsOwnPageItIsStillFoundByName() {
        let pageA = Self.page(Self.urlA, [Self.element("AXHeading", Self.titleA, CGRect(x: 480, y: 150, width: 420, height: 40))])
        let result = WandController.place([Self.titleNote(near: nil)], page: pageA, primaryMaxY: 1_000)
        #expect(result.placed.first?.predicted == false && result.placed.first?.frame == NSRect(x: 480, y: 810, width: 420, height: 40))
    }

    @Test func aThisPageTitleHintAndAGenericButtonKeepTodaysRule() {
        // Scoped to this page only: not on B at all (matchesScene), and placement keeps the strict rule.
        var onePage = Self.titleNote(near: nil)
        onePage.anchor.pattern = nil
        #expect(WandController.place([onePage], page: Self.pageB, primaryMaxY: 1_000).missing.map(\.id) == ["title"])
        // "Add to cart" on pages like this, on a page without one (out of stock): still left out, not put on its spot.
        var cart = Self.titleNote(near: nil)
        cart.anchor.role = "AXButton"
        cart.anchor.label = "Add to cart"
        let outOfStock = Self.page(Self.urlB, [Self.element("AXHeading", Self.titleB, CGRect(x: 500, y: 160, width: 400, height: 40))])
        #expect(WandController.place([cart], page: outOfStock, primaryMaxY: 1_000).missing.map(\.id) == ["title"])
    }
}
