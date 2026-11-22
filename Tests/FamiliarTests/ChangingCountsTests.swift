import AppKit
import Foundation
import Testing
@testable import Familiar

/// A hint on a control whose name carries a count that changes ("Notifications (3)"), when it would be missing: on the
/// one control of the page whose name differs only in the count. Names and pages are made up.
@Suite @MainActor
struct ChangingCountsTests {
    typealias P = PenSavePathTests
    typealias Lamp = ItemNameHintTests
    typealias V = ItemNameInViewTests

    // MARK: names

    /// One control, its count changed.
    nonisolated static let sameControl = [
        ("Notifications (3)", "Notifications (4)"),
        ("Customer reviews (1,234)", "Customer reviews (1,235)"),
        ("Shopping cart 1 item", "Shopping cart 2 items"),
        ("Shopping cart, 2 items", "Shopping cart, 3 items"),
        ("Shopping cart (1 item)", "Shopping cart (2 items)"),
        ("Cart contains 0 items", "Cart contains 1 item"),
        ("Messages, 3 unread messages", "Messages, 4 unread messages"),
        ("2 items in your cart", "1 item in your cart"),
        ("3 new notifications", "1 new notification"),
        ("Inbox, 5 unread", "Inbox, 6 unread"),
        ("View all 12 comments", "View all 13 comments"),
        ("See all 1,024 reviews", "See all 1,031 reviews"),
        ("Delete 2 items", "Delete 3 items"),
        ("Notifications, 3 new", "Notifications, 4 new"),
        ("Notifications (3 new)", "Notifications (1 new)"),
        ("Read 1 comment", "Read 2 comments"),
        ("Notifications (1)", "Notifications (12)"),
        ("Shopping cart (0 items)", "Shopping cart (1 item)"),
        ("1 unread message in Inbox", "4 unread messages in Inbox"),
        ("View cart (1 item)", "View cart (3 items)"),
        ("Wish list 1 item", "Wish list 4 items"),
        ("Friend requests 1 new", "Friend requests 2 new"),
        // Each shape's edges: ten characters of name; the years on either side; a count written with a comma.
        ("Open cases (3)", "Open cases (4)"),
        ("Yearly review (1899)", "Yearly review (2100)"),
        ("Customer reviews (1,950)", "Customer reviews (2,050)"),
        ("2 messages on this board", "3 messages on this board"),
        ("Notifications (3), open", "Notifications (4), open"),
        ("Notifications (3): open", "Notifications (4): open"),
        ("Notifications (3) open", "Notifications (4) open"),
        ("Notifications (0)", "Notifications (9)"),
        ("Messages, 1,000 unread messages", "Messages, 1 unread message"),
        // A "#" of the name's own, before the count and after it.
        ("#general: unread (3)", "#general: unread (4)"),
        ("Thread #12 comments (3)", "Thread #12 comments (14)"),
        ("Thread #12: 1 comment", "Thread #12: 2 comments"),
        ("3 messages in #general", "14 messages in #general"),
        ("Notifications (3) #general", "Notifications (4) #general"),
    ]

    /// One control too, and left missing: no shape here tells such a name from another control's.
    nonisolated static let leftMissing = [
        ("My team: 4 open tickets", "My team: 4 open ticket"),
        ("Open tickets 4 tickets", "Open tickets 5 tickets"),
        ("Cart, 2 items, view cart", "Cart, 3 items, view cart"),
        ("Notifications (99+)", "Notifications (98)"),
        ("Show 3 comments on this", "Show 4 comments on this"),
        ("3 reviews of this lamp", "4 reviews of this lamp"),
        ("Notifications 3", "Notifications 4"),
    ]

    /// Two controls.
    nonisolated static let otherControl = [
        ("Select size 10", "Select size 11"),
        ("Size 10", "Size 11"),
        ("Go to page 2", "Go to page 3"),
        ("Step 1 of 3", "Step 2 of 3"),
        ("Continue to step 1 of 3", "Continue to step 2 of 3"),
        ("Remove item 1", "Remove item 2"),
        ("Remove item 1 from cart", "Remove item 2 from cart"),
        ("Rating 4.5", "Rating 4"),
        ("Shopping cart 2 items", "Shopping cart 2 lists"),
        ("Select size 10 wide", "Select size 11 wide"),
        ("Men's size 10 shoes", "Men's size 11 shoes"),
        ("Go to page 2 results", "Go to page 3 results"),
        ("Subscribe for 1 month", "Subscribe for 3 months"),
        ("Add 2 years protection", "Add 3 years protection"),
        ("Select 100 GB storage", "Select 200 GB storage"),
        ("Filter by last 7 days", "Filter by last 30 days"),
        ("Filter by 4 stars and up", "Filter by 3 stars and up"),
        ("Choose 2 packs", "Choose 4 packs"),
        ("13 in Green Velvet Lamp", "18 in Green Velvet Lamp"),
        ("Bath towel 2 pieces", "Bath towel 4 pieces"),
        ("Annual report (2024)", "Annual report (2025)"),
        ("Call us (555) 123-4567", "Call us (556) 123-4567"),
        ("Select size (10)", "Select size (11)"),
        ("Open tab 2 settings", "Open tab 3 settings"),
        ("Show 10 results per page", "Show 20 results per page"),
        ("Buy 2 items get one free", "Buy 3 items get one free"),
        ("Save with 2 photos plan", "Save with 4 photos plan"),
        ("Family plan 4 devices", "Family plan 6 devices"),
        ("Book 2 nights in Rome", "Book 3 nights in Rome"),
        ("Team plan 5 users", "Team plan 10 users"),
        ("Table for 2 people", "Table for 4 people"),
        ("Boeing 737 seats", "Boeing 747 seats"),
        ("Interstate 5 exits", "Interstate 8 exits"),
        ("Pay in 4 installments", "Pay in 12 installments"),
        ("Apartment 2 keys", "Apartment 3 keys"),
        ("Add 1 to cart", "Add 2 to cart"),
        ("10 results per page", "20 results per page"),
        ("Show 10 results", "Show 20 results"),
        ("Page (2) of results", "Page (3) of results"),
        ("Go to page (2)", "Go to page (3)"),
        ("Items per page (10)", "Items per page (20)"),
        ("Version 2 updates", "Version 3 updates"),
        ("Rated 4 (120)", "Rated 5 (120)"),
        ("Plan 2 new", "Plan 3 news"),
        ("10 items per page", "20 items per page"),
        ("25 reviews per page", "50 reviews per page"),
        ("Show 20 items", "Show 40 items"),
        ("Buy 2 items", "Buy 3 items"),
        ("Choose 2 items", "Choose 4 items"),
        ("View last 10 orders", "View last 30 orders"),
        ("Load next 10 comments", "Load next 20 comments"),
        ("Practice test 10 questions", "Practice test 20 questions"),
        ("Quick quiz (10 questions)", "Quick quiz (20 questions)"),
        ("Starter plan 1,000 emails", "Starter plan 5,000 emails"),
        ("Budget report (1).pdf", "Budget report (2).pdf"),
        ("Document copy (1)", "Document copy (2)"),
        ("1 item or more", "2 items or more"),
        ("Up to 100 emails", "Up to 500 emails"),
        ("Order 2 items", "Order 3 items"),
        ("Conference room (4)", "Conference room (8)"),
        ("Apartment unit (12)", "Apartment unit (14)"),
        ("Add 2 items", "Add 4 items"),
        ("3 reviews or fewer stars", "4 reviews or fewer stars"),
        ("Mark 2 messages as read", "Mark 3 messages as read"),
        ("Section 2 review", "Section 3 review"),
        ("Chapter 1 review", "Chapter 2 reviews"),
        ("Lesson 1 review questions", "Lesson 2 review questions"),
        ("Midterm 1 review", "Midterm 2 review"),
        ("Assignment 1 review", "Assignment 1 reviews"),
        // And the other sides of each shape.
        ("Wish list 2 items", "Wish list 2 item"),          // "2 item" is no count
        ("Wish list 1,23 items", "Wish list 1,24 items"),
        ("Budget (2 items).pdf", "Budget (3 items).pdf"),
        ("Notifications (3).", "Notifications (4)."),
        ("Support line (3) 555", "Support line (4) 555"),
        ("Yearly review (1900)", "Yearly review (1800)"),   // one is a year
        ("Yearly review (2099)", "Yearly review (2200)"),
        ("Open tabs (3)", "Open tabs (4)"),                 // nine characters of name
        ("Inbox tray (3)", "Inbox, tray (4)"),
        ("Notifications (3), 2 items", "Notifications (4), 3 items"),   // two counts changed
        ("2 items on sale now", "2 items in sale now"),
        ("12 questions in your quiz", "13 questions in your quiz"),
        ("Wish list 3 emails", "Wish list 4 emails"),
        ("Wish list 3 new items", "Wish list 4 unread items"),
        ("Wish list 3 new items", "Wish list 4 items"),
        ("Wish list 3 orders", "Wish list 4 orders"),
        ("Inbox (3)", "Inbox (4)"),                         // five characters of name
        ("2 items in", "3 items in"),
        ("Thread #12 comments (3)", "Thread #13 comments (4)"),
        ("(3) Notifications (#)", "(#) Notifications (4)"),   // a count each, in another place
        ("2 messages in #general", "3 messages in #random"),
    ]

    /// Two controls told apart only by such a number, and taken for one: accepted. Each needs the hint's own name to be
    /// gone from the page, and exactly one such control on it.
    nonisolated static let acceptedWrong = [
        ("iPhone 15 storage (128)", "iPhone 15 storage (256)"),
        ("Order details (1002)", "Order details (1003)"),
        ("Lecture notes (12)", "Lecture notes (13)"),
        ("Product bundle, 2 items", "Product bundle, 4 items"),
        ("Module 1 review", "Module 2 reviews"),
        ("Support ticket 1 update", "Support ticket 2 updates"),
    ]

    @Test(arguments: sameControl) func aChangedCountIsTheSameControl(_ a: String, _ b: String) {
        #expect(ChangingCounts.differOnly(a, b), "\(a) ~ \(b)")
        #expect(ChangingCounts.differOnly(b, a), "\(b) ~ \(a)")
    }

    @Test(arguments: leftMissing + otherControl) func anyOtherNumberIsNot(_ a: String, _ b: String) {
        #expect(!ChangingCounts.differOnly(a, b), "\(a) ~ \(b)")
        #expect(!ChangingCounts.differOnly(b, a), "\(b) ~ \(a)")
    }

    @Test(arguments: acceptedWrong) func theseAreTakenForOneAndAcceptedAsThat(_ a: String, _ b: String) {
        #expect(ChangingCounts.differOnly(a, b), "\(a) ~ \(b)")
    }

    /// What `alike` sets apart, and the same name, stay apart.
    @Test(arguments: [
        ("Sign in with Google", "Sign in with Apple"), ("Remove from cart", "Remove from list"), ("Delete message", "Delete messages"),
        ("Delete this item", "Delete this item now"), ("Write a review for lamp", "Write a review for chair"), ("Add to cart", "Add to cart - Bananas"),
        ("Notifications (3)", "Notifications (3)"), ("Notifications (3)", "NOTIFICATIONS  (3)"), ("Notifications (3)", "Notifications"),
    ])
    func namesWithoutAChangedCountAreNotMatched(_ a: String, _ b: String) {
        #expect(!ChangingCounts.differOnly(a, b) && !ChangingCounts.differOnly(b, a))
    }

    @Test func noNameIsNoMatch() {
        #expect(!ChangingCounts.differOnly(nil, "Notifications (3)") && !ChangingCounts.differOnly("Notifications (3)", nil))
        #expect(!ChangingCounts.differOnly("Notifications (99999999999999999999)", "Notifications (3)"))
    }

    /// Every noun and every label word, so none goes from a list unseen.
    @Test func theListsAreTheOnesRuled() {
        #expect(ChangingCounts.things == ["item", "notification", "message", "review", "comment", "alert", "request", "task", "update", "rating", "answer"])
        #expect(ChangingCounts.newThings == ChangingCounts.things.union(["question", "email", "order"]))
        for word in ChangingCounts.labelWords {
            #expect(!ChangingCounts.differOnly("Shopping \(word) (3)", "Shopping \(word) (4)"), "\(word)")
            #expect(!ChangingCounts.differOnly("Shopping \(word) 3 items", "Shopping \(word) 4 items"), "\(word)")
            #expect(!ChangingCounts.differOnly("Shopping (\(word): 3 items)", "Shopping (\(word): 4 items)"), "\(word)")
        }
        for one in ChangingCounts.newThings {
            #expect(ChangingCounts.differOnly("Everything, 1 unread \(one)", "Everything, 2 unread \(one)s"), "\(one)")
            #expect(ChangingCounts.differOnly("Everything, 1 \(one)", "Everything, 2 \(one)s") == ChangingCounts.things.contains(one), "\(one)")
        }
    }

    // MARK: on a page

    static let spot = CGRect(x: 600, y: 300, width: 200, height: 40)
    static func button(_ label: String?, _ frame: CGRect? = spot, role: String = "AXButton", visible: Bool = true, id: String? = nil) -> PageElement {
        var e = PageElement(kind: "thing", role: role, label: label, frame: frame, visible: visible, enabled: true, document: 0)
        e.domID = id
        return e
    }
    static let elsewhere = CGRect(x: 40, y: 20, width: 180, height: 30)
    static let away = CGRect(x: 600, y: 2_300, width: 200, height: 40)
    static func page(_ elements: [PageElement], kind: Bool = false) -> PageSnapshot { Lamp.page(kind ? Lamp.urlB : Lamp.urlA, elements) }

    /// A hint on a button of page A, for this page or for pages like it.
    static func hint(_ label: String, kind: Bool = false, role: String = "AXButton", id: String? = nil) -> StickyNote {
        var anchor = NoteStore.sceneAnchor(bundleID: "com.google.Chrome", windowTitle: "Walmart", url: Lamp.urlA)
        anchor.role = role
        anchor.label = label
        anchor.domID = id
        anchor.rect = [0.6, 0.375, 0.2, 0.05]
        if kind { anchor.pattern = PagePattern.of(anchor.page!).description }
        return StickyNote(id: "count", anchor: anchor, kind: "tip", text: "t", by: "x", at: "2026-11-16", confirmed: "2026-11-16")
    }

    static func recounted(_ note: StickyNote, on page: PageSnapshot) -> Bool {
        WandController.place([note], page: page, primaryMaxY: P.Pen.top).placed.first?.recounted == true
    }

    @Test(arguments: [("Notifications (3)", "Notifications (4)", false), ("Shopping cart 1 item", "Shopping cart 2 items", false),
                      ("Shopping cart 1 item", "Shopping cart 2 items", true)])
    func theHintIsOnItsControlWithTheNewCount(_ was: String, _ now: String, _ kind: Bool) {
        let note = Self.hint(was, kind: kind)
        #expect(V.landing(note, on: Self.page([Self.button(now, Self.elsewhere)], kind: kind)) == .on(Self.elsewhere))
        #expect(Self.recounted(note, on: Self.page([Self.button(now, Self.elsewhere)], kind: kind)))
        #expect(V.landing(note, on: Self.page([Self.button(now, Self.away, visible: false)], kind: kind)) == .below)
        #expect(V.landing(note, on: Self.page([Self.button(now, nil, visible: false)], kind: kind)) == .below)
    }

    /// A hint whose name has a "#" of its own, among controls named much like it.
    @Test(arguments: [("Thread #12 comments (3)", "Thread #12 comments (4)"), ("3 messages in #general", "1 message in #general"), ("#12: 3 unread messages", "#12: 1,204 unread messages")])
    func aNameWithANumberSignIsFoundToo(_ was: String, _ now: String) {
        let others = ["Thread #13 comments (4)", "Thread #12 comments", "Thread #12 comments (2024)", "4 messages in #random", "Messages in #general", "#13: 1 unread message", "#12: unread messages"]
        let page = Self.page(others.map { Self.button($0) } + [Self.button(now, Self.elsewhere)])
        #expect(V.landing(Self.hint(was), on: page) == .on(Self.elsewhere))
    }

    @Test func twoSuchControlsAreNone() {
        let note = Self.hint("Shopping cart 1 item")
        let one = Self.button("Shopping cart 2 items"), two = Self.button("Shopping cart 3 items", Self.elsewhere)
        #expect(V.landing(note, on: Self.page([one, two])) == .missing)
        // One of them scrolled away, or one by the same name twice, or one with no frame: still two.
        #expect(V.landing(note, on: Self.page([one, Self.button("Shopping cart 3 items", Self.away, visible: false)])) == .missing)
        #expect(V.landing(note, on: Self.page([one, Self.button("Shopping cart 2 items", Self.elsewhere)])) == .missing)
        #expect(V.landing(note, on: Self.page([one, Self.button("Shopping cart 3 items", nil)])) == .missing)
        // And when one of the two has an id that says it is another control.
        #expect(V.landing(Self.hint("Shopping cart 1 item", id: "cart"), on: Self.page([one, Self.button("Shopping cart 3 items", Self.elsewhere, id: "saved")])) == .missing)
        // Another role is not such a control.
        #expect(V.landing(note, on: Self.page([one, Self.button("Shopping cart 3 items", Self.elsewhere, role: "AXLink")])) == .on(Self.spot))
    }

    @Test func itIsOfTheHintsRole() {
        #expect(V.landing(Self.hint("Shopping cart 1 item"), on: Self.page([Self.button("Shopping cart 2 items", role: "AXLink")])) == .missing)
        // A hint an older pen kept on the words inside a button has their role, not the button's.
        #expect(V.landing(Self.hint("Shopping cart 1 item", role: "AXStaticText"), on: Self.page([Self.button("Shopping cart 2 items")])) == .missing)
    }

    /// Its own name, or its own id, anywhere on the page: the hint is where that says, or missing.
    @Test func itsOwnControlOnThePageRulesItOut() {
        let note = Self.hint("Shopping cart 1 item"), other = Self.button("Shopping cart 2 items", Self.elsewhere)
        #expect(V.landing(note, on: Self.page([Self.button("Shopping cart 1 item"), other])) == .on(Self.spot))
        #expect(V.landing(note, on: Self.page([Self.button("Shopping cart 1 item", Self.away, visible: false), other])) == .below)
        #expect(V.landing(note, on: Self.page([Self.button("Shopping cart 1 item", nil), other])) == .missing)
        let named = Self.hint("Shopping cart 1 item", id: "cart")
        #expect(V.landing(named, on: Self.page([Self.button("Cart", Self.away, visible: false, id: "cart"), other])) == .below)
        #expect(V.landing(named, on: Self.page([Self.button("Cart", role: "AXLink", id: "cart"), other])) == .missing)
    }

    /// A control with a steady id of its own that is not the hint's is another, as `belongs` has it.
    @Test func anotherSteadyIdIsAnotherControl() {
        let page = { (id: String?) in Self.page([Self.button("Shopping cart 2 items", id: id)]) }
        #expect(V.landing(Self.hint("Shopping cart 1 item", id: "cart"), on: page("saved")) == .missing)
        #expect(V.landing(Self.hint("Shopping cart 1 item", id: "cart"), on: page(nil)) == .on(Self.spot))
        #expect(V.landing(Self.hint("Shopping cart 1 item"), on: page("saved")) == .on(Self.spot))
        // Ids made up as the page loads say nothing, on either.
        #expect(V.landing(Self.hint("Shopping cart 1 item", id: "ember412"), on: page("saved")) == .on(Self.spot))
        #expect(V.landing(Self.hint("Shopping cart 1 item", id: "cart"), on: page("ember412")) == .on(Self.spot))
    }

    /// Part of a page can't show there is no other.
    @Test func aPartOfAPageIsNotEnough() {
        let note = Self.hint("Shopping cart 1 item")
        var cut = Self.page([Self.button("Shopping cart 2 items")]), early = cut
        cut.truncated = true
        early.loading = true
        #expect(V.landing(note, on: cut) == .missing && V.landing(note, on: early) == .missing)
        // Its own name needs no such thing.
        var own = Self.page([Self.button("Shopping cart 1 item")])
        own.truncated = true
        own.loading = true
        #expect(V.landing(note, on: own) == .on(Self.spot))
    }

    /// Numbers in the item's own name are the item's, for this page as for pages like it.
    @Test(arguments: [false, true]) func theItemsOwnNameHasNoCount(_ kind: Bool) {
        let url = "https://www.walmart.com/ip/Velvet-Chair-Covers-2-items/5395422942"
        var anchor = NoteStore.sceneAnchor(bundleID: "com.google.Chrome", windowTitle: "Walmart", url: url)
        anchor.role = "AXHeading"
        anchor.label = "Velvet Chair Covers 2 items"
        if kind { anchor.pattern = PagePattern.of(anchor.page!).description }
        let note = StickyNote(id: "n", anchor: anchor, kind: "tip", text: "t", by: "x", at: "2026-11-16", confirmed: "2026-11-16")
        let other = Self.button("Velvet Chair Covers 4 items", role: "AXHeading")
        let there = Lamp.page("https://www.walmart.com/ip/5395422943", [other])
        #expect(ChangingCounts.differOnly(anchor.label, other.label))
        #expect(!Self.recounted(note, on: there) && V.landing(note, on: there) == .missing)
    }

    /// Only a hint that would be missing is placed by its count: what was placed or further down before is there still.
    @Test func whatIsPlacedOrFurtherDownWithoutItStaysThere() {
        // Another item's name after a separator, for pages of a kind: the nearest of two, as before.
        let kind = Self.hint("Notifications (3)", kind: true)
        let two = Self.page([Self.button("Notifications (4)", Self.elsewhere), Self.button("Notifications (settings)")], kind: true)
        #expect(V.landing(kind, on: two) == .on(Self.spot) && !Self.recounted(kind, on: two))
        // That one scrolled away: further down.
        #expect(V.landing(kind, on: Self.page([Self.button("Notifications (settings)", Self.away, visible: false)], kind: true)) == .below)
        // A name that carries the item's comes before a changed count, in view or not.
        let cart = Self.hint("Shopping cart 1 item", kind: true), recounted = Self.button("Shopping cart 2 items", Self.elsewhere)
        #expect(V.landing(cart, on: Self.page([recounted, Self.button("Shopping cart 1 item - sale")], kind: true)) == .on(Self.spot))
        #expect(V.landing(cart, on: Self.page([recounted, Self.button("Shopping cart 1 item - sale", Self.away, visible: false)], kind: true)) == .below)
        // A page still loading, or cut short, has the alike names as before.
        var early = two
        early.loading = true
        #expect(V.landing(kind, on: early) == .on(Self.spot))
    }

    /// `alike`, `--find` and the pen's test of one control know nothing of counts.
    @Test func alikeAndFindAndBelongsAreAsTheyWere() {
        #expect(!NoteAnchor.alike("Shopping cart 1 item", "Shopping cart 2 items"))
        let page = Self.page([Self.button("Shopping cart 2 items")])
        #expect(HeadlessRead.find("Shopping cart 1 item", role: "AXButton", in: page).match == "none")
        #expect(!WandController.belongs(Self.hint("Shopping cart 1 item"), to: AXElementInfo(role: "AXButton", title: "Shopping cart 2 items")))
        // Another app's window is not read whole, so it has no such rule.
        let scan = AXScan.Result(windowFrame: nil, items: [AXScan.Item(role: "AXButton", label: "Shopping cart 2 items", frame: Self.spot)])
        #expect(!WandController.place([Self.hint("Shopping cart 2 items")], scan: scan).isEmpty)
        #expect(WandController.place([Self.hint("Shopping cart 1 item")], scan: scan).isEmpty)
    }

    // MARK: the pen

    /// The pen on page A with a hint on "Shopping cart 1 item", the page read (or not yet).
    static func pen(_ note: StickyNote, read page: PageSnapshot?) -> P.Pen {
        let pen = P.Pen(on: Lamp.urlA, reads: P.Reads(page))
        pen.controller.notesProvider = { _ in [note] }
        pen.controller.takeScene()
        if let page { pen.controller.take(WandController.place([note], page: page, primaryMaxY: P.Pen.top)) }
        return pen
    }

    static func target(_ element: PageElement, at frame: CGRect? = nil) -> WandTarget {
        let f = P.Pen.appKit(frame ?? element.frame!)
        let info = AXElementInfo(role: element.role, title: element.label, frame: f, domID: element.domID)
        return WandTarget(screenPoint: NSPoint(x: f.midX, y: f.midY), element: info, windowOwner: "Chrome", windowTitle: "Walmart",
                          ownerBundleID: "com.google.Chrome", windowFrame: P.Pen.appKit(Lamp.window))
    }

    static let now = button("Shopping cart 2 items")

    @Test func pointingAtTheControlShowsItsHint() {
        let pen = Self.pen(Self.hint("Shopping cart 1 item"), read: Self.page([Self.now]))
        #expect(pen.controller.notes(on: Self.target(Self.now)).map(\.id) == ["count"])
    }

    /// Right-click there changes the hint it has, in place, with the name the control has now.
    @Test func changingItThereKeepsItWithTheNewName() throws {
        let note = Self.hint("Shopping cart 1 item"), pen = Self.pen(note, read: Self.page([Self.now]))
        try pen.open(Self.now)
        let kept = try pen.keep("Ask first", scope: 0)
        #expect(kept.id == note.id && kept.text == "Ask first" && kept.anchor.label == "Shopping cart 2 items")
        #expect(pen.controller.sceneNotes.count == 1 && pen.controller.placed.map(\.note.id) == [note.id])
        #expect(V.landing(kept, on: Self.page([Self.now])) == .on(Self.spot) && !Self.recounted(kept, on: Self.page([Self.now])))
        // Again, now by its own name.
        #expect(pen.controller.ownNote(on: Self.target(Self.now))?.id == note.id)
    }

    /// Where a late reading puts a hint kept meanwhile is not taken, nor a hint removed meanwhile.
    @Test func aHintKeptWhileThePageWasReadStaysWhereItWasPut() throws {
        let note = Self.hint("Shopping cart 1 item"), pen = Self.pen(note, read: Self.page([Self.now]))
        try pen.open(Self.now)
        let kept = try pen.keep("Ask first", scope: 0)
        let late = WandController.place([note], page: Self.page([Self.button("Shopping cart 3 items", Self.elsewhere)]), primaryMaxY: P.Pen.top)
        #expect(late.placed.count == 1)
        pen.controller.take(late)
        #expect(pen.controller.placed.map(\.frame) == [P.Pen.appKit(Self.spot)] && pen.controller.placed.first?.note == kept)
        pen.controller.delete(note.id)
        pen.controller.take(late)
        #expect(pen.controller.placed.isEmpty)
    }

    /// Before the page's reading is back there is no telling it is the only one: a new hint. Accepted.
    @Test func beforeTheReadingItHasNoHintOfItsOwn() {
        let pen = Self.pen(Self.hint("Shopping cart 1 item"), read: nil)
        #expect(pen.controller.ownNote(on: Self.target(Self.now)) == nil)
    }

    /// Never by overlap: another role, another frame, another name at the same place, a hint placed some other way.
    @Test func onlyThatControlHasTheHintForItsOwn() {
        let note = Self.hint("Shopping cart 1 item"), c = Self.pen(note, read: Self.page([Self.now])).controller
        #expect(c.ownNote(on: Self.target(Self.now))?.id == note.id)
        #expect(c.ownNote(on: Self.target(Self.now, at: Self.spot.offsetBy(dx: 2, dy: -2)))?.id == note.id)
        #expect(c.ownNote(on: Self.target(Self.now, at: Self.spot.offsetBy(dx: 3, dy: 0))) == nil)
        #expect(c.ownNote(on: Self.target(Self.now, at: Self.spot.offsetBy(dx: 0, dy: 3))) == nil)
        // One side of it alone out of place.
        let f = Self.spot
        for other in [CGRect(x: f.minX - 3, y: f.minY, width: f.width + 3, height: f.height), CGRect(x: f.minX, y: f.minY, width: f.width + 3, height: f.height),
                      CGRect(x: f.minX, y: f.minY - 3, width: f.width, height: f.height + 3), CGRect(x: f.minX, y: f.minY, width: f.width, height: f.height + 3)] {
            #expect(c.ownNote(on: Self.target(Self.now, at: other)) == nil, "\(other)")
        }
        #expect(c.ownNote(on: Self.target(Self.button("Shopping cart 2 items", role: "AXLink"))) == nil)
        #expect(c.ownNote(on: Self.target(Self.button("Saved for later"))) == nil)
        // Its count changed again since the reading: still the same control.
        #expect(c.ownNote(on: Self.target(Self.button("Shopping cart 5 items")))?.id == note.id)
        // A hint for this very control, by its own name, comes first.
        var own = Self.hint("Shopping cart 2 items")
        own.id = "own"
        let both = P.Pen(on: Lamp.urlA, reads: P.Reads(nil))
        both.controller.notesProvider = { _ in [note, own] }
        both.controller.takeScene()
        both.controller.take(WandController.place([note, own], page: Self.page([Self.now]), primaryMaxY: P.Pen.top))
        #expect(both.controller.placed.count == 2 && both.controller.ownNote(on: Self.target(Self.now))?.id == "own")
        // Placed there, but not by the count rule.
        let plain = Self.pen(note, read: nil).controller
        plain.take(([WandController.PlacedNote(note: note, frame: P.Pen.appKit(Self.spot))], [], []))
        #expect(plain.ownNote(on: Self.target(Self.now)) == nil)
    }

    /// With the steady id of another control, it is another control.
    @Test func aSteadyIdOfAnotherControlIsNotTheHints() {
        let note = Self.hint("Shopping cart 1 item", id: "cart"), c = Self.pen(note, read: Self.page([Self.now])).controller
        #expect(c.ownNote(on: Self.target(Self.now))?.id == note.id)
        #expect(c.ownNote(on: Self.target(Self.button("Shopping cart 2 items", id: "saved"))) == nil)
    }
}
