import AppKit
import Combine
import SwiftUI

/// Follows the store and the runner the jobs come from, so one view redraws when either changes; and the clock, so a
/// job that starts or ends moves between the live jobs and Upcoming or Ended with nothing else changing.
@MainActor
final class JobsChanges: ObservableObject {
    private var subscriptions: [AnyCancellable] = []
    private var windows: Task<Void, Never>?
    /// The longest it waits before looking again for the next start or end, in case a job's dates changed.
    static let windowLook: TimeInterval = 300

    init(folderJobs: FolderJobsPanel) {
        var publishers = [folderJobs.store.objectWillChange, folderJobs.runner.objectWillChange]
        if let notifier = folderJobs.notifier { publishers.append(notifier.objectWillChange) }
        subscriptions = publishers.map { $0.sink { [weak self] _ in self?.objectWillChange.send() } }
        followWindows(folderJobs.store)
    }

    /// Wakes the views a second after the next job starts or ends. It holds neither the views nor the store.
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

/// What the job controls do: run a job now, and turn your team's job on or off. Each says in plain words why it couldn't.
@MainActor
struct JobActions {
    var now: () -> Date = Date.init
    let folderJobs: FolderJobsPanel

    /// Whether Run now can start it: while it's on, between its start and end, and not already running or waiting its turn.
    func canRun(_ job: Job) -> Bool {
        guard let folderJob = folderJobs.store.job(id: job.id) else { return false }
        return !folderJobs.runner.isBusy(job.id) && folderJob.running(at: now())
    }

    /// Run now: runs its job.py. Nil once it started; otherwise why not.
    func runNow(_ job: Job) -> String? { folderJobs.runner.run(job.id) }

    func turn(_ job: Job, on: Bool) -> String? {
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
        case .openSettings:
            Button("Open Settings") { openSettings?() }.buttonStyle(PaperActionButton())
        case .runNow:
            Button(job.status == .running ? "Running…" : "Run now") { problem(actions.runNow(job)) }
                .buttonStyle(PaperActionButton()).disabled(!actions.canRun(job))
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

/// The top of a job's page: its name, what it does and how often, how its last run went, how it stands, and its buttons.
struct JobHeader: View {
    let job: Job
    let controls: JobControls

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
        case .job, .teamJob: return "folder"
        }
    }
}

/// Every live job in one list, yours and your team's. Those that need attention come first, then yours, then your
/// team's, each by name; a row opens the job's page. Jobs before their start or past their end wait under one line,
/// "Upcoming (1) · Ended (2) · Show", only to be looked at. Around the list: folders that aren't jobs, and why; and
/// where jobs come from.
struct JobsPage: View {
    let folderJobs: FolderJobsPanel
    var setup = JobsSetup()
    @ObservedObject var navigation: JobsNavigation
    var now: () -> Date = Date.init
    @StateObject private var changes: JobsChanges
    @State private var problem: String?
    /// The jobs before their start or past their end are shown, under the live jobs.
    @State private var showingOutside = false

    /// `showingOutside` starts with the jobs before their start or past their end shown (a render).
    init(folderJobs: FolderJobsPanel, setup: JobsSetup = JobsSetup(), navigation: JobsNavigation,
         now: @escaping () -> Date = Date.init, showingOutside: Bool = false) {
        self.folderJobs = folderJobs
        self.setup = setup
        self.navigation = navigation
        self.now = now
        _changes = StateObject(wrappedValue: JobsChanges(folderJobs: folderJobs))
        _showingOutside = State(initialValue: showingOutside)
    }

    private var input: Jobs.Input { Jobs.Input(setup: setup, now: now(), folderJobs: folderJobs) }
    private var actions: JobActions { JobActions(now: now, folderJobs: folderJobs) }

    /// A job's page.
    func open(_ job: Job) { navigation.route = .folderJob(job.id) }

    var body: some View {
        let all = Jobs.list(input)
        // A search over your team's jobs leaves out the ones that don't match, but never one you turned on.
        let shown = Jobs.searched(all, search)
        let jobs = shown.filter(\.isLive)
        let team = (shown: shown.filter(\.isTeam).count, total: all.filter(\.isTeam).count)
        let unreadable = Jobs.unreadable(own: folderJobs.store.unreadable, team: folderJobs.store.teamUnreadable, directory: folderJobs.store.directory)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                notices
                receiptRow
                ForEach(unreadable) { unreadableRow($0) }
                list(jobs, team: team)
                if jobs.isEmpty && unreadable.isEmpty {
                    Text(all.isEmpty ? Jobs.empty : Jobs.noneLive + ".").font(.system(size: 14))
                        .foregroundStyle(all.isEmpty ? Pad.ink : Pad.inkSoft).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                }
                outside(Jobs.outside(shown))
                footer
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await folderJobs.notifier?.refresh() }
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
        if Jobs.showsSearch(teamJobs: team.total, search: folderJobs.store.search) {
            JobsSearchBox(store: folderJobs.store, shown: team.shown, total: team.total)
        }
    }

    /// The search over your team's jobs, as last kept.
    private var search: String { folderJobs.store.search }

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

    /// What came of the deck today, in one line, which opens the receipt.
    @ViewBuilder private var receiptRow: some View {
        if let matters = folderJobs.matters {
            let receipt = Receipt.today(log: folderJobs.runner.memory, matters: matters, now: now())
            Button { navigation.open(.receipt, returningTo: .jobs) } label: {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.seal").frame(width: 17).foregroundStyle(Pad.penInk)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("What's been handled").font(.system(size: 13, weight: .semibold))
                        Text(receipt.tally + (receipt.yours.isEmpty ? "" : " · \(receipt.yours.count) yours")).font(.system(size: 11)).foregroundStyle(Pad.inkSoft).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Pad.inkSoft)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(11).background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
            .help("Today's tally, what you took, what Noteling did, what you put away")
        }
    }

    @ViewBuilder private var notices: some View {
        if folderJobs.store.jobs.contains(where: \.on), let off = folderJobs.notifier?.offReason {
            Label(off, systemImage: "bell.slash").font(.system(size: 12)).foregroundStyle(Pad.redInk).fixedSize(horizontal: false, vertical: true)
        }
        if let problem {
            HStack(alignment: .top) {
                Text(problem).font(.system(size: 12)).foregroundStyle(Pad.redInk).textSelection(.enabled)
                Spacer(minLength: 8)
                Button { self.problem = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
            }
        }
        if let receipt = folderJobs.runner.receipt { FolderJobReceiptLine(receipt: receipt, dismiss: folderJobs.runner.dismissReceipt) }
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
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }.buttonStyle(PaperActionButton())
            }
        }.padding(11).background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
    }

    /// Where your team's jobs come from, when none are here; and the guides: how jobs work, and how to write them for a
    /// team.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !folderJobs.store.jobs.contains(where: \.isTeam) && folderJobs.store.teamUnreadable.isEmpty {
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
