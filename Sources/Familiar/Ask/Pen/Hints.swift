import AppKit

/// Hints on the page in front, shown once the page holds still and following it: a small tag at each control someone
/// left a hint on, and the whole hint when the mouse comes to it. No model and no pixels: the page's own Accessibility
/// tree says where its controls are, and is read again when the page is scrolled, clicked or typed in, when its window
/// moves, and while a page is still settling after it came or was reloaded; a fresh page's marks go on only when two
/// looks a second apart put them in the same place. The pen's own stickers take over while it is up.
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
        /// The page said it was still loading: its controls may not all be there yet, or where they will be.
        var loading = false
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
    /// While a fresh page is still settling, the marks of the last look, not yet shown; nil once the page held still.
    /// A page just come, or loading again where it had finished, holds its marks until two looks agree.
    private var settling: [Mark]?
    /// The last reading said the page was still loading.
    private var loading = false
    /// How many marks the last report said were placed; nil before the first.
    private var reported: Int?
    private var lastHover = Date.distantPast
    private var windowFrame: NSRect?
    private var focus: AXUIElement?

    /// After the last turn of the wheel, before the page is read again.
    static let settle: TimeInterval = 0.25
    /// After a click or a key, which may have changed the page.
    static let afterInput: TimeInterval = 0.6
    /// How often the page is read again when something happened to it, or its window moved.
    static let heartbeatSeconds: TimeInterval = 3
    /// A page still settling is looked at again, a few times: one still loading, one whose controls aren't all there
    /// yet, one on which the marks moved since the last look (a page laying itself out after a reload or in a new
    /// tab). A fresh page's marks go on only once two looks agree, or when these looks run out. Every touch of the
    /// page starts the looks over.
    static let retryDelays: [TimeInterval] = [1, 2, 4]
    var retryDelays = HintsController.retryDelays

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
        reported = nil
        settling = []   // nothing shown until two looks agree
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
        focus = nil
        settling = nil
        loading = false
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
        let loading = reading?.loading == true
        if reported != marks.count {
            onPlaced?(marks.count, notes.count)
            let place = scene.url.flatMap(PageKey.of)?.description ?? scene.appName
            if let line = WandController.shortfall(reading?.notFound ?? [], of: notes.count, on: place) { Log.info(line) }
            reported = marks.count
        }
        // A page loading again where it had finished is a new document, a reload or another page at the address:
        // its marks are held like a fresh page's.
        if settling == nil, loading, !self.loading { settling = [] }
        self.loading = loading
        let before = settling ?? self.marks   // the last look: the one held while the page settles, else the one shown
        let moved = marks != before
        if let previous = settling {
            // A fresh page: a mark goes on once it is where the last look had it; all of them, where the last look
            // had them, once the looks run out.
            let steady = marks.filter { previous.contains($0) }
            if retries >= retryDelays.count || (!marks.isEmpty && steady.count == marks.count) {
                settling = nil
                show(marks)
            } else {
                settling = marks
                show(steady)
            }
        } else {
            show(marks)
        }
        // A page still settling is looked at again in a moment, a few times: some hint has nothing to stick to yet,
        // the page says it is still loading, the marks moved since the last look, or they are held until they stay.
        let missing = reading?.missing ?? notes.count
        if settling != nil || missing > 0 || loading || moved, retries < retryDelays.count {
            let delay = retryDelays[retries]
            retries += 1
            schedule(after: delay)
        }
    }

    /// These marks on the screen, when they are not the ones there.
    private func show(_ marks: [Mark]) {
        guard marks != self.marks else { return }
        self.marks = marks
        if let hovered, !marks.contains(where: { $0.note.id == hovered }) { self.hovered = nil }
        draw()
    }

    /// Something happened to the page (a key, a click, the wheel, a Space change, another element with the focus):
    /// it is read again, and gets its few looks to settle over again.
    func touch() {
        touched = true
        retries = 0
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
                self?.touch()
                self?.schedule(after: Self.afterInput)
            }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.hover(at: NSEvent.mouseLocation) }
        }) { monitors.append(monitor) }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.touch()
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
        touch()
        if !marks.isEmpty {   // stale at once: off until the page settles
            marks = []
            hovered = nil
            draw()
        }
        schedule(after: Self.settle)
    }

    /// Every few seconds: the page is read again if anything happened to it, its window moved, or another element
    /// has the focus, as when a reload brings a new document: the keystroke or click that asked for it was seen, but
    /// the page it brought may have come after the look that followed, and then nothing else would look again.
    private func beat() {
        guard let scene else { return }
        let front = Self.front(bundleID: scene.bundleID)
        let moved = windowFrame != nil && front.frame != windowFrame
        if let was = focus, let now = front.focus, !CFEqual(was, now) { touch() }
        windowFrame = front.frame
        focus = front.focus
        if touched || moved { read() }
    }

    private func screensChanged() {
        for panel in panels { panel.orderOut(nil) }
        panels = []
        draw()
    }

    /// The scene's front window's frame and the element with the focus, by a few attributes rather than a walk of
    /// the page: enough to notice the window moved, or that another document came.
    nonisolated static func front(bundleID: String) -> (frame: NSRect?, focus: AXUIElement?) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return (nil, nil) }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.2)
        let window = AX.element(axApp, kAXFocusedWindowAttribute) ?? AX.element(axApp, kAXMainWindowAttribute)
        let frame = window.flatMap { ScreenHitTester.axFrame(of: $0, primaryMaxY: NSScreen.screens.first?.frame.maxY ?? 0) }
        return (frame, AX.element(axApp, kAXFocusedUIElementAttribute))
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
                           notFound: placed.missing, loading: page.loading)
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
