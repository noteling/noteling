import AppKit
import Carbon.HIToolbox
import Combine
import FamiliarRuntime
import SwiftUI

/// The composition root: the one place that knows all three products and wires them to each other. Ask (the pen and
/// the chat), Act (Teach me and Do it for me, in front of the person or in the background) and Attend (jobs, what they
/// find, and the stickers) each set themselves up in their own file (`AppDelegate+Ask`, `+Act`, `+Attend`). This file
/// holds what is the app's own: the launch sequence, the menus, the hotkey, Settings, a team's setup file, and the
/// shared harness every product runs on (the scripts, the team's tools, the secrets).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var config = Config.load()
    var statusItem: NSStatusItem!
    var hotKey: HotKey?
    var cancellables = Set<AnyCancellable>()

    // The harness: scripts, the team's tools, and the secrets their scripts make.
    var runner: ScriptRunner!
    var registry: ToolRegistry!
    /// The four reading tools, for the chat and the minister.
    var recall: Recall!
    lazy var linkedTools = LinkedToolsUpdater(config: { [weak self] in self?.config ?? Config() })
    /// Your settings with the Claude settings the team's tools set: what reaches Claude. Never saved; `config` is.
    var effectiveConfig: Config { config.applying(linkedTools.team.settings) }
    let settings = SettingsWindowController()

    // Ask: the note on the screen, the chat, the pen and its notes.
    var panel: BubblePanel!
    var assistant: Assistant!
    let shell = ShellState()
    let watcher = ContextWatcher()
    let wand = WandController()
    let notesStore = NotesStore()
    var briefs: PageBriefs!
    let notesShortcut = NotesShortcut()
    let notesUsage = NotesUsageLog()
    let hideHint = HideHint()
    let origami = OrigamiFlightController()
    var savedBubbleFrame: NSRect?
    var dragOffset: NSPoint?     // cursor position relative to the panel origin while dragging

    // Act: mouse and keyboard control, the tasks it runs, Watch Me and Teach me.
    let control = ComputerController()
    let activities = NativeActivityGate()
    lazy var desktop = DesktopExecutionService(control: control, activities: activities)
    let execution = ExecutionCoordinator()
    var taskPanel: BackgroundTaskPanelController!
    lazy var recorder = WatchRecorder(config: config, watcher: watcher)
    lazy var learning = WatchLearnComposition.make(recorder: recorder, registry: registry, activities: activities, config: { [weak self] in self?.effectiveConfig ?? Config() })
    let watchDraftWindow = WatchDraftWindowController()
    var bubbleWasVisibleBeforeControl = false

    // Attend: the jobs, what they find, the Jobs window and the stickers.
    var jobsWindow: JobsWindowController!
    var folderJobs: FolderJobsFeature?
    var matters: Matters!
    var minister: Minister!
    var stickersPanel: StickersPanel?
    var stickersScreenObserver: NSObjectProtocol?

    var watcherMenuItem: NSMenuItem!
    var hideMenuItem: NSMenuItem!
    var stickersMenuItem: NSMenuItem!
    var screenPermItem: NSMenuItem!
    var axPermItem: NSMenuItem!
    var toolsMenuItem: NSMenuItem!
    var watchMenuItem: NSMenuItem!
    var stopWorkMenuItem: NSMenuItem!
    var tasksMenuItem: NSMenuItem!
    var origamiMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("Noteling launching (bundle: \(Bundle.main.bundleIdentifier ?? "none"), config: \(Config.file.path))")
        seedToolsIfMissing()
        MascotStyle.current = MascotStyle(rawValue: config.mascotStyle) ?? .innocent
        Secrets.store = Secrets.Store(rawValue: config.secretsStore) ?? (Signing.isDeveloperID ? .keychain : .file)
        Log.info("signing: \(Signing.description); secrets: \(Secrets.store.rawValue)")
        setupHarness()
        setupAsk()
        setupAct()
        setupEditMenu()
        setupPanel()
        setupAttend()
        setupStatusItem()
        setupHotKey()
        setupWatcher()
        setupWand()
        setupAttendHousekeeping()
        setupRunStickers()
        requestPermissionsOnFirstRun()
        Task {
            runner.networkEnv = await ScriptNetwork.current()   // before the first script: the Mac's proxy and certificates
            await registry.reload()
            assistant.notesHere = registry.notes(for: watcher.current)
            linkedTools.start()   // checks the linked repository now, then every 10 minutes
            Secrets.migrateKeychainToFile(keys: (config.connectionMode == "api" ? ["ANTHROPIC_API_KEY"] : []) + registry.packs.flatMap(\.requires))
            if !assistant.hasConnection { assistant.reconfigure(effectiveConfig) }   // pick up a migrated key
            ScriptedSecrets.shared.warm(effectiveConfig)   // a gateway token's script runs now, not on the first question
            startAttend()   // only once the packs are loaded, so a job.py can import what they hold
        }

        if !assistant.hasConnection {
            Log.info(ConversationBackend.setupMessage(config: effectiveConfig))
        }
        MainThreadDiagnostics.shared.start()
        MainThreadDiagnostics.shared.mark(.appReady)
    }

    // MARK: the harness

    /// The scripts, the team's tools and the secrets' scripts: what all three products run on.
    func setupHarness() {
        runner = ScriptRunner(config: config)
        registry = ToolRegistry(root: config.resolvedToolsDir, runner: runner)
        registry.linkedRoot = LinkedTools.root(for: config)   // the team's tools, once Settings links a repository
        registry.secretScripts = { [weak self] in self.map { Set($0.effectiveConfig.secretScripts.values) } ?? [] }
        recall = Recall.standard(home: Config.dir, tools: registry.root, team: { [weak self] in self?.registry.linkedRoot })
        ScriptedSecrets.shared.runner = runner   // a gateway's token is made with the Mac's proxy and certificates too
        linkedTools.onToolsChanged = { [weak self] in await self?.linkedToolsChanged() }
        runner.extraEnv = config.env
    }

    /// First run: copy the bundled example tool packs to ~/.noteling/tools and retire the old knowledge folder.
    func seedToolsIfMissing() {
        let fm = FileManager.default
        let dir = config.resolvedToolsDir
        if !fm.fileExists(atPath: dir.path), let bundled = Bundle.main.resourceURL?.appendingPathComponent("tools"), fm.fileExists(atPath: bundled.path) {
            try? fm.copyItem(at: bundled, to: dir)
            Log.info("seeded example tool packs into \(dir.path)")
        }
        // A pack added in an update (such as Mail) reaches existing installs; edited or removed packs are left alone.
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("tools"), fm.fileExists(atPath: bundled.path) {
            for name in ToolRegistry.addMissingPacks(from: bundled, to: dir) { Log.info("added tool pack \(name) to \(dir.path)") }
        }
        // Noteling's own jobs (Mail) reach every install once, as the person's own; one they deleted stays deleted.
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("jobs"), fm.fileExists(atPath: bundled.path) {
            for name in FolderJobFiles.addBundledJobs(from: bundled, to: Config.dir.appendingPathComponent("jobs")) { Log.info("added the \(name) job to jobs/") }
        }
        // A pack with no rules used to apply everywhere; once, the person's own such packs say so (`match: anywhere`).
        for name in ToolRegistry.markOwnPacksAnywhereOnce(in: dir) { Log.info("tool pack \(name) now says match: anywhere") }
        let legacy = Config.dir.appendingPathComponent("knowledge")
        let seededNames: Set<String> = ["expense-reports.md", "hr-portal.md", "vpn-and-access.md"]
        if let files = try? fm.contentsOfDirectory(atPath: legacy.path), !files.isEmpty, Set(files).isSubset(of: seededNames) {
            try? fm.removeItem(at: legacy)
            Log.info("removed old example knowledge folder (docs now live in tools/<pack>/docs)")
        }
    }

    @objc func reloadTools() {
        Task {
            await registry.reload()
            notesStore.reload()
            assistant.notesHere = registry.notes(for: watcher.current)
        }
    }

    /// A new copy of the team's tools, or none: reload, and take in the notes kept in it (its files are never renamed).
    /// Its Claude settings may have changed too: reconnect as saving Settings does, keeping the conversation.
    func linkedToolsChanged() async {
        registry.linkedRoot = LinkedTools.root(for: config)
        await registry.reload()
        if let linked = registry.linkedRoot { notesStore.moveNotes(fromPacksIn: linked, rename: false) }
        notesStore.reload()
        assistant.notesHere = registry.notes(for: watcher.current)
        assistant.reconfigure(effectiveConfig)
        ScriptedSecrets.shared.warm(effectiveConfig)
        folderJobs?.toolsChanged()   // the team's jobs as the new copy has them, now rather than at the next tick
    }

    @objc func openTools() { NSWorkspace.shared.open(config.resolvedToolsDir) }

    func requestPermissionsOnFirstRun() {
        if !Permissions.accessibilityGranted { Permissions.requestAccessibility() }
        if !Permissions.screenRecordingGranted { Permissions.requestScreenRecording() }
        Log.info("permissions: screen=\(Permissions.screenRecordingGranted) accessibility=\(Permissions.accessibilityGranted)")
    }

    @objc func fixScreenPermission() { if !Permissions.requestScreenRecording() { Permissions.openScreenRecordingSettings() } }
    @objc func fixAXPermission() { Permissions.requestAccessibility(); Permissions.openAccessibilitySettings() }

    // MARK: menus

    /// Standard application and Edit menus provide native Quit and text-editing shortcuts.
    func setupEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        appItem.submenu = NSMenu()
        let openJobs = NSMenuItem(title: Self.jobsMenuTitle, action: #selector(menuShowJobs), keyEquivalent: "")
        openJobs.target = self
        appItem.submenu?.addItem(openJobs)
        let openTasks = NSMenuItem(title: "Background Tasks…", action: #selector(menuShowTasks), keyEquivalent: "")
        openTasks.target = self
        appItem.submenu?.addItem(openTasks)
        let openChatItem = NSMenuItem(title: "Open Chat", action: #selector(openChat), keyEquivalent: "")
        openChatItem.target = self
        appItem.submenu?.addItem(openChatItem)
        appItem.submenu?.addItem(.separator())
        appItem.submenu?.addItem(NSMenuItem(title: "Quit Noteling", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]; edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        edit.addItem(.separator())
        let find = NSMenuItem(title: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        edit.addItem(find)
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let img = NSImage(systemSymbolName: "pencil.tip", accessibilityDescription: "Noteling") {
            img.isTemplate = true
            statusItem.button?.image = img
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: Self.jobsMenuTitle, action: #selector(menuShowJobs), keyEquivalent: ""))
        stickersMenuItem = NSMenuItem(title: "Stickers", action: nil, keyEquivalent: "")
        stickersMenuItem.submenu = NSMenu(title: "Stickers")
        menu.addItem(stickersMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Point the Pen   ⌃⌥Space", action: #selector(menuWand), keyEquivalent: ""))
        watchMenuItem = NSMenuItem(title: "Watch Me", action: #selector(menuWatch), keyEquivalent: "")
        menu.addItem(watchMenuItem)
        stopWorkMenuItem = NSMenuItem(title: "Stop Working", action: #selector(menuStopWork), keyEquivalent: "")
        stopWorkMenuItem.isHidden = true
        menu.addItem(stopWorkMenuItem)
        tasksMenuItem = NSMenuItem(title: "Background Tasks…", action: #selector(menuShowTasks), keyEquivalent: "")
        menu.addItem(tasksMenuItem)
        menu.addItem(NSMenuItem(title: "Open Chat", action: #selector(openChat), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show Bubble", action: #selector(menuShowBubble), keyEquivalent: ""))
        hideMenuItem = NSMenuItem(title: "Hide Bubble", action: #selector(menuHideBubble), keyEquivalent: "")
        menu.addItem(hideMenuItem)
        origamiMenuItem = NSMenuItem(title: "Fold into a Crane", action: #selector(takeOrigamiFlight), keyEquivalent: "")
        menu.addItem(origamiMenuItem)
        menu.addItem(.separator())
        watcherMenuItem = NSMenuItem(title: "Watcher: On", action: #selector(toggleWatcher), keyEquivalent: "")
        menu.addItem(watcherMenuItem)
        toolsMenuItem = NSMenuItem(title: "Tools: …", action: #selector(reloadTools), keyEquivalent: "")
        menu.addItem(toolsMenuItem)
        menu.addItem(NSMenuItem(title: "Open Tools Folder", action: #selector(openTools), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Open Config File", action: #selector(openConfig), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: ""))
        menu.addItem(.separator())
        screenPermItem = NSMenuItem(title: "Screen Recording: …", action: #selector(fixScreenPermission), keyEquivalent: "")
        axPermItem = NSMenuItem(title: "Accessibility: …", action: #selector(fixAXPermission), keyEquivalent: "")
        menu.addItem(screenPermItem)
        menu.addItem(axPermItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Noteling", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        watcherMenuItem.title = watcher.isRunning ? "Watcher: On" : "Watcher: Off"
        watchMenuItem.title = assistant.watching ? "Stop Watching   ⌃⌥Space" : "Watch Me"
        let working = desktop.tasks.activeTask != nil || (control.active && control.lane == .background)
        stopWorkMenuItem.isHidden = !working
        stopWorkMenuItem.title = desktop.tasks.activeTask != nil ? "Stop Current Task   \(HotKey.display(config.hotkey))"
            : "Stop Working in \(assistant.peek.appName)   \(HotKey.display(config.hotkey))"
        tasksMenuItem.isEnabled = desktop.tasks.hasTasks
        hideMenuItem.isEnabled = panel.isVisible || origami.isFlying
        updateStickersMenu()
        origamiMenuItem.title = origami.isFlying ? "Land Noteling   Esc" : "Fold into a Crane"
        origamiMenuItem.isEnabled = origami.isFlying || canTakeOrigamiFlight
        let scripts = registry.packs.reduce(0) { $0 + $1.scripts.count }
        let missing = registry.missingRequirements(for: registry.packs)
        toolsMenuItem.title = missing.isEmpty
            ? "Tools: \(registry.packs.count) packs, \(scripts) scripts\(linkedTools.menuNote(linkedPacks: registry.packs.filter(\.linked).count)) — Reload"
            : "Tools: \(missing.map { "\($0.pack.name) needs \($0.keys.joined(separator: ", "))" }.joined(separator: "; ")) — open Settings"
        screenPermItem.title = "Screen Recording: " + (Permissions.screenRecordingGranted ? "granted ✓" : "not granted — click to fix")
        axPermItem.title = "Accessibility: " + (Permissions.accessibilityGranted ? "granted ✓" : "not granted — click to fix")
    }

    /// Screen rect of the menu bar icon, if it is on screen.
    var statusItemRect: NSRect? {
        guard let b = statusItem.button, let w = b.window else { return nil }
        return w.convertToScreen(b.convert(b.bounds, to: nil))
    }

    func pulseStatusItem(remaining: Int) {
        guard remaining > 0, let b = statusItem.button else { return }
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.22; b.animator().alphaValue = 0.15 }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.22; b.animator().alphaValue = 1 }, completionHandler: { [weak self] in
                self?.pulseStatusItem(remaining: remaining - 1)
            })
        })
    }

    // MARK: the hotkey

    func setupHotKey() {
        hotKey?.unregister()
        hotKey = nil
        let spec = config.hotkey.isEmpty ? "control+option+space" : config.hotkey
        guard let (code, mods) = HotKey.parse(spec) else { Log.info("hotkey: cannot parse \"\(spec)\""); return }
        hotKey = HotKey(keyCode: code, modifiers: mods) { [weak self] in
            guard let self else { return }
            if self.assistant.watching { self.stopWatchingAndShow() }
            else if self.desktop.executor.stopActive() { }
            else if self.control.active, self.control.lane == .background { self.control.stop(reason: HotKey.display(self.config.hotkey)) }
            else if self.wand.isActive { self.wand.cancel() }
            else { self.startWand() }
        }
    }

    // MARK: the app's life

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if control.active { control.stop(reason: "Noteling is quitting"); control.end() }   // withdraws an outstanding activation record
        return .terminateNow
    }

    /// Quitting mid-recording leaves nothing behind: the unfinished recording and any draft still under review go.
    func applicationWillTerminate(_ notification: Notification) {
        MainThreadDiagnostics.shared.stop()
        assistant?.showMe?.stop()
        minister?.stop()
        origami.cancel()
        jobsWindow?.close()
        watchDraftWindow.close()
        folderJobs?.stop()
        execution.cancel()
        control.end()          // never leave a ghost cursor behind
        taskPanel.close()
        assistant.abortWatching()
        BrowserAccessibility.settle()   // last: a recording just stopped lets go of its browsers above
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let panel else { return true }
        openChat()
        sender.activate()
        panel.makeKeyAndOrderFront(nil)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Settings

    @objc func openSettings() {
        origami.cancel()
        ScriptedSecrets.shared.warm(effectiveConfig)   // so Settings says whether a gateway token's script works
        settings.model.importSetup = { [weak self] in self?.chooseSetupFile() }
        settings.show(config: config, packs: registry.packs, jobs: folderJobs?.store.jobs ?? [], linkedTools: linkedTools, onSave: { [weak self] in
            guard let self else { return }
            self.config = self.settings.model.save(into: self.config)
            self.linkedTools.settingsSaved()   // a changed address, branch or token is checked right away
            self.assistant.reconfigure(self.effectiveConfig)
            self.runner.extraEnv = self.config.env
            self.setupHotKey()
            MascotStyle.current = MascotStyle(rawValue: self.config.mascotStyle) ?? .innocent
            self.panel.sharingType = self.config.hideFromScreenShare ? .none : .readOnly
            self.taskPanel.updateSharing(self.config.hideFromScreenShare)
            self.jobsWindow.updateSharing(self.config.hideFromScreenShare)
            self.stickersPanel?.sharingType = self.config.hideFromScreenShare ? .none : .readOnly
            self.watchDraftWindow.updateSharing(self.config.hideFromScreenShare)
            self.control.maxLongEdge = self.config.maxImageLongEdge
            self.control.hideFromScreenShare = self.config.hideFromScreenShare
            self.control.preciseClicks = self.config.backgroundDirectClicks
            self.control.asksFirst = self.config.backgroundAsksFirst
            self.wand.hideFromScreenShare = self.config.hideFromScreenShare
            if self.config.notesShortcut { self.notesShortcut.start() } else { self.notesShortcut.stop() }
            Log.info("settings saved (connection: \(self.effectiveConfig.connectionMode), ready: \(self.assistant.hasConnection), hotkey: \(self.config.hotkey))")
        }, onOpenTools: { [weak self] in self?.openTools() }, onReloadTools: { [weak self] in self?.reloadTools() })
    }

    @objc func openConfig() { NSWorkspace.shared.open(Config.file) }
    @objc func openLog() { NSWorkspace.shared.open(Config.logFile) }

    // MARK: setup files

    /// A team's setup file, double-clicked in Finder (or dropped on the app's icon).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == NotelingSetup.fileExtension { offerSetup(url) }
    }

    /// Settings' Import setup file…
    func chooseSetupFile() {
        let panel = NSOpenPanel()
        panel.title = "Import a setup file"
        panel.message = "Choose the .notelingsetup file your team gave you."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        offerSetup(url)
    }

    /// Says what the file will do, applies it only if the person agrees, then links and says how that went.
    func offerSetup(_ url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let setup: NotelingSetup
        do {
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            guard size <= NotelingSetup.maxBytes else {
                throw NotelingSetupError("This file is too big to be a Noteling setup file (\(size / 1024) KB; a setup file is a few lines).")
            }
            setup = try NotelingSetup.parse(Data(contentsOf: url))
        } catch {
            setupAlert("This setup file can't be used", error.localizedDescription)
            return
        }
        let ask = NSAlert()
        ask.messageText = "Set up Noteling with “\(setup.name)”?"
        ask.informativeText = setup.summary(currentRepo: config.toolsRepo)
        ask.addButton(withTitle: "Set up")
        ask.addButton(withTitle: "Cancel")
        guard ask.runModal() == .alertFirstButtonReturn else { return }
        do {
            try setup.apply(to: &config, setSecret: { Secrets.set($0, $1) })
            config.save()
        } catch {
            setupAlert("Noteling isn't fully set up", error.localizedDescription)
            return
        }
        Log.info("setup: applied “\(setup.name)” (tools repo: \(setup.toolsRepo == nil ? "no" : "yes"), \(setup.secrets.count) secret(s))")
        guard setup.toolsRepo != nil else {
            setupAlert("Noteling is set up", "Saved \(setup.secrets.count == 1 ? "1 secret" : "\(setup.secrets.count) secrets") in your Keychain.")
            return
        }
        Task { @MainActor in
            await self.linkedTools.check()
            if let problem = self.linkedTools.record?.lastError {
                self.setupAlert("The setup is saved, but your team's tools aren't linked yet",
                                problem + " Noteling tries again every 10 minutes; Settings › Team tools from GitHub shows how it's going.")
                return
            }
            let packs = self.registry.packs.filter(\.linked).count
            let jobs = NotelingSetup.teamJobCount(in: self.registry.linkedRoot)
            let done = NSAlert()
            done.messageText = "Noteling is set up"
            done.informativeText = "Linked \(self.linkedTools.status())."
                + " \(packs == 1 ? "1 tool pack" : "\(packs) tool packs") and \(jobs == 1 ? "1 team job" : "\(jobs) team jobs") came with it."
                + (jobs > 0 ? " Turn on the jobs that are yours in Jobs." : "")
            done.addButton(withTitle: jobs > 0 ? "Open Jobs" : "Done")
            if jobs > 0 { done.addButton(withTitle: "Later") }
            if done.runModal() == .alertFirstButtonReturn, jobs > 0 { self.jobsWindow.showJobs() }
        }
    }

    func setupAlert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
