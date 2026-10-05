import SwiftUI

/// A reading job's page: the header every job's page has, then what it is and what it reads, Edit (or Review) and
/// Remove, reading a calendar on another day, and what its latest run found, from the run screens. The parts are the
/// ones Manage sources and the run screens had: its definition, its editor and its results.
struct SourceJobPage: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var runner: CalendarCollectionRunner
    @ObservedObject private var runs: SourceRunStore
    @ObservedObject var morning: MorningStore
    let id: UUID
    var setup = JobsSetup()
    var teaching: RunTeaching? = nil
    let openCard: (UUID) -> Void
    let openRun: (UUID, UUID?) -> Void
    let openHistory: () -> Void
    /// Remove took it out of future runs: back to Jobs, which can undo it.
    let removed: (UUID) -> Void
    var now: () -> Date = Date.init
    @State private var editing = false
    @State private var confirmingRemove = false
    @State private var anotherDay = false
    @State private var day = Date()
    @State private var startHour = 9
    @State private var endHour = 17
    @State private var problem: String?
    @State private var feedback: String?

    init(store: CalendarStore, runner: CalendarCollectionRunner, morning: MorningStore, id: UUID, setup: JobsSetup = JobsSetup(),
         teaching: RunTeaching? = nil, openCard: @escaping (UUID) -> Void, openRun: @escaping (UUID, UUID?) -> Void,
         openHistory: @escaping () -> Void, removed: @escaping (UUID) -> Void, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.runner = runner
        self.runs = store.runStore
        self.morning = morning
        self.id = id
        self.setup = setup
        self.teaching = teaching
        self.openCard = openCard
        self.openRun = openRun
        self.openHistory = openHistory
        self.removed = removed
        self.now = now
    }

    private var input: Jobs.Input { Jobs.Input(sources: store, watches: nil, morning: morning, setup: setup, now: now()) }
    private var reading: LearnedReadingSource? { store.readingSources.first { $0.id == id } }
    private var calendar: LearnedCalendarSource? { store.sources.first { $0.id == id } }

    var body: some View {
        if let job = Jobs.job(id, input) {
            page(job)
        } else {
            Text("This job is no longer here.").font(.system(size: 14)).foregroundStyle(Pad.inkSoft).padding(24)
        }
    }

    private func page(_ job: Job) -> some View {
        let actions = JobActions(sources: store, runner: runner, now: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                JobHeader(job: job, controls: JobControls(job: job, actions: actions, openSettings: setup.openSettings, problem: { problem = $0 }),
                          card: JobCardLink(cards: Jobs.cards(for: job, input), open: openCard))
                if job.status == .running, !runner.status.isEmpty {
                    Text(runner.status).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                }
                ForEach(job.problems, id: \.self) { line in
                    Label(line, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Pad.redInk)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if let problem { Text(problem).font(.system(size: 12)).foregroundStyle(Pad.redInk).textSelection(.enabled) }
                if let feedback { Text(feedback).font(.system(size: 12)).foregroundStyle(Pad.penInk) }
                if editing { editor } else {
                    definition
                    links
                    if confirmingRemove { removeConfirmation(job) }
                    if anotherDay, let calendar { dayControls(calendar) }
                    Divider().overlay(Pad.tabEdge.opacity(0.35))
                    results
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: what it is

    @ViewBuilder private var definition: some View {
        if let source = reading {
            VStack(alignment: .leading, spacing: 8) {
                Text(source.meaning).font(.system(size: 14)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text([source.application, source.account, source.script.map { "reads through \($0)" } ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                if let url = URL(string: source.url), readingHTTPURL(source.url) {
                    Link("Open its page", destination: url).font(.system(size: 12)).foregroundStyle(Pad.penInk).help(source.url)
                }
                if !source.uncertainties.isEmpty {
                    Text("Assuming: " + source.uncertainties.joined(separator: " ")).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                }
                Text("Reading rules").font(.system(size: 13, weight: .semibold)).padding(.top, 4)
                Text(source.scope).font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text(source.readsThroughScript
                     ? "Reads everything that arrived through a script in your tools folder, with no window. Your reading rules decide what becomes a card."
                     : source.account.isEmpty ? "Uses the account its app or page shows. Noteling records it during each read."
                     : "Each run reads fresh information within these rules.")
                    .font(.system(size: 11)).foregroundStyle(Pad.inkSoft).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).background(Pad.paperTop.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        } else if let source = calendar {
            VStack(alignment: .leading, spacing: 8) {
                Text(source.meaning).font(.system(size: 14)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text([source.application, source.account, source.calendarName, source.timeZoneID].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                if !source.uncertainties.isEmpty {
                    Text("Still to confirm: " + source.uncertainties.joined(separator: " ")).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                }
                Text("Run now reads today, 9 AM–5 PM in the calendar’s time zone.").font(.system(size: 11)).foregroundStyle(Pad.inkSoft)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).background(Pad.paperTop.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Edit (Review for a job learned from a demonstration that needs it), Remove, another day for a calendar, and
    /// Run history.
    private var links: some View {
        HStack(spacing: 16) {
            if reading?.requiresReview == true {
                Button("Review") { start(editing: true) }.buttonStyle(MorningActionButton(primary: true)).disabled(runner.isRunning)
            } else {
                Button("Edit") { start(editing: true) }.disabled(runner.isRunning)
            }
            Button("Remove…") { problem = nil; confirmingRemove = true }.disabled(runner.isRunning)
            if calendar != nil { Button(anotherDay ? "Hide another day" : "Read another day…") { anotherDay.toggle() }.disabled(runner.isRunning) }
            Button("Run history", action: openHistory)
        }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
    }

    private func start(editing value: Bool) {
        problem = nil
        feedback = nil
        confirmingRemove = false
        editing = value
    }

    @ViewBuilder private var editor: some View {
        if runner.isRunning {
            HStack {
                ProgressView().controlSize(.small)
                Text("Reading now. You can change this job when the run ends.").font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                Spacer()
                Button("Stop") { _ = runner.stopActive() }.buttonStyle(MorningActionButton())
            }
        }
        if let source = reading {
            ReadingSourceEditor(source: source, isRunning: runner.isRunning, save: { edited in
                guard !runner.isRunning else { throw CalendarDataError.invalid("Wait for the current reading to finish before saving changes.") }
                try store.saveReadingSource(edited)
                editing = false
                feedback = "Saved. Its next run uses these details and reading rules."
            }, cancel: { editing = false }).id(source.id)
        } else if let source = calendar {
            CalendarSourceEditor(source: source, isRunning: runner.isRunning, save: { edited in
                guard !runner.isRunning else { throw CalendarDataError.invalid("Wait for the current reading to finish before saving changes.") }
                try store.saveSource(edited)
                editing = false
                feedback = "Saved. Its next run uses these details."
            }, cancel: { editing = false }).id(source.id)
        }
    }

    private func removeConfirmation(_ job: Job) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Remove “\(job.name)”?").font(.system(size: 13, weight: .semibold))
            Text("It stops running. Its saved results and its cards stay, and you can restore it under Removed jobs. Its app and saved demonstration aren't touched.")
                .font(.system(size: 12)).foregroundStyle(Pad.inkSoft).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Remove") {
                    confirmingRemove = false
                    guard !runner.isRunning else { problem = "Wait for the current reading to finish."; return }
                    do { try store.removeSource(id: id); removed(id) } catch { problem = error.localizedDescription }
                }.buttonStyle(MorningActionButton(primary: true))
                Button("Cancel") { confirmingRemove = false }.buttonStyle(MorningActionButton())
            }
        }.padding(12).background(Pad.paperTop.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    /// A calendar on a chosen day and hours, as Manage sources read it.
    private func dayControls(_ source: LearnedCalendarSource) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Read another day").font(.system(size: 13, weight: .semibold))
            DatePicker("Read this day", selection: $day, displayedComponents: .date)
                .environment(\.timeZone, TimeZone(identifier: source.timeZoneID) ?? .current)
            HStack {
                Picker("From", selection: $startHour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                Picker("Until", selection: $endHour) { ForEach(1...24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
            }
            Text(source.timeZoneID.isEmpty ? "Edit the job to confirm its time zone, account and calendar before reading."
                 : "Briefing window in \(source.timeZoneID). Open time refers only to this calendar.")
                .font(.system(size: 11)).foregroundStyle(Pad.inkSoft)
            Button("Read calendar") {
                let request = CalendarReadRequest(source: source, day: day, startHour: startHour, endHour: endHour)
                do {
                    try request.validate()
                    problem = runner.collect(source: source, day: day, startHour: startHour, endHour: endHour) == nil
                        ? (runner.error ?? "It couldn't start.") : nil
                } catch { problem = error.localizedDescription }
            }.buttonStyle(MorningActionButton(primary: true)).disabled(runner.isRunning)
        }.font(.system(size: 13)).padding(14).background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: what it found

    /// Its latest run's findings, from the run screens, with the way to the whole run; or that it hasn't run.
    @ViewBuilder private var results: some View {
        if let part = Jobs.latest(id, in: runs.runs, finished: false) {
            HStack(alignment: .firstTextBaseline) {
                Text("Latest run").font(.system(size: 13, weight: .semibold))
                Text(part.run.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                Spacer()
                Button("Open the run") { openRun(part.run.id, id) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
                    .help("The whole run, with its saved files")
            }
            SourceResultContent(presentation: SourceResultPresentation(entry: part.entry),
                                collectedAt: part.entry.readingSnapshot?.collectedAt ?? part.entry.calendarSnapshot?.collectedAt,
                                teaching: teaching, showsTitle: false)
        } else {
            Text("Not run yet. Run now reads it, and what it finds shows here.").font(.system(size: 13)).foregroundStyle(Pad.inkSoft)
        }
    }
}
