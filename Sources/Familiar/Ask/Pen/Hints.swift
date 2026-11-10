import AppKit

/// Hints on the page in front, shown as you arrive and following the page: a small tag at each control someone left a
/// hint on, and the whole hint when the mouse comes to it. No model and no pixels: the page's own Accessibility tree
/// says where its controls are, and is read again when the page is scrolled, clicked or typed in, when its window
/// moves, and while a page is still loading. The pen's own stickers take over while it is up.
@MainActor
final class HintsController {
    struct Mark: Equatable {
        let note: StickyNote
        /// The control, in global coordinates.
        let frame: NSRect
    }

    /// What a read of the page in front found: the marks, the page's address as the page itself gives it, and how
    /// many hints have nothing on the page to stick to (yet: a page still loading has none of its controls).
    struct Reading {
        var marks: [Mark]
        var pageURL: String? = nil
        var missing: Int = 0
        /// The hints with nothing on the page to stick to, so the log can say what each looked for.
        var notFound: [StickyNote] = []
    }

    /// Hints show by themselves (Settings, and Noteling's menu).
    var enabled = true
    /// Whether panels go on the screen and events are listened to; tests keep both off.
    var shows = true
    /// The pen is up, or the hints are shown by hand: nothing is drawn twice.
    var suppressed: () -> Bool = { false }
    /// Reads the page in front and places the hints on it. The app reads the browser's page, or the window's
    /// Accessibility tree, off the main thread; tests hand in a page of their own.
    var reader: (ScreenContext, [StickyNote]) async -> Reading? = HintsController.readFront
    /// Told how many marks were placed of how many hints, each time the page is read.
    var onPlaced: ((_ placed: Int, _ of: Int) -> Void)?

    private(set) var scene: ScreenContext?
    private(set) var notes: [StickyNote] = []
    private(set) var marks: [Mark] = []
    private(set) var hovered: String?
    private var panels: [HintsPanel] = []
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var heartbeat: Timer?
    private var pending: DispatchWorkItem?
    private(set) var current: Task<Void, Never>?
    private var again = false
    private var generation = 0
    private var touched = false
    private var retries = 0
    /// Whether this page's placing was told once; after that only a change in the count is.
    private var reported = false
    private var lastHover = Date.distantPast
    private var windowFrame: NSRect?

    /// After the last turn of the wheel, before the page is read again.
    static let settle: TimeInterval = 0.25
    /// After a click or a key, which may have changed the page.
    static let afterInput: TimeInterval = 0.6
    /// How often the page is read again when something happened to it, or its window moved.
    static let heartbeatSeconds: TimeInterval = 3
    /// A page still loading is looked at again, a few times, until its controls are there.
    static let retryDelays: [TimeInterval] = [1, 2, 4]

    var isShowing: Bool { scene != nil }

    /// A page or window came to the front with hints on it: read it and mark them. Nothing comes up when there are
    /// none, or when hints are off. The same page with a new title keeps its marks and reads again.
    func arrive(_ scene: ScreenContext, notes: [StickyNote]) {
        if let old = self.scene, old.bundleID == scene.bundleID, let url = old.url, url == scene.url {
            self.scene = scene
            update(notes: notes)
            return
        }
        leave()
        guard enabled, !notes.isEmpty else { return }
        self.scene = scene
        self.notes = notes
        retries = 0
        reported = false
        listen()
        read()
    }

    /// The page is gone, or hints are off: every mark goes, and nothing is listened to.
    func leave() {
        generation += 1
        pending?.cancel(); pending = nil
        current?.cancel(); current = nil
        again = false
        heartbeat?.invalidate(); heartbeat = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer); NotificationCenter.default.removeObserver(observer) }
        observers = []
        scene = nil
        notes = []
        marks = []
        hovered = nil
        windowFrame = nil
        for panel in panels { panel.orderOut(nil) }
        panels = []
    }

    /// The scene in front and its hints, whatever changed: the page, a hint kept or removed, the team's tools updated.
    func sync(_ scene: ScreenContext?, notes: [StickyNote]) {
        guard let scene else { leave(); return }
        if isShowing { update(notes: notes) } else { arrive(scene, notes: notes) }
    }

    /// The hints on this page changed: read the page again with them; none left, and the marks go.
    func update(notes: [StickyNote]) {
        guard scene != nil else { return }
        if notes.isEmpty { leave(); return }
        self.notes = notes
        retries = 0
        read()
    }

    /// The pen came up, or the hints were shown by hand: the marks step aside until `resume`.
    func withdraw() {
        guard !marks.isEmpty else { return }
        marks = []
        hovered = nil
        draw()
    }

    /// The pen was put down, or the hints shown by hand went: the marks come back.
    func resume() { if scene != nil { read() } }

    /// Hints turned on or off, in Settings or Noteling's menu.
    func setEnabled(_ on: Bool, scene: ScreenContext?, notes: [StickyNote]) {
        enabled = on
        if !on { leave() } else if let scene { arrive(scene, notes: notes) }
    }

    // MARK: reading the page

    /// Reads the page now, or again once the read under way is done.
    func read() {
        guard scene != nil else { return }
        if current != nil { again = true; return }
        let generation = generation
        touched = false
        current = Task { [weak self] in
            guard let self, let scene = self.scene else { return }
            let reading = await self.reader(scene, self.notes)
            guard !Task.isCancelled, generation == self.generation else { return }
            self.current = nil
            self.took(reading)
            if self.again { self.again = false; self.read() }
        }
    }

    /// Waits for the read under way, and the one asked for meanwhile; for tests.
    func settle() async {
        while let task = current { await task.value }
    }

    private func took(_ reading: Reading?) {
        guard let scene else { return }
        // The page moved on under the marks: they go, and the watcher brings the next page's.
        if let url = reading?.pageURL, let here = scene.url, let a = PageKey.of(url), let b = PageKey.of(here), a != b {
            Log.info("hints: the page moved on to \(a); the marks for \(b) go")
            leave()
            return
        }
        let marks = reading?.marks ?? []
        if marks.count != self.marks.count || !reported {
            onPlaced?(marks.count, notes.count)
            let place = scene.url.flatMap(PageKey.of)?.description ?? scene.appName
            if let line = WandController.shortfall(reading?.notFound ?? [], of: notes.count, on: place) { Log.info(line) }
        }
        reported = true
        if marks != self.marks {
            self.marks = marks
            if let hovered, !marks.contains(where: { $0.note.id == hovered }) { self.hovered = nil }
            draw()
        }
        // A page still loading has nothing to stick to yet: look again in a moment, a few times.
        let missing = reading?.missing ?? notes.count
        if missing > 0, retries < Self.retryDelays.count {
            let delay = Self.retryDelays[retries]
            retries += 1
            schedule(after: delay)
        }
    }

    /// A read of the page after a pause, replacing one already waiting.
    func schedule(after delay: TimeInterval) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pending = nil
            self?.read()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: following the page

    private func listen() {
        guard shows else { return }
        // The marks can't follow a page as it scrolls: they go at the first turn of the wheel and are back once it settles.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.scrolled() }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .keyDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                self?.touched = true
                self?.schedule(after: Self.afterInput)
            }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.hover(at: NSEvent.mouseLocation) }
        }) { monitors.append(monitor) }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.touched = true
                self?.schedule(after: 0.5)
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        let timer = Timer(timeInterval: Self.heartbeatSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.beat() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    private func scrolled() {
        touched = true
        if !marks.isEmpty {   // stale at once: off until the page settles
            marks = []
            hovered = nil
            draw()
        }
        schedule(after: Self.settle)
    }

    /// Every few seconds: the page is read again if anything happened to it, or its window moved.
    private func beat() {
        guard let scene else { return }
        let frame = Self.frontWindowFrame(bundleID: scene.bundleID)
        let moved = windowFrame != nil && frame != windowFrame
        windowFrame = frame
        if touched || moved { read() }
    }

    private func screensChanged() {
        for panel in panels { panel.orderOut(nil) }
        panels = []
        draw()
    }

    /// The scene's front window, by two attributes rather than a walk of the page: enough to notice it moved.
    nonisolated static func frontWindowFrame(bundleID: String) -> NSRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.2)
        guard let window = AX.element(axApp, kAXFocusedWindowAttribute) ?? AX.element(axApp, kAXMainWindowAttribute) else { return nil }
        return ScreenHitTester.axFrame(of: window, primaryMaxY: NSScreen.screens.first?.frame.maxY ?? 0)
    }

    // MARK: the mouse

    /// The pointer moved: the hint under it opens, the one it left closes.
    func hover(at point: NSPoint) {
        guard !marks.isEmpty else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHover) > 0.03 else { return }
        lastHover = now
        let open = hovered.flatMap { id in openFrame(of: id).map { (id: id, frame: $0) } }
        let id = Self.pick(marks, open: open, at: point)
        guard id != hovered else { return }
        hovered = id
        for panel in panels { panel.hintsView?.setHovered(id) }
    }

    /// The mark under the pointer: the one whose control or tag is there, and one already open stays open while the
    /// pointer is on the hint itself, so it can be read.
    static func pick(_ marks: [Mark], open: (id: String, frame: NSRect)?, at point: NSPoint) -> String? {
        if let open, open.frame.contains(point) { return open.id }
        return marks.first { $0.frame.insetBy(dx: -4, dy: -4).contains(point) || tag(on: $0.frame).contains(point) }?.note.id
    }

    /// Where a mark's tag sits on the screen.
    static func tag(on control: NSRect) -> NSRect {
        StickerLayer.tagFrame(control: control, in: NSRect(x: -1e6, y: -1e6, width: 2e6, height: 2e6))
    }

    private func openFrame(of id: String) -> NSRect? {
        for panel in panels { if let frame = panel.hintsView?.openFrame(of: id) { return frame } }
        return nil
    }

    // MARK: drawing

    private func draw() {
        guard shows else { return }
        if marks.isEmpty || suppressed() {
            for panel in panels { panel.orderOut(nil) }
            panels = []
            return
        }
        if panels.isEmpty { panels = NSScreen.screens.map { HintsPanel(screen: $0) } }
        for panel in panels {
            panel.hintsView?.show(marks.filter { $0.frame.intersects(panel.frame) }, hovered: hovered)
            panel.orderFrontRegardless()
        }
    }

    // MARK: the app's reader

    /// The page in the browser in front, read off the main thread, or any other app's window from its Accessibility
    /// tree; the hints placed on it as the pen places them.
    static func readFront(_ scene: ScreenContext, _ notes: [StickyNote]) async -> Reading? {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let bundle = scene.bundleID
        if ContextWatcher.browserBundles.contains(bundle) {
            guard let page = await Task.detached(priority: .utility, operation: { PageReader.read(bundleID: bundle) }).value else { return nil }
            let placed = WandController.place(notes, page: page, primaryMaxY: primaryMaxY)
            var marks = placed.placed
            if marks.contains(where: \.predicted) {
                // A hint on a control with no name, placed by where the control should be: the live page says what is there.
                marks = await Task.detached(priority: .utility, operation: { WandController.snapped(marks, bundleID: bundle, primaryMaxY: primaryMaxY) }).value
            }
            return Reading(marks: marks.map { Mark(note: $0.note, frame: $0.frame) }, pageURL: page.url, missing: placed.missing.count,
                           notFound: placed.missing)
        }
        let scan = await Task.detached(priority: .utility, operation: { AXScan.frontmostWindow() }).value
        guard scan.bundleID == bundle else { return nil }
        let placed = WandController.place(notes, scan: scan)
        let notFound = notes.filter { note in !placed.contains { $0.note.id == note.id } }
        return Reading(marks: placed.map { Mark(note: $0.note, frame: $0.frame) }, pageURL: nil, missing: notFound.count, notFound: notFound)
    }
}

/// A see-through panel over one screen, letting every click through to the apps underneath, drawing the marks.
final class HintsPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        sharingType = .none   // hints and colleagues' names: never in a screen share, whatever the bubble's setting
        contentView = HintsView(frame: NSRect(origin: .zero, size: screen.frame.size), scale: screen.backingScaleFactor)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    var hintsView: HintsView? { contentView as? HintsView }
}

/// The marks on one screen: a tag on each control with a hint, the hint itself open where the pointer is.
final class HintsView: NSView {
    private var stickers: [StickerLayer] = []
    private let scale: CGFloat

    init(frame: NSRect, scale: CGFloat) {
        self.scale = scale
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ marks: [HintsController.Mark], hovered: String?) {
        stickers.forEach { $0.layer.removeFromSuperlayer() }
        stickers = marks.map { mark in
            let sticker = StickerLayer(note: mark.note, frame: mark.frame, scale: scale)
            sticker.mode = mark.note.id == hovered ? .open : .tag
            layer?.addSublayer(sticker.layer)
            layout(sticker)
            return sticker
        }
    }

    func setHovered(_ id: String?) {
        for sticker in stickers {
            let mode: StickerLayer.Mode = sticker.note.id == id ? .open : .tag
            if sticker.mode != mode { sticker.mode = mode; layout(sticker) }
        }
    }

    /// The open hint's frame on the screen, so it stays open while the pointer is on it.
    func openFrame(of id: String) -> NSRect? {
        stickers.first { $0.note.id == id && $0.isOpen }.map { global($0.layer.frame) }
    }

    private func layout(_ sticker: StickerLayer) { sticker.layout(control: local(sticker.frame), in: bounds) }

    private func local(_ global: NSRect) -> NSRect {
        guard let w = window else { return global }
        return NSRect(x: global.minX - w.frame.minX, y: global.minY - w.frame.minY, width: global.width, height: global.height)
    }

    private func global(_ local: NSRect) -> NSRect {
        guard let w = window else { return local }
        return NSRect(x: local.minX + w.frame.minX, y: local.minY + w.frame.minY, width: local.width, height: local.height)
    }
}
