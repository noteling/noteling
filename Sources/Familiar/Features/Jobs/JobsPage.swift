import AppKit
import Combine
import SwiftUI

/// Follows every store the jobs come from, whichever are there, so one view redraws when any of them changes.
@MainActor
final class JobsChanges: ObservableObject {
    private var subscriptions: [AnyCancellable] = []

    init(sources: CalendarStore?, runner: CalendarCollectionRunner?, watches: WatchListPanel?, morning: MorningStore) {
        var publishers = [morning.objectWillChange]
        if let sources { publishers += [sources.objectWillChange, sources.runStore.objectWillChange] }
        if let runner { publishers.append(runner.objectWillChange) }
        if let watches { publishers += [watches.store.objectWillChange, watches.runner.objectWillChange, watches.notifier.objectWillChange] }
        subscriptions = publishers.map { $0.sink { [weak self] _ in self?.objectWillChange.send() } }
    }
}

/// What the job controls do: read a reading job now, check a watch now, stop a read, pause or resume a watch of your
/// own, and turn your team's job on or off. Each says in plain words why it couldn't.
@MainActor
struct JobActions {
    var sources: CalendarStore?
    var runner: CalendarCollectionRunner?
    var watches: WatchListPanel?
    var now: () -> Date = Date.init

    func watch(_ id: UUID) -> WatchListWatch? { watches?.store.watch(id: id) }

    private var watchActions: WatchListActions? {
        watches.map { WatchListActions(store: $0.store, runner: $0.runner, notifier: $0.notifier) }
    }

    /// Whether Run now can start it: a reading job while nothing else reads and it can run as saved; a watch when
    /// Check now could (a watch of your own between its start and end, your team's job while it's on and running).
    func canRun(_ job: Job) -> Bool {
        if job.isWatch {
            guard let watches, let watch = watch(job.id) else { return false }
            return WatchListWords.canCheckNow(watch, checking: watches.runner.checking.contains(job.id), now: now())
        }
        guard let runner, !runner.isRunning else { return false }
        return job.status != .needsReview && job.status != .cantRunYet
    }

    /// Run now. A reading job reads as Read source did, a calendar today from 9 AM to 5 PM as Run all does; a watch is
    /// checked now, as Check now did. Nil once it started; otherwise why not.
    func runNow(_ job: Job) -> String? {
        if job.isWatch {
            guard let watch = watch(job.id), let watchActions else { return "This job is no longer here." }
            watchActions.checkNow(watch)
            return nil
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

    func setPaused(_ job: Job, _ paused: Bool) -> String? {
        guard let watch = watch(job.id), let watchActions else { return "This job is no longer here." }
        return watchActions.setPaused(watch, paused)
    }

    func turn(_ job: Job, on: Bool) -> String? {
        guard let watch = watch(job.id), let watchActions else { return "This job is no longer here." }
        return watchActions.turn(watch, on: on)
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
        case .pause, .resume:
            Button(control == .pause ? "Pause" : "Resume") { problem(actions.setPaused(job, control == .pause)) }
                .buttonStyle(MorningActionButton())
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

/// A job's card, one tap away: a watch's card, or a reading job's cards, a menu when there are several.
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
                if job.isTeam { Text(job.path).font(.system(size: 12)).foregroundStyle(Pad.inkSoft).lineLimit(1) }
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
/// its buttons; and what's wrong, or to know, about it.
private struct JobRow: View {
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
            ForEach(job.allProblems, id: \.self) { line in
                Label(line, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Pad.redInk)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            ForEach(job.notes, id: \.self) { note in
                Text(note).font(.system(size: 11)).foregroundStyle(Pad.inkSoft).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }.padding(11).background(Color.white.opacity(job.on ? 0.5 : 0.35), in: RoundedRectangle(cornerRadius: 7))
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: Self.symbol(job.kind)).frame(width: 17).foregroundStyle(Pad.penInk).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(job.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    if job.isTeam { Text(job.path).font(.system(size: 11)).foregroundStyle(Pad.inkSoft).lineLimit(1) }
                }
                Text(job.line).font(.system(size: 11)).foregroundStyle(Pad.inkSoft)
                Text(job.lastRun).font(.system(size: 11)).foregroundStyle(job.resultIsProblem ? Pad.redInk : Pad.inkSoft)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }

    static func symbol(_ kind: Job.Kind) -> String {
        switch kind {
        case .mail: return "envelope"
        case .web: return "globe"
        case .calendar: return "calendar"
        case .watch, .teamWatch: return "eye"
        }
    }
}

/// Every job in one list: those that read mail, a web page or a calendar, and those that check items, yours and your
/// team's. Those that need attention come first, then yours, then your team's, each by name; a row opens the job's
/// page. Around the list: Run all reading jobs, the latest run and Run history; folders that aren't jobs, and why;
/// saved demonstrations to review; removed jobs to restore; and how to start a new job.
struct JobsPage: View {
    let morning: MorningStore
    let sources: CalendarStore?
    let runner: CalendarCollectionRunner?
    let watches: WatchListPanel?
    var setup = JobsSetup()
    @ObservedObject var navigation: MorningNavigation
    var teach: (() -> Void)? = nil
    var now: () -> Date = Date.init
    @StateObject private var changes: JobsChanges
    @State private var problem: String?
    @State private var feedback: String?
    /// A saved demonstration being reviewed before it becomes a job.
    @State private var reviewing: LearnedReadingSource?

    init(morning: MorningStore, sources: CalendarStore?, runner: CalendarCollectionRunner?, watches: WatchListPanel?,
         setup: JobsSetup = JobsSetup(), navigation: MorningNavigation, teach: (() -> Void)? = nil, now: @escaping () -> Date = Date.init) {
        self.morning = morning
        self.sources = sources
        self.runner = runner
        self.watches = watches
        self.setup = setup
        self.navigation = navigation
        self.teach = teach
        self.now = now
        _changes = StateObject(wrappedValue: JobsChanges(sources: sources, runner: runner, watches: watches, morning: morning))
    }

    private var input: Jobs.Input { Jobs.Input(sources: sources, watches: watches, morning: morning, setup: setup, now: now()) }
    private var actions: JobActions { JobActions(sources: sources, runner: runner, watches: watches, now: now) }
    private var isReading: Bool { runner?.isRunning == true }

    /// A job's page: a watch's, or a reading job's.
    func open(_ job: Job) {
        navigation.route = job.isWatch ? .watch(job.id) : .sourceJob(job.id)
    }

    var body: some View {
        let jobs = Jobs.list(input)
        let unreadable = watches.map { Jobs.unreadable(own: $0.store.unreadable, team: $0.store.teamUnreadable, directory: $0.store.directory) } ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                notices
                if let reviewing { review(reviewing) } else {
                    runBar
                    ForEach(unreadable) { unreadableRow($0) }
                    list(jobs)
                    if jobs.isEmpty && unreadable.isEmpty {
                        Text(Jobs.empty).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    }
                    demonstrations
                    removed
                    footer(empty: jobs.isEmpty)
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await watches?.notifier.refresh() }
    }

    @ViewBuilder private func list(_ jobs: [Job]) -> some View {
        let team = jobs.first { $0.isTeam && !$0.needsAttention }?.id ?? jobs.first(where: \.isTeam)?.id
        ForEach(jobs) { job in
            if job.id == team {
                Text(Jobs.teamIntro).font(.system(size: 11)).foregroundStyle(Pad.inkSoft)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
            JobRow(job: job, actions: actions, openSettings: setup.openSettings, open: { open(job) }, problem: { problem = $0 })
        }
    }

    // MARK: around the list

    @ViewBuilder private var notices: some View {
        if let watches, watches.store.watches.contains(where: \.on), let off = watches.notifier.offReason {
            Label(off, systemImage: "bell.slash").font(.system(size: 12)).foregroundStyle(Pad.redInk).fixedSize(horizontal: false, vertical: true)
        }
        if let notice = watches?.store.notice { Text(notice).font(.system(size: 12)).foregroundStyle(Pad.inkSoft).textSelection(.enabled) }
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

    private func unreadableRow(_ row: Jobs.Unreadable) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Label(row.text, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Pad.redInk)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 8)
            if let folder = row.folder {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }.buttonStyle(MorningActionButton())
            }
        }.padding(11).background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
    }

    /// Saved demonstrations that aren't jobs yet, each with Review & add.
    @ViewBuilder private var demonstrations: some View {
        if let sources, !Jobs.demonstrations(sources).isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Saved demonstrations").font(.system(size: 13, weight: .semibold)).padding(.top, 6)
                Text("These aren't jobs yet. Review the page and what to read before adding one.")
                    .font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                ForEach(Jobs.demonstrations(sources)) { workflow in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workflow.name).font(.system(size: 13, weight: .medium))
                                Text(workflow.draft.meaning).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                            }
                            Spacer(minLength: 10)
                            Button("Review & add") { problem = nil; reviewing = workflow.draft }
                                .buttonStyle(MorningActionButton()).disabled(isReading)
                        }
                        Label("Needs review before it can run", systemImage: "exclamationmark.circle")
                            .font(.system(size: 11)).foregroundStyle(Pad.redInk)
                        if !workflow.draft.uncertainties.isEmpty {
                            Text(workflow.draft.uncertainties.joined(separator: " ")).font(.system(size: 11)).foregroundStyle(Pad.inkSoft)
                        }
                    }.padding(12).background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private func review(_ draft: LearnedReadingSource) -> some View {
        ReadingSourceEditor(source: draft, isRunning: isReading, save: { source in
            guard let sources, !isReading else { throw CalendarDataError.invalid("Wait for the current reading to finish before saving changes.") }
            try sources.saveReadingSource(source)
            reviewing = nil
            feedback = "“\(source.name)” is a job now. Run now reads it."
        }, cancel: { reviewing = nil }).id(draft.id)
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

    /// How to start a job: teach one that reads with Watch Me, or ask the chat to watch items; and where your team's
    /// jobs come from, when none are here.
    private func footer(empty: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let teach, sources != nil {
                Button("Teach a job with Watch Me", action: teach)
                    .buttonStyle(MorningActionButton(primary: empty)).disabled(isReading)
            }
            if let watches {
                Text(Jobs.watchHint).font(.system(size: 12)).foregroundStyle(Pad.inkSoft).fixedSize(horizontal: false, vertical: true)
                if !watches.store.watches.contains(where: \.isTeam) && watches.store.teamUnreadable.isEmpty {
                    Text(Jobs.emptyTeam(linked: watches.store.teamDirectory() != nil))
                        .font(.system(size: 11)).foregroundStyle(Pad.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.padding(.top, 8)
    }
}

/// The Jobs box on the Morning Files home: how many jobs there are, how many need attention, and when one last ran.
struct JobsEntry: View {
    let morning: MorningStore
    let sources: CalendarStore?
    let runner: CalendarCollectionRunner?
    let watches: WatchListPanel?
    var setup = JobsSetup()
    let open: () -> Void
    var now: () -> Date = Date.init
    @StateObject private var changes: JobsChanges

    init(morning: MorningStore, sources: CalendarStore?, runner: CalendarCollectionRunner?, watches: WatchListPanel?,
         setup: JobsSetup = JobsSetup(), open: @escaping () -> Void, now: @escaping () -> Date = Date.init) {
        self.morning = morning
        self.sources = sources
        self.runner = runner
        self.watches = watches
        self.setup = setup
        self.open = open
        self.now = now
        _changes = StateObject(wrappedValue: JobsChanges(sources: sources, runner: runner, watches: watches, morning: morning))
    }

    var body: some View {
        let jobs = Jobs.list(Jobs.Input(sources: sources, watches: watches, morning: morning, setup: setup, now: now()))
        let summary = Jobs.summary(jobs, demonstrations: sources.map { Jobs.demonstrations($0).count } ?? 0, now: now())
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
