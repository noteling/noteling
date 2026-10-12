import AppKit
import Combine
import Darwin
import Foundation

/// What one run of a job gets: its job.py in its folder, its input folder, a fresh empty output folder, its own folder
/// in the cards inbox, and the folders its job.py may import from. A press of one of its cards' buttons gets the same
/// but an output folder, and calls that button's function instead of run().
struct FolderJobRun {
    var job: FolderJob
    var folder: URL
    var input: URL
    /// For a press, its latest output: not given to the function.
    var output: URL
    /// Its folder in the cards inbox, for cards its job.py writes itself (NOTELING_CARDS_DIR).
    var cardsSource: String
    /// Your tools folder, then your team's: a job.py imports helpers from either.
    var importPaths: [URL]
    var timeout: TimeInterval
    /// A card's button: the function of job.py to call instead of run(), and its arguments as one JSON object.
    var function: String? = nil
    var args: String? = nil

    var script: URL { folder.appendingPathComponent(FolderJobFiles.entry) }

    /// What its script's environment gets for this run, besides what every script gets.
    var env: [String: String] {
        var env = ["NOTELING_INPUT": input.path, "PYTHONPATH": importPaths.map(\.path).joined(separator: ":")]
        if function == nil { env["NOTELING_OUTPUT"] = output.path }
        return env
    }

    /// The button's arguments; none for a run.
    var arguments: [String: Any] {
        guard let args, let object = try? JSONSerialization.jsonObject(with: Data(args.utf8)) as? [String: Any] else { return [:] }
        return object
    }
}

/// Runs the jobs: every 30 seconds it starts those whose schedule has come round, and again just after the Mac wakes;
/// Run now and turning a team job on start one at once. One job runs at a time; the rest wait their turn. Each run gets
/// a fresh output folder; a run that works puts it in place of the last one in one step, and one that fails leaves the
/// last one as it was and says why on the job's row. Then the job's card follows its output, and when its preview shows
/// something it didn't before, the person is told.
@MainActor
final class FolderJobRunner: ObservableObject {
    typealias Execute = (FolderJobRun) async throws -> Any

    let store: FolderJobStore
    /// The job running now, and those waiting their turn.
    @Published private(set) var running: UUID?
    @Published private(set) var queued: [UUID] = []
    /// What the last run someone started with Run now came to, said where they pressed it until they dismiss it or
    /// start another.
    @Published private(set) var receipt: FolderJobReceipt?
    /// Writes each job's card file; nil writes none.
    var cards: FolderJobCards?
    /// Card files changed: the app takes them into Morning Files.
    var onCardsChanged: (() -> Void)?
    /// At each tick and after each run: the app looks at the cards inbox, where a job.py may have written cards of its own.
    var onTick: (() -> Void)?
    /// A run left a preview that shows something it didn't before: the app tells the person.
    var onNews: ((FolderJob) -> Void)?
    /// Folders a job.py may import from, asked at each run.
    var importPaths: () -> [URL] = { [] }
    var hasSecret: (String) -> Bool = { Secrets.has($0) || ProcessInfo.processInfo.environment[$0] != nil }

    static let tickSeconds: Double = 30
    static let afterWakeSeconds: Double = 10
    /// How long one run may take.
    static let timeLimit: TimeInterval = 600

    private let execute: Execute
    private let now: () -> Date
    private var ticker: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var worker: Task<Void, Never>?
    private var current: Task<Any, Error>?
    /// Runs that say nothing when they're done: the first after a team job is turned on, which the person is looking at.
    private var quiet: Set<UUID> = []
    /// Runs someone started with Run now: each leaves a receipt when it ends.
    private var asked: Set<UUID> = []

    init(store: FolderJobStore, execute: @escaping Execute, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.execute = execute
        self.now = now
    }

    func start() {
        guard ticker == nil else { return }
        reconcileCards()
        ticker = Task { [weak self] in
            while !Task.isCancelled, let runner = self {
                runner.tick()
                try? await Task.sleep(nanoseconds: UInt64(Self.tickSeconds * 1_000_000_000))
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                                         queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Self.afterWakeSeconds * 1_000_000_000))
                self?.tick()
            }
        }
        Log.info("jobs: running \(store.jobs.count) job(s) from folders on schedule")
    }

    /// Stops the schedule and the run in progress.
    func stop() {
        ticker?.cancel()
        ticker = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        queued = []
        current?.cancel()
    }

    /// Takes in what changed in the jobs folders, starts the jobs that are due, and brings the cards in line.
    func tick() {
        for id in store.refresh() { cancel(id) }
        let time = now()
        for job in store.jobs where job.isDue(at: time) { enqueue(job.id) }
        reconcileCards()
        onTick?()
    }

    /// Run now. Nil once it's running or waiting its turn; otherwise why not.
    @discardableResult
    func run(_ id: UUID) -> String? {
        guard let job = store.job(id: id) else { return "This job is no longer here." }
        guard job.on else { return "Turn it on first." }
        guard job.running(at: now()) else { return "It runs only between its start and its end." }
        asked.insert(id)
        enqueue(id)
        return nil
    }

    func dismissReceipt() { receipt = nil }

    /// Turns a team job on or off. Turned on, it runs right away if it has started, and that first run says nothing:
    /// the person is looking at it. Turned off, its run stops and its card goes.
    func turn(_ id: UUID, on: Bool) throws {
        try store.setOn(id, on)
        if !on { cancel(id) } else if store.job(id: id)?.running(at: now()) == true { enqueue(id, quiet: true) }
        reconcileCards()
    }

    /// Stops a job's run, or takes it out of the queue.
    func cancel(_ id: UUID) {
        queued.removeAll { $0 == id }
        quiet.remove(id)
        asked.remove(id)
        if running == id { current?.cancel() }
    }

    /// Running, or waiting its turn.
    func isBusy(_ id: UUID) -> Bool { running == id || queued.contains(id) }

    /// The secrets a job still needs in Settings.
    func missingSecrets(_ job: FolderJob) -> [String] { job.requires.filter { !hasSecret($0) } }

    /// The work done: the queue empty and nothing running. Tests wait on it.
    func finish() async { await worker?.value }

    private func enqueue(_ id: UUID, quiet: Bool = false) {
        guard running != id, !queued.contains(id) else { return }
        queued.append(id)
        if quiet { self.quiet.insert(id) }
        if worker == nil { worker = Task { await self.drain() } }
    }

    private func drain() async {
        while !queued.isEmpty {
            let id = queued.removeFirst()
            let silent = quiet.remove(id) != nil
            guard let job = store.job(id: id), job.running(at: now()) else { continue }
            running = id
            await perform(job, quiet: silent)
            running = nil
        }
        worker = nil
    }

    private func perform(_ job: FolderJob, quiet: Bool) async {
        var state = job.state
        let before = job.state.preview
        state.lastRunAt = now()
        do {
            try await runScript(job, state: &state)
        } catch {
            state.error = Self.reason(error)
        }
        do { try store.record(job.id, state) } catch { Log.info("jobs: couldn't save how \(job.path) ran: \(error.localizedDescription)") }
        Log.info("jobs: \(job.isTeam ? "the team's " : "")\(job.path) " + (state.error.map { "failed: \($0)" } ?? "ran"))
        reconcileCards()
        onTick?()
        if asked.remove(job.id) != nil, let latest = store.job(id: job.id) {
            receipt = FolderJobReceipt(jobID: job.id, text: FolderJobWords.receipt(latest))
        }
        guard !quiet, state.error == nil, let preview = state.preview, preview != before,
              let latest = store.job(id: job.id), latest.running(at: now()) else { return }
        onNews?(latest)
    }

    /// Runs job.py into a fresh output folder, and on success puts it in place of the last one.
    private func runScript(_ job: FolderJob, state: inout FolderJobState) async throws {
        let missing = missingSecrets(job)
        guard missing.isEmpty else { throw FolderJobError(Jobs.needs(missing)) }
        guard let folder = store.folder(for: job), FileManager.default.fileExists(atPath: folder.appendingPathComponent(FolderJobFiles.entry).path)
        else { throw FolderJobError("Its job.py isn't there any more.") }
        let manager = FileManager.default
        let results = store.resultFolder(for: job)
        try manager.createDirectory(at: results, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // An output a quit or a crash left half written goes first.
        for name in (try? manager.contentsOfDirectory(atPath: results.path)) ?? [] where name.hasPrefix(".output-") && name.hasSuffix(".tmp") {
            try? manager.removeItem(at: results.appendingPathComponent(name))
        }
        let staging = results.appendingPathComponent(".output-\(UUID().uuidString).tmp")
        try manager.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: staging) }
        let run = FolderJobRun(job: job, folder: folder, input: folder.appendingPathComponent(FolderJobFiles.input), output: staging,
                               cardsSource: FolderJobCards.scriptSource(for: job), importPaths: importPaths(), timeout: Self.timeLimit)
        let task = Task { try await execute(run) }
        current = task
        defer { current = nil }
        let value: Any
        do { value = try await task.value } catch {
            if task.isCancelled { throw FolderJobError("Stopped.") }
            throw error
        }
        if task.isCancelled { throw FolderJobError("Stopped.") }
        let output = store.output(for: job)
        try Self.swap(staging, into: output)
        state.lastSuccessAt = now()
        state.error = nil
        state.said = Self.said(value)
        state.preview = FolderJobFiles.previewDigest(output: output)
    }

    /// Puts the new output in place of the old in one step: the two folders swap names, and the old one, now at the
    /// staging name, is deleted with it.
    static func swap(_ staging: URL, into destination: URL) throws {
        let flags = FileManager.default.fileExists(atPath: destination.path) ? UInt32(RENAME_SWAP) : 0
        guard renamex_np(staging.path, destination.path, flags) == 0 else {
            throw FolderJobError("Its output couldn't be put in place: \(String(cString: strerror(errno))).")
        }
    }

    /// What a run's `run()` said, when it returned words (or a number): trimmed, and not too long.
    static func said(_ value: Any) -> String? {
        let text: String
        switch value {
        case let string as String: text = string
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): text = number.stringValue
        default: return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : JobWords.clip(trimmed, 1_000)
    }

    /// Why a run failed, in its first line.
    static func reason(_ error: Error) -> String {
        if let error = error as? ScriptRunnerError, error.timedOut { return "It took longer than \(Int(timeLimit / 60)) minutes, so it was stopped." }
        if error is CancellationError { return "Stopped." }
        if let error = error as? FolderJobError { return error.message }
        return JobWords.reason(error.localizedDescription) ?? "It failed without saying why."
    }

    private func reconcileCards() {
        if cards?.reconcile(store.jobs, at: now()) == true { onCardsChanged?() }
    }
}

/// What a run someone started with Run now came to: which job, and one line for them.
struct FolderJobReceipt: Equatable {
    var jobID: UUID
    var text: String
}

/// What Morning Files needs to show the jobs kept as folders: where they're kept, what runs them and their cards'
/// buttons, and whether notifications are on.
struct FolderJobsPanel {
    let store: FolderJobStore
    let runner: FolderJobRunner
    var notifier: JobNotifier? = nil
    /// What the buttons on the jobs' cards run; nil shows them unable to run.
    var buttons: FolderJobButtons? = nil
}

/// The jobs kept as folders, put together once by the app: where they're kept, what runs them, their cards, the
/// notification when a preview has something new, and their tools in chat.
@MainActor
final class FolderJobsFeature {
    let store: FolderJobStore
    let runner: FolderJobRunner
    /// What the buttons on its jobs' cards run.
    let buttons: FolderJobButtons
    let notifier: JobNotifier
    let conversation: FolderJobConversation

    /// `inbox` is the cards inbox its cards are written into.
    init(registry: ToolRegistry, notifier: JobNotifier, store: FolderJobStore? = nil,
         inbox: URL = Config.dir.appendingPathComponent("cards/inbox")) {
        // Your team's jobs are `jobs/` in the linked tools, wherever the latest update put them.
        let store = store ?? FolderJobStore(teamDirectory: { [weak registry] in
            registry?.linkedRoot.map { $0.appendingPathComponent(ToolRegistry.jobsFolder) }
        })
        let scripts = registry.runner
        let execute: FolderJobRunner.Execute = { run in
            let script = ScriptTool(id: ToolRegistry.toolName("job__" + run.job.path), packDir: run.folder.lastPathComponent,
                                    fileName: FolderJobFiles.entry, path: run.script, description: run.job.about,
                                    inputSchema: ["type": "object", "properties": [:]], dependencies: [])
            return try await scripts.result(script, args: run.arguments, function: run.function, secrets: run.job.requires,
                                            timeout: run.timeout, toolDir: run.folder, cardsSource: run.cardsSource, env: run.env)
        }
        let runner = FolderJobRunner(store: store, execute: execute)
        let importPaths = { [weak registry] () -> [URL] in
            guard let registry else { return [] }
            return [registry.root] + (registry.linkedRoot.map { [$0] } ?? [])
        }
        runner.importPaths = importPaths
        let buttons = FolderJobButtons(store: store, execute: execute)
        buttons.importPaths = importPaths
        runner.cards = FolderJobCards(root: inbox)
        runner.onNews = { [weak notifier] job in
            notifier?.post(job: job.id, title: job.name, body: job.state.said ?? "Its preview has something new.")
        }
        let conversation = FolderJobConversation(store: store, runner: runner)
        conversation.notificationLine = { [weak notifier] in await notifier?.line() ?? "on" }
        conversation.askForNotifications = { [weak notifier] in notifier?.requestPermission() }
        self.store = store
        self.runner = runner
        self.buttons = buttons
        self.notifier = notifier
        self.conversation = conversation
    }

    var panel: FolderJobsPanel { FolderJobsPanel(store: store, runner: runner, notifier: notifier, buttons: buttons) }

    /// Starts the schedule; with jobs there, macOS is asked for notifications, which only prompts someone who never
    /// answered.
    func start() {
        if store.jobs.contains(where: \.on) { notifier.requestPermission() }
        runner.start()
    }

    func stop() { runner.stop() }

    /// A new copy of the team's tools, or none: their jobs as it has them, now rather than at the next tick.
    func toolsChanged() { runner.tick() }

    /// The card view's folder name for a job's folders in the inbox: the job's name.
    func cardFolderName(_ source: String) -> String? {
        store.jobs.first { FolderJobCards.source(for: $0) == source || FolderJobCards.scriptSource(for: $0) == source }?.name
    }

    /// Whether the cards in a folder of the inbox are put away for now: the cards a job's script wrote, while the job is
    /// off, or before its start or after its end. A folder that isn't a job's is never held.
    func holds(_ source: String, at now: Date = Date()) -> Bool {
        store.jobs.first { FolderJobCards.scriptSource(for: $0) == source }.map { !$0.running(at: now) } ?? false
    }

    /// The job a card is about, when it is a job's preview card.
    func job(forCard key: String) -> FolderJob? {
        store.jobs.first { FolderJobCards.key(for: $0) == key }
    }
}
