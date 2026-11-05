import AppKit
import Combine
import Foundation

/// Your notes on the screen: a panel for every note in the store, placed where the note says, a new one near the orb,
/// each kept as the note changes here or in its file, brought forward when its when comes, and all drawn at one size
/// that Bigger and Smaller step through.
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

    init(store: MemoStore, scale: CGFloat, hideFromScreenShare: Bool) {
        self.store = store
        self.scale = PaperLook.clamped(scale)
        self.hideFromScreenShare = hideFromScreenShare
    }

    func start() {
        sync()
        store.$all.receive(on: RunLoop.main).sink { [weak self] _ in self?.sync() }.store(in: &subscriptions)
        store.onWake = { [weak self] memo in self?.panels[memo.id]?.wake() }
        // The when words ("in 10 min") move with the clock.
        ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.panels.values.forEach { $0.state.now = Date() } }
        }
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
            if kept.isBlank { self.store.remove(kept.id); return }
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
