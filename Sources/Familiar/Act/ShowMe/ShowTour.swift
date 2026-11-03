import AppKit
import ApplicationServices

/// Where the person is when a way is to be taught: what the tour compares with where the way starts.
struct TourPlace: Equatable {
    /// The app in front, by the name a recording gives it.
    var app: String?
    var isBrowser: Bool
    /// The page's address, when the app is a browser and it can be read.
    var address: String?
}

/// What gets the person to where the way starts, when they are elsewhere.
enum TourEntry: Equatable {
    /// The page the way starts on, in a browser.
    case open(URL)
    /// The app the way starts in, to the front.
    case bring(String)
}

/// Shows someone the way, one step at a time, on their own screen. It looks for the step's control, rings it, follows it
/// as the page moves, and moves on when the person clicks it: they do every click themselves, so next time they know
/// the way. It never clicks for them. Esc or the card's × stops it.
///
/// Someone who asks from elsewhere (a search engine, a blank tab, another app) is taken to where the way starts first:
/// the tour opens that page in their browser, or brings that app forward, and the first ring appears when it shows.
/// That is the one thing it does for them: a page is an address, not a lesson.
@MainActor
final class ShowTour {
    /// How long a step is looked for on a page that can be read (the next page loading, a menu opening) before the
    /// card says it can't be seen.
    static let patience: TimeInterval = 10
    /// How long a page that can't be read yet is waited for before giving up all the same.
    static let pageWait: TimeInterval = 45
    /// How long a browser whose address can't be read is given before the page the way starts on is opened all the same.
    nonisolated static let entryPatience: TimeInterval = 3
    /// How long a control found out of view is given to come into it, once asked, before it is looked for again: one
    /// that never shows (not on the page after all) must not hold the tour.
    nonisolated static let offscreenPatience: TimeInterval = 4
    /// How far outside the ring a click still counts as clicking the control.
    static let slack: CGFloat = 10

    let path: ShowPath
    private(set) var progress: TourProgress
    var onProgress: ((TourProgress) -> Void)?
    /// Once, when the tour is over: done, or stopped.
    var onEnd: ((TourProgress) -> Void)?
    /// Each time a step's control is found: where it is, in AppKit global coordinates. For checks from the command line.
    var onFound: ((Int, NSRect) -> Void)?

    private let overlay: ShowOverlay
    private let bundleID: String?
    private var element: AXUIElement?
    private var frame: NSRect?            // AppKit global coordinates
    private var visibleArea: NSRect?      // AppKit global coordinates, the part of the window that shows
    private var timer: Timer?
    private var finding: Task<Void, Never>?
    private var lookingSince = Date()
    private var nextLook = Date.distantPast
    /// How long the step being looked for is given: the usual patience, or a page's load after the tour opened it.
    private var stepPatience = ShowTour.patience
    /// Whether the tour has taken the person to where the way starts; once at most, so a wrong guess costs one tab.
    private var opened = false
    /// Since when the step's control has been out of view.
    private var offscreenSince: Date?
    /// Where the person was the last time the step wasn't found, for the card when the step is given up.
    private var lastPlace: TourPlace?
    /// While the page in front can't be read yet: since when, and when the browser was last told again.
    private var unreadableSince: Date?
    private var lastNudge = Date.distantPast
    private var lastMissLog = Date.distantPast
    private var monitors: [Any] = []
    private var ended = false
    /// Browsers whose page trees this tour turned on, turned back off when it ends.
    private var held: Set<pid_t> = []
    /// Whether the step's control takes a click now. A greyed-out one is ringed and waited on until the page enables
    /// it; a click on it meanwhile is not the step done.
    private var enabled = true
    /// The step after the one shown, as found when this one was: its control and whether it took a click then. It
    /// becoming enabled, or appearing, once the person has acted is the step done without a click to see, as when a
    /// field is committed with Enter and the button under it comes alive.
    private var next: (element: AXUIElement, enabled: Bool)?
    /// The step after the one looked for, as it was the first time this step was looked for.
    private var nextSeen: (found: Bool, enabled: Bool)?
    /// Whether the person has clicked or typed since the step was shown: evidence the page changed for them.
    private var acted = false
    /// A field step the person has clicked into: done when they leave it, press Enter or Tab, or the page lets them on.
    private var inField = false
    private var fieldFocused = false
    private var lastPoll = Date.distantPast

    /// `bundleID` is the app the person asked from, looked in while Noteling's own pad is in front.
    init(path: ShowPath, bundleID: String?, hideFromScreenShare: Bool) {
        self.path = path
        self.bundleID = bundleID
        overlay = ShowOverlay(hideFromScreenShare: hideFromScreenShare)
        progress = TourProgress(title: path.title, steps: path.steps.map(\.say), current: 0, state: .looking)
    }

    func start() {
        guard !path.steps.isEmpty, timer == nil, !ended else { return }
        overlay.card.onStop = { [weak self] in self?.stop() }
        overlay.card.onRetry = { [weak self] in self?.retry() }
        overlay.card.onGotIt = { [weak self] in self?.finish() }
        overlay.card.onGo = { [weak self] in self?.goThere() }
        overlay.present(from: NSEvent.mouseLocation)
        overlay.update(progress)
        lookingSince = Date()
        let clicks: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.clicked(at: NSEvent.mouseLocation) }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: clicks) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            let code = Int(e.keyCode)
            MainActor.assumeIsolated {
                guard let self else { return }
                if code == 53 { self.stop(); return }   // Esc
                self.acted = true
                if [36, 76, 48].contains(code) { self.committed() }   // Return, keypad Enter, Tab
            }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard e.keyCode == 53, let self, !self.ended else { return e }
            self.stop()
            return nil
        }) { monitors.append(m) }
        let t = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func stop() {
        guard !ended else { return }
        set(.stopped)
        end(after: 0)
    }

    /// The card's "Look again" after a step couldn't be seen.
    func retry() {
        guard progress.state == .lost else { return }
        progress.elsewhere = nil
        lookingSince = Date()
        nextLook = .distantPast
        set(.looking)
    }

    /// The card's "Take me there" on a step whose page isn't open: opens it, as the tour does for the first step.
    func goThere() {
        guard progress.state == .lost, path.steps.indices.contains(progress.current),
              let url = path.steps[progress.current].url, let target = URL(string: url) else { return }
        progress.elsewhere = nil
        go(.open(target), step: path.steps[progress.current])
    }

    /// "Got it" on the last step: they found it, nothing more to click.
    func finish() {
        guard !ended else { return }
        progress.current = progress.steps.count
        set(.done)
        end(after: 2.2)
    }

    // MARK: - Each tick

    private func tick() {
        guard !ended else { return }
        switch progress.state {
        case .showing, .offscreen:
            guard let element, AX.string(element, kAXRoleAttribute) != nil else {
                lose()   // the control went away, such as when the page changed under it
                return
            }
            if Date().timeIntervalSince(lastPoll) > 0.3 {
                lastPoll = Date()
                poll(element)
                guard !ended, progress.state == .showing || progress.state == .offscreen, self.element === element else { return }
            }
            let now = ScreenHitTester.axFrame(of: element, primaryMaxY: Self.primaryMaxY).flatMap { $0.width >= 2 && $0.height >= 2 ? $0 : nil }
            let inView = now.map { now in visibleArea.map { $0.intersects(now) } ?? true } ?? false
            if let now, inView {
                offscreenSince = nil
                if progress.state == .offscreen {
                    frame = now
                    overlay.ring(now)
                    set(.showing)
                    onFound?(progress.current, now)
                } else {
                    if let frame, !Self.near(frame, now) { overlay.follow(now) }
                    frame = now
                }
            } else if progress.state == .showing {
                frame = nil
                overlay.unring()
                offscreenSince = Date()
                set(.offscreen)
            } else if Self.staysOutOfView(since: offscreenSince) {
                // It never came into view: not on this page after all, or nowhere it can be brought. Look again with
                // the patience the step has left, so a better match on the now-loaded page takes its place, or the
                // card says it can't be seen.
                Log.info("show: step \(progress.current + 1) stayed out of view; looking again")
                lose(afresh: false)
            }
        case .looking:
            if Date() > lookingSince.addingTimeInterval(stepPatience), finding == nil {
                progress.elsewhere = Self.elsewhere(for: path.steps[progress.current], place: lastPlace)
                set(.lost)
                return
            }
            if finding == nil, Date() >= nextLook { look() }
        case .lost, .done, .stopped:
            break
        }
    }

    /// The control is gone, or never showed: back to looking. `afresh` starts the step's patience over, as when the
    /// page changed under it; not when the control merely stayed out of view, so a step can't hold the tour for ever.
    private func lose(afresh: Bool = true) {
        element = nil
        frame = nil
        offscreenSince = nil
        next = nil
        inField = false
        fieldFocused = false
        progress.inField = false
        progress.disabled = false
        overlay.unring()
        if afresh { lookingSince = Date() }
        set(.looking)
    }

    /// Whether a control out of view since `since` has had its chance to come into it.
    nonisolated static func staysOutOfView(since: Date?, now: Date = Date()) -> Bool {
        guard let since else { return false }
        return now > since.addingTimeInterval(offscreenPatience)
    }

    /// What can change under a ringed control without a click to see: it going live or grey, the person leaving the
    /// field they were sent to, or the page letting them on to the next step.
    private func poll(_ element: AXUIElement) {
        let live = AXPageNode(element: element).flag("AXEnabled") ?? true
        if live != enabled {
            enabled = live
            progress.disabled = !live
            Log.info("show: step \(progress.current + 1) is \(live ? "enabled now" : "disabled")")
            set(progress.state)
        }
        if inField, let focused = AX.element(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute) {
            // Left for another control of the same app; focus gone to another app (Noteling's own pad) is not leaving.
            var focusedPid: pid_t = 0, fieldPid: pid_t = 0
            AXUIElementGetPid(focused, &focusedPid)
            AXUIElementGetPid(element, &fieldPid)
            if CFEqual(focused, element) {
                fieldFocused = true
            } else if fieldFocused, focusedPid == fieldPid {
                Log.info("show: step \(progress.current + 1) done: left the field")
                advance()
                return
            }
        }
        if let next, acted, !next.enabled, AXPageNode(element: next.element).flag("AXEnabled") == true {
            Log.info("show: step \(progress.current + 1) done: the page let them on")
            advance()
        }
    }

    /// Looks for the current step off the main thread, and for the one after it: the first time, to know whether it
    /// is there yet and takes a click, and whenever the step itself isn't seen, in case the person went ahead.
    private func look() {
        let index = progress.current
        guard path.steps.indices.contains(index) else { return }
        let step = path.steps[index]
        let after = path.steps.indices.contains(index + 1) ? path.steps[index + 1] : nil
        let seen = nextSeen
        let acted = self.acted
        guard let (app, window) = ShowFinder.window(fallback: bundleID) else { nextLook = Date().addingTimeInterval(0.3); return }
        // A browser's page has no controls to find until it is told someone is listening; the tree builds in a moment.
        if !held.contains(app.processIdentifier), BrowserAccessibility.hold(app) { held.insert(app.processIdentifier) }
        let target = UncheckedWindow(app: app, window: window)
        finding = Task.detached(priority: .userInitiated) { [weak self] in
            var found: (offset: Int, found: ShowFinder.Found<AXPageNode>)?
            if let f = ShowFinder.findOnScreen(step, app: target.app, window: target.window) {
                let onPage = f.how < .kindAndName ? ShowFinder.onPage(step, window: target.window, app: target.app) : false
                if ShowTour.accepts(f.how, offset: 0, onPage: onPage, atItsPlace: false) { found = (0, f) }
            }
            var next: Next?
            let lookedAhead = after != nil
            if let after, let f = ShowFinder.findOnScreen(after, app: target.app, window: target.window) {
                let atItsPlace = f.how >= .kindAndName ? ShowFinder.samePlace(after, app: target.app, window: target.window) : false
                if ShowTour.accepts(f.how, offset: 1, onPage: false, atItsPlace: atItsPlace) {
                    next = Next(element: f.node.element, enabled: f.enabled)
                    if found == nil, ShowTour.goneAhead(nextEnabled: f.enabled, seen: seen, acted: acted) { found = (1, f) }
                }
            }
            let result = found.map { Looked(offset: $0.offset, element: $0.found.node.element, frame: $0.found.frame,
                                            visible: $0.found.visible, enabled: $0.found.enabled, area: $0.found.area) }
            let readable = found != nil || ShowFinder.readable(app: target.app, window: target.window)
            let place = found == nil ? ShowTour.place(of: target.app, window: target.window) : nil
            await self?.looked(result, next: lookedAhead ? next : nil, lookedAhead: lookedAhead, for: index, readable: readable, place: place, app: target.app)
        }
    }

    /// Whether a match is the step. The step looked for is taken anywhere by the page's own id or by kind and name;
    /// by name alone, part of a name or where it was, only on the page it was recorded on, so a same-name control of
    /// another kind on the wrong page (the menu's "Search" for the page's "SEARCH") is never it. The step after it,
    /// which would mean the person went ahead, only as itself and only at its own place.
    nonisolated static func accepts(_ how: ShowFinder.How, offset: Int, onPage: Bool, atItsPlace: Bool) -> Bool {
        offset == 0 ? (how >= .kindAndName || onPage) : (how >= .kindAndName && atItsPlace)
    }

    /// Whether the step after the one looked for, found at its place while the step itself isn't seen, means the
    /// person went ahead. At first sight, when it takes a click. After that only when it appeared or came alive
    /// since, and the person has clicked or typed meanwhile: a button that was already there, grey or not, is no
    /// evidence of going ahead, or a field to fill before it would be skipped the moment the page showed.
    nonisolated static func goneAhead(nextEnabled: Bool, seen: (found: Bool, enabled: Bool)?, acted: Bool) -> Bool {
        guard nextEnabled else { return false }
        guard let seen else { return true }
        return acted && (!seen.found || !seen.enabled)
    }

    /// Where the step is when the page in front isn't it: its address, as the card says it, for "Take me there"; nil
    /// when the person is on the step's page, or it can't be told.
    nonisolated static func elsewhere(for step: ShowStep, place: TourPlace?) -> String? {
        guard let url = step.url, let target = URL(string: url), ["http", "https"].contains(target.scheme?.lowercased() ?? ""),
              let place else { return nil }
        if let address = place.address { return ShowFinder.samePage(address, url) ? nil : shortAddress(target) }
        return place.isBrowser ? nil : shortAddress(target)
    }

    /// Where the person is: the app in front and, in a browser, the page's address. The address bar answers before the
    /// page's tree is built, so a browser on the wrong page is known at once.
    nonisolated static func place(of app: NSRunningApplication, window: AXUIElement) -> TourPlace {
        let isBrowser = app.bundleIdentifier.map { ContextWatcher.browserBundles.contains($0) } ?? false
        let address = isBrowser ? ContextWatcher.browserURL(window: window).flatMap { $0.isEmpty ? nil : $0 } : nil
        return TourPlace(app: app.localizedName, isBrowser: isBrowser, address: address)
    }

    /// What gets the person to where `step` was shown, from `place`: the page, when they are on another one or in
    /// another kind of app, or when a browser hasn't said where it is for `entryPatience` seconds; the app, when the way
    /// is through one; nil when they are there, or it can't be told yet. A page is the same page with another query or
    /// fragment: the way is waited for there as usual.
    nonisolated static func entry(to step: ShowStep, from place: TourPlace, waited: TimeInterval) -> TourEntry? {
        if let url = step.url, let target = URL(string: url), ["http", "https"].contains(target.scheme?.lowercased() ?? "") {
            if let address = place.address { return ShowFinder.samePage(address, url) ? nil : .open(target) }
            if !place.isBrowser { return .open(target) }
            return waited >= entryPatience ? .open(target) : nil
        }
        if let app = step.app, let here = place.app, here != app { return .bring(app) }
        return nil
    }

    /// Takes the person to where the way starts, once: the page in the browser they asked from (else the one the way
    /// was shown in, if it is running, else the one that opens addresses), or the app, brought to the front. The first
    /// step is then given a page's load to show.
    private func go(_ entry: TourEntry, step: ShowStep) {
        opened = true
        switch entry {
        case .open(let url):
            if let browser = Self.browser(askedFrom: bundleID, recorded: step.app) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.addsToRecentItems = false
                NSWorkspace.shared.open([url], withApplicationAt: browser, configuration: configuration) { _, error in
                    if let error { Log.info("show: couldn't open \(url.absoluteString) in \(browser.lastPathComponent): \(error.localizedDescription)") }
                }
            } else {
                NSWorkspace.shared.open(url)
            }
            progress.opened = Self.shortAddress(url)
            Log.info("show: opening \(url.absoluteString), where the way starts")
        case .bring(let name):
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) else {
                Log.info("show: the way starts in \(name), which isn't running")
                return
            }
            app.activate()
            progress.opened = name
            Log.info("show: bringing \(name) forward, where the way starts")
        }
        stepPatience = Self.pageWait
        lookingSince = Date()
        unreadableSince = nil
        nextLook = Date().addingTimeInterval(0.8)
        set(.looking)
    }

    /// The browser to open the start page in: the one the person asked from, else the one the way was shown in when it
    /// is running, else nil for whichever opens addresses.
    private static func browser(askedFrom bundleID: String?, recorded name: String?) -> URL? {
        if let bundleID, ContextWatcher.browserBundles.contains(bundleID),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { return url }
        if let name, let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == name && ContextWatcher.browserBundles.contains($0.bundleIdentifier ?? "")
        }) { return app.bundleURL }
        return nil
    }

    /// "app.example.com/settings/tokens": the address as a person would say it, for the card.
    nonisolated static func shortAddress(_ url: URL) -> String {
        var s = (url.host ?? "") + (url.port.map { ":\($0)" } ?? "") + url.path
        while s.hasSuffix("/") { s.removeLast() }
        return s.count > 44 ? String(s.prefix(43)) + "…" : s
    }

    private struct UncheckedWindow: @unchecked Sendable {
        let app: NSRunningApplication
        let window: AXUIElement
    }

    private struct Looked {
        let offset: Int
        let element: AXUIElement
        let frame: CGRect?
        let visible: Bool
        let enabled: Bool
        let area: CGRect?
    }

    private struct Next {
        let element: AXUIElement
        let enabled: Bool
    }

    private func looked(_ result: Looked?, next: Next?, lookedAhead: Bool, for index: Int, readable: Bool, place: TourPlace?,
                        app: NSRunningApplication) {
        finding = nil
        nextLook = Date().addingTimeInterval(0.3)
        if !ended, progress.current == index, lookedAhead, nextSeen == nil || result?.offset == 0 {
            nextSeen = (next != nil, next?.enabled ?? false)
            if result?.offset == 0 { self.next = next.map { ($0.element, $0.enabled) } }
        }
        // A page that can't be read yet isn't a page without the control: the wait for the control starts once it can
        // be, and meanwhile the browser is told again every few seconds.
        if readable {
            if let since = unreadableSince {
                Log.info("show: page readable after \(String(format: "%.1f", Date().timeIntervalSince(since))) s")
                unreadableSince = nil
                lookingSince = Date()
            }
        } else {
            let since = unreadableSince ?? Date()
            unreadableSince = since
            if Date().timeIntervalSince(since) < Self.pageWait { lookingSince = Date() }
            if Date().timeIntervalSince(lastNudge) > 3 {
                lastNudge = Date()
                BrowserAccessibility.nudge(app)
            }
        }
        if result == nil, Date().timeIntervalSince(lastMissLog) > 2 {
            lastMissLog = Date()
            let window = ShowFinder.window(fallback: bundleID)
            Log.info("show: step \(index + 1) not found yet in \(window?.app.bundleIdentifier ?? "no app") “\(window.flatMap { AX.string($0.window, kAXTitleAttribute) } ?? "-")”\(readable ? "" : ", page not readable yet")")
        }
        if let place { lastPlace = place }
        guard !ended, progress.state == .looking, progress.current == index else { return }
        if let result {
            found(at: index + result.offset, result)
        } else if index == 0, !opened, let place,
                  let entry = Self.entry(to: path.steps[0], from: place, waited: readable ? Date().timeIntervalSince(lookingSince) : 0) {
            go(entry, step: path.steps[0])
        }
    }

    private func found(at index: Int, _ result: Looked) {
        // Each tick reads where it is on the main thread: a page that stops answering costs a quarter second, not six.
        AXUIElementSetMessagingTimeout(result.element, 0.25)
        element = result.element
        if index != progress.current { next = nil; nextSeen = nil; acted = false }   // gone ahead: the next step's slate is clean
        progress.current = index
        stepPatience = Self.patience
        enabled = result.enabled
        progress.disabled = !result.enabled
        progress.hint = path.steps[index].blocked
        inField = false
        fieldFocused = false
        progress.inField = false
        lastPoll = Date()
        if !result.enabled { Log.info("show: step \(index + 1) is disabled") }
        // What shows of the window: the page's own area in a browser, else the window; outside it is out of view.
        visibleArea = result.area.map(Self.appKit) ?? Self.windowFrame(of: result.element)
        if result.visible, let axFrame = result.frame {
            let rect = Self.appKit(axFrame)
            frame = rect
            overlay.ring(rect)
            set(.showing)
            onFound?(index, rect)
        } else {
            // On the page but out of view: bring it into view, the way a person scrolls to it, then ring it.
            frame = nil
            overlay.unring()
            offscreenSince = Date()
            set(.offscreen)
            let element = result.element
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, !self.ended, self.progress.state == .offscreen, self.element === element else { return }
                AXUIElementPerformAction(element, "AXScrollToVisible" as CFString)
            }
        }
        Log.info("show: step \(index + 1)/\(path.steps.count) found\(result.visible ? "" : " out of view")")
    }

    private func clicked(at point: NSPoint) {
        guard !ended, progress.state == .showing || progress.state == .offscreen else { return }
        acted = true
        let onIt = frame.map { $0.insetBy(dx: -Self.slack, dy: -Self.slack).contains(point) } ?? false
        if inField {
            // Done with the field by clicking away from it; a click back into it is still being in it.
            if !onIt { advance() }
            return
        }
        guard onIt else { return }
        // A greyed-out control takes no click: the page still wants something done first.
        guard enabled else { return }
        // A field is done when the person leaves it, not when they click into it.
        if path.steps[progress.current].isField {
            inField = true
            progress.inField = true
            set(progress.state)
            return
        }
        advance()
    }

    /// Enter or Tab in the field the person was sent to: they're done with it.
    private func committed() {
        guard !ended, progress.state == .showing || progress.state == .offscreen, inField else { return }
        Log.info("show: step \(progress.current + 1) done: committed the field")
        advance()
    }

    /// The step is done: on to the next, or the end.
    private func advance() {
        overlay.stepDone()
        element = nil
        frame = nil
        next = nil
        nextSeen = nil
        acted = false
        inField = false
        fieldFocused = false
        enabled = true
        progress.disabled = false
        progress.inField = false
        progress.hint = nil
        if progress.isLast {
            finish()
            return
        }
        progress.current += 1
        // The click is still being handled by the app: give the next page a moment before looking.
        lookingSince = Date()
        nextLook = Date().addingTimeInterval(0.35)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.ended, self.progress.state == .looking else { return }
            self.overlay.unring()
        }
        set(.looking)
    }

    private func set(_ state: TourProgress.State) {
        progress.state = state
        overlay.update(progress)
        onProgress?(progress)
    }

    private func end(after delay: TimeInterval) {
        ended = true
        timer?.invalidate()
        timer = nil
        finding?.cancel()
        finding = nil
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        for pid in held { BrowserAccessibility.release(pid) }
        held = []
        overlay.dismiss(after: delay)
        Log.info("show: \(progress.state == .done ? "done" : "stopped") at step \(min(progress.current + 1, path.steps.count))/\(path.steps.count)")
        onEnd?(progress)
    }

    // MARK: - Geometry

    private static var primaryMaxY: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    static func appKit(_ ax: CGRect) -> NSRect {
        NSRect(x: ax.minX, y: primaryMaxY - ax.maxY, width: ax.width, height: ax.height)
    }

    private static func near(_ a: NSRect, _ b: NSRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    private static func windowFrame(of element: AXUIElement) -> NSRect? {
        guard let window = AX.element(element, kAXWindowAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.25)
        return ScreenHitTester.axFrame(of: window, primaryMaxY: primaryMaxY)
    }
}
