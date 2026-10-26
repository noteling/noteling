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
        let wantID = isControlID(step.domID) ? step.domID : nil
        // Where it was and how big, for a control without a name, and to choose between two with the same name.
        let wasRect: CGRect? = {
            guard let r = step.rect, r.count == 4, let w = windowFrame, r[2] > 0, r[3] > 0 else { return nil }
            return CGRect(x: w.minX + w.width * r[0], y: w.minY + w.height * r[1], width: w.width * r[2], height: w.height * r[3])
        }()
        let was = wasRect.map { CGPoint(x: $0.midX, y: $0.midY) }
        var best: (found: Found<N>, rank: Double)?
        var stack: [(N, N?)] = [(window, nil)]
        var visited = 0
        while let (node, owner) = stack.popLast() {
            if visited >= budget || (visited % 64 == 63 && now() > deadline) { break }
            visited += 1
            let role = node.string(kAXRoleAttribute) ?? ""
            let isControl = controls.contains(role)
            if let how = match(node, role: role, want: want, wantRole: step.role, wantID: wantID, was: wasRect, isControl: isControl) {
                // The text inside a control stands for it, unless the "control" is a whole row of a table.
                var target = node, targetIsControl = isControl
                if !isControl, let owner, let frame = owner.frame, let inner = node.frame,
                   frame.width * frame.height <= max(inner.width * inner.height * 12, 6_000) {
                    target = owner
                    targetIsControl = true
                }
                let frame = target.frame.flatMap { $0.width >= 2 && $0.height >= 2 ? $0 : nil }
                // A spot is never the page around it: a click once recorded as the page's root must find nothing.
                if how == .place, let frame, let visibleArea, frame.width * frame.height > visibleArea.width * visibleArea.height * 0.4 {
                    stack.append(contentsOf: node.children.reversed().map { ($0, isControl ? node : owner) })
                    continue
                }
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

    /// Ids that name the page, not a control: a React or Vue mount, Next's root, the document's main. A step never
    /// goes by one, so a click once recorded as the page's root can't ring the whole page.
    static let rootIDs: Set<String> = ["app", "root", "__next", "__nuxt", "main", "body", "content", "page", "wrapper",
                                       "container", "layout", "application", "react-root", "root-container", "site"]

    /// A page's own id for a control that will be the same next time, and is a control's: see `rootIDs`.
    static func isControlID(_ id: String?) -> Bool {
        guard let id, NoteAnchor.isSteadyID(id) else { return false }
        return !rootIDs.contains(id.lowercased())
    }

    private static func match<N: PageNode>(_ node: N, role: String, want: String?, wantRole: String?, wantID: String?,
                                           was: CGRect?, isControl: Bool) -> How? {
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
        // A control without a name is found by where it was, and only then: the one at that spot of about that size,
        // so a card built from plain groups is the card again, not a group around it or inside it.
        if want == nil, isControl || role == wantRole, let was, let frame = node.frame, frame.contains(CGPoint(x: was.midX, y: was.midY)) {
            let area = frame.width * frame.height, wasArea = was.width * was.height
            if area >= wasArea / 4, area <= wasArea * 4 { return .place }
        }
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
              let hit else { return nil }
        // The climb from what was clicked up to the page (or window) around it, where it ends.
        var chain = [AXPageNode(element: hit)]
        var around: CGRect?
        var rootChild = false
        var element = hit
        for _ in 0..<12 {
            guard let parent = AX.element(element, kAXParentAttribute) else { break }
            let role = AX.string(parent, kAXRoleAttribute) ?? ""
            if role == kAXApplicationRole { break }
            if role == kAXWindowRole || role == "AXWebArea" {
                around = AXPageNode(element: parent).frame
                rootChild = true
                break
            }
            chain.append(AXPageNode(element: parent))
            element = parent
        }
        guard let picked = pick(chain, around: around, rootChild: rootChild),
              let frame = ScreenHitTester.axFrame(of: picked.node.element, primaryMaxY: primaryMaxY) else { return nil }
        let id = picked.node.string("AXDOMIdentifier").flatMap { $0.isEmpty ? nil : $0 }
        return Control(role: picked.node.string(kAXRoleAttribute) ?? "AXUnknown", name: picked.label, domID: isControlID(id) ? id : nil, frame: frame)
    }

    /// Which element on the climb from what was clicked stands for the control, and what to call it: the first with a
    /// control's role; else, for something built from plain groups (a card), the nearest named thing around the click
    /// that is still small next to the page, such as the clicked text itself; else what was clicked, found again by
    /// where it was. Never the page's root or anything that fills most of the page: a click on a card is the card,
    /// not the page around it, and a click on the page's background is no control at all. `around` is the page's (or
    /// window's) frame; `rootChild` says the chain's last element sits right under it.
    static func pick<N: PageNode>(_ chain: [N], around: CGRect?, rootChild: Bool) -> (node: N, label: String?)? {
        guard let hit = chain.first else { return nil }
        let pageArea = around.map { $0.width * $0.height }
        let hitArea = hit.frame.map { $0.width * $0.height } ?? 0
        func fillsThePage(_ n: N) -> Bool {
            guard let f = n.frame, let pageArea else { return false }
            return f.width * f.height > pageArea * 0.4
        }
        guard !fillsThePage(hit) else { return nil }
        for node in chain {
            if fillsThePage(node) { break }
            let role = node.string(kAXRoleAttribute) ?? ""
            if controls.contains(role) { return (node, name(node, role: role)) }
        }
        for (i, node) in chain.enumerated() {
            if fillsThePage(node) || (rootChild && chain.count > 1 && i == chain.count - 1) { break }
            if let f = node.frame, f.width * f.height > max(hitArea * 25, 20_000) { break }
            if let label = name(node, role: node.string(kAXRoleAttribute) ?? "") { return (node, label) }
        }
        return (hit, nil)
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
        let inBrowser = ContextWatcher.browserBundles.contains(app.bundleIdentifier ?? "")
        for scope in scopes(for: step, window: root, page: page, inBrowser: inBrowser) {
            guard var found = find(step, in: scope, visibleArea: visible, windowFrame: frame) else { continue }
            found.area = visible
            return found
        }
        return nil
    }

    /// Where a step is looked for, in order. One recorded on a web page is on the page: the browser's own tab strip and
    /// toolbar are never it (a "Search tabs" button is not the page's "Search"), and a page still loading has nothing
    /// to find yet. One named for the screen now is looked for on the page first, then in the rest of the window. In
    /// any other app, the window.
    static func scopes<N: PageNode>(for step: ShowStep, window: N, page: N?, inBrowser: Bool) -> [N] {
        guard inBrowser else { return [window] }
        if step.url != nil { return page.map { [$0] } ?? [] }
        return [page, window].compactMap { $0 }
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
