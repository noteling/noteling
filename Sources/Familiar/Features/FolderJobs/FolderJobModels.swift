import Foundation

/// A job kept as a folder: `job.json` says what it is and when it runs, `job.py`'s `run()` does it, `input/` holds what
/// it reads, and what it writes goes into an output folder on this Mac. Noteling knows nothing about what a job is
/// for: it runs the one entry point on schedule, shows the files in the output's `preview/` as they are, and offers
/// every output file to open or save. Yours are in `jobs/` in Noteling's folder; your team's in the linked tools'
/// `jobs/`, which Noteling only reads and runs once you turn them on.
struct FolderJob: Identifiable, Equatable {
    var id: UUID
    var source: WatchListSource
    /// Its folder under `jobs/`, such as `holiday/oct/gm`.
    var path: String
    var name: String
    /// What it is for, in its writer's words.
    var about = ""
    /// How often it runs; nil runs it only on Run now.
    var everyMinutes: Int?
    var starts: WatchListMoment?
    var ends: WatchListMoment?
    /// Secrets its job.py gets from the person's Keychain, by name.
    var requires: [String] = []
    /// Yours always are; your team's only once you turn them on.
    var on = true
    /// How its runs went, as kept on this Mac.
    var state = FolderJobState()

    var isTeam: Bool { source == .team }

    func notStarted(at now: Date) -> Bool { starts.map { now < $0.date } ?? false }
    func ended(at now: Date) -> Bool { ends.map { now > $0.date } ?? false }

    /// Where it stands against its start and end, as a watch does: before and after, it is out of the way.
    func phase(at now: Date) -> WatchListPhase {
        notStarted(at: now) ? .upcoming : ended(at: now) ? .ended : .live
    }

    /// It runs, on schedule or on Run now: on, and between its start and end.
    func running(at now: Date) -> Bool { on && phase(at: now) == .live }

    /// Its schedule has come round: it runs on one, it's running at `now`, and it hasn't run for `everyMinutes`. A run
    /// that failed counts, so a failing job doesn't run again at every tick.
    func isDue(at now: Date) -> Bool {
        guard let everyMinutes, running(at: now) else { return false }
        guard let last = state.lastRunAt else { return true }
        if last > now.addingTimeInterval(60) { return true }   // the clock went back: don't wait out the difference
        return now.timeIntervalSince(last) >= TimeInterval(everyMinutes * 60) - WatchListSchedule.slack
    }

    /// The next moment after `now` one of `jobs` starts or ends.
    static func nextChange(_ jobs: [FolderJob], after now: Date) -> Date? {
        jobs.flatMap { [$0.starts?.date, $0.ends?.date] }.compactMap { $0 }.filter { $0 > now }.min()
    }

    static let minimumMinutes = 5
    static let maximumMinutes = 1_440
}

/// How a job's runs went, kept in `run.json` beside its output: when it last ran and last succeeded, what its `run()`
/// said, why the last run failed, and a digest of its preview files, so a card reopens only when they change.
struct FolderJobState: Codable, Equatable {
    var lastRunAt: Date?
    var lastSuccessAt: Date?
    /// What the last run that worked returned, when it was words: shown on its row and its card.
    var said: String?
    /// The first line of why the last run failed; nil once a run works.
    var error: String?
    /// A digest of the latest output's preview files; nil when it has none.
    var preview: String?

    enum CodingKeys: String, CodingKey {
        case lastRunAt = "last_run_at", lastSuccessAt = "last_success_at", said, error, preview
    }
}

struct FolderJobError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
