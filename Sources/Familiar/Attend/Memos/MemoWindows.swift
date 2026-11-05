import AppKit
import Combine
import Foundation

/// Your notes on the screen: a panel for every note in the store, placed where the note says, a new one near the orb,
/// each kept as the note changes here or in its file, brought up when its when comes or for a glance at them all, and
/// all drawn at one size that Bigger and Smaller step through.
@MainActor
final class MemoWindows {
    let store: MemoStore
    private(set) var scale: CGFloat
    private let hideFromScreenShare: Bool
    /// Where the orb is, when it is on the screen: a new note goes just above it.
    var orbFrame: () -> NSRect? = { nil }
    var onScaleChange: ((CGFloat) -> Void)?
    var openPage: (String) -> Void = { page in if let url = URL(string: page) { NSWorkspace.shared.open(url) } }
    private(set) var panels: [String: MemoPanel] = [:]
    /// Whether panels are put on the screen; tests keep them off it.
    var shows = true
    private var subscriptions = Set<AnyCancellable>()
    private var ticker: Timer?
    /// While a glance lasts: the watch for a click anywhere else, which ends it.
    private var glanceMonitors: [Any] = []

    init(store: MemoStore, scale: CGFloat, hideFromScreenShare: Bool) {
        self.store = store
        self.scale = PaperLook.clamped(scale)
        self.hideFromScreenShare = hideFromScreenShare
    }

    func start() {
        sync()
        store.$all.receive(on: RunLoop.main).sink { [weak self] _ in self?.sync() }.store(in: &subscriptions)
        store.onWake = { [weak self] memo in self?.panels[memo.id]?.wake() }
        // The when words ("in 10 min") move with the clock, on the minute, as the menu bar's clock does.
        let timer = Timer(fire: Self.nextMinute(after: Date()), interval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// Every note reads its when against this moment.
    func tick(now: Date = Date()) {
        for panel in panels.values { panel.state.now = now }
    }

    /// Whether there is a note to show, and whether one is pinned.
    var hasNotes: Bool { !panels.isEmpty }
    var hasPinned: Bool { panels.values.contains { $0.memo.pinned } }
    var glancing: Bool { !glanceMonitors.isEmpty }

    /// A glance at your notes: every one comes up on top of everything where you are, pinned or lying on the desktop,
    /// and stays until you click somewhere else; then each goes back to its place. Pin one meanwhile and it stays.
    func showAll() {
        tick()
        for panel in panels.values {
            panel.raise()
            if shows { panel.orderFrontRegardless() }
        }
        guard glanceMonitors.isEmpty else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let elsewhere = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.endGlance() }
        }) { glanceMonitors.append(elsewhere) }
        if let here = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            if !(event.window is MemoPanel) { MainActor.assumeIsolated { self?.endGlance() } }
            return event
        }) { glanceMonitors.append(here) }
    }

    /// The glance is over: each note goes back to its place, but one that woke stays up until it is had, and one being
    /// written on settles when the writing ends.
    func endGlance() {
        for monitor in glanceMonitors { NSEvent.removeMonitor(monitor) }
        glanceMonitors = []
        for panel in panels.values where !panel.state.warm && !panel.state.editing { panel.settle() }
    }

    /// Every note lies down on the desktop, under your windows.
    func unpinAll() {
        for panel in panels.values { panel.pin(false) }
    }

    /// The next whole minute, a hair after it, so the words have moved once the menu bar's clock has.
    nonisolated static func nextMinute(after date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60 + 60.3)
    }

    /// A new note, blank unless given, placed near the orb and shown; a blank one opens for writing at once.
    @discardableResult
    func newNote(_ given: Memo? = nil) -> Memo {
        var memo = given ?? store.blank()
        if memo.at == nil { memo.at = spot() }
        store.save(memo)
        sync()
        if let panel = panels[memo.id], shows {
            panel.orderFrontRegardless()
            if memo.isBlank { panel.beginEditing() }
        }
        return memo
    }

    func setScale(_ next: CGFloat?) {
        guard let next else { return }
        scale = PaperLook.clamped(next)
        for panel in panels.values { panel.state.scale = scale }
        onScaleChange?(scale)
    }

    /// A panel for every note, none for a note that is gone, each showing the note as it is now.
    func sync() {
        let memos = store.all
        for memo in memos {
            if let panel = panels[memo.id] {
                panel.show(memo)
                if let at = memo.at, !panel.state.editing, panel.paperTopLeft != at { panel.place(topLeft: at); clamp(panel) }
            } else {
                add(memo)
            }
        }
        let ids = Set(memos.map(\.id))
        for (id, panel) in panels where !ids.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
        }
    }

    private func add(_ memo: Memo) {
        let panel = MemoPanel(memo: memo, scale: scale, hideFromScreenShare: hideFromScreenShare)
        panel.onChange = { [weak self] changed in
            guard let self else { return }
            var kept = changed
            if kept.isBlank { self.store.remove(kept.id, toTrash: false); return }
            if kept.at == nil { kept.at = panel.paperTopLeft }
            self.store.save(kept)
        }
        panel.onRemove = { [weak self] in self?.store.remove(memo.id) }
        panel.onResize = { [weak self] next in self?.setScale(next) }
        panel.onToggle = { [weak self] index in self?.store.toggle(memo.id, item: index) }
        panel.onOpenPage = { [weak self] page in self?.openPage(page) }
        panels[memo.id] = panel
        panel.place(topLeft: memo.at ?? spot())
        clamp(panel)
        if shows { panel.orderFrontRegardless() }
    }

    private func clamp(_ panel: MemoPanel) {
        guard let screen = FloatingWindowPlacement.screen(for: panel.frame, fallback: NSScreen.main) else { return }
        panel.setFrame(FloatingWindowPlacement.clamped(panel.frame, to: screen.visibleFrame), display: true)
    }

    /// Where a new note goes: above the orb, a little further along for each note already near there; else the top
    /// right of the main screen.
    func spot() -> NSPoint {
        let width = PaperLook.memoWidth * scale
        var top: NSPoint
        if let orb = orbFrame() {
            top = NSPoint(x: orb.midX - width / 2, y: orb.maxY + 12 + PaperLook.minHeight * scale)
        } else if let visible = NSScreen.main?.visibleFrame {
            top = NSPoint(x: visible.maxX - width - 40, y: visible.maxY - 40)
        } else {
            top = NSPoint(x: 100, y: 500)
        }
        let taken = store.all.compactMap(\.at)
        var tries = 0
        while taken.contains(where: { abs($0.x - top.x) < 12 && abs($0.y - top.y) < 12 }), tries < 12 {
            top.x += 22
            top.y -= 22
            tries += 1
        }
        return top
    }
}
