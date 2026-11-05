import AppKit
import Combine

/// Attend: the jobs, what they find, and the stickers beside the note. The jobs kept as folders, yours and your team's;
/// the minister, which turns what they report into matters and stickers; the Jobs window, where every job, a job's
/// page and a matter's page are; and the stickers themselves.
extension AppDelegate {
    /// The menu bar's way into Jobs.
    static let jobsMenuTitle = "Jobs…"

    /// The folder jobs and the minister, and the Jobs window that shows them.
    func setupAttend() {
        setupFolderJobs()   // before the window, which shows them
        guard var panel = folderJobs?.panel else { return }
        panel.matters = matters
        panel.lessons = lessons
        jobsWindow = JobsWindowController(folderJobs: panel, setup: jobsSetup, hideFromScreenShare: config.hideFromScreenShare)
        jobsWindow.onOpen = { [weak self] in self?.linkedTools.checkSoon() }   // a job pushed a moment ago shows without a restart
        assistant.onOpenJobs = { [weak self] in self?.jobsWindow.showJobs() }
    }

    /// Once the packs have loaded: the jobs' schedule.
    func startAttend() {
        folderJobs?.start()   // only once the packs are loaded, so a job.py can import what they hold
    }

    /// What earlier versions left that this one no longer reads, and what follows the jobs' tick: the minister's matters
    /// follow the jobs (one turned off loses its stickers).
    func setupAttendHousekeeping() {
        RetiredMorning.cleanUp(home: Config.dir)
        folderJobs?.runner.onTick = { [weak self] in self?.minister?.reconcile() }
    }

    /// The menu bar's Jobs…: every job in one list.
    @objc func menuShowJobs() { jobsWindow.showJobs() }

    /// What only the app knows about the jobs: how to open Settings. (The runner knows the Keychain.)
    var jobsSetup: JobsSetup {
        JobsSetup(openSettings: { [weak self] in self?.openSettings() })
    }

    // MARK: jobs kept as folders

    /// Jobs kept as folders: yours in `jobs/`, your team's in the linked tools' `jobs/`, run on schedule, reporting
    /// their findings, with their tools in chat. Set up before the Jobs window, which shows them; the schedule starts
    /// once the packs have loaded (`startAttend`).
    func setupFolderJobs() {
        let notifier = JobNotifier()
        notifier.activate()
        let feature = FolderJobsFeature(registry: registry, notifier: notifier)
        notifier.onOpenJob = { [weak self, weak feature] id in
            guard let self, feature?.store.job(id: id) != nil else { self?.jobsWindow?.showJobs(); return }
            self.jobsWindow?.showFolderJob(id: id)
        }
        notifier.onOpenMatter = { [weak self] id in self?.jobsWindow?.showMatter(id: id) }
        assistant.folderJobs = feature.conversation
        folderJobs = feature
        setupMinister(feature, notifier: notifier)
    }

    /// The minister: the findings the jobs report become matters and stickers, in its two turns; an urgent sticker is
    /// also a notification; what a button on a finding came to stays on its matter and in the log.
    func setupMinister(_ feature: FolderJobsFeature, notifier: JobNotifier) {
        let memory = feature.runner.memory ?? MemoryLog(directory: Config.dir.appendingPathComponent(MemoryLog.folder))
        matters = Matters(directory: Config.dir.appendingPathComponent(Matters.folder))
        minister = Minister(matters: matters, memory: memory, store: feature.store, config: { [weak self] in self?.effectiveConfig ?? Config() })
        minister.recall = recall
        lessons = Lessons(file: Config.dir.appendingPathComponent(Matters.folder).appendingPathComponent(Lessons.fileName))
        minister.lessons = lessons
        minister.onUrgent = { [weak notifier] matter in
            notifier?.post(matter: matter.id, title: matter.jobName, body: matter.view?.text ?? "")
        }
        feature.runner.onFindings = { [weak self] job, change in self?.minister.notice(job, change: change) }
        feature.buttons.record = { [weak self] job, row, action, press in
            guard let self else { return }
            let ref = FindingRef(job: job, id: row.id)
            self.matters.record(press, on: ref)
            memory.append(["finding": ref.key, "matter": self.matters.matter(containing: ref)?.id ?? "", "pressed": action.label,
                           "said": MemoryLog.redacted(press.said), "failed": press.failed])
        }
    }

    // MARK: stickers

    /// The minister's cards as a deck beside the bubble: one at a time, with the verbs under it. The deck follows the
    /// orb and steps aside while the pad is open or the bubble is away, until the person drags it to a spot of their
    /// own, which is remembered, as its size is. Do it runs the card's action after a few seconds they can take back;
    /// Mine makes the card one of their notes; Not now puts it away; a click opens the matter.
    func setupRunStickers() {
        guard let feature = folderJobs else { return }
        let model = DeckModel(matters: matters)
        let store = feature.store, buttons = feature.buttons
        model.press = { matter, action in
            guard let job = store.jobs.first(where: { MemoryLog.name(of: $0) == action.finding.job }),
                  let chosen = job.actions.first(where: { $0.run == action.run }),
                  let row = FindingsSnapshot.read(store.findingsFile(for: job)).rows[action.finding.id]?.row else {
                return FindingPress(label: action.label, at: Date(), said: "Its finding or its job isn't here any more.", failed: true)
            }
            return await buttons.press(job, chosen, for: row)
        }
        model.mine = { [weak self] matter in
            guard let self, let windows = self.memoWindows, let view = matter.view else { return }
            var memo = self.memos.blank()
            memo.headline = view.headline
            memo.text = view.text
            memo.page = view.page
            memo.matter = matter.id
            windows.newNote(memo)
        }
        model.open = { [weak self] id in self?.jobsWindow.showMatter(id: id) }
        model.openMore = { [weak self] in self?.jobsWindow.showJobs() }
        model.lessons = lessons
        var home: NSPoint?
        if let x = config.stickersX, let y = config.stickersY, x.isFinite, y.isFinite { home = NSPoint(x: x, y: y) }
        let stickers = StickersPanel(model: model, look: StickersLook(scale: CGFloat(config.stickerScale)), home: home,
                                     hideFromScreenShare: config.hideFromScreenShare)
        stickers.onChange = { [weak self] in
            guard let self, let stickers = self.stickersPanel else { return }
            self.config.stickersX = stickers.home.map { Double($0.x) }
            self.config.stickersY = stickers.home.map { Double($0.y) }
            self.config.stickerScale = Double(stickers.look.scale)
            self.config.save()
            self.placeRunStickers()
        }
        stickers.onHide = { [weak self] in self?.showStickersHiddenHint() }
        stickers.onClose = { [weak self] in
            self?.deckOpen = false
            self?.placeRunStickers()
        }
        stickersPanel = stickers
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.deckChanged() }
            .store(in: &cancellables)
        shell.lampHidden = config.lampHidden
        shell.onLamp = { [weak self] in self?.lampClicked() }
        shell.onOpenJobs = { [weak self] in self?.jobsWindow.showJobs() }
        shell.onReceipt = { [weak self] in self?.jobsWindow.showReceipt() }
        shell.onHideLamp = { [weak self] in self?.hideLamp() }
        deckChanged()
        stickersScreenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.placeRunStickers() } }
    }

    /// The deck changed: the lamp follows it, the menu bar's dot too, and a deck that ran out closes by itself.
    func deckChanged() {
        guard let model = stickersPanel?.model else { return }
        let urgent = model.cards.contains(where: \.urgent)
        shell.lamp = LampState.of(count: model.needs, urgent: urgent)
        shell.lampWords = LampState.words(count: model.needs, urgent: urgent)
        updateStatusItemImage()
        if !model.hasSomethingToShow { deckOpen = false }
        placeRunStickers()
    }

    /// The lamp was clicked: the deck opens, or closes if it was open; with nothing on it, the receipt opens instead.
    func lampClicked() {
        guard let model = stickersPanel?.model else { return }
        if model.count + model.asks == 0 { jobsWindow.showReceipt(); return }
        deckOpen.toggle()
        if deckOpen { stickersPanel?.hidden = false }
        placeRunStickers()
    }

    /// Hidden from its own menu, until Show the Lamp in the menu bar's Stickers.
    func hideLamp() {
        shell.lampHidden = true
        config.lampHidden = true
        config.save()
    }

    func showLamp() {
        shell.lampHidden = false
        config.lampHidden = false
        config.save()
    }

    /// The pencil in the menu bar carries a dot the colour of the lamp while something needs the person.
    func updateStatusItemImage() {
        guard let button = statusItem?.button else { return }
        button.image = Self.statusImage(lamp: shell.lamp)
    }

    /// The menu bar's pencil, with a dot at its foot when the lamp is warm or hot.
    nonisolated static func statusImage(lamp: LampState) -> NSImage? {
        guard let pencil = NSImage(systemSymbolName: "pencil.tip", accessibilityDescription: "Noteling") else { return nil }
        pencil.isTemplate = true
        guard lamp != .off else { return pencil }
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            pencil.draw(in: NSRect(x: 1, y: 1, width: 16, height: 16))
            let dot = NSBezierPath(ovalIn: NSRect(x: rect.maxX - 7, y: 0, width: 7, height: 7))
            (lamp == .hot ? NSColor(red: 0.95, green: 0.40, blue: 0.25, alpha: 1) : NSColor(red: 0.98, green: 0.72, blue: 0.25, alpha: 1)).setFill()
            dot.fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// On the screen while the person opened the deck and a card is on it and they haven't hidden it: beside the orb
    /// only while the bubble is collapsed and there, at its own spot whatever the bubble does; away otherwise.
    func placeRunStickers() {
        guard let stickersPanel else { return }
        let shown = StickersPanel.shows(count: stickersPanel.model.hasSomethingToShow ? max(stickersPanel.model.count, 1) : 0, opened: deckOpen,
                                        hidden: stickersPanel.hidden, controlling: stickersPanel.hiddenForControl,
                                        detached: stickersPanel.isDetached, bubbleVisible: panel.isVisible, alpha: panel.alphaValue,
                                        expanded: shell.expanded, flying: origami.isFlying)
        guard shown else { stickersPanel.orderOut(nil); return }
        stickersPanel.place(besideOrb: panel.frame, on: panel.screen)
        stickersPanel.orderFrontRegardless()
    }

    /// The menu bar's Stickers submenu, filled as the menu opens: each sticker to open it, Hide Stickers or Show
    /// Stickers, and Put back beside Noteling once the stack was moved; its title carries the count.
    func updateStickersMenu() {
        guard let submenu = stickersMenuItem.submenu else { return }
        let shown = stickersPanel?.model.cards ?? [], hidden = stickersPanel?.hidden == true
        stickersMenuItem.title = StickersPanel.menuBarTitle(count: shown.count, hidden: hidden)
        submenu.autoenablesItems = false
        submenu.removeAllItems()
        for item in StickersPanel.menuBar(stickers: shown, hidden: hidden, detached: stickersPanel?.isDetached == true) {
            guard let item else { submenu.addItem(.separator()); continue }
            let entry = WindowDragHandle.ClosureMenuItem(title: item.title) { [weak self] in
                guard let self else { return }
                if case .show = item.choice { self.deckOpen = true }
                self.stickersPanel?.choose(item.choice)
            }
            entry.isEnabled = item.enabled
            if case .open(let id) = item.choice, let sticker = shown.first(where: { $0.id == id }) {
                entry.toolTip = sticker.line(now: Date())
            }
            submenu.addItem(entry)
        }
        if shell.lampHidden {
            submenu.addItem(.separator())
            submenu.addItem(WindowDragHandle.ClosureMenuItem(title: "Show the Lamp") { [weak self] in self?.showLamp() })
        }
    }

    // MARK: your own notes

    /// Your notes: files in `memos/`, each a panel pinned where you put it. A new one comes from the menu bar, the
    /// bubble's menu, or the scribe in chat; the same menus bring them all up; the minister and the chat read them
    /// through recall.
    func setupMemos() {
        let store = MemoStore(directory: Config.dir.appendingPathComponent(MemoStore.folder))
        store.memory = matters?.memory ?? MemoryLog(directory: Config.dir.appendingPathComponent(MemoryLog.folder))
        memos = store
        Log.info("notes: \(store.all.count) in \(MemoStore.folder)/")
        let windows = MemoWindows(store: store, scale: CGFloat(config.memoScale), hideFromScreenShare: config.hideFromScreenShare)
        windows.orbFrame = { [weak self] in
            guard let self, self.panel.isVisible, !self.shell.expanded else { return nil }
            return self.panel.frame
        }
        windows.onScaleChange = { [weak self] scale in
            self?.config.memoScale = Double(scale)
            self?.config.save()
        }
        windows.start()
        memoWindows = windows
        shell.onNewNote = { [weak self] in self?.newNote() }
        shell.onShowMyNotes = { [weak self] in self?.showNotes() }
        store.$all.receive(on: RunLoop.main).sink { [weak self] all in self?.shell.noteCount = all.count }.store(in: &cancellables)
        // The scribe: "remind me to…" on the pad puts the paper up at once, and the model writes it properly.
        let scribe = MemoScribe(store: store, windows: windows)
        memoScribe = scribe
        assistant.extraRoutes = { [weak scribe] in scribe?.routes() ?? [] }
        assistant.onQuestion = { [weak scribe] question, ctx in scribe?.began(question, page: ctx?.url) }
        assistant.onTurnEnd = { [weak scribe] in scribe?.turnEnded() }
    }

    /// A blank note of your own, near the orb, open for writing.
    func newNote() { memoWindows?.newNote() }

    @objc func menuNewNote() { newNote() }

    /// Every note of yours comes up for a minute: they live on the desktop, under your windows, and this is how you see
    /// them when you want to.
    func showNotes() { memoWindows?.showAll() }

    @objc func menuShowNotes() { showNotes() }

    /// The stickers were hidden from their own menu: a callout under the menu bar icon says where they come back from.
    func showStickersHiddenHint() {
        guard let target = statusItemRect else { return }
        hideHint.show(under: target, title: "The stickers are hidden", subtitle: "Stickers › Show Stickers, in this menu, brings them back", seconds: 4.5) { [weak self] in
            self?.stickersPanel?.hidden = false
            self?.placeRunStickers()
        }
    }
}
