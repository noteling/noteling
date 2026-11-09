import AppKit
import Combine
import Foundation

/// Your notes on the screen: a panel for every note in the store, placed where the note says, a new one near the orb,
/// each kept as the note changes here or in its file, brought up for a moment when its time comes near, until clicked
/// when its when comes, and all together for a glance from a click on the orb; all drawn at one size that Bigger and
/// Smaller step through.
@MainActor
final class MemoWindows {
    let store: MemoStore
    private(set) var scale: CGFloat
    private let hideFromScreenShare: Bool
    /// Where the orb is, when it is on the screen: a new note goes just above it.
    var orbFrame: () -> NSRect? = { nil }
    var onScaleChange: ((CGFloat) -> Void)?
    var openPage: (String) -> Void = { page in if let url = URL(string: page) { NSWorkspace.shared.open(url) } }
    var clock: () -> Date = Date.init
    private(set) var panels: [String: MemoPanel] = [:]
    /// Whether panels are put on the screen; tests keep them off it.
    var shows = true
    private var subscriptions = Set<AnyCancellable>()
    private var ticker: Timer?
    private var spaceObserver: NSObjectProtocol?
    private var started = false
    /// How long a glance lasts, and a note's moment when its time comes near, unless something ends it sooner.
    static let glanceSeconds: TimeInterval = 20
    /// Every note is up for a look. It ends by itself, with a switch of Space, with another click on the orb, or when
    /// the chat or the pen opens.
    private(set) var glancing = false
    private var glanceEnd: DispatchWorkItem?
    /// The notes up on their own for a moment, by id: each when its time came near.
    private var moments: [String: DispatchWorkItem] = [:]

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
        // Another Space is another desk: a glance ends there, and the notes stay on theirs.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceChanged() }
        }
        started = true
        tick(now: clock())   // a note already within the hour of its time comes up for a moment, at launch as at the hour
    }

    /// Every note reads its when against this moment, and one whose time has just come within the hour comes up for a
    /// moment to say so: the heads-up before the wake, once.
    func tick(now: Date = Date()) {
        for panel in panels.values {
            panel.state.now = now
            guard let when = panel.memo.when, PaperWhen.state(when, now: now) == .near, !panel.headsUpGiven else { continue }
            panel.headsUpGiven = true
            moment(panel)
        }
    }

    /// Whether there is a note to show.
    var hasNotes: Bool { !panels.isEmpty }

    /// A glance at your notes: every one comes up on top of everything where you are and stays a moment; then each goes
    /// back to its place. It ends sooner with a switch of Space, another click on the orb, or the chat or the pen
    /// opening. A note you click meanwhile stays in front, as any window you touched does.
    func showAll() { show(ids: nil) }

    /// A glance at some of your notes, by id (the chat's "show my todos for this morning"); nil is all of them.
    func show(ids: Set<String>?) {
        tick(now: clock())
        for (id, panel) in panels where ids?.contains(id) ?? true {
            panel.raise()
            if shows { panel.orderFrontRegardless() }
        }
        glancing = true
        glanceEnd?.cancel()
        let end = DispatchWorkItem { [weak self] in self?.endGlance() }
        glanceEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.glanceSeconds, execute: end)
    }

    /// A click on the orb: the notes come up, or go back if they are up.
    func toggleGlance() {
        if glancing { endGlance() } else { showAll() }
    }

    /// The glance is over, and so is any note's moment: each goes back to its place, but one that woke stays up until
    /// it is had, and one being written on settles when the writing ends.
    func endGlance() {
        glanceEnd?.cancel()
        glanceEnd = nil
        glancing = false
        for work in moments.values { work.cancel() }
        moments = [:]
        for panel in panels.values where !panel.state.warm && !panel.state.editing { panel.settle() }
    }

    /// The person went to another Space: the glance ends, and the notes stay on theirs.
    func spaceChanged() { endGlance() }

    /// One note up on its own for a moment, as when its time comes near, opened if it slept folded; then back to its
    /// place, unless it woke, is being written on, or every note is up for a glance meanwhile.
    private func moment(_ panel: MemoPanel) {
        panel.unfold()
        panel.raise()
        if shows { panel.orderFrontRegardless() }
        let id = panel.memo.id
        moments[id]?.cancel()
        let end = DispatchWorkItem { [weak self, weak panel] in
            guard let self else { return }
            self.moments[id] = nil
            guard let panel, !self.glancing, !panel.state.warm, !panel.state.editing else { return }
            panel.settle()
        }
        moments[id] = end
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.glanceSeconds, execute: end)
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
        // A note made within the hour of its time is in front as it is made: no moment for it. At launch, every note is new
        // to the screen, so the first tick gives those within the hour theirs.
        if started, let when = memo.when, PaperWhen.state(when, now: clock()) == .near { panel.headsUpGiven = true }
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
