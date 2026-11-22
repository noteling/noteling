import AppKit
import Foundation
import Testing
@testable import Familiar

/// R03, the pen's half: a hint written on one lamp's page, from the control picked through the paper to the note
/// kept, then met on the other lamp's page. The page read while the paper is open is a fixture; nothing reads a real
/// app or shows the pen. `ItemNameHintTests` has the placement rules with notes made by hand.
@Suite @MainActor
struct PenSavePathTests {
    typealias Lamp = ItemNameHintTests

    /// The browser's page as the paper reads it: what it answers, how often it was asked, and a gate to hold it.
    final class Reads: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        private var answered = 0
        private let page: PageSnapshot?
        private let gate: DispatchSemaphore?

        init(_ page: PageSnapshot?, held: Bool = false) {
            self.page = page
            gate = held ? DispatchSemaphore(value: 0) : nil
        }

        func read(_ bundle: String) -> PageSnapshot? {
            lock.withLock { asked.append(bundle) }
            gate?.wait()
            lock.withLock { answered += 1 }
            return page
        }

        func release() { gate?.signal() }
        var bundles: [String] { lock.withLock { asked } }
        var answers: Int { lock.withLock { answered } }
    }

    struct TimedOut: Error {}

    /// Waits for a condition, not for a time: the bound is only there so a broken test ends.
    static func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(30)
        while !condition() {
            guard Date() < end else { throw TimedOut() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Time for something that should not happen to show itself: too short only lets a broken pen pass, never fails a
    /// good one.
    static func settle() async throws { try await Task.sleep(for: .milliseconds(100)) }

    /// The pen over a lamp's page, with no panel up.
    @MainActor final class Pen {
        static let top = NSScreen.screens.first?.frame.maxY ?? 0
        let controller = WandController()
        let view: WandView
        private(set) var kept: StickyNote?

        init(on url: String?, reads: Reads) {
            view = WandView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 800), controller: controller, screen: NSScreen.main ?? NSScreen.screens[0])
            controller.sceneProvider = {
                ScreenContext(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: "Walmart", url: url, focused: nil, timestamp: Date())
            }
            controller.readPage = { reads.read($0) }
            controller.onNoteSave = { [weak self] in self?.kept = $0 }
            controller.takeScene()
        }

        static func appKit(_ f: CGRect) -> NSRect { NSRect(x: f.minX, y: top - f.maxY, width: f.width, height: f.height) }

        /// Right-click on a control of the page, as `openEditor(at:)` does with what is under the pen.
        func open(_ element: PageElement) throws {
            let frame = try #require(element.frame), text = element.role == "AXStaticText"
            let info = AXElementInfo(role: element.role, title: text ? nil : element.label, value: text ? element.label : nil,
                                     frame: Self.appKit(frame), domID: element.domID)
            let target = WandTarget(screenPoint: NSPoint(x: info.frame!.midX, y: info.frame!.midY), element: info, windowOwner: "Chrome",
                                    windowTitle: "Walmart", ownerBundleID: "com.google.Chrome", windowFrame: Self.appKit(ItemNameHintTests.window))
            let anchor = try #require(controller.anchor(for: target))
            view.present(anchor: anchor, at: info.frame!, existing: controller.ownNote(on: target))
        }

        /// Return on the paper, with its words and where the hint is met: 0 this page, 1 pages like this, 2 the site;
        /// nil leaves the menu as it opened.
        @discardableResult
        func keep(_ text: String = "Check the shade size", scope: Int? = nil) throws -> StickyNote {
            let paper = try #require(view.openPaper)
            paper.textView.string = text
            if let scope { paper.selectScope(at: scope) }
            paper.commit()
            #expect(view.openPaper == nil)
            // As the pack's file has it.
            return try JSONDecoder().decode(StickyNote.self, from: JSONEncoder().encode(#require(kept)))
        }

        func pageRead() async throws { try await PenSavePathTests.wait { view.pageForPaper != nil } }
    }

    static func element(_ role: String, _ label: String?, _ frame: CGRect, id: String? = nil) -> PageElement {
        var e = PageElement(kind: "thing", role: role, label: label, frame: frame, visible: true, enabled: true, document: 0)
        e.domID = id
        return e
    }

    // Page A: the title, the price and the button under it.
    static let titleA = element("AXHeading", Lamp.titleA, CGRect(x: 500, y: 160, width: 400, height: 40))
    static let priceA = element("AXStaticText", "$24.97", CGRect(x: 500, y: 250, width: 80, height: 30))
    static let cartA = element("AXButton", "Add to cart", CGRect(x: 500, y: 400, width: 200, height: 44))
    static let pageA = Lamp.page(Lamp.urlA, [titleA, priceA, cartA])
    /// What the pen should record for A's title: "Add to cart", and where the title is from it.
    static let nearA = NoteNear(role: "AXButton", label: "Add to cart", dx: 0, dy: -240, width: 400, height: 40)

    // Page B, everything 100 points lower than on A.
    static let titleB = element("AXHeading", Lamp.titleB, CGRect(x: 500, y: 260, width: 400, height: 40))
    static let priceB = element("AXStaticText", "$31.50", CGRect(x: 500, y: 350, width: 80, height: 30))
    static let cartB = element("AXButton", "Add to cart", CGRect(x: 500, y: 500, width: 200, height: 44))
    static let pageB = Lamp.page(Lamp.urlB, [titleB, priceB, cartB])
    /// B with its name in a second heading, just where A's title was: the spot and the name alone would pick this
    /// one; the neighbour picks the title.
    static let pageBTwice = Lamp.page(Lamp.urlB, [element("AXHeading", Lamp.titleB, CGRect(x: 500, y: 165, width: 400, height: 40)), titleB, priceB, cartB])

    /// Where a note lands on a page, in the page's coordinates, and whether that is only a guess; nil when missing.
    static func landing(_ note: StickyNote, on page: PageSnapshot) -> (frame: CGRect, predicted: Bool)? {
        let result = WandController.place([note], page: page, primaryMaxY: Pen.top)
        return result.placed.first.map { (CGRect(x: $0.frame.minX, y: Pen.top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height), $0.predicted) }
    }

    private func lands(_ note: StickyNote, on page: PageSnapshot, at element: PageElement) -> Bool {
        guard let there = Self.landing(note, on: page) else { return false }
        return there.frame == element.frame && !there.predicted
    }

    private func metOn(_ note: StickyNote, _ url: String) -> Bool {
        note.anchor.matchesScene(ScreenContext(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: "Walmart", url: url, focused: nil, timestamp: Date()))
    }

    // MARK: 1, the page read in time

    @Test func theTitleIsKeptBesideTheButtonAndMetOnTheOtherLampsTitle() async throws {
        let reads = Reads(Self.pageA), pen = Pen(on: Lamp.urlA, reads: reads)
        try pen.open(Self.titleA)
        #expect(pen.view.openPaper?.chosenScope == .pages("/ip/*/*"))   // what the paper offers first
        try await pen.pageRead()
        let note = try pen.keep(scope: 1)
        #expect(reads.bundles == ["com.google.Chrome"])
        #expect(note.anchor.role == "AXHeading" && note.anchor.label == Lamp.titleA && note.anchor.domID == nil)
        #expect(note.anchor.pattern == "www.walmart.com/ip/*/*" && note.anchor.rect == [0.5, 0.2, 0.4, 0.05])
        #expect(note.anchor.near == Self.nearA)
        #expect(metOn(note, Lamp.urlA) && metOn(note, Lamp.urlB))
        #expect(lands(note, on: Self.pageA, at: Self.titleA))
        #expect(lands(note, on: Self.pageB, at: Self.titleB))
        // By the neighbour the pen recorded: without it the same note goes on the heading where A's title was.
        #expect(lands(note, on: Self.pageBTwice, at: Self.titleB))
        var without = note
        without.anchor.near = nil
        #expect(lands(without, on: Self.pageBTwice, at: Self.pageBTwice.elements[0]))
    }

    // MARK: 2, kept before the read ends

    @Test func keptBeforeThePageIsReadItHasNoNeighbourAndIsMetByTheItemsName() async throws {
        let reads = Reads(Self.pageA, held: true), pen = Pen(on: Lamp.urlA, reads: reads)
        defer { reads.release() }
        try pen.open(Self.titleA)
        try await Self.wait { reads.bundles.count == 1 }
        #expect(pen.view.pageForPaper == nil)
        let note = try pen.keep()
        #expect(note.anchor.pattern == "www.walmart.com/ip/*/*" && note.anchor.near == nil)
        #expect(lands(note, on: Self.pageB, at: Self.titleB))
        // The read ending afterwards changes nothing.
        reads.release()
        try await Self.wait { reads.answers == 1 }
        try await Self.settle()
        #expect(pen.view.pageForPaper == nil && pen.kept?.anchor.near == nil)
    }

    @Test func aPageThatCannotBeReadLeavesNoNeighbour() async throws {
        let reads = Reads(nil), pen = Pen(on: Lamp.urlA, reads: reads)
        try pen.open(Self.titleA)
        try await Self.wait { reads.answers == 1 }
        try await Self.settle()
        let note = try pen.keep()
        #expect(note.anchor.near == nil && lands(note, on: Self.pageB, at: Self.titleB))
    }

    /// The read of a paper since closed does not stand for the page read for the one open now.
    @Test func aReadEndingLateIsNotTheNextPapers() async throws {
        let old = Lamp.page(Lamp.urlA, [Self.element("AXButton", "Add to registry", Self.cartA.frame!)])
        let late = Reads(old, held: true), reads = Reads(Self.pageA), pen = Pen(on: Lamp.urlA, reads: late)
        defer { late.release() }
        try pen.open(Self.titleA)
        try await Self.wait { late.bundles.count == 1 }
        pen.controller.readPage = { reads.read($0) }
        try pen.open(Self.titleA)
        try await pen.pageRead()
        late.release()
        try await Self.wait { late.answers == 1 }
        try await Self.settle()
        #expect(try pen.keep().anchor.near == Self.nearA)
    }

    /// Each paper has its own read: one kept early does not use the page read for the paper before it.
    @Test func aPaperKeptEarlyDoesNotUseThePageReadForTheOneBefore() async throws {
        let reads = Reads(Self.pageA), later = Reads(Self.pageA, held: true), pen = Pen(on: Lamp.urlA, reads: reads)
        defer { later.release() }
        try pen.open(Self.priceA)
        try await pen.pageRead()
        try pen.keep()
        pen.controller.readPage = { later.read($0) }
        try pen.open(Self.titleA)
        #expect(try pen.keep().anchor.near == nil)
    }

    // MARK: 3, the title's own id

    @Test func aTitleWithASteadyIDIsMetByItAndNeedsNoNeighbour() async throws {
        let named = Self.element("AXHeading", Lamp.titleA, Self.titleA.frame!, id: "main-title")
        let reads = Reads(Self.pageA), pen = Pen(on: Lamp.urlA, reads: reads)
        try pen.open(named)
        try await Self.settle()
        let note = try pen.keep()
        #expect(note.anchor.domID == "main-title" && note.anchor.near == nil && reads.bundles.isEmpty)
        // By the id where B has it, among two headings with B's name; by B's name where it does not.
        let byID = Self.element("AXHeading", Lamp.titleB, Self.titleB.frame!, id: "main-title")
        let twice = Lamp.page(Lamp.urlB, [Self.pageBTwice.elements[0], byID, Self.cartB])
        #expect(lands(note, on: twice, at: byID))
        #expect(lands(note, on: Self.pageB, at: Self.titleB))
    }

    @Test func aTitleWithAGeneratedIDIsKeptBesideTheButton() async throws {
        let generated = Self.element("AXHeading", Lamp.titleA, Self.titleA.frame!, id: "ember412")
        let reads = Reads(Self.pageA), pen = Pen(on: Lamp.urlA, reads: reads)
        try pen.open(generated)
        try await pen.pageRead()
        let note = try pen.keep()
        #expect(note.anchor.domID == nil && note.anchor.near == Self.nearA)
        #expect(lands(note, on: Self.pageBTwice, at: Self.titleB))
    }

    // MARK: 4, controls that are not the item's name

    @Test func aNamedButtonIsKeptByItsNameAndThePageIsNotRead() async throws {
        let reads = Reads(Self.pageA), pen = Pen(on: Lamp.urlA, reads: reads)
        try pen.open(Self.cartA)
        #expect(pen.view.openPaper?.chosenScope == .pages("/ip/*/*"))
        try await Self.settle()
        let note = try pen.keep("Adds one")
        #expect(note.anchor.label == "Add to cart" && note.anchor.near == nil && reads.bundles.isEmpty)
        #expect(lands(note, on: Self.pageB, at: Self.cartB))
        // No such button (out of stock): left out, not put where it was.
        #expect(Self.landing(note, on: Lamp.page(Lamp.urlB, [Self.titleB, Self.priceB])) == nil)
    }

    @Test func aPriceHasNoNameAndIsKeptBesideTheButton() async throws {
        let reads = Reads(Self.pageA), pen = Pen(on: Lamp.urlA, reads: reads)
        try pen.open(Self.priceA)
        try await pen.pageRead()
        let note = try pen.keep("Per lamp")
        #expect(note.anchor.label == nil && note.anchor.role == "AXStaticText")
        #expect(note.anchor.near == NoteNear(role: "AXButton", label: "Add to cart", dx: 0, dy: -150, width: 80, height: 30))
        #expect(lands(note, on: Self.pageB, at: Self.priceB))
    }

    /// The neighbour is for pages of a kind: the title of this page only is found here by its name.
    @Test func aTitleKeptForThisPageOnlyHasNoNeighbour() async throws {
        let reads = Reads(Self.pageA), pen = Pen(on: Lamp.urlA, reads: reads)
        try pen.open(Self.titleA)
        try await pen.pageRead()
        let note = try pen.keep(scope: 0)
        #expect(note.anchor.scope == .page && note.anchor.near == nil)
        #expect(metOn(note, Lamp.urlA) && !metOn(note, Lamp.urlB))
        #expect(lands(note, on: Self.pageA, at: Self.titleA))
        #expect(Self.landing(note, on: Self.pageB) == nil)
    }

    /// A hint for the whole site has no page for a neighbour to be on.
    @Test func aPriceKeptForTheSiteHasNoNeighbour() async throws {
        let reads = Reads(Self.pageA), pen = Pen(on: Lamp.urlA, reads: reads)
        try pen.open(Self.priceA)
        try await pen.pageRead()
        let note = try pen.keep(scope: 2)
        #expect(note.anchor.scope == .site && note.anchor.page == nil && note.anchor.near == nil)
    }

    /// An unnamed control in an app's window: no page to read, and none to be beside a control on.
    @Test func anUnnamedControlInAnAppReadsNoPage() async throws {
        let reads = Reads(Self.pageA), pen = Pen(on: nil, reads: reads)
        try pen.open(Self.element("AXGroup", nil, Self.priceA.frame!))
        try await Self.settle()
        let note = try pen.keep()
        #expect(note.anchor.page == nil && note.anchor.near == nil && note.anchor.rect != nil && reads.bundles.isEmpty)
    }

    // MARK: 5, a hint changed

    @Test func changingAHintKeepsItsNeighbour() async throws {
        let reads = Reads(Self.pageA), pen = Pen(on: Lamp.urlA, reads: reads)
        try pen.open(Self.titleA)
        try await pen.pageRead()
        let first = try pen.keep()
        // The title sits elsewhere now; the hint it has is the one changed, with the neighbour it had, unread.
        let moved = Self.element("AXHeading", Lamp.titleA, CGRect(x: 480, y: 190, width: 420, height: 40))
        try pen.open(moved)
        try await Self.settle()
        let changed = try pen.keep("Check the shade and the base")
        #expect(changed.id == first.id && changed.text == "Check the shade and the base")
        #expect(changed.anchor.near == Self.nearA && changed.anchor.pattern == first.anchor.pattern)
        #expect(reads.bundles.count == 1)
        #expect(lands(changed, on: Self.pageBTwice, at: Self.titleB))
    }

    @Test func changingAHintThatHasNoNeighbourRecordsOne() async throws {
        let early = Pen(on: Lamp.urlA, reads: Reads(nil))
        try early.open(Self.titleA)
        let first = try early.keep()
        #expect(first.anchor.near == nil)
        let reads = Reads(Self.pageA), pen = Pen(on: Lamp.urlA, reads: reads)
        pen.controller.notesProvider = { _ in [first] }
        pen.controller.takeScene()
        try pen.open(Self.titleA)
        try await pen.pageRead()
        let changed = try pen.keep("Check the shade and the base")
        #expect(changed.id == first.id && changed.anchor.near == Self.nearA)
    }
}
