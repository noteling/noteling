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

    /// The same note with no neighbour, as the pen keeps it before the page is read.
    static func alone(_ note: StickyNote) -> StickyNote {
        var note = note
        note.anchor.near = nil
        return note
    }

    static let frameB = P.titleB.frame!

    /// A like lamp's heading, its every word in B's address, and fewer of them than B's title has.
    static let like = P.element("AXHeading", "Ceramic Table Lamp with Pleated Shade", CGRect(x: 100, y: 300, width: 200, height: 40))

    @Test func theTitleInViewWinsOverTheNeighbourScrolledAway() async throws {
        let note = try await Self.kept(on: P.titleA)
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [P.titleB, P.priceB, Self.away(P.cartB)])) == .on(Self.frameB))
        // The same as the hint with no neighbour.
        #expect(Self.landing(Self.alone(note), on: Lamp.page(Lamp.urlB, [P.titleB, P.priceB, Self.away(P.cartB)])) == .on(Self.frameB))
    }

    /// Of two headings with B's name in view, the nearer to where A's title was, as with no neighbour at all.
    @Test func ofTwoNamesInViewItIsTheNearerToTheSpot() async throws {
        let note = try await Self.kept(on: P.titleA)
        let first = P.pageBTwice.elements[0]
        for names in [[first, P.titleB], [P.titleB, first]] {
            #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, names + [Self.away(P.cartB)])) == .on(first.frame!))
        }
    }

    /// B's name in a second heading, scrolled away, does not keep the one in view from winning.
    @Test func theSameNameScrolledAwayDoesNotMatter() async throws {
        let note = try await Self.kept(on: P.titleA)
        let again = P.element("AXHeading", Lamp.titleB, Self.frameB)
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [Self.away(again), P.titleB, Self.away(P.cartB)])) == .on(Self.frameB))
    }

    /// A row of like items further down B lists A too: the hint's own name is on the page, scrolled away, and B's
    /// title is the one it goes on.
    @Test func itsOwnItemsNameInARowFurtherDownDoesNotMatter() async throws {
        let note = try await Self.kept(on: P.titleA)
        let page = Lamp.page(Lamp.urlB, [P.titleB, P.priceB, Self.away(P.cartB), Self.away(P.titleA)])
        #expect(Self.landing(note, on: page) == .on(Self.frameB))
        #expect(Self.landing(Self.alone(note), on: page) == .on(Self.frameB))
    }

    /// On the hint's own page the title is found by its name, whatever is scrolled away.
    @Test func onItsOwnPageItIsFoundByName() async throws {
        let note = try await Self.kept(on: P.titleA)
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlA, [P.titleA, Self.away(P.cartA)])) == .on(P.titleA.frame!))
    }

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
        // One word of the address, or fewer than most of a name's words, do not name the item.
        for other in ["Lamp", "Mainstays Ceramic Desk Lamp, Blue Drum Shade"] {
            let heading = P.element("AXHeading", other, Self.frameB)
            #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [heading, P.priceB, Self.away(P.cartB)])) == .below, "\(other)")
        }
    }

    // MARK: the item's name, scrolled away, and a like one in view

    @Test func aLikeNameInViewIsNotTheTitleScrolledAway() async throws {
        let note = try await Self.kept(on: P.titleA)
        #expect(NoteAnchor.namesTheItem(Self.like.label, page: PageKey.of(Lamp.urlB)))
        for cart in [Self.away(P.cartB, y: -400), P.cartB] {   // and with the cart in a bar that stays in view
            let page = Lamp.page(Lamp.urlB, [Self.away(P.titleB, y: -600), cart, Self.like])
            #expect(Self.landing(note, on: page) == .below)
            #expect(Self.landing(Self.alone(note), on: page) == .below)
        }
    }

    /// Both in view, the like one just where A's title was: B's title, not the nearer.
    @Test func ofTheTitleAndALikeNameInViewItIsTheTitle() async throws {
        let note = try await Self.kept(on: P.titleA)
        var near = Self.like
        near.frame = P.titleA.frame
        for names in [[near, P.titleB], [P.titleB, near]] {
            let page = Lamp.page(Lamp.urlB, names + [Self.away(P.cartB)])
            #expect(Self.landing(note, on: page) == .on(Self.frameB))
            #expect(Self.landing(Self.alone(note), on: page) == .on(Self.frameB))
        }
    }

    /// The same lamp in another colour, B's title but for one word.
    @Test func anotherColourInViewIsNotTheTitleScrolledAway() async throws {
        let note = try await Self.kept(on: P.titleA)
        let blue = P.element("AXHeading", Lamp.titleB.replacingOccurrences(of: "Ivory", with: "Blue"), Self.like.frame!)
        #expect(NoteAnchor.namesTheItem(blue.label, page: PageKey.of(Lamp.urlB)))
        let page = Lamp.page(Lamp.urlB, [Self.away(P.titleB, y: -600), Self.away(P.cartB, y: -400), blue])
        #expect(Self.landing(note, on: page) == .below)
        #expect(Self.landing(Self.alone(note), on: page) == .below)
    }

    /// Down A's own page, at a carousel of like lamps.
    @Test func onItsOwnPageALikeLampsNameIsNotTheTitleScrolledAway() async throws {
        let note = try await Self.kept(on: P.titleA)
        let pink = P.element("AXHeading", "Better Homes & Gardens 13 in Pink Velvet Pleated Shade Table Lamp", Self.like.frame!)
        #expect(NoteAnchor.namesTheItem(pink.label, page: PageKey.of(Lamp.urlA)))
        let page = Lamp.page(Lamp.urlA, [Self.away(P.titleA, y: -600), Self.away(P.cartA, y: -400), pink])
        #expect(Self.landing(note, on: page) == .below)
        #expect(Self.landing(Self.alone(note), on: page) == .below)
    }

    /// Known limit: B's title in a shorter form in view, and a fuller name of the item scrolled away. A miss, not a
    /// wrong place.
    @Test func aFullerNameScrolledAwayKeepsTheHintFromAShorterOneInView() async throws {
        let note = try await Self.kept(on: P.titleA)
        let short = P.element("AXHeading", "Home Decor Ribbed Ceramic Table Lamp", Self.frameB)
        let page = Lamp.page(Lamp.urlB, [short, Self.away(P.cartB), Self.away(P.titleB)])
        #expect(Self.landing(note, on: page) == .below)
        #expect(Self.landing(Self.alone(note), on: page) == .below)
    }

    /// Known limit: B's title is not listed at all, so a like name is the best the page has.
    @Test func withNoTitleListedALikeNameInViewTakesTheHint() async throws {
        let note = try await Self.kept(on: P.titleA)
        let page = Lamp.page(Lamp.urlB, [Self.like, P.priceB, Self.away(P.cartB)])
        #expect(Self.landing(note, on: page) == .on(Self.like.frame!))
        #expect(Self.landing(Self.alone(note), on: page) == .on(Self.like.frame!))
    }

    // MARK: names with as many words in the address

    /// B's title with more put to it: another listing, or a section about it.
    static let longer = ["\(Lamp.titleB), Set of 2", "About \(Lamp.titleB)"].map { P.element("AXHeading", $0, like.frame!) }

    @Test func theTitleWithMorePutToItIsNotTheTitleScrolledAway() async throws {
        let note = try await Self.kept(on: P.titleA)
        for other in Self.longer {
            #expect(NoteAnchor.itemWords(other.label, page: PageKey.of(Lamp.urlB)).inAddress
                    == NoteAnchor.itemWords(Lamp.titleB, page: PageKey.of(Lamp.urlB)).inAddress)
            for cart in [Self.away(P.cartB, y: -400), P.cartB] {
                let page = Lamp.page(Lamp.urlB, [Self.away(P.titleB, y: -600), cart, other])
                #expect(Self.landing(note, on: page) == .below, "\(other.label ?? "")")
                #expect(Self.landing(Self.alone(note), on: page) == .below, "\(other.label ?? "")")
            }
        }
    }

    /// Both in view, the longer one just where A's title was: B's title. And with the longer one scrolled away.
    @Test func ofTheTitleAndOneWithMorePutToItItIsTheTitle() async throws {
        let note = try await Self.kept(on: P.titleA)
        for other in Self.longer {
            var near = other
            near.frame = P.titleA.frame
            for names in [[near, P.titleB], [P.titleB, near], [Self.away(near), P.titleB]] {
                let page = Lamp.page(Lamp.urlB, names + [Self.away(P.cartB)])
                #expect(Self.landing(note, on: page) == .on(Self.frameB), "\(other.label ?? "")")
                #expect(Self.landing(Self.alone(note), on: page) == .on(Self.frameB), "\(other.label ?? "")")
            }
        }
    }

    /// The fewest words count only among the names with the most in the address: one of two words, both in it, is not
    /// the title.
    @Test func aShortNameAllInTheAddressIsNotTheTitle() async throws {
        let note = try await Self.kept(on: P.titleA)
        let short = P.element("AXHeading", "Home Decor", P.titleA.frame!)
        #expect(NoteAnchor.namesTheItem(short.label, page: PageKey.of(Lamp.urlB)))
        for names in [[short, P.titleB, Self.longer[0]], [Self.longer[0], P.titleB, short]] {
            let page = Lamp.page(Lamp.urlB, names + [Self.away(P.cartB)])
            #expect(Self.landing(note, on: page) == .on(Self.frameB))
            #expect(Self.landing(Self.alone(note), on: page) == .on(Self.frameB))
        }
    }

    /// Known limit: B's title without its brand (which B's address has), and a like lamp named with it, which then has
    /// more words in the address. In view it takes the hint: a wrong place. Scrolled away, it is a miss.
    @Test func aLikeNameWithTheBrandTakesTheHintFromATitleWithoutIt() async throws {
        let note = try await Self.kept(on: P.titleA)
        let bare = P.element("AXHeading", "18 in Ribbed Ceramic Table Lamp with Ivory Pleated Shade", Self.frameB)
        let blue = P.element("AXHeading", Lamp.titleB.replacingOccurrences(of: "Ivory", with: "Blue"), Self.like.frame!)
        let both = Lamp.page(Lamp.urlB, [bare, blue, Self.away(P.cartB)])
        #expect(Self.landing(note, on: both) == .on(blue.frame!))
        #expect(Self.landing(Self.alone(note), on: both) == .on(blue.frame!))
        // The cart in view: the neighbour finds the title, and with no neighbour it is the like lamp's again.
        let cart = Lamp.page(Lamp.urlB, [bare, blue, P.cartB])
        #expect(Self.landing(note, on: cart) == .on(Self.frameB))
        #expect(Self.landing(Self.alone(note), on: cart) == .on(blue.frame!))
        let miss = Lamp.page(Lamp.urlB, [bare, Self.away(blue), Self.away(P.cartB)])
        #expect(Self.landing(note, on: miss) == .below)
        #expect(Self.landing(Self.alone(note), on: miss) == .below)
    }

    // MARK: names alike but for words of one or two letters

    static let spotA = P.titleA.frame!
    static let bulbsUrl = "https://www.walmart.com/ip/Great-Value-LED-Bulbs-60-Watt-Soft-White-2-Pack/123456789"
    static let bulbs = "Great Value LED Bulbs 60 Watt Soft White 2 Pack"

    /// A page: its address, its title, and a name alike.
    struct Alike: CustomTestStringConvertible {
        let url: String, title: String, other: String
        var testDescription: String { other }
        @MainActor func heading() -> PageElement { P.element("AXHeading", title, ItemNameInViewTests.frameB) }
        @MainActor func like(_ frame: CGRect) -> PageElement { P.element("AXHeading", other, frame) }
        @MainActor func page(_ elements: [PageElement]) -> PageSnapshot { Lamp.page(url, elements) }
    }

    static let shortWordsApart = [
        Alike(url: bulbsUrl, title: bulbs, other: "Great Value LED Bulbs 60 Watt Soft White 4 Pack"),
        Alike(url: bulbsUrl, title: bulbs, other: "Great Value LED Bulbs 40 Watt Soft White 2 Pack"),
        Alike(url: Lamp.urlB, title: Lamp.titleB, other: "\(Lamp.titleB), 2 Pk"),
        Alike(url: Lamp.urlB, title: Lamp.titleB, other: Lamp.titleB.replacingOccurrences(of: "18 in ", with: "")),
    ]
    static let hundredWatt = Alike(url: bulbsUrl, title: bulbs, other: "Great Value LED Bulbs 100 Watt Soft White 2 Pack")

    @Test(arguments: shortWordsApart + [hundredWatt], [true, false])
    func aNameAlikeButForShortWordsIsNotTheTitleScrolledAway(_ it: Alike, cartInView: Bool) async throws {
        let note = try await Self.kept(on: P.titleA)
        let cart = cartInView ? P.cartB : Self.away(P.cartB, y: -400)
        for names in [[Self.away(it.heading(), y: -600), it.like(Self.like.frame!)], [it.like(Self.like.frame!), Self.away(it.heading(), y: -600)]] {
            #expect(Self.landing(note, on: it.page(names + [cart])) == .below)
            #expect(Self.landing(Self.alone(note), on: it.page(names + [cart])) == .below)
        }
    }

    /// Both in view, the other just where A's title was.
    @Test(arguments: shortWordsApart + [hundredWatt], [true, false])
    func ofTheTitleAndANameAlikeButForShortWordsItIsTheTitle(_ it: Alike, cartInView: Bool) async throws {
        let note = try await Self.kept(on: P.titleA)
        let cart = cartInView ? P.cartB : Self.away(P.cartB)
        for names in [[it.heading(), it.like(Self.spotA)], [it.like(Self.spotA), it.heading()]] {
            #expect(Self.landing(note, on: it.page(names + [cart])) == .on(Self.frameB))
            #expect(Self.landing(Self.alone(note), on: it.page(names + [cart])) == .on(Self.frameB))
        }
    }

    static let blueB = Lamp.titleB.replacingOccurrences(of: "Ivory", with: "Blue")

    /// A title, and a like item's name with fewer of the longer words in the address: some with more of the short
    /// ones, which the title lacks or writes otherwise.
    static let aLongWordApart = ["", "18in ", "18\" ", "18 in "].map {
        Alike(url: Lamp.urlB, title: Lamp.titleB.replacingOccurrences(of: "18 in ", with: $0), other: blueB)
    } + [
        Alike(url: "https://www.walmart.com/ip/Ceramic-Table-Lamp-in-Ivory-by-Home-Decor/123456789",
              title: "Home Decor Ceramic Table Lamp, Ivory", other: "Ceramic Table Lamp in Blue by Home Decor"),
        Alike(url: "https://www.walmart.com/ip/Great-Value-LED-Bulbs-Soft-White-A-19-E-26-2-Pack/123456789",
              title: "Great Value LED Bulbs Soft White 2 Pack", other: "Great Value LED Bulbs Cool White A 19 E 26 2 Pack"),
    ]

    /// Short words never outdo a longer one.
    @Test(arguments: aLongWordApart)
    func shortWordsDoNotOutdoALongerOne(_ it: Alike) async throws {
        let note = try await Self.kept(on: P.titleA)
        for hint in [note, Self.alone(note)] {
            for cart in [P.cartB, Self.away(P.cartB)] {
                #expect(Self.landing(hint, on: it.page([Self.away(it.heading(), y: -600), it.like(Self.like.frame!), cart])) == .below)
                #expect(Self.landing(hint, on: it.page([it.like(Self.spotA), it.heading(), cart])) == .on(Self.frameB))
                #expect(Self.landing(hint, on: it.page([it.heading(), Self.away(it.like(Self.like.frame!)), cart])) == .on(Self.frameB))
            }
        }
    }

    /// Nor do they outdo the fewest of the longer words.
    @Test func shortWordsDoNotOutdoTheFewestLongerOnes() async throws {
        let note = try await Self.kept(on: P.titleA)
        let it = Alike(url: Lamp.urlB, title: Lamp.titleB.replacingOccurrences(of: "18 in ", with: ""), other: "About \(Lamp.titleB)")
        for hint in [note, Self.alone(note)] {
            #expect(Self.landing(hint, on: it.page([Self.away(it.heading(), y: -600), it.like(Self.like.frame!), Self.away(P.cartB)])) == .below)
            #expect(Self.landing(hint, on: it.page([it.like(Self.spotA), it.heading(), Self.away(P.cartB)])) == .on(Self.frameB))
        }
        // Known limit, the price of it: a title with one word more than a pack sibling, which takes the hint.
        let new = Alike(url: Self.bulbsUrl, title: "New \(Self.bulbs)", other: Self.shortWordsApart[0].other)
        for hint in [note, Self.alone(note)] {
            #expect(Self.landing(hint, on: new.page([Self.away(new.heading(), y: -600), new.like(Self.like.frame!), Self.away(P.cartB)])) == .on(Self.like.frame!))
        }
    }

    /// Known limits, each a wrong place with the like name in view and a miss with it scrolled away: the address lacks
    /// a short word of the title, and a like name lacks it too, so has the fewest words; or the title lacks a short
    /// word of the address, and a like name has it.
    static let shortWordLimits = [
        Alike(url: "https://www.walmart.com/ip/nike-air-max-running-shoes/123456789",
              title: "Nike Air Max 90 Running Shoes", other: "Nike Air Max Running Shoes"),
        Alike(url: "https://www.walmart.com/ip/Home-Decor-18-in-Ribbed-Ceramic-Table-Lamp/123456789",
              title: "Home Decor Ribbed Ceramic Table Lamp", other: "Home Decor 20 in Ribbed Ceramic Table Lamp"),
    ]

    @Test(arguments: shortWordLimits)
    func aShortWordOnlyTheTitleOrTheAddressHasCostsTheTitleTheHint(_ it: Alike) async throws {
        let note = try await Self.kept(on: P.titleA)
        let both = [it.heading(), it.like(Self.like.frame!)]   // the title the nearer to where A's was
        for hint in [note, Self.alone(note)] {
            #expect(Self.landing(hint, on: it.page(both + [Self.away(P.cartB)])) == .on(Self.like.frame!))
            #expect(Self.landing(hint, on: it.page([it.heading(), Self.away(it.like(Self.like.frame!)), Self.away(P.cartB)])) == .below)
        }
        // The cart in view: the neighbour finds the title.
        #expect(Self.landing(note, on: it.page(both + [P.cartB])) == .on(Self.frameB))
    }

    // MARK: as before

    @Test func aPriceIsFurtherDownWithItsNeighbour() async throws {
        let note = try await Self.kept(on: P.priceA)
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [P.titleB, P.priceB, Self.away(P.cartB)])) == .below)
        #expect(Self.landing(note, on: P.pageB) == .on(P.priceB.frame!))
    }

    /// Kept for this page only, the hint is on its own title or none: not on B's, with the pattern taken off.
    @Test func aHintForOnePageIsNotPutOnAnotherName() async throws {
        var note = try await Self.kept(on: P.titleA)
        note.anchor.pattern = nil
        // Nor further down with the neighbour it still carries: its title is not on this page at all.
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [P.titleB, P.priceB, Self.away(P.cartB)])) == .missing)
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
