import AppKit
import Combine
import SwiftUI

/// The Jobs window: every job in one list, a job's page, and a matter's page from its sticker. One floating panel,
/// where the person last left it, that takes the focus only when they click into it and gives it back to the app they
/// were in when it closes.
@MainActor final class JobsWindowController: NSObject, NSWindowDelegate, WindowDragHandling {
    let navigation = JobsNavigation()
    private let panel: JobsPanel
    private let placement = FloatingWindowPlacement("jobsWindow")
    private var topLeft: NSPoint?
    private var adjustingFrame = false
    private weak var draggedWindow: NSWindow?
    private var routeObservation: AnyCancellable?
    private var screenObservation: NSObjectProtocol?
    private var hiddenForForegroundGrant = false
    private var requested = false
    /// Opened, not already open: the app looks for a newer copy of the team's tools, so a job pushed a moment ago shows.
    var onOpen: (() -> Void)?

    /// Nothing opens at launch; opening is always an explicit action.
    init(folderJobs: FolderJobsPanel, setup: JobsSetup = JobsSetup(), hideFromScreenShare: Bool) {
        panel = JobsPanel(hideFromScreenShare: hideFromScreenShare)
        super.init()
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: JobsWindowView(navigation: navigation, folderJobs: folderJobs, setup: setup,
                                                                  close: { [weak self] in self?.hide() }))
        routeObservation = navigation.$route.receive(on: RunLoop.main).sink { [weak self] _ in self?.position() }
        position()
        screenObservation = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.position() } }
    }

    /// Jobs, every job in one list: from the menu bar's Jobs…, the chat's Open Jobs tab, or a notification whose job is gone.
    func showJobs() {
        navigation.route = .jobs
        open()
    }

    /// A job's page.
    func showFolderJob(id: UUID) {
        navigation.route = .folderJob(id)
        open()
    }

    /// A matter's page, from its sticker or its notification; Back goes to Jobs.
    func showMatter(id: String) {
        navigation.open(.matter(id), returningTo: .jobs)
        open()
    }

    /// The receipt, from the lamp or Jobs; Back goes to Jobs.
    func showReceipt() {
        navigation.open(.receipt, returningTo: .jobs)
        open()
    }

    /// The screen showing, for the ways in to check where they lead.
    var route: JobsNavigation.Route { navigation.route }
    var isVisible: Bool { panel.isVisible }

    /// While Noteling works in front of the person, the window is away; it comes back where it was, without taking focus.
    func setHiddenForForegroundGrant(_ hidden: Bool) {
        hiddenForForegroundGrant = hidden
        if hidden {
            panel.orderOut(nil)
        } else {
            position()
            if requested { panel.orderFrontRegardless() }
        }
    }

    func updateSharing(_ hideFromScreenShare: Bool) {
        panel.sharingType = hideFromScreenShare ? .none : .readOnly
    }

    func close() {
        routeObservation?.cancel()
        routeObservation = nil
        if let screenObservation { NotificationCenter.default.removeObserver(screenObservation) }
        screenObservation = nil
        panel.orderOut(nil)
        panel.close()
    }

    private func open() {
        let wasOpen = requested
        requested = true
        if !wasOpen { onOpen?() }
        position()
        guard !hiddenForForegroundGrant else { return }
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        requested = false
        panel.orderOut(nil)
    }

    /// The window hangs from its top-left corner, where the person last left it (or near the screen's top left the
    /// first time), and takes each screen's height, kept on the screen.
    private func position() {
        guard draggedWindow == nil, let fallback = FloatingWindowPlacement.screen(for: panel.frame, fallback: NSScreen.main) else { return }
        if topLeft == nil {
            if let saved = placement.restore(size: NSSize(width: Self.width, height: Self.preferredHeight(for: .jobs))) {
                topLeft = NSPoint(x: saved.minX, y: saved.maxY)
            } else {
                let visible = fallback.visibleFrame
                topLeft = NSPoint(x: visible.minX + 18, y: visible.maxY - 18)
            }
        }
        guard let anchor = topLeft else { return }
        let height = Self.preferredHeight(for: navigation.route)
        let requested = NSRect(x: anchor.x, y: anchor.y - height, width: Self.width, height: height)
        let screen = FloatingWindowPlacement.screen(for: requested, fallback: fallback) ?? fallback
        adjustingFrame = true
        defer { adjustingFrame = false }
        panel.setFrame(FloatingWindowPlacement.clamped(requested, to: screen.visibleFrame), display: true)
    }

    func windowDidMove(_ notification: Notification) {
        guard !adjustingFrame, draggedWindow == nil, NSEvent.pressedMouseButtons == 0,
              let window = notification.object as? NSWindow else { return }
        finishedDragging(window)
    }

    func beganDragging(_ window: NSWindow) { draggedWindow = window }

    func finishedDragging(_ window: NSWindow) {
        guard !adjustingFrame, window === panel, let screen = FloatingWindowPlacement.screen(for: window.frame) else { return }
        draggedWindow = nil
        adjustingFrame = true
        window.setFrame(FloatingWindowPlacement.clamped(window.frame, to: screen.visibleFrame), display: true)
        adjustingFrame = false
        topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        placement.save(window.frame)
        position()
    }

    /// One width for every screen, so moving between them never shifts the window sideways. It fits a file's row on a
    /// job's page: its name and size, and Open, Save as… and Show in Finder.
    static let width: CGFloat = 650

    /// A row per job, or a job's or a matter's page with its findings: one height for every screen.
    static func preferredHeight(for route: JobsNavigation.Route) -> CGFloat {
        switch route {
        case .jobs, .folderJob, .matter, .receipt: return 680
        }
    }
}

private final class JobsPanel: NSPanel {
    init(hideFromScreenShare: Bool) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: JobsWindowController.width, height: 680),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        title = "Jobs"
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        sharingType = hideFromScreenShare ? .none : .readOnly
        animationBehavior = .utilityWindow
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// A click on a button leaves the panel unfocused, so the app you're in keeps your typing. A right-click focuses it
    /// first, because a menu only opens in a window that has focus.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseDown, !isKeyWindow { makeKey() }
        super.sendEvent(event)
    }
}
