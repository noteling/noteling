import AppKit
import ApplicationServices

/// What `--read-page --json` and `--find` tell a program reading the front browser page: one JSON object, and an exit
/// code it can act on. By default only counts and the control asked for: an agent's run never copies what a page says
/// unless `--full` asks for it.
enum HeadlessRead {
    /// 0 read or found, 1 not found, 2 a usage mistake, 3 no browser window with a page, 4 Accessibility not granted,
    /// 5 read only in part (the page still loading, or the walk stopped at its budget).
    enum Exit: Int32 { case ok = 0, notFound = 1, usage = 2, noWindow = 3, noPermission = 4, partial = 5 }

    /// The counts `--read-page` has always printed, as fields.
    struct Counts: Codable, Equatable {
        var app: String
        var bundle: String
        var site: String
        var documents: Int
        var tabs: Int
        var sheetOpen: Bool
        var kinds: [String: Int]
        var withPageID: Int
        var elements: Int
        var onScreen: Int
        var loading: Bool
        var truncated: Bool
        var ms: Int
        /// How many things on the page have the `--contains` words in their name or value; nil without `--contains`.
        var contains: Int?
    }

    /// A control `--find` met: its role, its name and its state. Nothing around it.
    struct Hit: Codable, Equatable {
        var role: String
        var kind: String
        var label: String?
        var visible: Bool
        var enabled: Bool
        var frame: [Double]?
    }

    /// The page as the hint rules see a control's name: the same name ("exact"), the same control on another page of
    /// the kind ("alike", as `NoteAnchor.alike`), or none. Exact wins over alike, as in `WandController.place`.
    /// An alike hit's `label` is the control's own name on this page, so it can carry words beyond the name asked
    /// ("Add to cart – Bananas" for "Add to cart"): page words, even without `--full`.
    struct Found: Codable, Equatable {
        var name: String
        var role: String?
        var match: String          // "exact" | "alike" | "none"
        var count: Int
        var unique: Bool
        var hits: [Hit]
    }

    struct Report: Codable, Equatable {
        var ok: Bool
        var exit: Int32
        var error: String?
        var page: Counts?
        var find: Found?
        /// The page's text, only with `--full`.
        var text: String?
    }

    static func counts(_ page: PageSnapshot, contains: String? = nil) -> Counts {
        let words = NoteAnchor.norm(contains)
        return Counts(app: page.appName, bundle: page.bundleID, site: ReadPageCommand.site(page), documents: page.documents.count,
                      tabs: page.tabs.count, sheetOpen: page.sheet != nil,
                      kinds: Dictionary(grouping: page.elements, by: \.kind).mapValues(\.count),
                      withPageID: page.elements.filter { $0.domID != nil }.count,
                      elements: page.elements.count, onScreen: page.elements.filter(\.visible).count,
                      loading: page.loading, truncated: page.truncated, ms: Int(page.elapsed * 1_000),
                      contains: words.map { w in page.elements.filter {
                          (NoteAnchor.norm($0.label)?.contains(w) ?? false) || (NoteAnchor.norm($0.value)?.contains(w) ?? false)
                      }.count })
    }

    /// The control named `name` (and of `role`, when given) by the hint rules. With no role, any role will do.
    static func find(_ name: String, role: String?, in page: PageSnapshot) -> Found {
        let anchor = NoteAnchor(role: role, label: name)
        func roleOK(_ r: String) -> Bool { role == nil || anchor.roleAgrees(r) }
        let want = NoteAnchor.norm(name)
        let exact = page.elements.filter { roleOK($0.role) && want != nil && NoteAnchor.norm($0.label) == want }
        let alike = exact.isEmpty ? page.elements.filter { roleOK($0.role) && NoteAnchor.alike(name, $0.label) } : []
        let hits = (exact.isEmpty ? alike : exact).map { e in
            Hit(role: e.role, kind: e.kind, label: e.label, visible: e.visible, enabled: e.enabled,
                frame: e.frame.map { [$0.minX, $0.minY, $0.width, $0.height].map(Double.init) })
        }
        return Found(name: name, role: role, match: !exact.isEmpty ? "exact" : !alike.isEmpty ? "alike" : "none",
                     count: hits.count, unique: hits.count == 1, hits: hits)
    }

    /// The report for a page read (or not), and the exit code a caller acts on.
    static func report(_ page: PageSnapshot?, trusted: Bool, full: Bool = false, contains: String? = nil,
                       find name: String? = nil, role: String? = nil) -> Report {
        guard trusted else {
            return Report(ok: false, exit: Exit.noPermission.rawValue,
                          error: "Accessibility permission isn't granted to the app running this.")
        }
        guard let page else {
            return Report(ok: false, exit: Exit.noWindow.rawValue, error: "No browser window with a page was found.")
        }
        var report = Report(ok: true, exit: Exit.ok.rawValue, page: counts(page, contains: contains))
        if full { report.text = page.text(limit: 60_000) }
        if let name {
            let found = find(name, role: role, in: page)
            report.find = found
            if found.count == 0 { report.ok = false; report.exit = (page.loading || page.truncated ? Exit.partial : Exit.notFound).rawValue }
        } else if page.loading || page.truncated {
            report.exit = Exit.partial.rawValue
        }
        return report
    }

    static func json(_ report: Report) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(report)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"ok\":false,\"exit\":2}"
    }

    /// The value after `flag` in `args`, when there is one and it isn't itself a flag.
    static func value(after flag: String, in args: [String]) -> String?? {
        guard let i = args.firstIndex(of: flag) else { return .none }
        let next = args.index(after: i)
        guard next < args.endIndex, !args[next].hasPrefix("--") else { return .some(nil) }
        return .some(args[next])
    }

    /// The same seam as the human `--read-page`: hold before reading, retry a freshly held empty page, settle on exit.
    typealias Browser = ReadPageCommand.Browser

    /// `--read-page --json [--full] [--contains T] [--app BUNDLE]` and `--find NAME [--role R] [--app BUNDLE]`.
    /// Every way out settles the browser, so none is left in enhanced-UI mode after the process exits.
    static func run(_ args: [String], browser: Browser = .live, print say: (String) -> Void = { print($0) }) -> Int32 {
        defer { browser.settle() }
        let contains = value(after: "--contains", in: args), app = value(after: "--app", in: args)
        let find = value(after: "--find", in: args), role = value(after: "--role", in: args)
        for case .some(nil) in [contains, app, find, role] {
            say(json(Report(ok: false, exit: Exit.usage.rawValue, error: "A flag is missing its value.")))
            return Exit.usage.rawValue
        }
        // Only a browser's page is read: the page walker reads web areas, and a native window would come back as
        // "no browser window" with no word of why. Say so instead.
        if let bundle = app ?? nil, !ContextWatcher.browserBundles.contains(bundle) {
            say(json(Report(ok: false, exit: Exit.usage.rawValue,
                            error: "--app takes a browser's bundle id (\(ContextWatcher.browserBundles.sorted().joined(separator: ", "))); \(bundle) isn't one.")))
            return Exit.usage.rawValue
        }
        let trusted = browser.trusted()
        let page = trusted ? browser.app(app ?? nil).flatMap { ReadPageCommand.read($0, with: browser) } : nil
        let report = report(page, trusted: trusted, full: args.contains("--full"), contains: contains ?? nil,
                            find: find ?? nil, role: role ?? nil)
        say(json(report))
        return report.exit
    }
}
