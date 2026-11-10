import AppKit
import ApplicationServices
import Foundation

/// Where a note is stuck. A scene (a page, by its key; or, in notes from before page keys, a site's host and path; or
/// an app's bundle id and window) plus a control on it (the page's own id for it, then its Accessibility role and the
/// label shown on screen). Spots without a label, and circled regions, keep a rectangle relative to the window instead.
struct NoteAnchor: Codable, Equatable {
    var host: String? = nil       // "127.0.0.1:4310" for a site (lowercase, with the port when there is one)
    var path: String? = nil       // URL path; nil or "/" means any page on the host
    var page: PageKey? = nil      // the page, as PageKey names it: when set, the note is on this page only
    var domID: String? = nil      // the page's own id for the control, found again before its role and label
    var bundle: String? = nil     // bundle id for a native app
    var window: String? = nil     // a window-title fragment for a native app (nil for browsers: page titles change)
    var role: String? = nil       // "AXButton"
    var label: String? = nil      // the control's title / description / placeholder as shown
    var rect: [Double]? = nil     // x, y, w, h as fractions of the window frame, top-left origin
    /// Pages like the one it was left on, as `PagePattern` text ("www.walmart.com/ip/*/*"): the hint is met on every
    /// page of the kind. Without it, a note with a page is on that page only.
    var pattern: String? = nil
    /// For a control with no name of its own: a named control near it, and where it sits from that one.
    var near: NoteNear? = nil
    /// The page's class names for the control, the steady ones, to tell it from its neighbours on the next page.
    var classes: [String]? = nil

    var isRegion: Bool { label == nil && rect != nil }

    /// Where a hint on a page is met: this page, pages like it, or the whole site. Nil for a window in an app.
    var scope: HintScope? {
        if let pattern { return .pages(PagePattern(pattern, host: host)?.pathAndQuery ?? pattern) }
        if page != nil { return .page }
        if host != nil { return path == nil || path == "/" ? .site : .page }
        return nil
    }

    /// `button “Save page” on 127.0.0.1:4310`, or `a spot in “Untitled” (com.apple.TextEdit)`.
    var summary: String {
        let place = pattern ?? page?.description ?? host.map { $0 + (path.map { $0 == "/" ? "" : $0 } ?? "") } ?? window.map { "“\($0)”" } ?? bundle ?? "?"
        if let label { return "\(Self.roleWord(role)) “\(label)” on \(place)" }
        return "a circled spot on \(place)"
    }

    /// The control alone: `button “Save page”`, or `a circled spot`.
    var controlSummary: String {
        if let label { return "\(Self.roleWord(role)) “\(label)”" }
        return "a circled spot"
    }

    /// A context that stands for the scene, so pack match rules can be applied to it.
    var sceneContext: ScreenContext {
        ScreenContext(appName: "", bundleID: bundle ?? "", windowTitle: window ?? "",
                      url: host.map { "http://\($0)\(path ?? "/")" }, focused: nil, timestamp: Date())
    }

    static func roleWord(_ role: String?) -> String {
        guard let role, !role.isEmpty else { return "control" }
        return role.replacingOccurrences(of: "AX", with: "")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).lowercased()
    }

    /// Lowercased, whitespace collapsed; nil when empty.
    static func norm(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        return t.isEmpty ? nil : t
    }

    static func hostKey(_ url: String?) -> String? {
        guard let url, let c = URLComponents(string: url), let h = c.host?.lowercased(), !h.isEmpty else { return nil }
        return c.port.map { "\(h):\($0)" } ?? h
    }

    static func pathKey(_ url: String?) -> String {
        guard let url, let c = URLComponents(string: url) else { return "/" }
        return c.path.isEmpty ? "/" : c.path
    }

    func matchesScene(_ ctx: ScreenContext) -> Bool { matchesScene(ctx, page: ctx.url.flatMap(PageKey.of)) }

    /// On this scene: a note for pages of a kind is on every page of the kind; one with a page key is on that page
    /// only, so a site that serves every page from one path no longer shows every page's notes everywhere.
    func matchesScene(_ ctx: ScreenContext, page current: PageKey?) -> Bool {
        if let pattern, let kind = PagePattern(pattern, host: host) { return current.map(kind.matches) ?? false }
        if let page { return page == current }
        if let host {
            guard Self.hostKey(ctx.url) == host.lowercased() else { return false }
            if let path, !path.isEmpty, path != "/" { return Self.pathKey(ctx.url) == path }
            return true
        }
        if let bundle {
            guard ctx.bundleID == bundle else { return false }
            if let w = Self.norm(window) { return Self.norm(ctx.windowTitle)?.contains(w) ?? false }
            return true
        }
        return false
    }

    /// An id a page generates as it loads (ember412, :r5:, ext-gen12, mat-input-3, ui-id-4, long hex), which can name
    /// another control on the next load, so a note is never stuck by one.
    static func isSteadyID(_ id: String?) -> Bool { GeneratedID.isSteady(id) }

    func matchesElement(role r: String?, label l: String?) -> Bool {
        guard let label, roleAgrees(r), let want = Self.norm(label), let have = Self.norm(l) else { return false }
        return want == have
    }

    /// The same control on another page of the kind, where its name carries the item's own ("Add to cart - Great
    /// Value Milk" there, "Add to cart - Bananas" here): the same role, and the names share their first words.
    func isLikeElement(role r: String?, label l: String?) -> Bool {
        guard let label, roleAgrees(r) else { return false }
        return Self.alike(label, l)
    }

    /// The control's role is the hint's; or the hint was kept by an older pen on the words inside a control (the
    /// text's role with the control's name), and the control is of a kind whose words are its name, which is how the
    /// page reader lists such a control, never its text.
    func roleAgrees(_ r: String?) -> Bool {
        guard let role, let r else { return false }
        return role == r || (role == "AXStaticText" && PageWalk.atomic.contains(r))
    }

    /// Two names of one control across pages: equal, or sharing at least ten characters of whole words at the start.
    static func alike(_ a: String?, _ b: String?) -> Bool {
        guard let a = norm(a), let b = norm(b) else { return false }
        if a == b { return true }
        let shared = String(zip(a, b).prefix { $0 == $1 }.map(\.0))
        if shared.count == min(a.count, b.count) { return shared.count >= 10 }   // one is the other's start
        // Back to the last whole word, so "save changes" and "save draft" share only "save".
        let words = shared.split(separator: " ", omittingEmptySubsequences: false).dropLast().joined(separator: " ")
        return words.count >= 10
    }

    /// The rect anchor as a screen rect inside `windowFrame` (AppKit coordinates).
    func screenRect(in windowFrame: NSRect) -> NSRect? {
        guard let r = rect, r.count == 4, windowFrame.width > 0, windowFrame.height > 0 else { return nil }
        let w = windowFrame.width * r[2], h = windowFrame.height * r[3]
        let x = windowFrame.minX + windowFrame.width * r[0]
        let top = windowFrame.maxY - windowFrame.height * r[1]
        return NSRect(x: x, y: top - h, width: w, height: h)
    }

    /// Where the control was in the window, as a rectangle in this window, in Accessibility's top-left coordinates
    /// (the page reader's): the place of a hint with no name to go by; and of several controls by one name, or
    /// several named neighbours, the hint's is the one nearest it.
    func spot(in window: CGRect?) -> CGRect? {
        guard let window, let r = rect, r.count == 4 else { return nil }
        return CGRect(x: window.minX + window.width * r[0], y: window.minY + window.height * r[1],
                      width: window.width * r[2], height: window.height * r[3])
    }

    static func fractions(of rect: NSRect, in windowFrame: NSRect) -> [Double] {
        guard windowFrame.width > 0, windowFrame.height > 0 else { return [0, 0, 0, 0] }
        let x = (rect.minX - windowFrame.minX) / windowFrame.width
        let top = (windowFrame.maxY - rect.maxY) / windowFrame.height
        return [x, top, rect.width / windowFrame.width, rect.height / windowFrame.height]
            .map { (Double(min(max($0, 0), 1)) * 10000).rounded() / 10000 }
    }
}

/// A script from the tools folder that tests what a note claims, run as the person who reads the note: the note
/// "you need role Y" with a script that reads your roles. Its fixed arguments go to the script as they are.
struct NoteCheck: Codable, Equatable {
    var script: String                    // the tool id, "pack__script"
    var args: [String: String]? = nil
}

/// A named control near one that has no name of its own (a price block), and where the unnamed one sits from it: how
/// a hint on the block finds it on the next page of the kind, where the block's place in the window differs but its
/// place beside "Add to cart" does not. Offsets and sizes are points, in Accessibility's top-left coordinates.
struct NoteNear: Codable, Equatable {
    var role: String
    var label: String
    var dx: Double
    var dy: Double
    var width: Double
    var height: Double

    /// Where the control is, from where the named one is now.
    func rect(from named: CGRect) -> CGRect { CGRect(x: named.minX + dx, y: named.minY + dy, width: width, height: height) }

    /// Named controls whose name is steady across pages of a kind: short, no number, no price; buttons, links and
    /// fields first, headings and text (which may be the item's own name) only when nothing else is near.
    static func tier(of element: PageElement) -> Int? {
        guard let label = element.label?.trimmingCharacters(in: .whitespacesAndNewlines), label.count <= 40, PageWalk.isAName(label) else { return nil }
        switch element.role {
        case "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXTab", "AXTextField", "AXComboBox": return 1
        case "AXHeading", "AXStaticText": return 2
        default: return nil
        }
    }

    /// The best named neighbour of a control on the page, in the control's document, within reach: by the gap
    /// between them, controls within 320 points before text within 200.
    static func of(control: CGRect, in page: PageSnapshot, reach: (CGFloat, CGFloat) = (320, 200)) -> NoteNear? {
        var best: (PageElement, CGRect, Int, CGFloat)?
        for element in page.elements {
            guard let tier = tier(of: element), let frame = element.frame, frame.width > 0, frame.height > 0, frame != control else { continue }
            let gap = Self.gap(control, frame)
            guard gap <= (tier == 1 ? reach.0 : reach.1) else { continue }
            if let b = best, (b.2, b.3) <= (tier, gap) { continue }
            best = (element, frame, tier, gap)
        }
        guard let (element, frame, _, _) = best, let label = element.label else { return nil }
        return NoteNear(role: element.role, label: String(label.prefix(80)), dx: control.minX - frame.minX, dy: control.minY - frame.minY,
                        width: control.width, height: control.height)
    }

    /// The distance between two rectangles' edges; zero when they touch or overlap.
    static func gap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = max(0, max(a.minX, b.minX) - min(a.maxX, b.maxX)), dy = max(0, max(a.minY, b.minY) - min(a.maxY, b.maxY))
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Where a hint on a page is met, as the paper offers it.
enum HintScope: Equatable {
    /// This page only, by its key.
    case page
    /// Pages like this: a `PagePattern`'s part after the host, as the paper shows it ("/ip/*/*").
    case pages(String)
    /// Every page of the site.
    case site
}

/// One sticky note, kept one file each in the notes store (once in a pack's `notes.json`).
struct StickyNote: Codable, Identifiable, Equatable {
    var id: String
    var anchor: NoteAnchor
    var kind: String          // "tip" | "warning"
    var text: String
    var by: String
    var at: String            // yyyy-MM-dd
    var confirmed: String     // yyyy-MM-dd, last time someone said it still holds
    var check: NoteCheck? = nil

    var isWarning: Bool { kind == "warning" }
    var byline: String { "\(by) · \(confirmed)" }

    /// No one has said it still holds for this long: it may be out of date, and says so.
    static let oldAfterDays = 90

    /// Whole days since someone last said it holds, or nil when the date can't be read.
    func daysSinceConfirmed(at now: Date = Date()) -> Int? {
        guard let date = NoteStore.day.date(from: confirmed) else { return nil }
        return max(0, Calendar(identifier: .gregorian).dateComponents([.day], from: date, to: now).day ?? 0)
    }

    func isOld(at now: Date = Date()) -> Bool { (daysSinceConfirmed(at: now) ?? 0) > Self.oldAfterDays }

    /// "confirmed today", "confirmed 3 days ago", "confirmed 2 wk ago", "confirmed 8 mo ago".
    func confirmedWords(at now: Date = Date()) -> String {
        guard let days = daysSinceConfirmed(at: now) else { return "confirmed \(confirmed)" }
        switch days {
        case 0: return "confirmed today"
        case 1: return "confirmed yesterday"
        case ..<14: return "confirmed \(days) days ago"
        case ..<60: return "confirmed \(days / 7) wk ago"
        case ..<730: return "confirmed \(days / 30) mo ago"
        default: return "confirmed \(days / 365) yr ago"
        }
    }

    /// How the pad and the model see who said it: "PEOPLE SAY · Ana · confirmed 3 days ago", and, when old,
    /// "· no one since in 8 months".
    func peopleSay(at now: Date = Date()) -> String {
        "PEOPLE SAY · \(by) · \(confirmedWords(at: now))" + (isOld(at: now) ? " · may be out of date" : "")
    }
}

/// What the pen hands over when a note is written: enough to build a `StickyNote`, and the frame to stick it at.
struct NoteDraft {
    var existingID: String?
    var anchor: NoteAnchor
    var kind: String
    var text: String
    var frame: NSRect          // where the sticker goes on screen, AppKit global coordinates
    var check: NoteCheck? = nil
}

/// `notes.json` in a pack folder: `{"notes": [...]}`.
enum NoteStore {
    static let fileName = "notes.json"
    private struct File: Codable { var notes: [StickyNote] }
    static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()

    /// The pack's notes, or an error when the file is there but can't be read, so nothing treats it as empty.
    static func read(packDir: URL) throws -> [StickyNote] {
        try JSONDecoder().decode(File.self, from: Data(contentsOf: packDir.appendingPathComponent(fileName))).notes
    }

    static func load(packDir: URL) -> [StickyNote] {
        let url = packDir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return [] }
        do { return try JSONDecoder().decode(File.self, from: data).notes }
        catch { Log.info("notes: cannot read \(url.path): \(error.localizedDescription)"); return [] }
    }

    static func save(_ notes: [StickyNote], packDir: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(File(notes: notes)).write(to: packDir.appendingPathComponent(fileName), options: .atomic)
    }

    static func author(_ config: Config) -> String {
        let n = config.noteAuthor.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        let full = NSFullUserName().trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? NSUserName() : full
    }

    static func make(_ d: NoteDraft, by: String, date: Date = Date()) -> StickyNote {
        let when = day.string(from: date)
        return StickyNote(id: d.existingID ?? UUID().uuidString.lowercased(), anchor: d.anchor,
                          kind: d.kind == "warning" ? "warning" : "tip",
                          text: d.text.trimmingCharacters(in: .whitespacesAndNewlines), by: by, at: when, confirmed: when, check: d.check)
    }

    /// The scene half of an anchor: host and path for a page in a browser, bundle and window for anything else.
    static func sceneAnchor(bundleID: String?, windowTitle: String?, url: String?) -> NoteAnchor {
        var a = NoteAnchor()
        if let b = bundleID, ContextWatcher.browserBundles.contains(b), let host = NoteAnchor.hostKey(url) {
            a.host = host
            a.path = NoteAnchor.pathKey(url)
            a.page = url.flatMap(PageKey.of)
        } else {
            a.bundle = bundleID
            let t = windowTitle?.trimmingCharacters(in: .whitespaces) ?? ""
            a.window = t.isEmpty ? nil : String(t.prefix(80))
        }
        return a
    }

    /// Folder name for a scene that has no pack yet: the host or the app's name, as a slug.
    static func packSlug(for anchor: NoteAnchor, appName: String?) -> String {
        let base = anchor.host ?? appName ?? anchor.bundle?.split(separator: ".").last.map(String.init) ?? "notes"
        let s = PackWriter.slug(base)
        return s.isEmpty ? "notes" : s
    }

    /// Creates a minimal pack (a SKILL.md with a match rule) so the note has a home, in `dirName` when given, else
    /// in a folder named for the scene. Returns the pack folder.
    @discardableResult
    static func ensurePack(for anchor: NoteAnchor, appName: String?, root: URL, dirName: String? = nil) throws -> URL {
        let dir = root.appendingPathComponent(dirName ?? packSlug(for: anchor, appName: appName))
        let skill = dir.appendingPathComponent("SKILL.md")
        guard !FileManager.default.fileExists(atPath: skill.path) else { return dir }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = (anchor.host ?? appName ?? dir.lastPathComponent).replacingOccurrences(of: "\n", with: " ")
        var s = "---\nname: \(name)\ndescription: Notes left with the pen.\nmatch:\n"
        if let host = anchor.host { s += "  urls: [\(host)]\n" }
        if let bundle = anchor.bundle { s += "  bundles: [\(bundle)]\n" }
        s += "---\nNotes left by people who use this. See notes.json; each note is stuck to a control by its role and label.\n"
        try s.write(to: skill, atomically: true, encoding: .utf8)
        Log.info("notes: created pack \(dir.lastPathComponent) for \(anchor.summary)")
        return dir
    }
}

/// A walk of the frontmost app's focused window: labelled controls with their frames, for placing stickers and for
/// naming what sits inside a circled region.
enum AXScan {
    struct Item {
        let role: String
        let label: String?
        let frame: NSRect      // AppKit global coordinates
        var summary: String { label.map { "\(NoteAnchor.roleWord(role)) “\($0.prefix(60))”" } ?? NoteAnchor.roleWord(role) }
    }
    struct Result {
        var bundleID: String?
        var windowFrame: NSRect?
        var items: [Item] = []
    }

    static let structural: Set<String> = ["AXGroup", "AXUnknown", "AXSplitGroup", "AXScrollArea", "AXLayoutArea", "AXWebArea", "AXList", "AXTable", "AXOutline"]

    static func frontmostWindow(maxNodes: Int = 2500) -> Result {
        var out = Result()
        guard Permissions.accessibilityGranted,
              let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return out }
        out.bundleID = app.bundleIdentifier
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 1)
        guard let win = AX.element(axApp, kAXFocusedWindowAttribute) ?? AX.element(axApp, kAXMainWindowAttribute) else { return out }
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        out.windowFrame = ScreenHitTester.axFrame(of: win, primaryMaxY: primaryMaxY)
        var stack: [AXUIElement] = [win]
        var visited = 0
        while let el = stack.popLast(), visited < maxNodes {
            visited += 1
            let role = AX.string(el, kAXRoleAttribute) ?? "AXUnknown"
            if !structural.contains(role), let frame = ScreenHitTester.axFrame(of: el, primaryMaxY: primaryMaxY), frame.width > 0, frame.height > 0 {
                // Plain text goes by its own words, when they can be a name, as the page reader lists it.
                let label = role == "AXStaticText" ? PageWalk.nameOfText(AX.string(el, kAXValueAttribute))
                    : [AX.string(el, kAXTitleAttribute), AX.string(el, kAXDescriptionAttribute), AX.string(el, kAXPlaceholderValueAttribute)]
                        .compactMap { $0 }.first { !$0.isEmpty }
                out.items.append(Item(role: role, label: label, frame: frame))
            }
            for k in AX.children(el).reversed() { stack.append(k) }
        }
        return out
    }
}
