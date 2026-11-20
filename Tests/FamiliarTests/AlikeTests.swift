import AppKit
import Foundation
import Testing
@testable import Familiar

/// `NoteAnchor.alike` names one control across pages of a kind ("Add to cart - Milk" there, "Add to cart - Bananas"
/// here), never two different controls that start with the same words.
@Suite @MainActor
struct AlikeTests {
    typealias H = HeadlessReadTests
    typealias I = ItemNameHintTests

    /// Different controls that share ten or more characters of whole leading words.
    @Test(arguments: [
        ("Sign in with Google", "Sign in with Apple"),
        ("Continue with Google", "Continue with Facebook"),
        ("Remove from cart", "Remove from list"),
        ("Delete this item", "Delete this account"),
        ("Download for Mac", "Download for Windows"),
        ("Buy now with Apple Pay", "Buy now with PayPal"),
        // One is the other's start with more words after it, but no separator: another action, not the item's name.
        ("Delete this item", "Delete this item now"),
        ("Add to cart", "Add to cart Bananas"),
    ])
    func sharedLeadingWordsAreNotEnough(_ a: String, _ b: String) {
        #expect(!NoteAnchor.alike(a, b), "\(a) ~ \(b)")
        #expect(!NoteAnchor.alike(b, a), "\(b) ~ \(a)")
    }

    /// One name is the other's start, ending mid-word: a single action against its bulk form.
    @Test(arguments: [
        ("Delete message", "Delete messages"),
        ("Remove item", "Remove items"),
    ])
    func aStartEndingMidWordIsNotEnough(_ a: String, _ b: String) {
        #expect(!NoteAnchor.alike(a, b), "\(a) ~ \(b)")
    }

    /// The same control, named for each page's item after a separator.
    @Test func theSameControlNamedForTheItem() {
        #expect(NoteAnchor.alike("Add to cart - Great Value Milk", "Add to cart - Bananas"))
        #expect(NoteAnchor.alike("Add to cart", "Add to cart – Bananas"))
        #expect(NoteAnchor.alike("Add to cart - Great Value Whole Milk", "Add to cart - Bananas, each"))
        #expect(NoteAnchor.alike("Add to list: Milk", "Add to list: Bread"))
        #expect(NoteAnchor.alike("Add to registry (Milk)", "Add to registry (Bread)"))
        #expect(NoteAnchor.alike("Add to cart", "Add to cart"))
        // Ten characters of words before the separator, not counting it.
        #expect(!NoteAnchor.alike("Buy now - Milk", "Buy now - Bread"))
        #expect(!NoteAnchor.alike("Save changes", "Save draft") && !NoteAnchor.alike("Add to cart - Milk", "Add to list - Milk"))
        #expect(!NoteAnchor.alike(nil, "Add to cart") && !NoteAnchor.alike("", ""))
    }

    /// Two titles of one brand share the brand, not the item: not alike.
    @Test func sameBrandTitlesAreNotAlike() {
        #expect(!NoteAnchor.alike("Better Homes & Gardens 13 in Green Velvet Pillow", "Better Homes & Gardens 15 in Blue Linen Lamp"))
        #expect(!NoteAnchor.alike("Better Homes & Gardens 13 in Green Velvet Pillow", "Mainstays 15 in Blue Linen Lamp"))
    }

    /// A hint kept for this page only is never drawn on a different control by a name merely like its own.
    @Test func aThisPageHintIsNotDrawnOnALikeNamedControl() {
        let hint = H.hint(on: "Add to cart - Great Value Milk")
        #expect(hint.anchor.pattern == nil)
        let page = H.page("https://shop.example/ip/milk/1", [H.element("AXButton", "Add to cart - Bananas", H.cart)])
        let result = WandController.place([hint], page: page, primaryMaxY: 800)
        #expect(result.placed.isEmpty && result.missing.map(\.id) == ["n"])
        // Nor counted as scrolled out of view because a like-named control is.
        let hidden = H.page("https://shop.example/ip/milk/1", [H.element("AXButton", "Add to cart - Bananas", H.cart, visible: false)])
        let off = WandController.place([hint], page: hidden, primaryMaxY: 800)
        #expect(off.below.isEmpty && off.missing.map(\.id) == ["n"])
    }

    /// `--find` no longer reports another provider's button as an "alike" hit.
    @Test func findDoesNotReportAnotherProvider() {
        let page = H.page("https://shop.example/login", [H.element("AXButton", "Sign in with Apple", H.cart)])
        let found = HeadlessRead.find("Sign in with Google", role: "AXButton", in: page)
        #expect(found.match == "none" && found.count == 0)
    }

    /// R03 with two lamps of one brand: page A's title hint goes on page B's title, found as the item's name there
    /// (not by the brand the two titles share, and not on A's spot).
    @Test func sameBrandTitleHintGoesOnTheOtherTitle() {
        let urlC = "https://www.walmart.com/ip/Better-Homes-Gardens-15-in-Blue-Linen-Drum-Shade-Table-Lamp/123456789"
        let titleC = "Better Homes & Gardens 15 in Blue Linen Drum Shade Table Lamp"
        let page = I.page(urlC, [I.element("AXHeading", titleC, CGRect(x: 100, y: 300, width: 400, height: 40))])
        let result = WandController.place([I.titleNote(near: nil)], page: page, primaryMaxY: 1_000)
        #expect(result.missing.isEmpty)
        #expect(result.placed.first?.predicted == false)
        #expect(result.placed.first?.frame == NSRect(x: 100, y: 1_000 - 340, width: 400, height: 40))
    }

    /// The other brand's lamp, no neighbour: on page B's title, not on A's spot.
    @Test func otherBrandTitleHintGoesOnTheTitle() {
        let page = I.page(I.urlB, [I.element("AXHeading", I.titleB, CGRect(x: 100, y: 300, width: 400, height: 40)),
                                   I.element("AXButton", "Add to cart", CGRect(x: 500, y: 400, width: 200, height: 44))])
        let result = WandController.place([I.titleNote(near: nil)], page: page, primaryMaxY: 1_000)
        #expect(result.placed.first?.predicted == false)
        #expect(result.placed.first?.frame == NSRect(x: 100, y: 660, width: 400, height: 40))
    }

    /// Of several headings that name an item on the page (a carousel of like lamps), the one nearest the hint's spot;
    /// a heading of another role or not naming the item is passed over.
    @Test func ofSeveralItemNamesTheNearestOfItsRole() {
        let near = I.element("AXHeading", I.titleB, CGRect(x: 480, y: 150, width: 420, height: 40))
        let carousel = I.element("AXHeading", "Home Decor Collection 18 in Ribbed Ceramic Lamp", CGRect(x: 0, y: 700, width: 200, height: 20))
        let link = I.element("AXLink", I.titleB, CGRect(x: 500, y: 165, width: 400, height: 40))
        let generic = I.element("AXHeading", "Specifications", CGRect(x: 500, y: 160, width: 400, height: 40))
        let page = I.page(I.urlB, [carousel, link, generic, near])
        let result = WandController.place([I.titleNote(near: nil)], page: page, primaryMaxY: 1_000)
        #expect(result.placed.first?.predicted == false)
        #expect(result.placed.first?.frame == NSRect(x: 480, y: 810, width: 420, height: 40))
    }

    /// A hint for this page only on a title is not moved onto another item's title.
    @Test func aThisPageTitleHintIsNotMovedToAnotherTitle() {
        var onePage = I.titleNote(near: nil)
        onePage.anchor.pattern = nil
        let page = I.page(I.urlB, [I.element("AXHeading", I.titleB, CGRect(x: 100, y: 300, width: 400, height: 40))])
        #expect(WandController.place([onePage], page: page, primaryMaxY: 1_000).missing.map(\.id) == ["title"])
    }
}
