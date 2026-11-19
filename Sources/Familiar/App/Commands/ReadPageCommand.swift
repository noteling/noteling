import AppKit
import Foundation

/// `--read-page [--full]`: what the page reader sees in the browser window nearest the front, said for a person.
/// Chrome, Edge and Brave build a page's accessibility tree only while an assistive app says it is listening, so the
/// browser is held on before reading (as `--find-step` does) and let go before the process exits; without that, a
/// Chromium page read from Terminal with no screen reader running came back empty.
enum ReadPageCommand {
    /// What `run` touches outside itself, so a test can stand in for the browser and count what it was told.
    struct Browser {
        /// Without Accessibility nothing can be read, so nothing is held or waited for.
        var trusted: () -> Bool
        var app: () -> NSRunningApplication?
        /// Says an assistive app is listening; true when this call newly holds the browser.
        var hold: (NSRunningApplication) -> Bool
        var nudge: (NSRunningApplication) -> Void
        var read: (NSRunningApplication) -> PageSnapshot?
        /// Takes back every hold at once: nothing is left running to do it later.
        var settle: () -> Void
        var wait: (TimeInterval) -> Void

        /// BrowserAccessibility is the main actor's; `run` runs off it, so the main run loop must be running.
        private static func onMain<T>(_ work: @MainActor () -> T) -> T {
            Thread.isMainThread ? MainActor.assumeIsolated(work) : DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
        }

        static let live = Browser(
            trusted: { Permissions.accessibilityGranted },
            app: { frontBrowser() },
            hold: { app in onMain { BrowserAccessibility.hold(app) } },
            nudge: { app in onMain { BrowserAccessibility.nudge(app) } },
            read: { PageReader.read($0) },
            settle: { onMain { BrowserAccessibility.settle() } },
            wait: { Thread.sleep(forTimeInterval: $0) })
    }

    /// The browser owning the on-screen window nearest the front, whatever app is frontmost (as `readFrontBrowser`).
    static func frontBrowser() -> NSRunningApplication? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows where (window[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, let app = NSRunningApplication(processIdentifier: pid),
                  let bundle = app.bundleIdentifier, ContextWatcher.browserBundles.contains(bundle) else { continue }
            return app
        }
        return nil
    }

    /// How long a browser held just now gets to build its page: `--find-step` looks for up to five seconds.
    static let buildTries = 6, buildPause: TimeInterval = 0.5

    /// The page in `app`, holding a Chromium browser's page tree on first. A browser held only now may still show an
    /// empty page for a moment; it is told again and read again meanwhile, as a tour step does.
    static func read(_ app: NSRunningApplication, with browser: Browser) -> PageSnapshot? {
        let fresh = browser.hold(app)
        var page = browser.read(app)
        guard fresh else { return page }
        for _ in 0..<buildTries where page?.elements.isEmpty != false {
            browser.wait(buildPause)
            browser.nudge(app)
            page = browser.read(app)
        }
        return page
    }

    /// What `--read-page` prints for `page`. By default only counts, so a check run by anyone, or by an agent, never
    /// copies what a page says or which company's site it is; `--full` prints the page.
    static func lines(_ page: PageSnapshot?, full: Bool) -> [String] {
        guard let page else {
            return ["No browser window with a page was found, or Accessibility permission isn't granted to the app running this."]
        }
        var out: [String] = []
        if full {
            out.append(page.text(limit: 60_000))
        } else {
            let kinds = Dictionary(grouping: page.elements, by: \.kind).mapValues(\.count).sorted { $0.key < $1.key }
            let host = page.key?.host ?? ""
            let site = host.isEmpty ? "none" : host.hasPrefix("127.0.0.1") || host.hasPrefix("localhost") ? "local"
                : host.contains("service-now") || page.key?.path.hasSuffix(".do") == true ? "servicenow" : "other"
            out.append("\(page.appName): \(page.documents.count) document(s), \(page.tabs.count) tab(s), site: \(site)"
                       + (page.sheet != nil ? ", a sheet is open" : ""))
            out.append(kinds.map { "\($0.key) \($0.value)" }.joined(separator: " · "))
            out.append("with the page's own id: \(page.elements.filter { $0.domID != nil }.count)")
        }
        let visible = page.elements.filter(\.visible).count
        out.append("\(page.elements.count) things read (\(visible) on screen) in \(Int(page.elapsed * 1_000)) ms"
                   + (page.truncated ? ", stopped at the budget" : ""))
        return out
    }

    /// Reads and prints; always exits 0, as it always has. Every way out lets the browser go.
    static func run(_ args: [String], browser: Browser = .live, print say: (String) -> Void = { print($0) }) -> Int32 {
        defer { browser.settle() }
        let page = !browser.trusted() ? nil : browser.app().flatMap { read($0, with: browser) }
        lines(page, full: args.contains("--full")).forEach(say)
        return 0
    }
}
