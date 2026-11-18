import AppKit
import Foundation
import Testing
@testable import Familiar

/// `--read-page` for a person: holds a Chromium browser's page tree on before reading, as `--find-step` does, and
/// lets it go on every way out. What it prints is unchanged. A stand-in browser counts what it was told.
@Suite @MainActor
struct ReadPageCommandTests {
    static let window = CGRect(x: 0, y: 0, width: 1_000, height: 800)

    static func page(_ url: String, _ elements: [PageElement]) -> PageSnapshot {
        PageSnapshot(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: "Shop",
                     documents: [PageDocument(url: url, frame: window)],
                     elements: elements, selectedText: nil, windowFrame: window, truncated: false, elapsed: 0.012)
    }

    static let shop = page("https://shop.example/ip/milk/1", [
        PageElement(kind: "button", role: "AXButton", label: "Add to cart", frame: CGRect(x: 10, y: 10, width: 100, height: 30),
                    visible: true, enabled: true, document: 0),
        PageElement(kind: "link", role: "AXLink", label: "Help", frame: CGRect(x: 10, y: 900, width: 40, height: 20),
                    visible: false, enabled: true, document: 0),
    ])
    static let empty = page("https://shop.example/ip/milk/1", [])

    final class Told { var order: [String] = [], holds = 0, nudges = 0, reads = 0, settles = 0, waits = 0 }

    /// A browser that answers `pages` in turn (the last one again once they run out).
    static func browser(_ told: Told, trusted: Bool = true, app: Bool = true, fresh: Bool = true,
                        pages: [PageSnapshot?]) -> ReadPageCommand.Browser {
        ReadPageCommand.Browser(
            trusted: { trusted },
            app: { app ? NSRunningApplication.current : nil },
            hold: { _ in told.holds += 1; told.order.append("hold"); return fresh },
            nudge: { _ in told.nudges += 1 },
            read: { _ in
                told.reads += 1; told.order.append("read")
                return pages[min(told.reads - 1, pages.count - 1)]
            },
            settle: { told.settles += 1; told.order.append("settle") },
            wait: { _ in told.waits += 1 })
    }

    @Test func itHoldsTheBrowserBeforeReadingAndLetsItGoAfter() {
        let told = Told()
        var said: [String] = []
        let code = ReadPageCommand.run(["--read-page"], browser: Self.browser(told, pages: [Self.shop]), print: { said.append($0) })
        #expect(code == 0)
        #expect(told.order == ["hold", "read", "settle"])
        #expect(said.last?.hasPrefix("2 things read (1 on screen)") == true)
    }

    @Test func aBrowserHeldJustNowGetsTimeToBuildItsPage() {
        let told = Told()
        var said: [String] = []
        _ = ReadPageCommand.run(["--read-page"], browser: Self.browser(told, pages: [Self.empty, Self.empty, Self.shop]),
                                print: { said.append($0) })
        #expect(told.reads == 3 && told.nudges == 2 && told.waits == 2 && told.settles == 1)
        #expect(said.last?.hasPrefix("2 things read") == true)
    }

    @Test func itStopsWaitingAfterFindStepsFewSeconds() {
        let told = Told()
        _ = ReadPageCommand.run(["--read-page"], browser: Self.browser(told, pages: [Self.empty]), print: { _ in })
        #expect(told.reads == 1 + ReadPageCommand.buildTries && told.settles == 1)
        #expect(Double(told.waits) * ReadPageCommand.buildPause <= 5)
    }

    @Test func aBrowserAlreadyOnIsReadOnce() {
        let told = Told()
        _ = ReadPageCommand.run(["--read-page"], browser: Self.browser(told, fresh: false, pages: [Self.empty]), print: { _ in })
        #expect(told.reads == 1 && told.waits == 0 && told.settles == 1)
    }

    @Test(arguments: [(false, true), (true, false)])
    func withNothingToReadItHoldsNothingAndStillSettles(trusted: Bool, app: Bool) {
        let told = Told()
        var said: [String] = []
        let code = ReadPageCommand.run(["--read-page"], browser: Self.browser(told, trusted: trusted, app: app, pages: [Self.shop]),
                                       print: { said.append($0) })
        #expect(code == 0)
        #expect(told.holds == 0 && told.reads == 0 && told.waits == 0 && told.settles == 1)
        #expect(said == ["No browser window with a page was found, or Accessibility permission isn't granted to the app running this."])
    }

    /// The person's output is what 0.10.4 printed: counts only by default.
    @Test func byDefaultItPrintsCountsAsBefore() {
        #expect(ReadPageCommand.lines(Self.shop, full: false) == [
            "Chrome: 1 document(s), 0 tab(s), site: other",
            "button 1 · link 1",
            "with the page's own id: 0",
            "2 things read (1 on screen) in 12 ms",
        ])
    }

    @Test func fullPrintsThePageThenTheCount() {
        let out = ReadPageCommand.lines(Self.shop, full: true)
        #expect(out.count == 2)
        #expect(out.first == Self.shop.text(limit: 60_000))
        #expect(out.last == "2 things read (1 on screen) in 12 ms")
    }
}
