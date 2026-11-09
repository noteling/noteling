import Foundation

/// Something Noteling runs on a schedule: a job kept as a folder, yours in `jobs/` in Noteling's folder or your team's
/// in their linked tools, that runs its job.py and reports what it finds (`FolderJobStore`, run by `FolderJobRunner`).
/// The Jobs page lists them as one list; this is each one as that list and the job's own page say it.
struct Job: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Yours, in `jobs/`; your team's, in their linked tools, which runs only once you turn it on; the chat's, a
        /// source it read for you, scanned again only when you ask.
        case job, teamJob, chatScan
    }

    /// How a job stands, on its row and its page. A job that is ready says nothing.
    enum Status: Equatable {
        case ready, running, waiting, off, needsSettings, failed

        var label: String? {
            switch self {
            case .ready: return nil
            case .running: return "Running"
            case .waiting: return "Waiting to run"
            case .off: return "Off"
            case .needsSettings: return "Needs Settings"
            case .failed: return "Failed"
            }
        }

        /// Something the person has to do or look at: said in red.
        var isProblem: Bool { [.needsSettings, .failed].contains(self) }
    }

    var id: UUID
    var kind: Kind
    var name: String
    /// A team job's path in the team's tools; empty for your own.
    var path = ""
    /// What it does: "Price and badge on the event items · from your team's tools".
    var does: String
    /// How often it runs: "Every 15 minutes", "Every 2 hours · Ends Sat Oct 31, 11:59 PM", "When you run it".
    var every: String
    /// When it last ran and what came of it: "Last run 6:31 PM · found 3", or "Not run yet".
    var lastRun: String
    var lastRunAt: Date? = nil
    var status: Job.Status
    /// What its last run came to is a problem (a failed run): its last-run line is red.
    var resultIsProblem = false
    /// What needs the person before it can run well, one line each, in red: what Settings lacks, or what is wrong with
    /// its folder.
    var problems: [String] = []
    /// Why its last run failed, in red on its row; its page shows it with that run's results.
    var runProblem: String? = nil
    /// Listed first: a failure, a problem, or something missing in Settings.
    var needsAttention = false
    /// What it is for, in its job.json's words.
    var meaning = ""
    /// Whether your team's job is on for you.
    var on = true
    /// A job before its start or after its end: out of the way, under Upcoming or Ended, only to be looked at. Every
    /// other job is live.
    var phase = JobPhase.live
    /// When an upcoming job starts, or when an ended one ended: the order they're listed in.
    var phaseAt: Date? = nil
    /// Who shared it: "Shared by Yang", for a job whose job.json names them.
    var sharedBy: String? = nil

    var isTeam: Bool { kind == .teamJob }
    var isChat: Bool { kind == .chatScan }
    var isLive: Bool { phase == .live }
    /// Everything its row says is wrong: what needs the person, then its last run's problem.
    var allProblems: [String] { problems + (runProblem.map { [$0] } ?? []) }
    /// "Runs its job.py · Every hour": what it does and how often, on one line.
    var line: String { does + " · " + every }
}

/// What only the app knows about jobs: the secrets each still needs in Settings, and how to open Settings. Tests and
/// renders leave it empty.
struct JobsSetup {
    var missingJobSecrets: (FolderJob) -> [String] = { _ in [] }
    var openSettings: (() -> Void)? = nil
}

/// The jobs as the Jobs page and a job's page say them: each job's words, how it stands, and the order they come in.
@MainActor
enum Jobs {
    static let whenYouRunIt = "When you run it"
    static let notRunYet = "Not run yet"
    static let fromTeam = "from your team's tools"
    static let teamIntro = "From your team's tools. Turn on the ones that are yours: only those run and tell you."
    static let empty = "No jobs yet. A job is a folder with a job.py that reports what it finds: yours in Noteling's jobs folder, your team's with their tools."
    /// The Jobs page when every job is before its start or past its end.
    static let noneLive = "No jobs running now"
    /// The guides under the list, and beside a folder that can't be a job (`HelpLinks`).
    static let howJobsWork = "How jobs work"
    static let writingJobs = "Writing jobs for your team"
    static let messagesLink = "What this means"
    static let outsideIntro = "Before their start and after their end, jobs stay out of the way: they don't run or tell you anything."
    static let armIntro = "Turn on an upcoming team job to have it run from its start."

    /// Your team's jobs, under the list: where they come from.
    static func emptyTeam(linked: Bool) -> String {
        linked ? "Your team's tools have no jobs yet." : "Your team's jobs show here once your team's tools are linked in Settings."
    }

    /// What the jobs are made of, at one moment.
    struct Input {
        /// The jobs kept as folders, the one running and those waiting their turn.
        var folderJobs: [FolderJob] = []
        var runningJob: UUID?
        var queuedJobs: Set<UUID> = []
        var setup = JobsSetup()
        var now = Date()
    }

    // MARK: the list

    /// Every job, live or not, in the order the Jobs page lists the live ones (`outside` orders the rest).
    static func list(_ input: Input) -> [Job] {
        sorted(input.folderJobs.map { folderJob($0, input) })
    }

    /// One job, as its page shows it; nil once it is gone.
    static func job(_ id: UUID, _ input: Input) -> Job? {
        input.folderJobs.first { $0.id == id }.map { folderJob($0, input) }
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

    // MARK: searching your team's jobs

    /// Your team's jobs a search leaves in the list: every job that isn't your team's, every team job you turned on, and
    /// the others whose name or path has every word of `search`, ignoring case. An empty search leaves them all.
    static func searched(_ jobs: [Job], _ search: String) -> [Job] {
        let words = search.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return jobs }
        return jobs.filter { job in
            !job.isTeam || job.on || words.allSatisfy { job.name.localizedCaseInsensitiveContains($0) || job.path.localizedCaseInsensitiveContains($0) }
        }
    }

    /// Under the search box while it holds a search: "Showing 5 of 100 · Clear". Nil without one.
    static func searchLine(shown: Int, of total: Int, search: String) -> String? {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return "Showing \(shown) of \(total)"
    }

    /// The search box shows once your team has more jobs than fit at a glance, and whenever a search is kept, so a
    /// kept search is never out of sight.
    static func showsSearch(teamJobs: Int, search: String) -> Bool { teamJobs > searchFrom || !search.isEmpty }
    static let searchFrom = 6

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

    // MARK: each job

    /// A job kept as a folder as a job: what it's about, how often it runs, how its last run went (what its `run()`
    /// said, or that it failed, and why), and whether it's on. Before its start or after its end, nothing about it asks
    /// for the person: no problem status, no red, never first in the list; an upcoming one still says what it lacks
    /// (quietly, under Upcoming), so it can be put right before it starts.
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
        let line = aboutLine(job)
        let about = line.isEmpty ? (job.source == .chat ? "What the chat read for you" : "Runs its job.py") : line
        return Job(id: job.id, kind: job.source == .team ? .teamJob : job.source == .chat ? .chatScan : .job, name: job.name, path: job.isTeam ? job.path : "",
                   does: about + (job.isTeam ? " · " + fromTeam : job.source == .chat ? " · read by the chat for you" : ""), every: FolderJobWords.schedule(job, now: now),
                   lastRun: FolderJobWords.lastRun(job, now: now), lastRunAt: job.state.lastRunAt, status: status,
                   resultIsProblem: live && job.on && failed, problems: problems,
                   runProblem: live && failed ? job.state.error : nil,
                   needsAttention: live && job.on && (failed || !missing.isEmpty), meaning: job.about, on: job.on, phase: phase,
                   phaseAt: phase == .upcoming ? job.starts?.date : phase == .ended ? job.ends?.date : nil,
                   sharedBy: FolderJobWords.sharedBy(job))
    }

    /// What a job is for, on its row: the first line of its `about`, up to 90 characters, without a closing full stop,
    /// since more follows it on the row. Empty when it says nothing.
    static func aboutLine(_ job: FolderJob) -> String {
        var line = JobWords.clip(job.about.components(separatedBy: .newlines).first ?? "", 90)
        if line.hasSuffix("."), !line.hasSuffix("..") { line.removeLast() }
        return line
    }

    /// Its row had to shorten what it is for, so its page says all of it.
    static func aboutShortened(_ job: FolderJob) -> Bool {
        let line = aboutLine(job), about = job.about.trimmingCharacters(in: .whitespacesAndNewlines)
        return !about.isEmpty && line != about && line + "." != about
    }

    // MARK: the rest of the page

    /// A folder among the jobs that can't be a job, and why: listed with the jobs that need attention.
    struct Unreadable: Identifiable, Equatable {
        var id: String
        var text: String
        /// Yours, to show in Finder; nil for your team's.
        var folder: URL?
    }

    static func unreadable(own: [String: String], team: [String: String], directory: URL?) -> [Unreadable] {
        own.keys.sorted().map { Unreadable(id: "own-job:" + $0, text: "The job in the “\($0)” folder can't run. \(own[$0] ?? "")",
                                           folder: directory?.appendingPathComponent($0)) }
            + team.keys.sorted().map { Unreadable(id: "team-job:" + $0, text: "Not listing your team's job \($0). \(team[$0] ?? "")") }
    }

    /// The buttons a job has on its row and its page: Run now, or Open Settings when it needs something there; and the
    /// on/off switch for your team's job. Before its start or after its end a job is only to be looked at, and has
    /// none, except that an upcoming team job keeps its switch, so it can be turned on ahead of a start in the night.
    enum Control: Hashable {
        case runNow, openSettings, onOff
    }

    static func controls(_ job: Job, canOpenSettings: Bool) -> [Control] {
        guard job.isLive else { return job.phase == .upcoming && job.isTeam ? [.onOff] : [] }
        var controls: [Control] = []
        if job.status == .needsSettings && canOpenSettings { controls.append(.openSettings) }
        else if job.on, !job.isChat { controls.append(.runNow) }   // the chat's sources are scanned by asking it
        if job.isTeam { controls.append(.onOff) }
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
    /// The jobs as the store and the runner have them now.
    @MainActor
    init(setup: JobsSetup = JobsSetup(), now: Date = Date(), folderJobs: FolderJobsPanel) {
        self.init()
        self.folderJobs = folderJobs.store.jobs
        runningJob = folderJobs.runner.running
        queuedJobs = Set(folderJobs.runner.queued)
        self.setup = setup
        let runner = folderJobs.runner
        self.setup.missingJobSecrets = { runner.missingSecrets($0) }   // the runner knows the Keychain
        self.now = now
    }
}
