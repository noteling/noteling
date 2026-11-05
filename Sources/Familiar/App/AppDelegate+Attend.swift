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
        stickersPanel = stickers
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.placeRunStickers() }
            .store(in: &cancellables)
        stickersScreenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.placeRunStickers() } }
    }

    /// On the screen while a matter has something to show and the person hasn't hidden them: beside the orb only while
    /// the bubble is collapsed and there, at their own spot whatever the bubble does; away otherwise.
    func placeRunStickers() {
        guard let stickersPanel else { return }
        let shown = StickersPanel.shows(count: stickersPanel.model.count, hidden: stickersPanel.hidden, controlling: stickersPanel.hiddenForControl,
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
            let entry = WindowDragHandle.ClosureMenuItem(title: item.title) { [weak self] in self?.stickersPanel?.choose(item.choice) }
            entry.isEnabled = item.enabled
            if case .open(let id) = item.choice, let sticker = shown.first(where: { $0.id == id }) {
                entry.toolTip = sticker.line(now: Date())
            }
            submenu.addItem(entry)
        }
    }

    // MARK: your own notes

    /// Your notes: files in `memos/`, each a panel pinned where you put it. A new one comes from the hotkey, the menu
    /// bar, the bubble's menu, or the scribe in chat; the minister and the chat read them through recall.
    func setupMemos() {
        let store = MemoStore(directory: Config.dir.appendingPathComponent(MemoStore.folder))
        store.memory = matters?.memory ?? MemoryLog(directory: Config.dir.appendingPathComponent(MemoryLog.folder))
        memos = store
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

    /// The stickers were hidden from their own menu: a callout under the menu bar icon says where they come back from.
    func showStickersHiddenHint() {
        guard let target = statusItemRect else { return }
        hideHint.show(under: target, title: "The stickers are hidden", subtitle: "Stickers › Show Stickers, in this menu, brings them back", seconds: 4.5) { [weak self] in
            self?.stickersPanel?.hidden = false
            self?.placeRunStickers()
        }
    }
}
