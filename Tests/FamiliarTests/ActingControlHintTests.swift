import AppKit
import Foundation
import Testing
@testable import Familiar

/// A hint for pages like this on a control that acts (a button and the like) whose name is the item's: it is on that
/// control by its own name, or on nothing. The steps that find a title on the next item's page (by the item's name,
/// the neighbour, the old spot) would put it on another control with that item's name, such as "Remove …".
@Suite @MainActor
struct ActingControlHintTests {
    typealias P = PenSavePathTests
    typealias Lamp = ItemNameHintTests
    typealias V = ItemNameInViewTests

    /// The last is no role there is: a role not known to be a name for reading is taken to act.
    nonisolated static let acting = ["AXButton", "AXLink", "AXMenuItem", "AXCheckBox", "AXDisclosureTriangle", "AXGroup", "AXNotARole"]
    nonisolated static let reading = ["AXHeading", "AXImage", "AXStaticText"]

    static let place = CGRect(x: 500, y: 160, width: 400, height: 40)

    static func element(_ role: String, _ label: String, y: CGFloat = 160) -> PageElement {
        P.element(role, label, CGRect(x: 500, y: y, width: 400, height: 40))
    }

    /// A hint on a control of a page, for pages of its kind.
    static func hint(_ role: String, _ label: String, on url: String, near: NoteNear? = nil) throws -> StickyNote {
        var anchor = NoteStore.sceneAnchor(bundleID: "com.google.Chrome", windowTitle: "Shop", url: url)
        anchor.role = role
        anchor.label = label
        anchor.rect = [0.5, 0.2, 0.4, 0.05]
        anchor.pattern = PagePattern.of(try #require(anchor.page)).description
        anchor.near = near
        return StickyNote(id: "acting", anchor: anchor, kind: "tip", text: "t", by: "x", at: "2026-11-22", confirmed: "2026-11-22")
    }

    /// B's page is one the hint is met on, else a test of where it goes there shows nothing.
    static func met(_ note: StickyNote, on url: String) -> Bool {
        note.anchor.matchesScene(ScreenContext(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: "Shop", url: url, focused: nil, timestamp: Date()))
    }

    static let review = "Write a review for "
    static let removeB = "Remove \(Lamp.titleB)"

    // MARK: another page of the kind

    @Test(arguments: acting) func aReviewsHintIsNotOnRemove(_ role: String) throws {
        let note = try Self.hint(role, Self.review + Lamp.titleA, on: Lamp.urlA)
        #expect(Self.met(note, on: Lamp.urlB))
        #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [Self.element(role, Self.removeB)])) == .missing)
        // Nor on B's own "Write a review for …", whose name is another: missing, not a guess.
        #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [Self.element(role, Self.removeB), Self.element(role, Self.review + Lamp.titleB, y: 300)])) == .missing)
        #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [])) == .missing)
    }

    @Test(arguments: acting) func aHintOnAControlThatIsJustTheTitleIsNotOnRemove(_ role: String) throws {
        let note = try Self.hint(role, Lamp.titleA, on: Lamp.urlA)
        #expect(Self.met(note, on: Lamp.urlB))
        #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [Self.element(role, Self.removeB)])) == .missing)
        #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [P.titleB])) == .missing)
    }

    /// Pages whose address is itself an action's name.
    nonisolated static let actions = [
        ("https://shop.example/help/Track-My-Recent-Order/1234567", "Track my recent order",
         "https://shop.example/help/Cancel-My-Recent-Order/7654321", "Cancel my recent order"),
        ("https://shop.example/account/view-my-saved-cards", "View my saved cards",
         "https://shop.example/account/delete-my-saved-cards", "Delete my saved cards"),
        ("https://app.example/help/sign-in-to-my-account/1234567", "Sign in to my account",
         "https://app.example/help/delete-all-my-data/7654321", "Delete all my data"),
        ("https://app.example/help/change-your-email-address", "Change your email address",
         "https://app.example/help/delete-your-account-for-good", "Delete your account for good"),
        ("https://app.example/help/change-your-email-address/1234567", "Change your email address",
         "https://app.example/help/sign-out-of-all-your-devices/7654321", "Sign out of all your devices"),
        ("https://app.example/settings/turn-on-two-step-sign-in", "Turn on two step sign in",
         "https://app.example/settings/close-your-account-and-delete-it", "Close your account and delete it"),
    ]

    @Test(arguments: acting, actions) func anActionsPageIsNotAnItems(_ role: String, _ c: (String, String, String, String)) throws {
        let note = try Self.hint(role, c.1, on: c.0)
        #expect(Self.met(note, on: c.2))
        #expect(V.landing(note, on: Lamp.page(c.2, [Self.element(role, c.3)])) == .missing)
        #expect(V.landing(note, on: Lamp.page(c.0, [Self.element(role, c.3)])) == .missing)
        #expect(V.landing(note, on: Lamp.page(c.0, [Self.element(role, c.3, y: 100), Self.element(role, c.1)])) == .on(Self.place))
    }

    /// A neighbour kept by an older build is not gone by, in view or away.
    @Test(arguments: acting) func aNeighbourItAlreadyCarriesIsNotGoneBy(_ role: String) throws {
        let note = try Self.hint(role, Self.review + Lamp.titleA, on: Lamp.urlA, near: P.nearA)
        let remove = Self.element(role, Self.removeB, y: 260)       // where the neighbour would put it
        #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [remove, P.cartB])) == .missing)
        #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [remove, V.away(P.cartB)])) == .missing)
        #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [P.cartB])) == .missing)
    }

    /// Only what is listed is there to be read: a hint or a control with no role, or one not known, acts.
    @Test func whatIsNotListedActs() throws {
        for role in Self.reading { #expect(NoteAnchor.isForReading(role), "\(role)") }
        for role in Self.acting { #expect(!NoteAnchor.isForReading(role), "\(role)") }
        #expect(!NoteAnchor.isForReading(nil) && !NoteAnchor.isForReading(""))
        var note = try Self.hint("AXHeading", Lamp.titleA, on: Lamp.urlA, near: P.nearA)
        note.anchor.role = nil
        #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [P.titleB, P.cartB])) == .missing)
    }

    // MARK: its own page

    @Test(arguments: acting, ["Remove ", "Save ", "Add to cart - "]) func onItsOwnPageItIsOnItsOwnControlOrFurtherDown(_ role: String, _ verb: String) throws {
        let note = try Self.hint(role, Self.review + Lamp.titleA, on: Lamp.urlA)
        let own = Self.element(role, Self.review + Lamp.titleA, y: 300), other = Self.element(role, verb + Lamp.titleA)
        #expect(V.landing(note, on: Lamp.page(Lamp.urlA, [other, own])) == .on(own.frame!))
        #expect(V.landing(note, on: Lamp.page(Lamp.urlA, [other, V.away(own)])) == .below)
        #expect(V.landing(note, on: Lamp.page(Lamp.urlA, [other])) == .missing)
    }

    @Test(arguments: acting) func itsNeighbourInViewDoesNotComeBeforeItsOwnControlScrolledAway(_ role: String) throws {
        let note = try Self.hint(role, Self.review + Lamp.titleA, on: Lamp.urlA, near: P.nearA)
        let own = Self.element(role, Self.review + Lamp.titleA)
        #expect(V.landing(note, on: Lamp.page(Lamp.urlA, [Self.element(role, "Remove \(Lamp.titleA)"), V.away(own), P.cartA])) == .below)
    }

    /// The names part at a plain word, and most of each name's words are in its address (docs/use/hints.md).
    @Test(arguments: acting) func namesThatPartAtAPlainWordArePartedWhateverTheAddress(_ role: String) throws {
        let milk = "https://shop.example/ip/Great-Value-Milk-Whole-Gallon/1234567", eggs = "https://shop.example/ip/Great-Value-Eggs-Large-Dozen/7654321"
        let note = try Self.hint(role, "Add to cart - Great Value Milk", on: milk)
        #expect(NoteAnchor.namesTheItem(note.anchor.label, page: note.anchor.page))
        #expect(V.landing(note, on: Lamp.page(eggs, [Self.element(role, "Add to cart - Great Value Eggs")])) == .missing)
    }

    /// What stays: a name that differs after a separator, and one that differs in a count.
    @Test(arguments: acting) func aSeparatorOrACountStillFindsIt(_ role: String) throws {
        let milk = "https://shop.example/ip/Great-Value-Whole-Milk-Gallon/1234567", eggs = "https://shop.example/ip/Large-White-Eggs-Dozen/7654321"
        let cart = try Self.hint(role, "Add to cart - Great Value Whole Milk Gallon", on: milk)
        #expect(V.landing(cart, on: Lamp.page(eggs, [Self.element(role, "Remove Large White Eggs Dozen"), Self.element(role, "Add to cart - Large White Eggs Dozen", y: 300)]))
                == .on(CGRect(x: 500, y: 300, width: 400, height: 40)))
        let bag = try Self.hint(role, "Great Value Whole Milk Gallon (3)", on: milk)
        #expect(V.landing(bag, on: Lamp.page(milk, [Self.element(role, "Great Value Whole Milk Gallon (4)")])) == .on(Self.place))
    }

    // MARK: a hint on something that does not act, where a control that acts has the item's name

    /// A hint kept as text agrees with buttons, for the older pens' hints on the words inside one; but not by the
    /// item's name.
    @Test(arguments: reading, ["AXButton", "AXLink"]) func aTitlesHintIsNotOnRemove(_ role: String, _ there: String) throws {
        let note = try Self.hint(role, Lamp.titleA, on: Lamp.urlA)
        let remove = Self.element(there, Self.removeB, y: 600)
        // Where it was, as before, but for text with no neighbour (below).
        #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [remove])) == (role == "AXStaticText" ? .missing : .guessed(Self.place)))
        // B's title wins over the button, in view; and keeps the hint from a guess, scrolled away.
        let title = Self.element(role, Lamp.titleB, y: 400)
        #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [remove, title])) == .on(title.frame!))
        #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [remove, V.away(title)])) == .below)
    }

    /// A hint on text goes where it was only with a neighbour kept; an older pen's, on the words inside a button, has
    /// none.
    @Test func aTextHintGoesWhereItWasOnlyWithANeighbourKept() throws {
        let alone = try Self.hint("AXStaticText", Lamp.titleA, on: Lamp.urlA)
        let kept = try Self.hint("AXStaticText", Lamp.titleA, on: Lamp.urlA, near: P.nearA)
        let page = Lamp.page(Lamp.urlB, [P.element("AXStaticText", "$31.50", CGRect(x: 500, y: 350, width: 80, height: 30))])
        #expect(V.landing(alone, on: page) == .missing)
        #expect(V.landing(kept, on: page) == .guessed(Self.place))
        // B's title is found with or without one.
        let title = Self.element("AXStaticText", Lamp.titleB, y: 400)
        for note in [alone, kept] { #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [title])) == .on(title.frame!)) }
    }

    /// An older pen's hint on the words inside a button, the button scrolled away: further down, whatever other text
    /// there is with the item's name.
    @Test(arguments: ["AXButton", "AXLink"]) func itsOwnControlScrolledAwayIsFurtherDown(_ role: String) throws {
        let own = Self.element(role, Self.review + Lamp.titleA)
        for near in [nil, P.nearA] {
            let note = try Self.hint("AXStaticText", Self.review + Lamp.titleA, on: Lamp.urlA, near: near)
            for others in [[], [P.cartA], [Self.element(role, "Save \(Lamp.titleA)"), P.cartA], [Self.element("AXStaticText", Lamp.titleA, y: 300)]] {
                #expect(V.landing(note, on: Lamp.page(Lamp.urlA, others + [V.away(own)])) == .below)
            }
        }
    }

    /// Another item's page that links to the hint's own in a row further down: the title's hint is on this page's
    /// title, as it is on a heading's with a heading in the row.
    @Test(arguments: ["AXButton", "AXLink"]) func aLinkToItsOwnItemFurtherDownDoesNotMatter(_ role: String) throws {
        let row = V.away(Self.element(role, Lamp.titleA)), title = Self.element("AXStaticText", Lamp.titleB, y: 260)
        for near in [nil, P.nearA] {
            let note = try Self.hint("AXStaticText", Lamp.titleA, on: Lamp.urlA, near: near)
            #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [title, row])) == .on(title.frame!))
            #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [title, P.cartB, row])) == .on(title.frame!))
        }
    }

    /// Known: an older pen's hint on a button's words, on another item's page that lists that very button scrolled away,
    /// is on the title there when the title is plain text, with or without the button. Never on "Remove" that item.
    @Test(arguments: ["AXButton", "AXLink"], ["Remove ", review]) func onAnotherPageItsOwnControlScrolledAwayLeavesTheTitleToBeFound(_ role: String, _ verb: String) throws {
        let own = V.away(Self.element(role, verb + Lamp.titleA)), title = Self.element("AXStaticText", Lamp.titleB, y: 260)
        let remove = Self.element(role, Self.removeB, y: 600)
        for near in [nil, P.nearA] {
            let note = try Self.hint("AXStaticText", verb + Lamp.titleA, on: Lamp.urlA, near: near)
            #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [title, remove, own])) == .on(title.frame!))
            #expect(V.landing(note, on: Lamp.page(Lamp.urlB, [title, remove])) == .on(title.frame!))
        }
        let alone = try Self.hint("AXStaticText", verb + Lamp.titleA, on: Lamp.urlA)
        #expect(V.landing(alone, on: Lamp.page(Lamp.urlB, [remove, own])) == .below)
        #expect(V.landing(alone, on: Lamp.page(Lamp.urlB, [remove])) == .missing)
    }

    /// Only a control that acts, by the hint's own name and of a role that agrees, puts it further down before the
    /// title is looked for; and only where the hint's own is not in view. `variant` is A's title with a word put another
    /// way, so it is found by the item's name alone.
    static let variant = Lamp.titleA.replacingOccurrences(of: " & ", with: " ")

    @Test(arguments: reading) func itsOwnTitleScrolledAwayLeavesAnotherOfTheItemsNameInView(_ role: String) throws {
        let own = V.away(Self.element(role, Lamp.titleA)), other = Self.element(role, Self.variant, y: 300)
        for near in [nil, P.nearA] {
            let note = try Self.hint(role, Lamp.titleA, on: Lamp.urlA, near: near)
            for beside in [[], [P.cartA]] { #expect(V.landing(note, on: Lamp.page(Lamp.urlA, [other, own] + beside)) == .on(other.frame!)) }
            // One with the item's name just where the neighbour says.
            let there = Self.element(role, Self.variant)
            #expect(V.landing(note, on: Lamp.page(Lamp.urlA, [there, own, P.cartA])) == .on(there.frame!))
        }
    }

    /// Two controls by its name, a plain one or the item's, one of them scrolled away: on the one in view.
    @Test(arguments: ["AXButton", "AXLink"], ["Add to cart", Lamp.titleA, review + Lamp.titleA]) func anotherByItsNameScrolledAwayDoesNotMatter(_ role: String, _ name: String) throws {
        let own = Self.element(role, name), again = V.away(Self.element(role, name, y: 300))
        for kept in [role, "AXStaticText"] {
            var note = try Self.hint(kept, name, on: Lamp.urlA)
            for pattern in [note.anchor.pattern, nil] {
                note.anchor.pattern = pattern
                #expect(V.landing(note, on: Lamp.page(Lamp.urlA, [again, own])) == .on(own.frame!))
            }
        }
    }

    @Test(arguments: ["AXButton", "AXLink"]) func aControlOfAnotherRoleByItsNameIsNotItsOwn(_ role: String) throws {
        let there = V.away(Self.element(role, Lamp.titleA)), other = Self.element("AXHeading", Self.variant, y: 300)
        let title = try Self.hint("AXHeading", Lamp.titleA, on: Lamp.urlA)
        #expect(V.landing(title, on: Lamp.page(Lamp.urlA, [other, there])) == .on(other.frame!))
        let box = try Self.hint("AXCheckBox", Lamp.titleA, on: Lamp.urlA)
        #expect(V.landing(box, on: Lamp.page(Lamp.urlA, [there])) == .missing)
    }

    @Test(arguments: ["AXButton", "AXLink"]) func aControlWhoseNameOnlyStartsAsItsDoesIsNotItsOwn(_ role: String) throws {
        let like = V.away(Self.element(role, Lamp.titleA + " - Save")), other = Self.element("AXStaticText", Self.variant, y: 300)
        var note = try Self.hint("AXStaticText", Lamp.titleA, on: Lamp.urlA)
        #expect(note.anchor.isLikeElement(role: role, label: like.label))
        #expect(V.landing(note, on: Lamp.page(Lamp.urlA, [other, like])) == .on(other.frame!))
        note.anchor.pattern = nil
        #expect(V.landing(note, on: Lamp.page(Lamp.urlA, [other, like])) == .missing)
        // Nor is "Add to cart - Eggs" the "Add to cart - Milk" of this page.
        for kept in [role, "AXStaticText"] {
            var milk = try Self.hint(kept, "Add to cart - Milk", on: Lamp.urlA)
            milk.anchor.pattern = nil
            #expect(V.landing(milk, on: Lamp.page(Lamp.urlA, [V.away(Self.element(role, "Add to cart - Eggs"))])) == .missing)
        }
    }

    /// Its own page is the one with its page key: parameters that don't name the page change nothing; another slug for
    /// the same item is another page.
    @Test func itsOwnPageIsToldByThePageKey() throws {
        let note = try Self.hint("AXStaticText", Self.review + Lamp.titleA, on: Lamp.urlA)
        let els = [Self.element("AXStaticText", Lamp.titleA, y: 300), V.away(Self.element("AXButton", Self.review + Lamp.titleA))]
        #expect(V.landing(note, on: Lamp.page(Lamp.urlA + "?utm_source=mail", els)) == .below)
        let other = Lamp.urlA.replacingOccurrences(of: "/Better-Homes-Gardens-13-in-", with: "/Better-Homes-13-in-")
        #expect(Self.met(note, on: other) && PageKey.of(other) != PageKey.of(Lamp.urlA))
        #expect(V.landing(note, on: Lamp.page(other, els)) == .on(els[0].frame!))
    }

    /// An older pen's hint on a button's words is still on that button by its name.
    @Test func aHintKeptAsTextIsStillOnItsButton() throws {
        let note = try Self.hint("AXStaticText", Self.review + Lamp.titleA, on: Lamp.urlA)
        let own = Self.element("AXButton", Self.review + Lamp.titleA, y: 300)
        #expect(V.landing(note, on: Lamp.page(Lamp.urlA, [Self.element("AXButton", "Remove \(Lamp.titleA)"), own])) == .on(own.frame!))
    }

    // MARK: what is as it was

    /// Known, from `alike`, and the same before: two controls whose names share ten characters or more before a
    /// separator are one control's on pages of a kind.
    @Test(arguments: acting) func namesAlikeBeforeASeparatorAreStillOneControls(_ role: String) throws {
        let option = try Self.hint(role, "Remove the saved option for this order: Gift Wrap and Message Card", on: "https://shop.example/ip/Gift-Wrap-and-Message-Card/1234567")
        #expect(V.landing(option, on: Lamp.page(Lamp.urlB, [Self.element(role, "Remove the saved option for this order: \(Lamp.titleB)")])) == .on(Self.place))
        let milk = try Self.hint(role, "Add to cart - Milk", on: "https://shop.example/ip/Great-Value-Whole-Milk/1234567")
        let own = V.away(Self.element(role, "Add to cart - Milk")), eggs = Self.element(role, "Add to cart - Eggs", y: 300)
        #expect(V.landing(milk, on: Lamp.page("https://shop.example/ip/Great-Value-White-Eggs/7654321", [eggs, own])) == .on(eggs.frame!))
    }

    /// For this page it is on its own control, further down or missing, whatever the role and whatever it carries.
    @Test(arguments: acting + reading) func forThisPageItIsOnItsOwnControlOrNothing(_ role: String) throws {
        var note = try Self.hint(role, Lamp.titleA, on: Lamp.urlA, near: P.nearA)
        note.anchor.pattern = nil
        let own = Self.element(role, Lamp.titleA), other = Self.element(role, "Remove \(Lamp.titleA)", y: 300)
        #expect(V.landing(note, on: Lamp.page(Lamp.urlA, [other, own, P.cartA])) == .on(Self.place))
        #expect(V.landing(note, on: Lamp.page(Lamp.urlA, [other, V.away(own), P.cartA])) == .below)
        #expect(V.landing(note, on: Lamp.page(Lamp.urlA, [other, P.cartA])) == .missing)
    }

    // MARK: the pen

    @Test(arguments: acting) func thePenKeepsNoNeighbourAndReadsNoPageForIt(_ role: String) async throws {
        let reads = P.Reads(P.pageA), pen = P.Pen(on: Lamp.urlA, reads: reads)
        try pen.open(Self.element(role, Self.review + Lamp.titleA))
        try await P.settle()
        let note = try pen.keep(scope: 1)
        #expect(note.anchor.role == role && note.anchor.label == Self.review + Lamp.titleA && note.anchor.pattern != nil)
        #expect(note.anchor.near == nil && reads.bundles.isEmpty)
    }

    @Test(arguments: reading) func thePenStillKeepsOneForATitle(_ role: String) async throws {
        let reads = P.Reads(P.pageA), pen = P.Pen(on: Lamp.urlA, reads: reads)
        try pen.open(Self.element(role, Lamp.titleA))
        try await pen.pageRead()
        #expect(try pen.keep(scope: 1).anchor.near == P.nearA)
    }

    /// Nor for what is there to be read under a name that is not the item's.
    @Test(arguments: reading) func thePenReadsNoPageForAnotherName(_ role: String) async throws {
        let reads = P.Reads(P.pageA), pen = P.Pen(on: Lamp.urlA, reads: reads)
        try pen.open(Self.element(role, "Customer reviews"))
        try await P.settle()
        let note = try pen.keep(scope: 1)
        #expect(note.anchor.label == "Customer reviews" && note.anchor.pattern != nil)
        #expect(note.anchor.near == nil && reads.bundles.isEmpty)
    }
}
