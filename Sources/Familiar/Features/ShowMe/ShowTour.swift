import AppKit
import ApplicationServices

/// Shows someone the way, one step at a time, on their own screen. It looks for the step's control, rings it, follows it
/// as the page moves, and moves on when the person clicks it: they do every click themselves, so next time they know
/// the way. It never clicks for them. Esc or the card's × stops it.
@MainActor
final class ShowTour {
    /// How long a step is looked for on a page that can be read (the next page loading, a menu opening) before the
    /// card says it can't be seen.
    static let patience: TimeInterval = 10
    /// How long a page that can't be read yet is waited for before giving up all the same.
    static let pageWait: TimeInterval = 45
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
    /// While the page in front can't be read yet: since when, and when the browser was last told again.
    private var unreadableSince: Date?
    private var lastNudge = Date.distantPast
    private var lastMissLog = Date.distantPast
    private var monitors: [Any] = []
    private var ended = false
    /// Browsers whose page trees this tour turned on, turned back off when it ends.
    private var held: Set<pid_t> = []

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
        overlay.present(from: NSEvent.mouseLocation)
        overlay.update(progress)
        lookingSince = Date()
        let clicks: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.clicked(at: NSEvent.mouseLocation) }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: clicks) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard e.keyCode == 53 else { return }   // Esc
            MainActor.assumeIsolated { self?.stop() }
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
        lookingSince = Date()
        nextLook = .distantPast
        set(.looking)
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
            let now = ScreenHitTester.axFrame(of: element, primaryMaxY: Self.primaryMaxY).flatMap { $0.width >= 2 && $0.height >= 2 ? $0 : nil }
            let inView = now.map { now in visibleArea.map { $0.intersects(now) } ?? true } ?? false
            if let now, inView {
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
                set(.offscreen)
            }
        case .looking:
            if Date() > lookingSince.addingTimeInterval(Self.patience), finding == nil {
                set(.lost)
                return
            }
            if finding == nil, Date() >= nextLook { look() }
        case .lost, .done, .stopped:
            break
        }
    }

    private func lose() {
        element = nil
        frame = nil
        overlay.unring()
        lookingSince = Date()
        set(.looking)
    }

    /// Looks for the current step off the main thread, and for the one after it too, in case the person went ahead.
    private func look() {
        let index = progress.current
        guard path.steps.indices.contains(index) else { return }
        let steps = Array(path.steps[index...].prefix(2))
        guard let (app, window) = ShowFinder.window(fallback: bundleID) else { nextLook = Date().addingTimeInterval(0.3); return }
        // A browser's page has no controls to find until it is told someone is listening; the tree builds in a moment.
        if !held.contains(app.processIdentifier), BrowserAccessibility.hold(app) { held.insert(app.processIdentifier) }
        let target = UncheckedWindow(app: app, window: window)
        finding = Task.detached(priority: .userInitiated) { [weak self] in
            var found: (offset: Int, found: ShowFinder.Found<AXPageNode>)?
            for (offset, step) in steps.enumerated() {
                guard let f = ShowFinder.findOnScreen(step, app: target.app, window: target.window) else { continue }
                // The next step counts only as itself on its own page: a "Create" anywhere isn't the person going ahead.
                if offset == 0 || (f.how >= .kindAndName && ShowFinder.samePlace(step, app: target.app, window: target.window)) {
                    found = (offset, f)
                    break
                }
            }
            let result = found.map { Looked(offset: $0.offset, element: $0.found.node.element, frame: $0.found.frame,
                                            visible: $0.found.visible, area: $0.found.area) }
            let readable = found != nil || ShowFinder.readable(app: target.app, window: target.window)
            await self?.looked(result, for: index, readable: readable, app: target.app)
        }
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
        let area: CGRect?
    }

    private func looked(_ result: Looked?, for index: Int, readable: Bool, app: NSRunningApplication) {
        finding = nil
        nextLook = Date().addingTimeInterval(0.3)
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
        guard !ended, progress.state == .looking, progress.current == index, let result else { return }
        found(at: index + result.offset, result)
    }

    private func found(at index: Int, _ result: Looked) {
        // Each tick reads where it is on the main thread: a page that stops answering costs a quarter second, not six.
        AXUIElementSetMessagingTimeout(result.element, 0.25)
        element = result.element
        progress.current = index
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
        guard !ended, progress.state == .showing || progress.state == .offscreen,
              let frame, frame.insetBy(dx: -Self.slack, dy: -Self.slack).contains(point) else { return }
        overlay.stepDone()
        element = nil
        self.frame = nil
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
