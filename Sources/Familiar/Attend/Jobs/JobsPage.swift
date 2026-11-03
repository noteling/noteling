import AppKit
import Combine
import SwiftUI

/// Follows every store the jobs come from, whichever are there, so one view redraws when any of them changes; and the
/// clock, so a job that starts or ends moves between the live jobs and Upcoming or Ended with nothing else changing.
@MainActor
final class JobsChanges: ObservableObject {
    private var subscriptions: [AnyCancellable] = []
    private var windows: Task<Void, Never>?
    /// The longest it waits before looking again for the next start or end, in case a job's dates changed.
    static let windowLook: TimeInterval = 300

    init(sources: CalendarStore?, runner: CalendarCollectionRunner?, morning: MorningStore, folderJobs: FolderJobsPanel? = nil) {
        var publishers = [morning.objectWillChange]
        if let sources { publishers += [sources.objectWillChange, sources.runStore.objectWillChange] }
        if let runner { publishers.append(runner.objectWillChange) }
        if let folderJobs {
            publishers += [folderJobs.store.objectWillChange, folderJobs.runner.objectWillChange]
            if let notifier = folderJobs.notifier { publishers.append(notifier.objectWillChange) }
        }
        subscriptions = publishers.map { $0.sink { [weak self] _ in self?.objectWillChange.send() } }
        if let folderJobs { followWindows(folderJobs.store) }
    }

    /// Wakes the views a second after the next job starts or ends. It holds neither the views nor the stores.
    private func followWindows(_ jobs: FolderJobStore) {
        windows = Task { [weak self, weak jobs] in
            while !Task.isCancelled {
                let now = Date()
                let next = jobs.flatMap { FolderJob.nextChange($0.jobs, after: now) }
                let wait = min(next.map { $0.timeIntervalSince(now) + 1 } ?? Self.windowLook, Self.windowLook)
                try? await Task.sleep(nanoseconds: UInt64(max(1, wait) * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                if let next, Date() > next { self.objectWillChange.send() }
            }
        }
    }

    deinit { windows?.cancel() }
}

/// What the job controls do: run a job now, stop a read, and turn your team's job on or off. Each says in plain words
/// why it couldn't.
@MainActor
struct JobActions {
    var sources: CalendarStore?
    var runner: CalendarCollectionRunner?
    var now: () -> Date = Date.init
    var folderJobs: FolderJobsPanel? = nil

    /// Whether Run now can start it: a reading job while nothing else reads and it can run as saved; a job kept as a
    /// folder while it's on, between its start and end, and not already running or waiting its turn.
    func canRun(_ job: Job) -> Bool {
        if job.isFolderJob {
            guard let folderJobs, let folderJob = folderJobs.store.job(id: job.id) else { return false }
            return !folderJobs.runner.isBusy(job.id) && folderJob.running(at: now())
        }
        guard let runner, !runner.isRunning else { return false }
        return job.status != .needsReview && job.status != .cantRunYet
    }

    /// Run now. A reading job reads as Read source did, a calendar today from 9 AM to 5 PM as Run all does; a job kept
    /// as a folder runs its job.py. Nil once it started; otherwise why not.
    func runNow(_ job: Job) -> String? {
        if job.isFolderJob {
            guard let folderJobs else { return "This job is no longer here." }
            return folderJobs.runner.run(job.id)
        }
        guard let sources, let runner else { return "Reading jobs are unavailable." }
        guard !runner.isRunning else { return "Another job is reading now. Run this one when it ends." }
        if let source = sources.readingSources.first(where: { $0.id == job.id }) {
            do { try source.validateForRead() } catch { return error.localizedDescription }
            return runner.collect(source: source) == nil ? (runner.error ?? "It couldn't start.") : nil
        }
        if let source = sources.sources.first(where: { $0.id == job.id }) {
            let day = now()
            do { try CalendarReadRequest(source: source, day: day).validate() } catch { return error.localizedDescription }
            return runner.collect(source: source, day: day) == nil ? (runner.error ?? "It couldn't start.") : nil
        }
        return "This job is no longer here."
    }

    func stop() { _ = runner?.stopActive() }

    func turn(_ job: Job, on: Bool) -> String? {
        guard job.isFolderJob, let folderJobs else { return "This job is no longer here." }
        do {
            try folderJobs.runner.turn(job.id, on: on)
            if on { folderJobs.notifier?.requestPermission() }
            return nil
        } catch { return error.localizedDescription }
    }
}

/// A job's buttons, on its row and its page (`Jobs.controls`).
struct JobControls: View {
    let job: Job
    let actions: JobActions
    var openSettings: (() -> Void)? = nil
    let problem: (String?) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Jobs.controls(job, canOpenSettings: openSettings != nil), id: \.self) { control($0) }
        }
    }

    @ViewBuilder private func control(_ control: Jobs.Control) -> some View {
        switch control {
        case .stop:
            ProgressView().controlSize(.small)
            Button("Stop") { actions.stop() }.buttonStyle(MorningActionButton()).help("Stop reading")
        case .openSettings:
            Button("Open Settings") { openSettings?() }.buttonStyle(MorningActionButton())
        case .runNow:
            Button(job.status == .running ? "Running…" : "Run now") { problem(actions.runNow(job)) }
                .buttonStyle(MorningActionButton()).disabled(!actions.canRun(job))
                .accessibilityLabel("Run \(job.name) now")
        case .onOff:
            Toggle("On", isOn: Binding(get: { job.on }, set: { problem(actions.turn(job, on: $0)) }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                .help(job.on ? "On: it runs for you. Turn it off to stop." : "Off. Turn it on to have it run for you.")
                .accessibilityLabel(job.on ? "Turn off \(job.name)" : "Turn on \(job.name)")
        }
    }
}

/// How a job stands, in a word or two; nothing for a job that is ready.
struct JobStatusLabel: View {
    let status: Job.Status

    var body: some View {
        if let label = status.label {
            Text(label).font(.system(size: 11, weight: .medium)).lineLimit(1)
                .foregroundStyle(status.isProblem ? Pad.redInk : Pad.inkSoft)
        }
    }
}

/// A job's card, one tap away: a job kept as a folder's card, or a reading job's cards, a menu when there are several.
struct JobCardLink: View {
    let cards: [MorningCard]
    let open: (UUID) -> Void

    var body: some View {
        if let label = Jobs.cardLabel(cards) {
            if cards.count == 1, let card = cards.first {
                Button { open(card.id) } label: { Label(label, systemImage: "doc.text") }
                    .buttonStyle(.plain).help("Open its card: " + card.title)
            } else {
                Menu {
                    ForEach(cards) { card in Button(card.title) { open(card.id) } }
                } label: { Label(label, systemImage: "doc.on.doc") }
                    .menuStyle(.borderlessButton).fixedSize().help("Open one of its cards")
            }
        }
    }
}

/// The top of a job's page, the same for every job: its name, what it does and how often, how its last run went, how
/// it stands, its buttons, and its card.
struct JobHeader: View {
    let job: Job
    let controls: JobControls
    let card: JobCardLink

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(job.name).font(HandFont.font(size: 26)).fixedSize(horizontal: false, vertical: true)
                if let place = JobRow.place(job) { Text(place).font(.system(size: 12)).foregroundStyle(Pad.inkSoft).lineLimit(1) }
            }
            Text(job.line).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
            Text(job.lastRun).font(.system(size: 12)).foregroundStyle(job.resultIsProblem ? Pad.redInk : Pad.inkSoft)
            HStack(spacing: 10) {
                controls
                JobStatusLabel(status: job.status)
                Spacer(minLength: 8)
                card.font(.system(size: 12, weight: .medium)).foregroundStyle(Pad.penInk)
            }.padding(.top, 5)
        }
    }
}

/// One job in the list: what it is, what it does and how often, its last run and how it stands, which opens its page;
/// its buttons; and what's wrong with it.
struct JobRow: View {
    let job: Job
    let actions: JobActions
    var openSettings: (() -> Void)?
    let open: () -> Void
    let problem: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                Button(action: open) { summary }.buttonStyle(.plain)
                    .help(job.meaning.isEmpty ? "Open this job" : job.meaning).accessibilityLabel("Open \(job.name)")
                JobStatusLabel(status: job.status)
                JobControls(job: job, actions: actions, openSettings: openSettings, problem: problem)
            }
            // Under Upcoming, what it lacks is said quietly: it can wait until the job starts.
            ForEach(job.allProblems, id: \.self) { line in
                Label(line, systemImage: "exclamationmark.triangle").font(.system(size: 12))
                    .foregroundStyle(job.isLive ? Pad.redInk : Pad.inkSoft)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }.padding(11).background(Color.white.opacity(job.on && job.isLive ? 0.5 : 0.35), in: RoundedRectangle(cornerRadius: 7))
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: Self.symbol(job.kind)).frame(width: 17).foregroundStyle(Pad.penInk).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(job.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    if let place = Self.place(job) { Text(place).font(.system(size: 11)).foregroundStyle(Pad.inkSoft).lineLimit(1) }
                }
                Text(job.line).font(.system(size: 11)).foregroundStyle(Pad.inkSoft)
                Text(job.lastRun).font(.system(size: 11)).foregroundStyle(job.resultIsProblem ? Pad.redInk : Pad.inkSoft)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }

    /// Beside its name: a team job's path, and who shared it. "holiday/oct/gm · Shared by Yang"; nil with neither.
    static func place(_ job: Job) -> String? {
        let parts = [job.isTeam ? job.path : nil, job.sharedBy].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func symbol(_ kind: Job.Kind) -> String {
        switch kind {
        case .mail: return "envelope"
        case .web: return "globe"
        case .calendar: return "calendar"
        case .job, .teamJob: return "folder"
        }
    }
}

/// Every live job in one list: those that read mail, a web page or a calendar, and those kept as folders, yours and
/// your team's. Those that need attention come first, then yours, then your team's, each by name; a row opens the
/// job's page. Jobs before their start or past their end wait under one line, "Upcoming (1) · Ended (2) · Show",
/// only to be looked at. Around the list: Run all reading jobs, the latest run and Run history; folders that aren't
/// jobs, and why; removed jobs to restore; and where jobs come from.
struct JobsPage: View {
    let morning: MorningStore
    let sources: CalendarStore?
    let runner: CalendarCollectionRunner?
    var setup = JobsSetup()
    @ObservedObject var navigation: MorningNavigation
    var now: () -> Date = Date.init
    var folderJobs: FolderJobsPanel? = nil
    @StateObject private var changes: JobsChanges
    @State private var problem: String?
    @State private var feedback: String?
    /// The jobs before their start or past their end are shown, under the live jobs.
    @State private var showingOutside = false

    /// `showingOutside` starts with the jobs before their start or past their end shown (a render).
    init(morning: MorningStore, sources: CalendarStore?, runner: CalendarCollectionRunner?,
         setup: JobsSetup = JobsSetup(), navigation: MorningNavigation, now: @escaping () -> Date = Date.init,
         showingOutside: Bool = false, folderJobs: FolderJobsPanel? = nil) {
        self.morning = morning
        self.sources = sources
        self.runner = runner
        self.setup = setup
        self.navigation = navigation
        self.now = now
        self.folderJobs = folderJobs
        _changes = StateObject(wrappedValue: JobsChanges(sources: sources, runner: runner, morning: morning, folderJobs: folderJobs))
        _showingOutside = State(initialValue: showingOutside)
    }

    private var input: Jobs.Input {
        Jobs.Input(sources: sources, morning: morning, setup: setup, now: now(), folderJobs: folderJobs)
    }
    private var actions: JobActions { JobActions(sources: sources, runner: runner, now: now, folderJobs: folderJobs) }
    private var isReading: Bool { runner?.isRunning == true }

    /// A job's page: a job kept as a folder's, or a reading job's.
    func open(_ job: Job) {
        navigation.route = job.isFolderJob ? .folderJob(job.id) : .sourceJob(job.id)
    }

    var body: some View {
        let all = Jobs.list(input)
        // A search over your team's jobs leaves out the ones that don't match, but never one you turned on.
        let shown = Jobs.searched(all, search)
        let jobs = shown.filter(\.isLive)
        let team = (shown: shown.filter(\.isTeam).count, total: all.filter(\.isTeam).count)
        let unreadable = Jobs.unreadable(own: folderJobs?.store.unreadable ?? [:], team: folderJobs?.store.teamUnreadable ?? [:],
                                         directory: folderJobs?.store.directory)
            + Jobs.retiredWatches(own: folderJobs?.store.retiredWatches, team: folderJobs?.store.teamRetiredWatches())
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                notices
                runBar
                ForEach(unreadable) { unreadableRow($0) }
                list(jobs, team: team)
                if jobs.isEmpty && unreadable.isEmpty {
                    Text(all.isEmpty ? Jobs.empty : Jobs.noneLive + ".").font(.system(size: 14))
                        .foregroundStyle(all.isEmpty ? Pad.ink : Pad.inkSoft).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                }
                outside(Jobs.outside(shown))
                removed
                footer
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await folderJobs?.notifier?.refresh() }
    }

    @ViewBuilder private func list(_ jobs: [Job], team: (shown: Int, total: Int)) -> some View {
        let first = jobs.first { $0.isTeam && !$0.needsAttention }?.id ?? jobs.first(where: \.isTeam)?.id
        ForEach(jobs) { job in
            if job.id == first { teamHeader(team) }
            JobRow(job: job, actions: actions, openSettings: setup.openSettings, open: { open(job) }, problem: { problem = $0 })
        }
        // A search that leaves none of your team's jobs keeps its box, so it can be changed or cleared.
        if first == nil && team.total > 0 { teamHeader(team) }
    }

    /// Where your team's jobs start: where they come from, and the search over them once there are many.
    @ViewBuilder private func teamHeader(_ team: (shown: Int, total: Int)) -> some View {
        Text(Jobs.teamIntro).font(.system(size: 11)).foregroundStyle(Pad.inkSoft)
            .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
        if let store = folderJobs?.store, Jobs.showsSearch(teamJobs: team.total, search: store.search) {
            JobsSearchBox(store: store, shown: team.shown, total: team.total)
        }
    }

    /// The search over your team's jobs, as last kept.
    private var search: String { folderJobs?.store.search ?? "" }

    /// Jobs before their start or past their end: one quiet line, and once it's clicked, their rows, which open their
    /// pages and have no buttons but an upcoming team job's switch.
    @ViewBuilder private func outside(_ jobs: (upcoming: [Job], ended: [Job])) -> some View {
        if let line = Jobs.outsideLine(upcoming: jobs.upcoming.count, ended: jobs.ended.count, showing: showingOutside) {
            Button(line) { showingOutside.toggle() }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Pad.penInk).padding(.top, 6)
                .help("Jobs before their start or past their end. They come back here on their own when they start.")
            if showingOutside {
                Text(Jobs.outsideIntro + (jobs.upcoming.contains(where: \.isTeam) ? " " + Jobs.armIntro : ""))
                    .font(.system(size: 11)).foregroundStyle(Pad.inkSoft).fixedSize(horizontal: false, vertical: true)
                group("Upcoming", jobs.upcoming)
                group("Ended", jobs.ended)
            }
        }
    }

    @ViewBuilder private func group(_ title: String, _ jobs: [Job]) -> some View {
        if !jobs.isEmpty {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Pad.inkSoft).padding(.top, 4)
            ForEach(jobs) { job in
                JobRow(job: job, actions: actions, openSettings: setup.openSettings, open: { open(job) }, problem: { problem = $0 })
            }
        }
    }

    // MARK: around the list

    @ViewBuilder private var notices: some View {
        if let folderJobs, folderJobs.store.jobs.contains(where: \.on), let off = folderJobs.notifier?.offReason {
            Label(off, systemImage: "bell.slash").font(.system(size: 12)).foregroundStyle(Pad.redInk).fixedSize(horizontal: false, vertical: true)
        }
        if let error = runner?.error ?? sources?.runStore.error ?? sources?.error {
            Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Pad.redInk).textSelection(.enabled)
        }
        if let problem {
            HStack(alignment: .top) {
                Text(problem).font(.system(size: 12)).foregroundStyle(Pad.redInk).textSelection(.enabled)
                Spacer(minLength: 8)
                Button { self.problem = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
            }
        }
        if let sources, let id = navigation.removedJob, let gone = sources.removedSources.first(where: { $0.id == id }) {
            HStack(alignment: .top, spacing: 10) {
                Text("“\(gone.name)” no longer runs. You can restore it, with its saved results, under Removed jobs.")
                    .font(.system(size: 12)).foregroundStyle(Pad.penInk).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Undo") { restore(id) }.buttonStyle(MorningActionButton()).disabled(isReading)
                Button { navigation.removedJob = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss")
            }.padding(12).background(Pad.paperTop.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
        }
        if let feedback { Text(feedback).font(.system(size: 12)).foregroundStyle(Pad.penInk) }
        if let runner = folderJobs?.runner, let receipt = runner.receipt { FolderJobReceiptLine(receipt: receipt, dismiss: runner.dismissReceipt) }
    }

    /// Run all reading jobs, Stop all and how a batch goes; the latest run, with what didn't finish; and Run history.
    @ViewBuilder private var runBar: some View {
        if let sources, let runner {
            let count = sources.sources.count + sources.readingSources.count
            let latest = sources.runStore.runs.first
            if count > 0 || latest != nil {
                VStack(alignment: .leading, spacing: 10) {
                    if count > 0 {
                        CalendarBatchControls(sourceCount: count, isRunning: runner.isRunning, isBatchRunning: runner.isBatchRunning,
                                              status: runner.status,
                                              runAll: { problem = nil; if runner.collectAll() != nil { navigation.route = .latestRun } },
                                              stop: { _ = runner.stopActive() })
                    }
                    HStack(spacing: 16) {
                        if let latest {
                            Button { navigation.route = .latestRun } label: {
                                HStack(spacing: 0) {
                                    Text("Latest run")
                                    if let note = LatestRunNote(run: latest) {
                                        Text(" · " + note.text).foregroundStyle(note.isProblem ? Pad.redInk : Pad.inkSoft)
                                    }
                                }
                            }.help("Open the newest run’s results")
                        }
                        Button("Run history") { navigation.route = .sourceRuns }
                    }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
                }.padding(14).background(Pad.paperTop.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    /// A folder that can't be a job, or watches left behind: what's wrong, What this means (the guide's page of
    /// messages), and the folder in Finder when it's on this Mac.
    private func unreadableRow(_ row: Jobs.Unreadable) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Label(row.text, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Pad.redInk)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Button(Jobs.messagesLink) { NSWorkspace.shared.open(HelpLinks.messages) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Pad.penInk).padding(.leading, 22)
                    .help(HelpLinks.messages.absoluteString)
            }
            Spacer(minLength: 8)
            if let folder = row.folder {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }.buttonStyle(MorningActionButton())
            }
        }.padding(11).background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder private var removed: some View {
        if let sources, !sources.removedSources.isEmpty {
            RemovedSourcesList(sources: sources.removedSources, isRunning: isReading, restore: restore)
        }
    }

    /// Brings a removed job back, with its saved results: Undo after removing it, and Restore under Removed jobs.
    func restore(_ id: UUID) {
        guard let sources, !isReading else { return }
        let name = sources.removedSources.first { $0.id == id }?.name ?? "The job"
        do {
            try sources.restoreSource(id: id)
            if navigation.removedJob == id { navigation.removedJob = nil }
            problem = nil
            feedback = "“\(name)” is back, with its saved results."
        } catch { problem = error.localizedDescription }
    }

    /// Where your team's jobs come from, when none are here; and the guides: how jobs work, and how to write them for a
    /// team.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let folderJobs, !folderJobs.store.jobs.contains(where: \.isTeam) && folderJobs.store.teamUnreadable.isEmpty {
                Text(Jobs.emptyTeam(linked: folderJobs.store.teamDirectory() != nil))
                    .font(.system(size: 11)).foregroundStyle(Pad.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 16) {
                Button(Jobs.howJobsWork) { NSWorkspace.shared.open(HelpLinks.jobs) }.help(HelpLinks.jobs.absoluteString)
                Button(Jobs.writingJobs) { NSWorkspace.shared.open(HelpLinks.teamTools) }.help(HelpLinks.teamTools.absoluteString)
            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
        }.padding(.top, 8)
    }
}

/// The search over your team's jobs: one box, matching a job's name or folder path, kept until it's cleared; and while
/// it holds something, how many of the team's jobs it shows, and Clear. The jobs you turned on always show.
struct JobsSearchBox: View {
    @ObservedObject var store: FolderJobStore
    let shown: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField("Find your team's jobs by name or folder", text: Binding(get: { store.search }, set: { store.setSearch($0) }))
                .textFieldStyle(.roundedBorder).font(.system(size: 12)).accessibilityLabel("Find your team's jobs")
            if let line = Jobs.searchLine(shown: shown, of: total, search: store.search) {
                HStack(spacing: 6) {
                    Text(line).foregroundStyle(Pad.inkSoft)
                    Text("·").foregroundStyle(Pad.inkSoft)
                    Button("Clear") { store.setSearch("") }.buttonStyle(.plain).foregroundStyle(Pad.penInk)
                }.font(.system(size: 11))
                .help("Jobs you turned on always show, whatever the search.")
            }
        }
    }
}

/// The Jobs box on the Morning Files home: how many jobs there are, how many need attention, and when one last ran.
struct JobsEntry: View {
    let morning: MorningStore
    let sources: CalendarStore?
    let runner: CalendarCollectionRunner?
    var setup = JobsSetup()
    let open: () -> Void
    var now: () -> Date = Date.init
    var folderJobs: FolderJobsPanel? = nil
    @StateObject private var changes: JobsChanges

    init(morning: MorningStore, sources: CalendarStore?, runner: CalendarCollectionRunner?,
         setup: JobsSetup = JobsSetup(), open: @escaping () -> Void, now: @escaping () -> Date = Date.init, folderJobs: FolderJobsPanel? = nil) {
        self.morning = morning
        self.sources = sources
        self.runner = runner
        self.setup = setup
        self.open = open
        self.now = now
        self.folderJobs = folderJobs
        _changes = StateObject(wrappedValue: JobsChanges(sources: sources, runner: runner, morning: morning, folderJobs: folderJobs))
    }

    var body: some View {
        let jobs = Jobs.list(Jobs.Input(sources: sources, morning: morning, setup: setup, now: now(), folderJobs: folderJobs))
        let summary = Jobs.summary(jobs, now: now())
        let attention = jobs.contains { $0.needsAttention && $0.status != .off }
        // Saved runs or reading jobs that can't be opened or saved: said on the home, as the sources' box did.
        let stored = sources?.runStore.error ?? sources?.error
        return Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "checklist").font(.system(size: 21))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Jobs").font(.system(size: 14, weight: .semibold))
                    Text(summary).font(.system(size: 12)).foregroundStyle(attention ? Pad.redInk : Pad.inkSoft)
                    if let stored {
                        Text(stored).font(.system(size: 12)).foregroundStyle(Pad.redInk).lineLimit(3).multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
            }.padding(14).background(Pad.paperTop.opacity(0.6), in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Jobs, " + summary).help("Everything Noteling runs for you")
    }
}
