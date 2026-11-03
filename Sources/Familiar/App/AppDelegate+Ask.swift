import AppKit
import Combine
import SwiftUI

/// Ask: the pen and the chat. The note on the screen (the bubble, its hiding place in the menu bar and its flights as a
/// crane), the chat behind it, the watcher that knows what is in front, the pen and the notes it leaves, and the page
/// briefs.
extension AppDelegate {
    /// The chat and what it is told about: notes, briefs, and the bubble's own gestures.
    func setupAsk() {
        // A tools folder of one's own gives its notes up once; one outside Noteling's folder may be shared, so its
        // notes are copied and the file stays for the others.
        let ownTools = config.resolvedToolsDir.standardizedFileURL.path.hasPrefix(Config.dir.standardizedFileURL.path)
        notesStore.moveNotes(fromPacksIn: config.resolvedToolsDir, rename: ownTools)
        if let linked = registry.linkedRoot { notesStore.moveNotes(fromPacksIn: linked, rename: false) }   // the team's notes
        registry.notesStore = notesStore
        briefs = PageBriefs(registry: registry)
        assistant = Assistant(config: effectiveConfig, watcher: watcher, registry: registry, shell: shell, learning: learning, execution: execution, desktop: desktop)
        assistant.briefs = briefs
        assistant.onStartWand = { [weak self] in self?.startWand() }
        assistant.onCancelWand = { [weak self] in if self?.wand.isActive == true { self?.wand.cancel() } }
        assistant.onOpenSettings = { [weak self] in self?.openSettings() }
        shell.onHideBubble = { [weak self] in self?.hideBubbleWithHint() }
        shell.onDragBubble = { [weak self] phase in
            guard let self else { return }
            let mouse = NSEvent.mouseLocation
            switch phase {
            case .moved:
                if self.dragOffset == nil {
                    self.dragOffset = NSPoint(x: mouse.x - self.panel.frame.origin.x, y: mouse.y - self.panel.frame.origin.y)
                }
                let o = self.dragOffset!
                self.panel.setFrameOrigin(NSPoint(x: mouse.x - o.x, y: mouse.y - o.y))
                self.placeRunStickers()
            case .ended:
                self.dragOffset = nil
                self.config.bubbleX = self.panel.frame.origin.x
                self.config.bubbleY = self.panel.frame.origin.y
                self.config.save()
                self.placeRunStickers()
            }
        }
        shell.onOpenSettings = { [weak self] in self?.openSettings() }
        if let w = config.cardWidth, let h = config.cardHeight, w >= 340, h >= 400 {
            shell.cardSize = NSSize(width: w, height: h)
        }
        shell.onResizeCard = { [weak self] size, done in
            guard let self else { return }
            self.shell.cardSize = size
            if self.shell.expanded { self.panel.resizeKeepingTopLeft(to: size) }
            if done { self.config.cardWidth = size.width; self.config.cardHeight = size.height; self.config.save() }
        }
        shell.onToggleLarge = { [weak self] in
            guard let self else { return }
            let large = BubblePanel.largeExpandedSize
            let target = self.shell.cardSize.height >= large.height - 1 ? BubblePanel.defaultExpandedSize : large
            self.shell.onResizeCard?(target, true)
        }
        shell.onPoke = { [weak self] in
            guard let self, self.config.pokeHintsShown < 3 else { return }
            self.config.pokeHintsShown += 1
            self.config.save()
            self.hideHint.show(under: self.panel.frame, title: "Double-click to chat", subtitle: "Hold the note to pick up the pen", seconds: 2.5) { [weak self] in
                self?.shell.expanded = true
            }
        }
    }

    // MARK: the bubble

    func setupPanel() {
        panel = BubblePanel(hideFromScreenShare: config.hideFromScreenShare)
        let host = NSHostingView(rootView: BubbleView(state: assistant, shell: shell, onOrigami: { [weak self] in self?.takeOrigamiFlight() }))
        host.frame = NSRect(origin: .zero, size: BubblePanel.collapsedSize)
        panel.contentView = host
        if let x = config.bubbleX, let y = config.bubbleY,
           NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -20, dy: -20).contains(NSPoint(x: x + 42, y: y + 42)) }) {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.placeAtBottomRight()
        }
        panel.orderFrontRegardless()

        shell.$expanded
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] expanded in
                guard let self else { return }
                if self.origami.isFlying {
                    if expanded { self.origami.cancel() } else { return }
                }
                self.panel.resize(to: expanded ? self.shell.cardSize : BubblePanel.collapsedSize, animate: false)
                if expanded {
                    if self.shell.consumeQuietExpand() { self.panel.orderFrontRegardless() } else { self.panel.makeKeyAndOrderFront(nil) }
                } else { self.panel.orderFrontRegardless(); self.panel.resignKey() }
                self.placeRunStickers()
            }
            .store(in: &cancellables)

        assistant.$chatBusy.combineLatest(learning.$phase)
            .receive(on: RunLoop.main)
            .sink { [weak self] chatBusy, phase in
                if chatBusy || phase == .recording || phase == .stopping || phase == .summarizing || phase == .saving { self?.origami.cancel() }
            }
            .store(in: &cancellables)
    }

    @objc func openChat() {
        origami.cancel()
        if !panel.isVisible { showBubble() }
        shell.expanded = true
        MainThreadDiagnostics.shared.mark(.chatPanelShown, itemCount: assistant.transcript.count)
    }

    @objc func menuHideBubble() { if panel.isVisible || origami.isFlying { hideBubbleWithHint() } }

    /// Always available: bring the bubble back, or if it is already on screen, bring it to the front and hop.
    @objc func menuShowBubble() {
        origami.cancel()
        if panel.isVisible {
            panel.orderFrontRegardless()
            hop()
        } else {
            showBubble()
        }
    }

    func hop() {
        let home = panel.frame
        var up = home; up.origin.y += 18
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16; ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.panel.animator().setFrame(up, display: true)
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22; ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.panel.animator().setFrame(home, display: true)
            }
        })
    }

    /// Fly the bubble into the menu bar icon, pulse the icon, and show a callout saying where it went.
    func hideBubbleWithHint() {
        origami.cancel()
        shell.expanded = false
        wand.deactivate()
        stickersPanel?.orderOut(nil)
        guard let target = statusItemRect else { panel.orderOut(nil); return }
        let start = panel.frame
        savedBubbleFrame = start
        let end = NSRect(x: target.midX - 10, y: target.minY - 6, width: 20, height: 20)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.panel.animator().setFrame(end, display: true)
            self.panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.stickersPanel?.orderOut(nil)
            self.panel.alphaValue = 1
            self.panel.setFrame(start, display: false)
            self.hideHint.show(under: target) { [weak self] in self?.showBubble() }
            self.pulseStatusItem(remaining: 3)
        })
    }

    func showBubble() {
        origami.cancel()
        hideHint.dismiss(animated: true)
        guard !panel.isVisible else { return }
        let dest = savedBubbleFrame ?? panel.frame
        if let target = statusItemRect {
            panel.setFrame(NSRect(x: target.midX - 10, y: target.minY - 6, width: 20, height: 20), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.panel.animator().setFrame(dest, display: true)
                self.panel.animator().alphaValue = 1
            }
        } else {
            panel.setFrame(dest, display: true)
            panel.orderFrontRegardless()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.placeRunStickers() }
    }

    // MARK: the crane

    var canTakeOrigamiFlight: Bool {
        !assistant.busy && !assistant.watching && !control.active && !wand.isActive
    }

    @objc func takeOrigamiFlight() {
        if origami.isFlying { origami.cancel(); return }
        guard canTakeOrigamiFlight else { return }
        hideHint.dismiss(animated: false)
        shell.expanded = false
        // Collapse synchronously before measuring home. The published resize skips a flight already in progress.
        panel.resize(to: BubblePanel.collapsedSize, animate: false)
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let home = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let started = origami.start(home: home, screen: screen, hideFromScreenShare: config.hideFromScreenShare) { [weak self] in
            guard let self else { return }
            // A disconnected/resized display must not leave even part of the note beyond the desktop.
            let center = CGPoint(x: self.panel.frame.midX, y: self.panel.frame.midY)
            let screens = NSScreen.screens
            let destination = screens.first { $0.visibleFrame.contains(center) } ?? screens.min {
                hypot($0.visibleFrame.midX - center.x, $0.visibleFrame.midY - center.y)
                    < hypot($1.visibleFrame.midX - center.x, $1.visibleFrame.midY - center.y)
            }
            if let bounds = destination?.visibleFrame {
                let frame = self.panel.frame
                self.panel.setFrameOrigin(CGPoint(
                    x: min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width)),
                    y: min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height))
                ))
            }
            self.panel.orderFrontRegardless()
            self.placeRunStickers()
            Log.info("origami: returned home")
        }
        if started {
            panel.orderOut(nil)
            placeRunStickers()
            Log.info("origami: folding for a flight")
        }
    }

    // MARK: the watcher

    func setupWatcher() {
        watcher.onChange = { [weak self] ctx in
            guard let self else { return }
            if self.wand.isShowingNotes { self.wand.hideNotes() }   // another page: its notes go with it
            self.briefs.prefetch(ctx)   // a page whose pack briefs it: read it now, so the pen answers without waiting
            let here = self.registry.notes(for: ctx)
            self.assistant.notesHere = here
            if !here.isEmpty {
                self.notesUsage.record("arrive", counts: ["notes": here.count, "warnings": here.filter(\.isWarning).count], notes: here.map(\.id))
            }
            self.assistant.inFront = ctx
            guard !self.assistant.watching else { return }   // the line reads "Watching…" while recording
            self.assistant.contextLine = ctx.summaryLine
        }
        if config.watcherEnabled { watcher.start(interval: config.watcherIntervalSeconds) } else { assistant.contextLine = "Watcher off" }
    }

    @objc func toggleWatcher() {
        if watcher.isRunning { watcher.stop(); assistant.contextLine = "Watcher off" } else { watcher.start(interval: config.watcherIntervalSeconds) }
        config.watcherEnabled = watcher.isRunning
        config.save()
    }

    // MARK: the pen and its notes

    func setupWand() {
        wand.onPick = { [weak self] target in
            guard let self else { return }
            if !self.panel.isVisible { self.showBubble() }
            self.assistant.wandPick(target)
            // The pad asks what about it: take the keyboard so the question can be typed straight away.
            if self.shell.expanded { self.panel.makeKeyAndOrderFront(nil) }
        }
        assistant.onCaptured = { [weak self] moment in
            CaptureFlash.show(moment, toward: self?.panel.isVisible == true ? self?.panel.frame : nil)
        }
        wand.sceneProvider = { [weak self] in self?.watcher.sample() ?? self?.watcher.current }
        wand.notesProvider = { [weak self] ctx in self?.registry.notes(for: ctx) ?? [] }
        wand.author = { [weak self] in self.map { NoteStore.author($0.config) } ?? NSFullUserName() }
        wand.onNoteSave = { [weak self] note in self?.assistant.saveNote(note) }
        wand.onNoteDelete = { [weak self] id in self?.assistant.deleteNote(id) }
        assistant.onNotesChanged = { [weak self] in
            guard let self else { return }
            self.assistant.notesHere = self.registry.notes(for: self.watcher.current)
        }
        assistant.notesUsage = notesUsage
        assistant.onShowNotes = { [weak self] in self?.toggleNotes(via: "badge") }
        wand.checksProvider = { [weak self] ctx in
            // Scripts of the packs for this scene that need no arguments: what a note's claim can be tested with.
            guard let self else { return [] }
            return self.registry.select(for: ctx).active.flatMap { pack in
                pack.scripts.filter { ($0.inputSchema["required"] as? [String] ?? []).isEmpty }.map { script in
                    NoteEditor.CheckChoice(script: script.id, title: "\(script.id.components(separatedBy: "__").last ?? script.id) (\(pack.name))")
                }
            }
        }
        wand.onPlaced = { [weak self] placed, notOnScreen, shown in
            self?.notesUsage.record("placed", counts: ["placed": placed, "notOnScreen": notOnScreen], tags: ["mode": shown ? "shown" : "pen"])
        }
        wand.hideFromScreenShare = config.hideFromScreenShare
        notesShortcut.onPress = { [weak self] in self?.toggleNotes(via: "shortcut") }
        if config.notesShortcut { notesShortcut.start() }
    }

    func startWand() {
        origami.cancel()
        guard !assistant.watching else { assistant.startWand(); return }   // no-op with a status line
        guard !assistant.busy else { shell.expanded = true; return }
        shell.expanded = false
        wand.activate()
    }

    @objc func menuWand() { startWand() }

    /// Shows the notes on the screen in front, or puts them away, and notes how it was asked for.
    func toggleNotes(via: String) {
        guard !wand.isActive else { return }
        if wand.isShowingNotes {
            wand.hideNotes()
            notesUsage.record("hide", tags: ["via": via])
        } else {
            notesUsage.record("show", counts: ["notes": assistant.notesHere.count], tags: ["via": via])
            wand.showNotes()
        }
    }
}
