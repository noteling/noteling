import AppKit
import Foundation
import Testing
@testable import Familiar

/// R04 slice 1: `--read-page --json` and `--find`, as a program reads them. Made-up pages, so no browser is needed.
@Suite @MainActor
struct HeadlessReadTests {
    static let window = CGRect(x: 0, y: 0, width: 1_000, height: 800)

    static func page(_ url: String, _ elements: [PageElement], loading: Bool = false) -> PageSnapshot {
        var page = PageSnapshot(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: "Shop",
                                documents: [PageDocument(url: url, frame: window)],
                                elements: elements, selectedText: nil, windowFrame: window, truncated: false, elapsed: 0.012)
        page.loading = loading
        return page
    }

    static func element(_ role: String, _ label: String, _ frame: CGRect, kind: String = "button", visible: Bool = true,
                        enabled: Bool = true) -> PageElement {
        PageElement(kind: kind, role: role, label: label, frame: frame, visible: visible, enabled: enabled, document: 0)
    }

    /// The page reader's own made-up page, with its password field holding "hunter2".
    static func readersPage() throws -> PageSnapshot {
        let read = try #require(PageWalk.read(window: PageReaderTests.window(), viewport: PageReaderTests.viewport))
        return PageSnapshot(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: "Sign in", documents: read.documents,
                            elements: read.elements, selectedText: nil, windowFrame: PageReaderTests.viewport,
                            truncated: read.truncated, elapsed: 0.02)
    }

    // MARK: - Privacy

    @Test func byDefaultItSaysNoWordFromThePage() throws {
        let page = try Self.readersPage()
        let out = HeadlessRead.json(HeadlessRead.report(page, trusted: true))
        #expect(!out.contains("hunter2"))
        for label in page.elements.compactMap(\.label) where label.count > 3 {
            #expect(!out.contains(label), "\(label)")
        }
        #expect(!out.contains("\"text\":\""))   // no page text field (the kind "text" is a count)
        let report = try JSONDecoder().decode(HeadlessRead.Report.self, from: Data(out.utf8))
        #expect(report.ok && report.exit == 0)
        #expect(report.page?.elements == page.elements.count)
        #expect(report.page?.kinds["password field"] == 1)
    }

    @Test func fullTextStillHidesThePassword() throws {
        let out = HeadlessRead.json(HeadlessRead.report(try Self.readersPage(), trusted: true, full: true))
        #expect(out.contains("\"text\":\""))
        #expect(!out.contains("hunter2"))
    }

    @Test func containsCountsWithoutSaying() throws {
        let page = Self.page("https://shop.example/ip/milk/1", [
            Self.element("AXButton", "Add to cart", CGRect(x: 10, y: 10, width: 100, height: 30)),
            Self.element("AXStaticText", "Ships to your cart tomorrow", CGRect(x: 10, y: 50, width: 300, height: 20), kind: "text"),
            Self.element("AXLink", "Help", CGRect(x: 10, y: 90, width: 40, height: 20), kind: "link"),
        ])
        let report = HeadlessRead.report(page, trusted: true, contains: "CART")
        #expect(report.page?.contains == 2)
        #expect(!HeadlessRead.json(report).contains("tomorrow"))
        #expect(HeadlessRead.report(page, trusted: true).page?.contains == nil)
    }

    // MARK: - Exit codes

    @Test func exitCodesSayWhatWentWrong() {
        let page = Self.page("https://shop.example/a", [Self.element("AXButton", "Save", CGRect(x: 1, y: 1, width: 10, height: 10))])
        #expect(HeadlessRead.report(nil, trusted: false).exit == 4)
        #expect(HeadlessRead.report(page, trusted: false).exit == 4)
        #expect(HeadlessRead.report(nil, trusted: true).exit == 3)
        #expect(HeadlessRead.report(page, trusted: true).exit == 0)
        #expect(HeadlessRead.report(page, trusted: true, find: "Save").exit == 0)
        #expect(HeadlessRead.report(page, trusted: true, find: "Delete").exit == 1)
        let loading = Self.page("https://shop.example/a", page.elements, loading: true)
        #expect(HeadlessRead.report(loading, trusted: true).exit == 5)
        #expect(HeadlessRead.report(loading, trusted: true, find: "Delete").exit == 5)
        #expect(HeadlessRead.report(loading, trusted: true, find: "Save").exit == 0)
    }

    @Test func aFlagWithoutItsValueIsAUsageMistake() {
        #expect(HeadlessRead.value(after: "--find", in: ["x", "--find"]) == .some(nil))
        #expect(HeadlessRead.value(after: "--find", in: ["x", "--find", "--role", "AXButton"]) == .some(nil))
        #expect(HeadlessRead.value(after: "--find", in: ["x", "--find", "Save"]) == .some("Save"))
        #expect(HeadlessRead.value(after: "--find", in: ["x"]) == .none)
    }

    // MARK: - --find agrees with where a hint goes

    static let cart = CGRect(x: 500, y: 400, width: 200, height: 44)

    static func hint(on label: String, role: String = "AXButton") -> StickyNote {
        var anchor = NoteStore.sceneAnchor(bundleID: "com.google.Chrome", windowTitle: "Shop", url: "https://shop.example/ip/milk/1")
        anchor.role = role
        anchor.label = label
        anchor.rect = [0.5, 0.5, 0.2, 0.05]
        return StickyNote(id: "n", anchor: anchor, kind: "tip", text: "t", by: "David", at: "2026-11-16", confirmed: "2026-11-16")
    }

    /// `--find` and `WandController.place` give the same answer: found where the hint goes, missing where it is left out.
    /// But for a name whose count has changed ("Shopping cart 1 item", now "2 items"): a hint is on it when the page has
    /// no other, and `--find`, which looks for the name asked for, says there is none.
    @Test func findAgreesWithPlace() {
        let pages = [
            Self.page("https://shop.example/ip/milk/1", [Self.element("AXButton", "Add to cart", Self.cart)]),
            Self.page("https://shop.example/ip/bananas/2", [Self.element("AXButton", "Add to cart – Bananas", Self.cart)]),
            Self.page("https://shop.example/ip/gone/3", [Self.element("AXButton", "Add to list", Self.cart)]),
            Self.page("https://shop.example/ip/link/4", [Self.element("AXLink", "Add to cart", Self.cart, kind: "link")]),
        ]
        let expected = ["exact", "alike", "none", "none"]
        // "alike" is the same control on another page of the kind, so the hint is one for pages of the kind.
        var hint = Self.hint(on: "Add to cart")
        hint.anchor.pattern = hint.anchor.page.map { PagePattern.of($0).description }
        #expect(hint.anchor.pattern != nil)
        for (page, match) in zip(pages, expected) {
            let found = HeadlessRead.find("Add to cart", role: "AXButton", in: page)
            let placed = WandController.place([hint], page: page, primaryMaxY: 800).placed
            #expect(found.match == match, "\(page.url ?? "")")
            #expect((found.count > 0) == !placed.isEmpty, "\(page.url ?? "")")
            if let hit = found.hits.first, let note = placed.first {
                #expect(hit.frame == [500, 400, 200, 44])
                #expect(note.frame.minX == 500 && note.frame.width == 200)
            }
        }
    }

    @Test func findDoesNotFollowAChangedCountAsAHintDoes() {
        let page = Self.page("https://shop.example/ip/milk/1", [Self.element("AXButton", "Shopping cart 2 items", Self.cart)])
        #expect(WandController.place([Self.hint(on: "Shopping cart 1 item")], page: page, primaryMaxY: 800).placed.count == 1)
        let found = HeadlessRead.find("Shopping cart 1 item", role: "AXButton", in: page)
        #expect(found.match == "none" && found.count == 0)
    }

    @Test func exactWinsOverAlikeAndAnyRoleWithoutRole() {
        let page = Self.page("https://shop.example/ip/milk/1", [
            Self.element("AXButton", "Add to cart – Milk", CGRect(x: 0, y: 0, width: 10, height: 10)),
            Self.element("AXButton", "Add to cart", Self.cart, enabled: false),
            Self.element("AXLink", "add  to CART", CGRect(x: 0, y: 50, width: 10, height: 10), kind: "link"),
        ])
        let withRole = HeadlessRead.find("Add to cart", role: "AXButton", in: page)
        #expect(withRole.match == "exact" && withRole.unique && withRole.hits[0].enabled == false)
        let anyRole = HeadlessRead.find("Add to cart", role: nil, in: page)
        #expect(anyRole.match == "exact" && anyRole.count == 2 && !anyRole.unique)
        #expect(HeadlessRead.find("Checkout", role: nil, in: page).match == "none")
    }

    // MARK: - The browser is always let go

    /// A stand-in browser that counts what it was told.
    final class Told { var holds = 0, nudges = 0, reads = 0, settles = 0, waits = 0 }

    static func browser(_ told: Told, trusted: Bool = true, app: Bool = true, fresh: Bool = true,
                        pages: [PageSnapshot?]) -> HeadlessRead.Browser {
        HeadlessRead.Browser(
            trusted: { trusted },
            app: { _ in app ? NSRunningApplication.current : nil },
            hold: { _ in told.holds += 1; return fresh },
            nudge: { _ in told.nudges += 1 },
            read: { _ in told.reads += 1; return pages[min(told.reads - 1, pages.count - 1)] },
            settle: { told.settles += 1 },
            wait: { _ in told.waits += 1 })
    }

    static let shop = page("https://shop.example/p/1", [element("AXButton", "Add to cart", CGRect(x: 10, y: 10, width: 80, height: 30))])
    static let empty = page("https://shop.example/p/1", [])
    static let loading = page("https://shop.example/p/1", [element("AXButton", "Menu", CGRect(x: 0, y: 0, width: 10, height: 10))], loading: true)

    @Test(arguments: [
        (["--read-page", "--json", "--contains"], true, true, [shop] as [PageSnapshot?], HeadlessRead.Exit.usage),
        (["--read-page", "--json"], false, true, [shop], .noPermission),
        (["--read-page", "--json"], true, false, [shop], .noWindow),
        (["--read-page", "--json"], true, true, [nil], .noWindow),
        (["--find", "Checkout"], true, true, [shop], .notFound),
        (["--find", "Checkout"], true, true, [loading], .partial),
        (["--read-page", "--json"], true, true, [loading], .partial),
        (["--find", "Add to cart"], true, true, [shop], .ok),
        (["--read-page", "--json"], true, true, [shop], .ok),
        (["--read-page", "--json", "--app", "com.apple.TextEdit"], true, true, [shop], .usage),
        (["--find", "Add to cart", "--app", "com.apple.finder"], true, true, [shop], .usage),
        (["--read-page", "--json", "--app", "com.google.Chrome"], true, true, [shop], .ok),
    ])
    func everyWayOutLetsTheBrowserGo(args: [String], trusted: Bool, app: Bool, pages: [PageSnapshot?],
                                     exit: HeadlessRead.Exit) {
        let told = Told()
        var out: [String] = []
        let code = HeadlessRead.run(args, browser: Self.browser(told, trusted: trusted, app: app, pages: pages)) { out.append($0) }
        #expect(code == exit.rawValue)
        #expect(told.settles == 1, "settled \(told.settles) times for exit \(code)")
        #expect(out.count == 1)
    }

    /// `--app` names the browser read through the shared seam; without it the one nearest the front is read.
    @Test func theNamedBrowserIsTheOneRead() {
        var asked: [String?] = []
        var browser = Self.browser(Told(), pages: [Self.shop])
        browser.app = { asked.append($0); return NSRunningApplication.current }
        _ = HeadlessRead.run(["--read-page", "--json", "--app", "com.google.Chrome"], browser: browser) { _ in }
        _ = HeadlessRead.run(["--read-page", "--json"], browser: browser) { _ in }
        #expect(asked == ["com.google.Chrome", nil])
    }

    @Test func itHoldsTheBrowserBeforeReading() {
        let told = Told()
        let browser = HeadlessRead.Browser(
            trusted: { true }, app: { _ in NSRunningApplication.current },
            hold: { _ in told.holds += 1; return true }, nudge: { _ in },
            read: { _ in #expect(told.holds == 1, "read before hold"); told.reads += 1; return Self.shop },
            settle: { told.settles += 1 }, wait: { _ in })
        #expect(HeadlessRead.run(["--find", "Add to cart"], browser: browser) { _ in } == 0)
        #expect(told.reads == 1 && told.settles == 1)
    }

    @Test func aBrowserHeldJustNowGetsTimeToBuildItsPage() {
        let told = Told()
        let code = HeadlessRead.run(["--find", "Add to cart"], browser: Self.browser(told, pages: [Self.empty, Self.empty, Self.shop])) { _ in }
        #expect(code == 0)
        #expect(told.reads == 3 && told.nudges == 2 && told.waits == 2)
        #expect(told.settles == 1)
    }

    @Test func aBrowserAlreadyOnIsReadOnce() {
        let told = Told()
        let code = HeadlessRead.run(["--find", "Add to cart"], browser: Self.browser(told, fresh: false, pages: [Self.empty, Self.shop])) { _ in }
        #expect(code == HeadlessRead.Exit.notFound.rawValue)
        #expect(told.reads == 1 && told.waits == 0 && told.settles == 1)
    }

    @Test func anEmptyPageIsGivenUpOnInTime() {
        let told = Told()
        _ = HeadlessRead.run(["--read-page", "--json"], browser: Self.browser(told, pages: [Self.empty])) { _ in }
        #expect(told.reads == 1 + ReadPageCommand.buildTries && told.waits == ReadPageCommand.buildTries)
        #expect(told.settles == 1)
    }
}
