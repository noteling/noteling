import AppKit
import Combine

/// Attend: the jobs, what they find, and the stickers beside the note. The jobs kept as folders, the reading jobs (mail,
/// calendars, pages), the stickers, and, until the minister replaces it, Morning Files with its cards, the card step,
/// the cards inbox and the one-week attention test.
extension AppDelegate {
    /// The menu bar's way into Jobs.
    static let jobsMenuTitle = "Jobs…"

    /// The card queue, the reading jobs and the card step, the folder jobs, and the Morning panel that shows them all.
    func setupAttend() {
        morningTasks = MorningTaskRunner(store: morning, desktop: desktop, registry: registry,
                                        activities: activities, config: { [weak self] in self?.effectiveConfig ?? Config() })
        calendarReader = CalendarCollectionRunner(store: calendarSources, desktop: desktop, registry: registry,
                                                  activities: activities, config: { [weak self] in self?.effectiveConfig ?? Config() })
        cardGeneration = CardGenerationService(morning: morning, sources: calendarSources, desktop: desktop,
                                               config: { [weak self] in self?.effectiveConfig ?? Config() })
        cardGeneration.onSorted = { [weak self] observations, runIDs in
            guard let self else { return }
            self.attention.recordSorted(observations, runIDs: runIDs, runs: self.calendarSources.runStore, cards: self.morning.cards)
        }
        attention.onTaught = { [weak self] facts, change in try? self?.morning.teach(facts, change) }
        attention.backfill(receipts: morning.workspace.cardGenerations ?? [], sources: calendarSources, cards: morning.cards)
        attention.watch(morning)
        calendarReader.trackedItems = { [weak self] sourceID in self?.morning.trackedItems(sourceID: sourceID) ?? [] }
        calendarReader.openSource = { await SourcePageOpener().prepare($0) }
        calendarReader.onRunFinished = { [weak self] runID in _ = self?.cardGeneration.generate(runID: runID) }
        calendarReader.sortedRunIDs = { [weak self] in Set((self?.morning.workspace.cardGenerations ?? []).flatMap(\.runIDs)) }
        let cardConversation = CardConversation(store: morning)
        cardConversation.onHandoff = { [weak self] _ in self?.morningTasks.wake() }
        assistant.cardConversation = cardConversation
        let sourceConversation = SourceConversation(store: calendarSources)
        sourceConversation.isRunning = { [weak self] in self?.calendarReader.isRunning ?? false }
        sourceConversation.sourceScripts = { [weak self] in
            guard let registry = self?.registry else { return [] }
            return registry.sourceScripts().map { pack, script in
                SourceScript(id: script.id, pack: pack.name, description: script.description,
                             missingSecrets: registry.missingRequirements(for: [pack]).first?.keys ?? [])
            }
        }
        assistant.sourceConversation = sourceConversation
        assistant.onOpenJobs = { [weak self] in self?.morningPanel.showJobs(trigger: .chat) }
        assistant.onRunSource = { [weak self] id in self?.runSavedSource(id) }
        setupFolderJobs()   // before the panel, which shows them among the jobs
        morningPanel = MorningPanelController(store: morning, hideFromScreenShare: config.hideFromScreenShare,
                                             calendarSources: calendarSources, calendarRunner: calendarReader, cardGeneration: cardGeneration,
                                             attention: attention, jobs: jobsSetup,
                                             showLauncher: config.morningFolderOnScreen, folderJobs: folderJobs?.panel)
        morningPanel.onLauncherShownChanged = { [weak self] shown in
            guard let self else { return }
            self.config.morningFolderOnScreen = shown
            self.config.save()
        }
        morningPanel.onDiscussCard = { [weak self] card in
            guard let self, self.assistant.discussCard(card) else { return }
            self.openChat()
        }
        morningPanel.handoffDestination = { [weak self] in self?.taskPanel.landingFrame }
        morningPanel.onOpen = { [weak self] in self?.linkedTools.checkSoon() }   // a job pushed a moment ago shows without a restart
        morningPanel.onHandoff = { [weak self] _ in
            guard let self else { return }
            self.morningTasks.wake()
        }
    }

    /// Once the packs have loaded: the card queue, the card step and the jobs' schedule.
    func startAttend() {
        morningTasks.start()
        cardGeneration.start()
        folderJobs?.start()   // only once the packs are loaded, so a job.py can import what they hold
    }

    @objc func menuShowMorning() { morningPanel.show() }
    /// The little Morning folder on the screen, put away or brought back; Morning Files still opens from the menu.
    @objc func toggleMorningFolder() { morningPanel.setLauncherShown(!morningPanel.launcherShown) }
    @objc func menuShowPeople() { morningPanel.showPeople() }

    /// The chat's Run now tab: run one reading job, then show it on its page in Jobs, where its progress, results and
    /// cards are.
    func runSavedSource(_ id: UUID) {
        let started: Task<Void, Never>?
        if let source = calendarSources.readingSources.first(where: { $0.id == id }) {
            started = calendarReader.collect(source: source)
        } else if let source = calendarSources.sources.first(where: { $0.id == id }) {
            started = calendarReader.collect(source: source, day: Date())
        } else {
            assistant.status = "That job is no longer in Jobs."
            return
        }
        assistant.status = started == nil ? (calendarReader.error ?? "That job could not start.") : "Running your job. Its page in Jobs shows how it goes."
        morningPanel.showSourceJob(id: id)
    }

    /// What only the app knows about the jobs: the secrets each still needs in Settings, whether mouse and keyboard
    /// control is on, and how to open Settings.
    var jobsSetup: JobsSetup {
        JobsSetup(missingSecrets: { [weak self] source in
            guard let registry = self?.registry, let script = source.script, let pack = registry.pack(holdingScript: script) else { return [] }
            return registry.missingRequirements(for: [pack]).first?.keys ?? []
        }, controlAllowed: { [weak self] in
            self?.effectiveConfig.allowControl ?? true
        }, openSettings: { [weak self] in self?.openSettings() })
    }

    // MARK: jobs kept as folders

    /// Jobs kept as folders: yours in `jobs/`, your team's in the linked tools' `jobs/`, run on schedule, with a card
    /// while their output has a preview, a notification when it has something new, and their tools in chat. Set up
    /// before the Morning panel, which shows them; the schedule starts once the packs have loaded (`startAttend`).
    func setupFolderJobs() {
        let notifier = JobNotifier()
        notifier.activate()
        let feature = FolderJobsFeature(registry: registry, notifier: notifier)
        notifier.onOpenJob = { [weak self, weak feature] id in
            guard let self, let job = feature?.store.job(id: id) else { self?.morningPanel?.showJobs(); return }
            let card = CardInboxFormat.cardID(FolderJobCards.key(for: job))
            if self.morning.cards.contains(where: { $0.id == card }) { self.morningPanel?.showCard(id: card, trigger: nil) }
            else { self.morningPanel?.showFolderJob(id: id) }
        }
        assistant.folderJobs = feature.conversation
        folderJobs = feature
    }

    /// The menu bar's Jobs…: every job, the reading jobs and those kept as folders, in one list.
    @objc func menuShowJobs() { morningPanel.showJobs() }

    // MARK: run stickers

    /// A job's latest finding as a sticky note beside the bubble, from whoever shared the job: the stickers follow the
    /// orb, step aside while the pad is open or the bubble is away, and a click opens the job's page.
    func setupRunStickers() {
        let model = RunStickers(file: Config.dir.appendingPathComponent("job-results/stickers.json"))
        runStickers = model
        stickersPanel = RunStickersPanel(model: model, hideFromScreenShare: config.hideFromScreenShare,
                                         open: { [weak self] id in self?.morningPanel.showFolderJob(id: id) },
                                         more: { [weak self] in self?.morningPanel.showJobs() },
                                         putAway: { [weak model] id in model?.putAway(id) })
        model.$stickers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.placeRunStickers() }
            .store(in: &cancellables)
        stickersScreenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.placeRunStickers() } }
        refreshRunStickers()
    }

    /// The jobs as they stand: at launch, at each tick and after each run.
    func refreshRunStickers() {
        guard let jobs = folderJobs?.store.jobs else { return }
        runStickers?.update(jobs)
    }

    /// Beside the orb while the bubble is collapsed and on the screen and a job has something to show; away otherwise.
    func placeRunStickers() {
        guard let stickersPanel, let runStickers else { return }
        let shown = RunStickersPanel.shows(bubbleVisible: panel.isVisible, alpha: panel.alphaValue, expanded: shell.expanded,
                                           flying: origami.isFlying, count: runStickers.stickers.count)
        guard shown else { stickersPanel.orderOut(nil); return }
        stickersPanel.place(besideOrb: panel.frame, on: panel.screen)
        stickersPanel.orderFrontRegardless()
    }

    // MARK: cards inbox

    /// Cards that scripts and jobs write into `cards/inbox/`, picked up into Morning Files at the jobs' tick, after each
    /// run, right after a job's card changes, and after a press of a button on a job's card. A card's buttons open its
    /// page, ask about it in chat, or run a function of its job's job.py. What watches wrote there goes first: they no
    /// longer run.
    func setupCardInbox() {
        RetiredWatchCards.cleanUp(inbox: Config.dir.appendingPathComponent("cards/inbox"))
        let inbox = CardInbox(store: morning)
        inbox.folderName = { [weak self] source in self?.folderJobs?.cardFolderName(source) }
        inbox.held = { [weak self] source in self?.folderJobs?.holds(source) ?? false }
        folderJobs?.runner.onTick = { [weak inbox, weak self] in inbox?.scan(); self?.refreshRunStickers() }
        folderJobs?.runner.onCardsChanged = { [weak inbox, weak self] in inbox?.scan(); self?.refreshRunStickers() }
        // A card's button that runs its job's code: what it came to stays on the card, and the card follows its file.
        folderJobs?.buttons.onCardsChanged = { [weak inbox] in inbox?.scan() }
        folderJobs?.buttons.record = { [weak self] id, press in
            do { try self?.morning.recordPress(cardID: id, press) }
            catch { Log.info("cards: couldn't keep what a button came to: \(error.localizedDescription)") }
        }
        morningPanel.onAskAboutCard = { [weak self] card, question in self?.askAboutCard(card, question: question) }
        cardInbox = inbox
        inbox.scan()
    }

    /// A card's question button asks about the card in chat.
    func askAboutCard(_ card: MorningCard, question: String) {
        guard assistant.discussCard(card) else { return }
        openChat()
        assistant.question = question
        assistant.ask()
    }
}
