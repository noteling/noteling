import AppKit
import ApplicationServices

/// Finds a step's control on the live screen the way a person would look for it: the page's own id for it first, then
/// its kind and name, then its name alone, and a control with no name by where it was in the window. The text inside a
/// button stands for the button. Works on any Accessibility tree, so it is tested on made-up ones.
enum ShowFinder {
    /// How sure the match is, weakest first.
    enum How: Int, Comparable {
        case place = 1, partOfName, nameButNumbers, name, kindAndName, id
        static func < (a: How, b: How) -> Bool { a.rawValue < b.rawValue }
    }

    struct Found<N> {
        var node: N
        /// Accessibility's top-left global coordinates; nil for a control the page has but doesn't place, such as one
        /// scrolled far out of view.
        let frame: CGRect?
        let how: How
        /// Inside the part of the window that shows; false when it is scrolled out of view.
        let visible: Bool
        /// That part of the window: a browser's page area, else the window.
        var area: CGRect? = nil
    }

    /// Roles a person clicks. Text inside one of these is taken for the control itself.
    static let controls: Set<String> = ["AXButton", "AXLink", "AXMenuItem", "AXMenuBarItem", "AXTab", "AXRadioButton",
                                        "AXCheckBox", "AXPopUpButton", "AXMenuButton", "AXComboBox", "AXTextField",
                                        "AXSearchField", "AXTextArea", "AXDisclosureTriangle", "AXRow", "AXCell", "AXSwitch"]

    static func find<N: PageNode>(_ step: ShowStep, in window: N, visibleArea: CGRect?, windowFrame: CGRect? = nil,
                                  budget: Int = 8_000, seconds: TimeInterval = 1.5, now: () -> Date = Date.init) -> Found<N>? {
        let deadline = now().addingTimeInterval(seconds)
        let want = NoteAnchor.norm(step.label)
        let wantID = NoteAnchor.isSteadyID(step.domID) ? step.domID : nil
        // Where it was, for a control without a name, and to choose between two with the same name.
        let was: CGPoint? = {
            guard let r = step.rect, r.count == 4, let w = windowFrame else { return nil }
            return CGPoint(x: w.minX + w.width * (r[0] + r[2] / 2), y: w.minY + w.height * (r[1] + r[3] / 2))
        }()
        var best: (found: Found<N>, rank: Double)?
        var stack: [(N, N?)] = [(window, nil)]
        var visited = 0
        while let (node, owner) = stack.popLast() {
            if visited >= budget || (visited % 64 == 63 && now() > deadline) { break }
            visited += 1
            let role = node.string(kAXRoleAttribute) ?? ""
            let isControl = controls.contains(role)
            if let how = match(node, role: role, want: want, wantRole: step.role, wantID: wantID, was: was, isControl: isControl) {
                // The text inside a control stands for it, unless the "control" is a whole row of a table.
                var target = node, targetIsControl = isControl
                if !isControl, let owner, let frame = owner.frame, let inner = node.frame,
                   frame.width * frame.height <= max(inner.width * inner.height * 12, 6_000) {
                    target = owner
                    targetIsControl = true
                }
                let frame = target.frame.flatMap { $0.width >= 2 && $0.height >= 2 ? $0 : nil }
                let visible = frame.map { frame in visibleArea.map { $0.intersects(frame) } ?? true } ?? false
                var rank = Double(how.rawValue) * 10 + (visible ? 5 : 0) + (targetIsControl ? 2 : 0) + (frame == nil ? -1 : 0)
                if let was, let frame { rank -= min(3, hypot(frame.midX - was.x, frame.midY - was.y) / 400) }
                if how == .place, let frame { rank -= Double(frame.width * frame.height) / 1_000_000 }   // the smallest that holds the spot
                if best == nil || rank > best!.rank {
                    best = (Found(node: target, frame: frame, how: how, visible: visible), rank)
                }
            }
            let next = isControl ? node : owner
            stack.append(contentsOf: node.children.reversed().map { ($0, next) })
        }
        return best?.found
    }

    private static func match<N: PageNode>(_ node: N, role: String, want: String?, wantRole: String?, wantID: String?,
                                           was: CGPoint?, isControl: Bool) -> How? {
        if let wantID, node.string("AXDOMIdentifier") == wantID { return .id }
        if let want, let have = NoteAnchor.norm(name(node, role: role)) {
            if have == want { return role == wantRole ? .kindAndName : .name }
            // "Inbox 3" is the same control as "Inbox 1" was: a count after the name changes, the name doesn't.
            if role == wantRole || wantRole == nil, let name = withoutCount(want), name == withoutCount(have) { return .nameButNumbers }
            // Part of a name: the control says a little more than was recorded ("Create agent token…"), or most of
            // it. Never a short word that merely appears in a longer name, such as "Settings".
            if isControl, want.count >= 4, have.count <= want.count * 3,
               contains(have, want) || (contains(want, have) && have.count * 10 >= want.count * 6) {
                return .partOfName
            }
        }
        // A control without a name is found by where it was, and only then.
        if want == nil, isControl, let was, let frame = node.frame, frame.contains(was) { return .place }
        return nil
    }

    /// Whether `inner`'s words appear together, as whole words, in `outer`: "Page 1" is not in "Page 12".
    static func contains(_ outer: String, _ inner: String) -> Bool {
        let words = { (s: String) in s.split { !$0.isLetter && !$0.isNumber }.map(String.init) }
        let o = words(outer), i = words(inner)
        guard !i.isEmpty, i.count <= o.count else { return false }
        return (0...(o.count - i.count)).contains { Array(o[$0..<($0 + i.count)]) == i }
    }

    /// A name without the count at its end ("Inbox 3", "Notifications (12)"), or nil when it has none or too little is
    /// left to tell controls apart. Numbers inside a name ("Q3 2026 report", "Page 2 of 5") are part of the name.
    static func withoutCount(_ name: String) -> String? {
        guard let count = name.range(of: #"[\s(\[]*\d+[)\]]?\s*$"#, options: .regularExpression) else { return nil }
        let rest = name[..<count.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.count >= 5 ? rest : nil
    }

    /// What a person would call it: its title, description or placeholder; a text's own words; a control's inner text.
    static func name<N: PageNode>(_ node: N, role: String) -> String? {
        let own = [node.string(kAXTitleAttribute), node.string(kAXDescriptionAttribute), node.string(kAXPlaceholderValueAttribute)]
            .lazy.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        if let own { return own }
        if role == "AXStaticText" {
            let text = node.string(kAXValueAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? text : nil
        }
        if PageWalk.atomic.contains(role) || role == "AXRow" || role == "AXCell" { return PageWalk.contentName(node) }
        return nil
    }

    // MARK: - On the live screen

    /// The control under a point (AppKit global coordinates), climbing from the text or picture under it to the control
    /// around it: what a click there pressed. For Watch Me's clicks.
    struct Control {
        let role: String
        let name: String?
        let domID: String?
        let frame: NSRect   // AppKit global coordinates
    }

    @MainActor
    static func control(at point: NSPoint) -> Control? {
        guard Permissions.accessibilityGranted else { return nil }
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(primaryMaxY - point.y), &hit) == .success,
              var element = hit else { return nil }
        for _ in 0..<5 {
            let role = AX.string(element, kAXRoleAttribute) ?? ""
            if controls.contains(role) { break }
            guard let parent = AX.element(element, kAXParentAttribute),
                  ![kAXWindowRole, "AXWebArea", kAXApplicationRole].contains(AX.string(parent, kAXRoleAttribute) ?? "") else { break }
            element = parent
        }
        let node = AXPageNode(element: element)
        let role = node.string(kAXRoleAttribute) ?? "AXUnknown"
        guard let frame = ScreenHitTester.axFrame(of: element, primaryMaxY: primaryMaxY) else { return nil }
        return Control(role: role, name: name(node, role: role), domID: node.string("AXDOMIdentifier").flatMap { $0.isEmpty ? nil : $0 },
                       frame: frame)
    }

    /// The window a step is looked for in: the focused window of the app in front, or of `fallback` (the app the person
    /// asked from) while Noteling's own pad is in front.
    static func window(fallback bundleID: String?) -> (app: NSRunningApplication, window: AXUIElement)? {
        let own = Bundle.main.bundleIdentifier
        var app = NSWorkspace.shared.frontmostApplication
        if app == nil || app?.bundleIdentifier == own || app?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            app = bundleID.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
        }
        guard let app, Permissions.accessibilityGranted else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.5)
        guard let window = AX.element(axApp, kAXFocusedWindowAttribute) ?? AX.element(axApp, kAXMainWindowAttribute) else { return nil }
        return (app, window)
    }

    /// Looks for a step in the window in front. Call it off the main thread: a page's tree is read one call at a time.
    static func findOnScreen(_ step: ShowStep, app: NSRunningApplication, window: AXUIElement) -> Found<AXPageNode>? {
        let root = AXPageNode(element: window)
        let frame = root.frame
        // A browser's page: what shows is the page's own area, not the window with its toolbars.
        let page = PageWalk.page(among: PageWalk.webAreas(under: root, limit: 800).areas)
        let visible = page?.frame.flatMap { area in frame.map { $0.intersection(area) } ?? area } ?? frame
        guard var found = find(step, in: root, visibleArea: visible, windowFrame: frame) else { return nil }
        found.area = visible
        return found
    }

    /// Whether the window in front shows the page (or window) a step was recorded on: its address without the part after
    /// #, or for an app, its window's title. A step that says neither is anywhere.
    static func samePlace(_ step: ShowStep, app: NSRunningApplication, window: AXUIElement) -> Bool {
        if let recorded = step.url {
            let page = PageWalk.page(among: PageWalk.webAreas(under: AXPageNode(element: window), limit: 800).areas)
            guard let address = page?.string("AXURL") else { return false }
            return PageWalk.safeAddress(address) == PageWalk.safeAddress(recorded)
        }
        if let title = NoteAnchor.norm(step.title) { return NoteAnchor.norm(AX.string(window, kAXTitleAttribute)) == title }
        return true
    }

    /// Whether two addresses are the same page: the same host and path, whatever the scheme, "www.", a trailing slash,
    /// the query or the fragment. The page a way starts on with another item selected is still that page.
    static func samePage(_ a: String, _ b: String) -> Bool {
        func key(_ address: String) -> String? {
            guard let c = URLComponents(string: address), var host = c.host?.lowercased() else { return nil }
            if host.hasPrefix("www.") { host.removeFirst(4) }
            var path = c.path
            while path.hasSuffix("/") { path.removeLast() }
            return host + (c.port.map { ":\($0)" } ?? "") + path
        }
        guard let a = key(a), let b = key(b) else { return false }
        return a == b
    }

    /// Whether there is anything to look in yet. A browser's page can read as empty for a while after it is told
    /// someone is listening, and "not found" then means "not readable yet", not "not on this page".
    static func readable(app: NSRunningApplication, window: AXUIElement) -> Bool {
        guard BrowserAccessibility.needs(app) else { return true }
        guard let page = PageWalk.page(among: PageWalk.webAreas(under: AXPageNode(element: window), limit: 800).areas) else { return false }
        return hasContent(page)
    }

    /// More than an empty group or two under the page: the tree has been built.
    static func hasContent<N: PageNode>(_ page: N, atLeast: Int = 8) -> Bool {
        var queue = page.children, index = 0
        while index < queue.count, queue.count < atLeast {
            queue.append(contentsOf: queue[index].children)
            index += 1
        }
        return queue.count >= atLeast
    }
}
