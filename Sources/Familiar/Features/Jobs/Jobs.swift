import Foundation

/// Something Noteling runs that produces results and a card. A reading job is a saved source: it reads mail, a web
/// page or a calendar, through the screen or a script, and the card step decides what becomes a card (`CalendarStore`,
/// run by `CalendarCollectionRunner`). A watch checks items on a schedule and keeps one card for what it finds
/// (`WatchListStore`, run by `WatchListRunner`). A job kept as a folder runs its job.py on a schedule and keeps one card
/// while its output has a preview (`FolderJobStore`, run by `FolderJobRunner`). To a person they are all jobs: the Jobs
/// page lists them as one, and each kind keeps its own storage and runner.
struct Job: Identifiable, Equatable {
    enum Kind: Equatable {
        case mail, web, calendar, watch, teamWatch, job, teamJob
    }

    /// How a job stands, on its row and its page. A job that is ready says nothing.
    enum Status: Equatable {
        case ready, running, waiting, paused, pausedByTeam, off, needsSettings, needsReview, cantRunYet, failed

        var label: String? {
            switch self {
            case .ready: return nil
            case .running: return "Running"
            case .waiting: return "Waiting to run"
            case .paused: return "Paused"
            case .pausedByTeam: return "Paused in the team's tools"
            case .off: return "Off"
            case .needsSettings: return "Needs Settings"
            case .needsReview: return "Needs review"
            case .cantRunYet: return "Can't run yet"
            case .failed: return "Failed"
            }
        }

        /// Something the person has to do or look at: said in red.
        var isProblem: Bool { [.needsSettings, .needsReview, .cantRunYet, .failed].contains(self) }
    }

    var id: UUID
    var kind: Kind
    var name: String
    /// A team job's path in the team's tools; empty for any other job.
    var path = ""
    /// What it does: "Reads mail", "Checks 3 items", "Checks 3 items · from your team's tools".
    var does: String
    /// How often it runs: "Every 15 minutes", "Every 2 hours · Ends Sat Oct 31, 11:59 PM", "When you run it".
    var every: String
    /// When it last ran and what came of it: "Last run 6:31 PM · 12 new · 3 cards", or "Not run yet".
    var lastRun: String
    var lastRunAt: Date? = nil
    var status: Job.Status
    /// What its last run came to is a problem (items not as expected, a partial read): its last-run line is red.
    var resultIsProblem = false
    /// What needs the person before it can run well, one line each, in red: why it can't run, what Settings lacks, or
    /// what is wrong with its files.
    var problems: [String] = []
    /// Why its last run failed or fell short, in red on its row; its page shows it with that run's results.
    var runProblem: String? = nil
    /// What to know about it, said quietly: a watch's items file, the rows it leaves out, columns its check doesn't report.
    var notes: [String] = []
    /// Listed first: a failure, a problem, something missing in Settings, or items that aren't as expected.
    var needsAttention = false
    /// What it is for, in the person's words: a reading job's meaning.
    var meaning = ""
    /// A watch that is paused (yours by you, your team's in its tools), and whether your team's job is on for you.
    var paused = false
    var on = true
    /// A watch before its start or after its end: out of the way, under Upcoming or Ended, only to be looked at. Every
    /// other job is live.
    var phase = WatchListPhase.live
    /// When an upcoming job starts, or when an ended one ended: the order they're listed in.
    var phaseAt: Date? = nil

    var isTeam: Bool { kind == .teamWatch || kind == .teamJob }
    var isWatch: Bool { kind == .watch || kind == .teamWatch }
    /// A job kept as a folder, yours or your team's.
    var isFolderJob: Bool { kind == .job || kind == .teamJob }
    /// A reading job: one that reads mail, a web page or a calendar.
    var isReading: Bool { [.mail, .web, .calendar].contains(kind) }
    var isLive: Bool { phase == .live }
    /// Everything its row says is wrong: what needs the person, then its last run's problem.
    var allProblems: [String] { problems + (runProblem.map { [$0] } ?? []) }
    /// "Reads mail · When you run it": what it does and how often, on one line.
    var line: String { does + " · " + every }
}

/// What only the app knows about jobs: the secrets each still needs in Settings, whether mouse and keyboard control
/// is on (a reading job that reads from the screen needs it), and how to open Settings. Tests and renders leave it empty.
struct JobsSetup {
    var missingSecrets: (LearnedReadingSource) -> [String] = { _ in [] }
    var missingWatchSecrets: (WatchListWatch) -> [String] = { _ in [] }
    var missingJobSecrets: (FolderJob) -> [String] = { _ in [] }
    var controlAllowed: () -> Bool = { true }
    var openSettings: (() -> Void)? = nil
}

/// One reading job's part of one run in the run archive.
struct JobRun: Equatable {
    var run: SourceRunRecord
    var entry: SourceRunEntry
    /// When that part ended, or began while it runs.
    var at: Date { entry.finishedAt ?? entry.startedAt ?? run.startedAt }
}

/// The jobs as the Jobs page, a job's page and the Morning Files home say them: one list made of the reading jobs and
/// the watches, each job's words, how it stands, the order they come in, and the cards each one made.
@MainActor
enum Jobs {
    static let whenYouRunIt = "When you run it"
    static let notRunYet = "Not run yet"
    static let fromTeam = "from your team's tools"
    static let teamIntro = "From your team's tools. Turn on the ones that are yours: only those run and tell you."
    static let empty = "No jobs yet. A job reads your mail, a web page or a calendar, or checks items on a schedule, and puts what matters on a card."
    static let watchHint = "To check items on a schedule, ask in chat: “watch these items: …”"
    static let needsReview = "Confirm its address and what to read before it runs."
    static let readsFromScreen = "It reads from the screen, so it needs mouse and keyboard control: turn that on in Settings."
    /// The Jobs page and the home's box when every job is before its start or past its end.
    static let noneLive = "No jobs running now"
    static let outsideIntro = "Before their start and after their end, jobs stay out of the way: they don't run, tell you or keep a card."
    static let armIntro = "Turn on an upcoming team job to have it run from its start."

    /// Your team's jobs, under the list: where they come from.
    static func emptyTeam(linked: Bool) -> String {
        linked ? "Your team's tools have no jobs yet." : "Your team's jobs show here once your team's tools are linked in Settings."
    }

    /// What the jobs are made of, at one moment.
    struct Input {
        var calendars: [LearnedCalendarSource] = []
        var readings: [LearnedReadingSource] = []
        /// Every run of the reading jobs, newest first, as `SourceRunStore` keeps them.
        var runs: [SourceRunRecord] = []
        var watches: [WatchListWatch] = []
        /// The watches being checked right now.
        var checking: Set<UUID> = []
        /// Watches whose watch.json or items file can't be read right now, and why.
        var problems: [UUID: String] = [:]
        /// The jobs kept as folders, the one running and those waiting their turn.
        var folderJobs: [FolderJob] = []
        var runningJob: UUID?
        var queuedJobs: Set<UUID> = []
        var cards: [MorningCard] = []
        /// The runs the card step has sorted.
        var sorted: Set<UUID> = []
        var setup = JobsSetup()
        var now = Date()
    }

    // MARK: the list

    /// Every job, live or not, in the order the Jobs page lists the live ones (`outside` orders the rest).
    static func list(_ input: Input) -> [Job] {
        sorted(input.calendars.map { calendarJob($0, input) } + input.readings.map { readingJob($0, input) }
               + input.watches.map { watchJob($0, input) } + input.folderJobs.map { folderJob($0, input) })
    }

    /// One job, as its page shows it; nil once it is gone.
    static func job(_ id: UUID, _ input: Input) -> Job? {
        if let source = input.readings.first(where: { $0.id == id }) { return readingJob(source, input) }
        if let source = input.calendars.first(where: { $0.id == id }) { return calendarJob(source, input) }
        if let job = input.folderJobs.first(where: { $0.id == id }) { return folderJob(job, input) }
        return input.watches.first { $0.id == id }.map { watchJob($0, input) }
    }

    /// The jobs out of the way, as the Jobs page lists them under its Upcoming and Ended line: those that start
    /// soonest first, and those that ended most recently first; each then by name.
    static func outside(_ jobs: [Job]) -> (upcoming: [Job], ended: [Job]) {
        func by(_ jobs: [Job], soonest: Bool) -> [Job] {
            jobs.sorted { a, b in
                if a.phaseAt != b.phaseAt, let x = a.phaseAt, let y = b.phaseAt { return soonest ? x < y : x > y }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
        return (by(jobs.filter { $0.phase == .upcoming }, soonest: true), by(jobs.filter { $0.phase == .ended }, soonest: false))
    }

    /// The line under the live jobs: "Upcoming (1) · Ended (2) · Show", or "Hide upcoming and ended jobs" while they're
    /// shown; nothing when every job is live.
    static func outsideLine(upcoming: Int, ended: Int, showing: Bool) -> String? {
        guard upcoming + ended > 0 else { return nil }
        if showing {
            return "Hide " + (upcoming > 0 && ended > 0 ? "upcoming and ended" : upcoming > 0 ? "upcoming" : "ended") + " jobs"
        }
        let counts = [(upcoming, "Upcoming"), (ended, "Ended")].filter { $0.0 > 0 }.map { "\($0.1) (\($0.0))" }
        return (counts + ["Show"]).joined(separator: " · ")
    }

    /// Those that need attention first; then yours, then your team's; each by name.
    static func sorted(_ jobs: [Job]) -> [Job] {
        jobs.sorted { a, b in
            if a.needsAttention != b.needsAttention { return a.needsAttention }
            if a.isTeam != b.isTeam { return !a.isTeam }
            let order = a.name.localizedStandardCompare(b.name)
            if order != .orderedSame { return order == .orderedAscending }
            return a.id.uuidString < b.id.uuidString
        }
    }

    // MARK: reading jobs

    static func readingJob(_ source: LearnedReadingSource, _ input: Input) -> Job {
        var blocked: (Job.Status, String)?
        if source.requiresReview { blocked = (.needsReview, needsReview) }
        else if let missing = source.missingSetup { blocked = (.cantRunYet, missing) }
        var settings: String?
        if source.readsThroughScript {
            let missing = input.setup.missingSecrets(source)
            if !missing.isEmpty { settings = needs(missing) }
        } else if !input.setup.controlAllowed() {
            settings = readsFromScreen
        }
        return sourceJob(id: source.id, kind: source.kind == .mail ? .mail : .web, name: source.name, meaning: source.meaning,
                         does: source.kind == .mail ? "Reads mail" : "Reads a web page", blocked: blocked, settings: settings, input)
    }

    static func calendarJob(_ source: LearnedCalendarSource, _ input: Input) -> Job {
        var blocked: (Job.Status, String)?
        do { try CalendarReadRequest(source: source, day: input.now).validate() }
        catch { blocked = (.cantRunYet, error.localizedDescription) }
        return sourceJob(id: source.id, kind: .calendar, name: source.name, meaning: source.meaning, does: "Reads your calendar",
                         blocked: blocked, settings: input.setup.controlAllowed() ? nil : readsFromScreen, input)
    }

    private static func sourceJob(id: UUID, kind: Job.Kind, name: String, meaning: String, does: String,
                                  blocked: (Job.Status, String)?, settings: String?, _ input: Input) -> Job {
        let current = latest(id, in: input.runs, finished: false)
        let finished = latest(id, in: input.runs, finished: true)
        let state = finished?.entry.state
        var status = Job.Status.ready
        if let current, current.run.status == .running, current.entry.state == .reading { status = .running }
        else if let current, current.run.status == .running, current.entry.state == .waiting { status = .waiting }
        else if let blocked { status = blocked.0 }
        else if settings != nil { status = .needsSettings }
        else if state == .failed || state == .interrupted { status = .failed }

        var problems: [String] = []
        if let blocked { problems.append(blocked.1) }
        if let settings { problems.append(settings) }
        var runProblem: String?
        if let finished, let state, [.failed, .interrupted, .notRun, .partial].contains(state) {
            let notes = finished.entry.readingSnapshot?.coverageNotes ?? finished.entry.calendarSnapshot?.coverageNotes ?? []
            let why = state == .partial ? (notes.first ?? finished.entry.message) : finished.entry.message
            if calendarHasText(why) { runProblem = SourceResultPresentation.excerpt(why, limit: 240) }
        }
        let lastRun = finished.map { run in
            "Last run " + WatchListWords.time(run.at, now: input.now) + " · "
                + result(run, cards: cardCount(id, run: run.run.id, input.cards), sorted: input.sorted.contains(run.run.id))
        } ?? notRunYet
        let troubled = state == .partial || state == .notRun || state == .failed || state == .interrupted
        return Job(id: id, kind: kind, name: name, does: does, every: whenYouRunIt, lastRun: lastRun, lastRunAt: finished?.at,
                   status: status, resultIsProblem: troubled, problems: problems, runProblem: runProblem,
                   needsAttention: status.isProblem || state == .partial || state == .notRun, meaning: meaning)
    }

    /// A reading job's newest part of a run, or its newest that has ended.
    static func latest(_ id: UUID, in runs: [SourceRunRecord], finished: Bool) -> JobRun? {
        for run in runs {
            guard let entry = run.entries.first(where: { $0.sourceID == id }) else { continue }
            if finished && (entry.state == .waiting || entry.state == .reading) { continue }
            return JobRun(run: run, entry: entry)
        }
        return nil
    }

    /// What a reading job's run came to, in a few words: "12 new · 3 cards", "2 found · no cards", "3 events",
    /// "partial · 2 found", "nothing saved", "stopped" or "didn't run". The cards are those that run made or saw again;
    /// "no cards" only once the card step has sorted it.
    static func result(_ part: JobRun, cards: Int, sorted: Bool) -> String {
        let entry = part.entry
        switch entry.state {
        case .complete, .partial:
            var words: [String] = []
            if let snapshot = entry.readingSnapshot {
                if let counts = snapshot.scriptRead {
                    words.append(counts.arrived == 0 ? "nothing new"
                                 : counts.truncated ? "\(snapshot.items.count) of \(counts.arrived) new" : "\(counts.arrived) new")
                } else {
                    if entry.state == .partial { words.append("partial") }
                    words.append(snapshot.items.isEmpty ? "nothing found" : "\(snapshot.items.count) found")
                }
            } else if let snapshot = entry.calendarSnapshot {
                if entry.state == .partial { words.append("partial") }
                let count = snapshot.events.count
                words.append(count == 0 ? "no events" : "\(count) event\(count == 1 ? "" : "s")")
            }
            if cards > 0 { words.append("\(cards) card\(cards == 1 ? "" : "s")") }
            else if sorted { words.append("no cards") }
            return words.joined(separator: " · ")
        case .failed, .interrupted: return "nothing saved"
        case .stopped: return "stopped"
        case .notRun: return "didn't run"
        case .waiting, .reading: return "running"
        }
    }

    /// The cards one run of a reading job made or saw again.
    static func cardCount(_ sourceID: UUID, run: UUID, _ cards: [MorningCard]) -> Int {
        cards.filter { $0.tracking?.sourceID == sourceID && $0.tracking?.lastRunID == run }.count
    }

    // MARK: watches

    /// A watch as a job. Before its start or after its end, nothing about it asks for the person: no problem status,
    /// no red, never first in the list; an upcoming one still says what it lacks (quietly, under Upcoming), so it can
    /// be put right before it starts.
    static func watchJob(_ watch: WatchListWatch, _ input: Input) -> Job {
        let now = input.now
        let phase = watch.phase(at: now)
        let live = phase == .live
        let missing = input.setup.missingWatchSecrets(watch)
        let checked = watch.items.filter { $0.status != nil }
        let grey = watch.items.filter { if case .couldNotCheck? = $0.status { return true }; return false }
        let red = watch.items.filter(\.isRed)
        let failed = !checked.isEmpty && grey.count == checked.count
        let status: Job.Status = input.checking.contains(watch.id) ? .running
            : watch.isTeam && !watch.on ? .off
            : watch.paused ? (watch.isTeam ? .pausedByTeam : .paused)
            : !live ? .ready
            : !missing.isEmpty ? .needsSettings
            : failed ? .failed : .ready
        var problems: [String] = []
        if let problem = WatchListWords.problem(input.problems[watch.id]) { problems.append(problem) }
        if !missing.isEmpty { problems.append(needs(missing)) }
        if phase == .ended { problems = [] }
        var runProblem: String?
        if status == .failed, case .couldNotCheck(let reason)? = grey.first?.status { runProblem = "Couldn't check: " + reason }
        let last = ([watch.lastRunAt] + watch.items.map(\.checkedAt)).compactMap { $0 }.max()
        let lastRun = last.map { "Last run " + WatchListWords.time($0, now: now) + (watchResult(watch).map { " · " + $0 } ?? "") } ?? notRunYet
        let items = watch.items.isEmpty ? "Checks no items yet" : "Checks " + WatchListWords.itemCount(watch.items.count)
        let running = watch.checking(at: now)
        let troubled = !red.isEmpty || !grey.isEmpty
        return Job(id: watch.id, kind: watch.isTeam ? .teamWatch : .watch, name: watch.name, path: watch.isTeam ? watch.path : "",
                   does: items + (watch.isTeam ? " · " + fromTeam : ""), every: WatchListWords.schedule(watch, now: now),
                   lastRun: lastRun, lastRunAt: last, status: status, resultIsProblem: live && watch.on && troubled, problems: problems,
                   runProblem: runProblem, notes: WatchListWords.notes(watch),
                   needsAttention: live && ((watch.on && input.problems[watch.id] != nil) || (running && (!missing.isEmpty || troubled))),
                   paused: watch.paused, on: watch.on, phase: phase,
                   phaseAt: phase == .upcoming ? watch.starts?.date : phase == .ended ? watch.ends?.date : nil)
    }

    /// How a watch's items stand after its runs, in a few words: "2 of 8 not as expected · 1 couldn't check",
    /// "couldn't check 1 of 8", "all 8 as expected", "3 of 4 as expected · 1 not checked yet"; nil before any is checked.
    static func watchResult(_ watch: WatchListWatch) -> String? {
        let count = watch.items.count
        guard count > 0 else { return "no items" }
        var red = 0, grey = 0, green = 0, unchecked = 0
        for item in watch.items {
            switch item.status {
            case .asExpected?: green += 1
            case .notAsExpected?: red += 1
            case .couldNotCheck?: grey += 1
            case nil: unchecked += 1
            }
        }
        guard unchecked < count else { return nil }
        var words: [String] = []
        if red > 0 { words.append("\(red) of \(count) not as expected") }
        if grey > 0 { words.append(red > 0 ? "\(grey) couldn't check" : "couldn't check \(grey) of \(count)") }
        if red == 0 && grey == 0 { words.append(green == count ? "all \(count) as expected" : "\(green) of \(count) as expected") }
        if unchecked > 0 { words.append("\(unchecked) not checked yet") }
        return words.joined(separator: " · ")
    }

    // MARK: jobs kept as folders

    /// A job kept as a folder as a job: what it's about, how often it runs, how its last run went (what its `run()`
    /// said, or that it failed, and why), and whether it's on. Before its start or after its end, as a watch: nothing
    /// asks for the person.
    static func folderJob(_ job: FolderJob, _ input: Input) -> Job {
        let now = input.now
        let phase = job.phase(at: now)
        let live = phase == .live
        let missing = input.setup.missingJobSecrets(job)
        let failed = job.state.error != nil
        let status: Job.Status = input.runningJob == job.id ? .running : input.queuedJobs.contains(job.id) ? .waiting
            : job.isTeam && !job.on ? .off
            : !live ? .ready
            : !missing.isEmpty ? .needsSettings
            : failed ? .failed : .ready
        var problems = missing.isEmpty ? [] : [needs(missing)]
        if phase == .ended { problems = [] }
        let about = job.about.isEmpty ? "Runs its job.py" : WatchListValue.clip(job.about.components(separatedBy: .newlines).first ?? "", 90)
        return Job(id: job.id, kind: job.isTeam ? .teamJob : .job, name: job.name, path: job.isTeam ? job.path : "",
                   does: about + (job.isTeam ? " · " + fromTeam : ""), every: FolderJobWords.schedule(job, now: now),
                   lastRun: FolderJobWords.lastRun(job, now: now), lastRunAt: job.state.lastRunAt, status: status,
                   resultIsProblem: live && job.on && failed, problems: problems,
                   runProblem: live && failed ? job.state.error : nil,
                   needsAttention: live && job.on && (failed || !missing.isEmpty), meaning: job.about, on: job.on, phase: phase,
                   phaseAt: phase == .upcoming ? job.starts?.date : phase == .ended ? job.ends?.date : nil)
    }

    // MARK: cards

    /// The cards a job made, to open from its page: a watch's one card (its job.json in the cards inbox), whether open
    /// or resolved; a job kept as a folder's preview card, and the open cards its script wrote itself; or a reading
    /// job's open cards, those its latest run made or saw first, then the newest.
    static func cards(for job: Job, _ input: Input) -> [MorningCard] {
        if job.isFolderJob {
            guard let folderJob = input.folderJobs.first(where: { $0.id == job.id }) else { return [] }
            let id = CardInboxFormat.cardID(FolderJobCards.key(for: folderJob))
            let own = FolderJobCards.scriptSource(for: folderJob) + "/"
            return input.cards.filter { $0.id == id } + input.cards.filter { !$0.isResolved && $0.inbox?.key.hasPrefix(own) == true }
        }
        if job.isWatch {
            guard let watch = input.watches.first(where: { $0.id == job.id }) else { return [] }
            let id = CardInboxFormat.cardID(WatchListCards.key(for: watch))
            return input.cards.filter { $0.id == id }
        }
        let newest = latest(job.id, in: input.runs, finished: true)?.run.id
        return input.cards.filter { $0.tracking?.sourceID == job.id && !$0.isResolved }.sorted { a, b in
            let aLatest = a.tracking?.lastRunID == newest, bLatest = b.tracking?.lastRunID == newest
            if aLatest != bLatest { return aLatest }
            return a.updatedAt > b.updatedAt
        }
    }

    /// The link to a job's cards: "Card", "Card (resolved)" or "Cards (3)"; nil when it has none.
    static func cardLabel(_ cards: [MorningCard]) -> String? {
        switch cards.count {
        case 0: return nil
        case 1: return cards[0].isResolved ? "Card (resolved)" : "Card"
        default: return "Cards (\(cards.count))"
        }
    }

    // MARK: the rest of the page

    /// A folder among the watches that isn't a job, and why: listed with the jobs that need attention.
    struct Unreadable: Identifiable, Equatable {
        var id: String
        var text: String
        /// Yours, to show in Finder; nil for your team's.
        var folder: URL?
    }

    static func unreadable(own: [String: String], team: [String: String], directory: URL, ownJobs: [String: String] = [:],
                           teamJobs: [String: String] = [:], jobsDirectory: URL? = nil) -> [Unreadable] {
        own.keys.sorted().map { Unreadable(id: "own:" + $0, text: "The job in the “\($0)” folder can't run. \(own[$0] ?? "")",
                                           folder: directory.appendingPathComponent($0)) }
            + team.keys.sorted().map { Unreadable(id: "team:" + $0, text: "Not listing your team's job \($0). \(team[$0] ?? "")") }
            + ownJobs.keys.sorted().map { Unreadable(id: "own-job:" + $0, text: "The job in the “\($0)” folder can't run. \(ownJobs[$0] ?? "")",
                                                     folder: jobsDirectory?.appendingPathComponent($0)) }
            + teamJobs.keys.sorted().map { Unreadable(id: "team-job:" + $0, text: "Not listing your team's job \($0). \(teamJobs[$0] ?? "")") }
    }

    /// Saved demonstrations that aren't jobs yet: each needs a review before it can be added.
    static func demonstrations(_ store: CalendarStore) -> [SavedReadingWorkflow] {
        store.savedReadingWorkflows.filter { workflow in !store.readingSources.contains { $0.id == workflow.draft.id } }
    }

    /// The Jobs box on the Morning Files home, in one line: "5 jobs · 2 need attention · last run 6:31 PM". Only live
    /// jobs count: one before its start or past its end isn't mentioned, and with only those, "No jobs running now". A
    /// team job that is off isn't one of yours yet; with only those: "3 team jobs you can turn on".
    static func summary(_ jobs: [Job], demonstrations: Int = 0, now: Date) -> String {
        let live = jobs.filter(\.isLive)
        let yours = live.filter { $0.status != .off }
        var words: [String] = []
        if yours.isEmpty {
            let off = live.count
            words.append(off > 0 ? "\(off) team job\(off == 1 ? "" : "s") you can turn on" : jobs.isEmpty ? "No jobs yet" : noneLive)
        } else {
            words.append("\(yours.count) job\(yours.count == 1 ? "" : "s")")
            let running = yours.filter { $0.status == .running }.count
            if running > 0 { words.append("\(running) running") }
            let attention = yours.filter(\.needsAttention).count
            if attention > 0 { words.append("\(attention) need\(attention == 1 ? "s" : "") attention") }
            if let last = yours.compactMap(\.lastRunAt).max() { words.append("last run " + WatchListWords.time(last, now: now)) }
        }
        if demonstrations > 0 { words.append("\(demonstrations) demonstration\(demonstrations == 1 ? "" : "s") to review") }
        return words.joined(separator: " · ")
    }

    /// The buttons a job has on its row and its page: Run now, or Stop while it reads, or Open Settings when it needs
    /// something there; and Pause or Resume for a watch of your own, or the on/off switch for your team's job. Before
    /// its start or after its end a job is only to be looked at, and has none, except that an upcoming team job keeps
    /// its switch, so it can be turned on ahead of a start in the night.
    enum Control: Hashable {
        case runNow, stop, openSettings, pause, resume, onOff
    }

    static func controls(_ job: Job, canOpenSettings: Bool) -> [Control] {
        guard job.isLive else { return job.phase == .upcoming && job.isTeam ? [.onOff] : [] }
        var controls: [Control] = []
        if job.isReading && job.status == .running { controls.append(.stop) }
        else if job.status == .needsSettings && canOpenSettings { controls.append(.openSettings) }
        else if job.on { controls.append(.runNow) }
        if job.isTeam { controls.append(.onOff) }
        else if job.isWatch { controls.append(job.paused ? .resume : .pause) }
        return controls
    }

    /// "Needs MAIL_ADDRESS and MAIL_APP_PASSWORD in Settings."
    static func needs(_ secrets: [String]) -> String {
        let names = secrets.count < 3 ? secrets.joined(separator: " and ")
            : secrets.dropLast().joined(separator: ", ") + " and " + (secrets.last ?? "")
        return "Needs \(names) in Settings."
    }
}

extension Jobs.Input {
    /// The jobs as the stores have them now; either kind may be missing (a test, a render).
    @MainActor
    init(sources: CalendarStore?, watches: WatchListPanel?, morning: MorningStore, setup: JobsSetup = JobsSetup(), now: Date = Date(),
         folderJobs: FolderJobsPanel? = nil) {
        self.init()
        calendars = sources?.sources ?? []
        readings = sources?.readingSources ?? []
        runs = sources?.runStore.runs ?? []
        self.watches = watches?.store.watches ?? []
        checking = watches?.runner.checking ?? []
        problems = watches?.store.problems ?? [:]
        self.setup = setup
        if let folderJobs {
            self.folderJobs = folderJobs.store.jobs
            runningJob = folderJobs.runner.running
            queuedJobs = Set(folderJobs.runner.queued)
            let runner = folderJobs.runner
            self.setup.missingJobSecrets = { runner.missingSecrets($0) }   // the runner knows the Keychain
        }
        cards = morning.cards
        sorted = Set((morning.workspace.cardGenerations ?? []).flatMap(\.runIDs))
        self.now = now
    }
}
