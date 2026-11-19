import AppKit
import ApplicationServices
import CryptoKit
import Foundation

/// `--click NAME [--role R] [--app BUNDLE] --json --token T --prepare` and
/// `--click NAME ... --json --token T --fire --expect PAGE,HIT [--named-approval NAME] [--require-front]`:
/// one named control on the front browser page, pressed at most once, for a program that has already had a person
/// approve it (Synthetics' screen_click). `--prepare` presses nothing; `--fire` presses through Accessibility only
/// (AXPress: no coordinates clicked, no activation, no cursor move).
///
/// Only an exact name counts (never the hint rules' "alike"), and only when exactly one control has it, on screen and
/// enabled. No page words leave: the report carries the asked name, counts, the site's host, and two opaque tokens
/// (HMAC-SHA256 under the caller's per-request key T) that `--fire` compares, so a different page or a replaced
/// control is refused without the caller ever learning the page's address or the control's page id.
enum HeadlessClick {
    /// HeadlessRead.Exit 0-5, plus: 6 the page or the control changed since `--prepare` (or the token was already
    /// used), 7 the irreversible-action guard refused, 8 the name isn't exactly one visible, enabled control,
    /// 9 the browser isn't the frontmost app and `--require-front` was given.
    enum Exit: Int32 { case pageChanged = 6, guardRefused = 7, notUniqueOrNotExact = 8, notFront = 9 }

    struct Report: Codable, Equatable {
        var ok: Bool
        var exit: Int32
        var error: String?
        var reason: String?
        var page: HeadlessRead.Counts?
        var find: HeadlessRead.Found?
        /// The site's host only (never a path or query), so the person approving knows which site is meant.
        var host: String?
        /// "safe", "confirm" or "forbidden", by IrreversibleGuard.
        var `guard`: String?
        var page_token: String?
        var hit_token: String?
        var pressed: Bool?
        var changed: Bool?
    }

    // MARK: - Tokens

    static func isToken(_ s: String?) -> Bool {
        guard let s, s.count == 64 else { return false }
        return s.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    private static func bytes(_ hex: String) -> Data {
        var out = Data()
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            out.append(UInt8(hex[i..<j], radix: 16) ?? 0)
            i = j
        }
        return out
    }

    static func mac(_ key: String, _ text: String) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: bytes(key)))
        return code.map { String(format: "%02x", $0) }.joined()
    }

    static func pageToken(_ page: PageSnapshot, key: String) -> String? {
        page.key.map { mac(key, "page|" + $0.description) }
    }

    /// Covers everything the irreversible-action guard reads (role, label, value, DOM id) and the guard's own verdict,
    /// so a control whose value gains a confirm word between `--prepare` and `--fire` is "control_changed", never pressed
    /// on the strength of a `--named-approval` given for the safe control.
    static func hitToken(_ e: PageElement, key: String) -> String {
        mac(key, ["hit", e.role, e.kind, NoteAnchor.norm(e.label) ?? "", e.domID ?? "", NoteAnchor.norm(e.value) ?? "",
                  guardWord(e, inSheet: false).word].joined(separator: "|"))
    }

    // MARK: - Deciding (pure)

    /// The controls with exactly `name` (and `role`, when given). Never "alike".
    static func exact(_ name: String, role: String?, in page: PageSnapshot) -> [PageElement] {
        let anchor = NoteAnchor(role: role, label: name)
        guard let want = NoteAnchor.norm(name) else { return [] }
        return page.elements.filter { (role == nil || anchor.roleAgrees($0.role)) && NoteAnchor.norm($0.label) == want }
    }

    static func guardWord(_ e: PageElement, inSheet: Bool) -> (word: String, about: String?) {
        let info = IrreversibleGuard.ElementInfo(role: e.role, subrole: nil, title: e.label, description: nil,
                                                 domID: e.domID, value: e.value)
        switch IrreversibleGuard.classifyPress(info, inSheet: inSheet, declared: [], warningNoteLabels: []) {
        case .safe: return ("safe", nil)
        case .confirm(let about): return ("confirm", about)
        case .forbidden(let about): return ("forbidden", about)
        }
    }

    struct Ask: Equatable {
        var name: String
        var role: String?
        var key: String
        var fire = false
        var expect: (page: String, hit: String)? = nil
        var namedApproval: String? = nil
        var requireFront = false

        static func == (a: Ask, b: Ask) -> Bool {
            a.name == b.name && a.role == b.role && a.key == b.key && a.fire == b.fire && a.expect?.page == b.expect?.page
                && a.expect?.hit == b.expect?.hit && a.namedApproval == b.namedApproval && a.requireFront == b.requireFront
        }
    }

    /// Everything `--prepare` reports, and for `--fire` whether it may press: the report so far and the one control
    /// to press (nil when it must not). Pure, so every refusal is unit-tested without a browser.
    static func decide(_ page: PageSnapshot, _ ask: Ask, front: Bool) -> (Report, PageElement?) {
        var report = Report(ok: false, exit: HeadlessRead.Exit.ok.rawValue, page: HeadlessRead.counts(page),
                            host: page.key?.host)
        func refuse(_ exit: Int32, _ reason: String) -> (Report, PageElement?) {
            report.ok = false; report.exit = exit; report.reason = reason
            return (report, nil)
        }
        guard let pageToken = pageToken(page, key: ask.key) else {
            return refuse(HeadlessRead.Exit.noWindow.rawValue, "no_page")
        }
        if ask.fire, let expect = ask.expect, expect.page != pageToken { return refuse(Exit.pageChanged.rawValue, "page_changed") }
        let hits = exact(ask.name, role: ask.role, in: page)
        let found = HeadlessRead.find(ask.name, role: ask.role, in: page)
        // An alike hit's label is the control's own name on this page (page words): report counts only.
        report.find = found.match == "exact" ? found
            : HeadlessRead.Found(name: ask.name, role: ask.role, match: found.match, count: found.count,
                                 unique: found.unique, hits: [])
        if hits.isEmpty {
            if found.match == "alike" { return refuse(Exit.notUniqueOrNotExact.rawValue, "not_exact") }
            return refuse((page.loading || page.truncated ? HeadlessRead.Exit.partial : HeadlessRead.Exit.notFound).rawValue,
                          "not_found")
        }
        if hits.count > 1 { return refuse(Exit.notUniqueOrNotExact.rawValue, "not_unique") }
        let hit = hits[0]
        if !hit.visible { return refuse(Exit.notUniqueOrNotExact.rawValue, "not_visible") }
        if !hit.enabled { return refuse(Exit.notUniqueOrNotExact.rawValue, "disabled") }
        let hitToken = hitToken(hit, key: ask.key)
        report.page_token = pageToken
        report.hit_token = hitToken
        if page.sheet != nil {
            return refuse(ask.fire ? Exit.pageChanged.rawValue : Exit.guardRefused.rawValue, "sheet_open")
        }
        let verdict = guardWord(hit, inSheet: false)
        report.guard = verdict.word
        if verdict.word == "forbidden" { return refuse(Exit.guardRefused.rawValue, "guard_forbidden") }
        guard ask.fire else {
            report.ok = true
            return (report, nil)
        }
        if let expect = ask.expect, expect.hit != hitToken { return refuse(Exit.pageChanged.rawValue, "control_changed") }
        if verdict.word == "confirm",
           NoteAnchor.norm(ask.namedApproval) == nil || NoteAnchor.norm(ask.namedApproval) != NoteAnchor.norm(hit.label) {
            return refuse(Exit.guardRefused.rawValue, "guard_confirm")
        }
        if ask.requireFront && !front { return refuse(Exit.notFront.rawValue, "not_front") }
        report.ok = true
        return (report, hit)
    }

    // MARK: - Arguments

    struct Usage: Error, Equatable { var message: String }

    static func ask(_ args: [String]) -> Result<Ask, Usage> {
        let v = HeadlessRead.value
        let name = v("--click", args), role = v("--role", args), token = v("--token", args), app = v("--app", args)
        let expect = v("--expect", args), named = v("--named-approval", args)
        for case .some(nil) in [name, role, token, app, expect, named] { return .failure(Usage(message: "A flag is missing its value.")) }
        guard let name = name ?? nil, NoteAnchor.norm(name) != nil else { return .failure(Usage(message: "--click needs a control's name.")) }
        let prepare = args.contains("--prepare"), fire = args.contains("--fire")
        guard prepare != fire else { return .failure(Usage(message: "Give exactly one of --prepare and --fire.")) }
        guard args.contains("--json") else { return .failure(Usage(message: "--click speaks JSON only: add --json.")) }
        guard let key = token ?? nil, isToken(key) else { return .failure(Usage(message: "--token takes 64 lowercase hex characters.")) }
        var ask = Ask(name: name, role: role ?? nil, key: key, fire: fire, namedApproval: named ?? nil,
                      requireFront: args.contains("--require-front"))
        if fire {
            let parts = (expect ?? nil)?.split(separator: ",").map(String.init) ?? []
            guard parts.count == 2, parts.allSatisfy({ isToken($0) }) else {
                return .failure(Usage(message: "--fire needs --expect PAGE,HIT: the two tokens --prepare gave."))
            }
            ask.expect = (parts[0], parts[1])
        } else if expect != nil {
            return .failure(Usage(message: "--expect goes with --fire only."))
        }
        return .success(ask)
    }

    // MARK: - Running

    /// What `--click` touches beyond the page read, so a test can stand in for each.
    struct Hands {
        var browser: HeadlessRead.Browser
        /// The browser is the frontmost app.
        var isFront: (NSRunningApplication) -> Bool
        /// Marks a token's key used; false when it already was (a token presses at most once).
        var spend: (String) -> Bool
        /// Re-finds the control in `app`, re-checks it is still that control and enabled, and AXPresses it once.
        var press: (NSRunningApplication, PageElement) -> Bool

        static let live = Hands(
            browser: .live,
            isFront: { NSWorkspace.shared.frontmostApplication?.processIdentifier == $0.processIdentifier },
            spend: { UsedTokens.spend($0) },
            press: { LivePress.press($0, $1) })
    }

    static func json(_ report: Report) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(report)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"ok\":false,\"exit\":2}"
    }

    static func run(_ args: [String], hands: Hands = .live, print say: (String) -> Void = { print($0) }) -> Int32 {
        let browser = hands.browser
        defer { browser.settle() }
        func out(_ report: Report) -> Int32 { say(json(report)); return report.exit }
        let ask: Ask
        switch Self.ask(args) {
        case .failure(let usage): return out(Report(ok: false, exit: HeadlessRead.Exit.usage.rawValue, error: usage.message))
        case .success(let a): ask = a
        }
        let app = HeadlessRead.value(after: "--app", in: args) ?? nil
        if let app, !ContextWatcher.browserBundles.contains(app) {
            return out(Report(ok: false, exit: HeadlessRead.Exit.usage.rawValue, error: "--app takes a browser's bundle id."))
        }
        guard browser.trusted() else {
            return out(Report(ok: false, exit: HeadlessRead.Exit.noPermission.rawValue,
                              error: "Accessibility permission isn't granted to the app running this."))
        }
        guard let running = browser.app(app), let page = ReadPageCommand.read(running, with: browser) else {
            return out(Report(ok: false, exit: HeadlessRead.Exit.noWindow.rawValue, error: "No browser window with a page was found."))
        }
        var (report, hit) = decide(page, ask, front: hands.isFront(running))
        guard ask.fire, let hit else { return out(report) }
        guard hands.spend(ask.key) else {
            report.ok = false; report.exit = Exit.pageChanged.rawValue; report.reason = "token_used"; report.pressed = false
            return out(report)
        }
        guard hands.press(running, hit) else {
            report.ok = false; report.exit = Exit.pageChanged.rawValue; report.reason = "control_changed"; report.pressed = false
            return out(report)
        }
        report.pressed = true
        browser.wait(0.5)
        if let after = browser.read(running) {
            let before = (report.page_token, report.hit_token)
            let now = (pageToken(after, key: ask.key),
                       exact(ask.name, role: ask.role, in: after).map { hitToken($0, key: ask.key) })
            report.changed = now.0 != before.0 || now.1 != [before.1].compactMap { $0 }
                || exact(ask.name, role: ask.role, in: after).first.map { $0.enabled != hit.enabled || $0.value != hit.value } == true
        }
        return out(report)
    }
}

/// Keys of tokens `--fire` has pressed under, kept as one-way hashes, owner-only, for a week. Spending is one
/// read-modify-write under an exclusive flock on a sibling lock file, and a file that exists but can't be read or
/// decoded refuses (fail closed) rather than counting as "nothing used".
enum UsedTokens {
    static var file: URL { Config.dir.appendingPathComponent("click-used.json") }

    static func spend(_ key: String, at file: URL = UsedTokens.file, now: Date = Date()) -> Bool {
        let id = HeadlessClick.mac(key, "used")
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockPath = file.appendingPathExtension("lock").path
        let fd = open(lockPath, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { return false }
        defer { flock(fd, LOCK_UN) }
        var used: [String: Double] = [:]
        if fm.fileExists(atPath: file.path) {
            guard let data = try? Data(contentsOf: file),
                  let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else { return false }
            used = decoded
        }
        used = used.filter { now.timeIntervalSince1970 - $0.value < 7 * 86_400 }
        guard used[id] == nil else { return false }
        used[id] = now.timeIntervalSince1970
        guard let data = try? JSONEncoder().encode(used) else { return false }
        let tmp = file.appendingPathExtension("tmp-\(UUID().uuidString)")
        guard fm.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]),
              rename(tmp.path, file.path) == 0
        else { try? fm.removeItem(at: tmp); return false }
        return true
    }
}

/// The one press: re-find the element at the hit's centre through Accessibility (no click there), climb to the
/// pressable control, check it is still the same control and enabled, then AXPress it.
enum LivePress {
    static func actions(_ el: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(el, &names) == .success, let list = names as? [String] else { return [] }
        return list
    }

    static func press(_ app: NSRunningApplication, _ hit: PageElement) -> Bool {
        guard let frame = hit.frame else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.5)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(axApp, Float(frame.midX), Float(frame.midY), &found) == .success,
              var el = found else { return false }
        for _ in 0..<12 where !actions(el).contains(kAXPressAction) {
            guard let parent = AX.element(el, kAXParentAttribute) else { return false }
            el = parent
        }
        guard actions(el).contains(kAXPressAction), AX.string(el, kAXRoleAttribute) == hit.role else { return false }
        let label = [AX.string(el, kAXTitleAttribute), AX.string(el, kAXDescriptionAttribute)].compactMap { $0 }
            .first { !$0.isEmpty }
        guard NoteAnchor.norm(label) == NoteAnchor.norm(hit.label) else { return false }
        var enabled: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXEnabledAttribute as CFString, &enabled) == .success,
           (enabled as? Bool) == false { return false }
        return AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
    }
}
