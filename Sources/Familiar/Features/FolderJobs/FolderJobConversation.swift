import Foundation
import FamiliarContracts
import FamiliarRuntime

/// The jobs kept as folders in general chat, so whatever Jobs shows can be talked about there: list them, run one now,
/// turn one of the team's on or off, and read one's latest result. The chat never makes a job: jobs are written by
/// whoever keeps the team's tools, as folders. Changes go through the same store and runner as Jobs in Morning Files,
/// so they show there at once. A run the chat starts is waited for (at most `waitLimit`) and its result returned.
@MainActor
final class FolderJobConversation {
    let store: FolderJobStore
    let runner: FolderJobRunner
    /// "on", or why notifications are off and how to turn them on.
    var notificationLine: () async -> String = { "on" }
    /// Asks macOS for permission to notify; called when a team job is turned on.
    var askForNotifications: () -> Void = {}
    /// A job was run, or turned on or off: a one-line receipt for the pad.
    var onChange: ((String) -> Void)?
    /// A run still going after this carries on; Jobs shows it when it ends.
    var waitLimit: Double = 90
    var now: () -> Date = Date.init

    /// What a result's preview gives the chat: rows of a table, characters of a text, and files named.
    static let rowLimit = 50
    static let textLimit = 4_000
    static let fileLimit = 30
    static let stillRunning = "It's still running. Jobs shows its result when it ends."

    init(store: FolderJobStore, runner: FolderJobRunner) {
        self.store = store
        self.runner = runner
    }

    // MARK: tools

    func routes() -> [ToolRoute] {
        let job: [String: Any] = ["type": "string", "description": "The job's name, id or path, as list_jobs gives them; a team job's path may be its last part, like \"gm\"."]
        return [
            route("list_jobs", "List the jobs Noteling runs from folders: the person's own and their team's, from the team's tools. For each: its name, id, path, what it is for, whether it is on (a team job runs only once the person turns it on), how often it runs, when it starts or ends (before its start and after its end it doesn't run and waits under Upcoming or Ended in Jobs), and its last run: when, what it said, or why it failed. Jobs are written by whoever keeps the team's tools; the chat can't make or change one.",
                  [:], required: []) { [unowned self] _ in await self.list() },
            route("run_job_now", "Run one job now instead of waiting for its schedule, and return what its run said and its latest result's preview. Only a job that is on, and between its start and end. Use it when the person asks to run or check a job now.",
                  ["job": job], required: ["job"]) { [unowned self] input in try await self.runNow(input) },
            route("turn_on_job", "Turn on one of the team's jobs for the person, so it runs on its schedule, keeps a card while its preview has something, and tells them when that changes. It runs right away if it has started.",
                  ["job": job], required: ["job"]) { [unowned self] input in try await self.turn(input, on: true) },
            route("turn_off_job", "Turn off one of the team's jobs for the person: it no longer runs, and its card is put away; what it left stays.",
                  ["job": job], required: ["job"]) { [unowned self] input in try await self.turn(input, on: false) },
            route("read_job_result", "Read a job's latest result: what its last run that worked said, the files in its preview as they are (tables as CSV, up to \(Self.rowLimit) rows; texts up to \(Self.textLimit) characters), and the names of its other files. Use it to answer questions about what a job found.",
                  ["job": job], required: ["job"]) { [unowned self] input in try self.read(input) },
        ]
    }

    /// Each tool first takes in what changed in the jobs folders, so it answers from the files as they are.
    private func route(_ name: String, _ description: String, _ properties: [String: Any], required: [String],
                       action: @escaping ([String: Any]) async throws -> String) -> ToolRoute {
        ToolRoute(match: .tool(name: name), definition: ["name": name, "description": description,
            "input_schema": ["type": "object", "additionalProperties": false, "properties": properties, "required": required]]) { [weak self] _, input, _ in
            self?.store.refresh()
            do { return .text(try await action(input)) }
            catch { return .text(error.localizedDescription, isError: true) }
        }
    }

    // MARK: actions

    private func list() async -> String {
        let unreadable = store.unreadable.keys.sorted().map { ["folder": $0, "problem": store.unreadable[$0]!] }
            + store.teamUnreadable.keys.sorted().map { ["folder": $0, "from": "your team's tools", "problem": store.teamUnreadable[$0]!] }
        guard !store.jobs.isEmpty || !unreadable.isEmpty else {
            return store.teamDirectory() == nil ? "No jobs yet. Your team's jobs show once your team's tools are linked in Settings."
                : "No jobs yet: your team's tools have none."
        }
        var result: [String: Any] = ["jobs": store.jobs.map(summary)]
        if !unreadable.isEmpty { result["folders_that_cant_run"] = unreadable }
        if store.jobs.contains(where: \.on) { result["notifications"] = await notificationLine() }
        return Self.json(result)
    }

    private func runNow(_ input: [String: Any]) async throws -> String {
        let job = try resolve(input["job"])
        if let reason = notRunning(job) { throw FolderJobError(reason) }
        if let why = runner.run(job.id) { throw FolderJobError(why) }
        onChange?("Running “\(JobWords.clip(job.name, 80))” now.")
        let finished = await waitForRun(job.id)
        var result = store.job(id: job.id).map(summary) ?? [:]
        if let latest = store.job(id: job.id) { result["latest_result"] = preview(latest) }
        if !finished { result["still_running"] = Self.stillRunning }
        return Self.json(result)
    }

    private func turn(_ input: [String: Any], on: Bool) async throws -> String {
        let job = try resolve(input["job"])
        let name = "“\(JobWords.clip(job.name, 80))”"
        guard job.isTeam else { throw FolderJobError("\(name) is one of the person's own jobs: it runs while its folder is there.") }
        guard job.on != on else { return "\(name) is already \(on ? "on" : "off")." }
        try runner.turn(job.id, on: on)
        if on { askForNotifications() }
        onChange?(on ? "Turned on \(name) from your team's tools." : "Turned off \(name). It no longer runs.")
        guard on else { return "Turned off \(name). It no longer runs, and its card is put away; what it left stays." }
        let finished = runner.isBusy(job.id) ? await waitForRun(job.id) : true
        var result = store.job(id: job.id).map(summary) ?? [:]
        result["turned_on"] = true
        if let latest = store.job(id: job.id), let reason = notRunning(latest) { result["note"] = reason }
        if !finished { result["still_running"] = Self.stillRunning }
        result["notifications"] = await notificationLine()
        return Self.json(result)
    }

    private func read(_ input: [String: Any]) throws -> String {
        let job = try resolve(input["job"])
        var result = summary(job)
        result["latest_result"] = preview(job)
        return Self.json(result)
    }

    /// Waits for a job's run, at most `waitLimit`. True when it ended.
    private func waitForRun(_ id: UUID) async -> Bool {
        let deadline = Date().addingTimeInterval(waitLimit)
        while runner.isBusy(id) {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return true
    }

    /// Why a job doesn't run now, so the chat can tell the person where it is; nil when it does.
    private func notRunning(_ job: FolderJob) -> String? {
        let name = "“\(JobWords.clip(job.name, 80))”"
        if job.notStarted(at: now()), let starts = job.starts {
            return "\(name) starts \(starts.words); it doesn't run before then. Until then it waits under Upcoming in Jobs."
        }
        if job.ended(at: now()), let ends = job.ends {
            return "\(name) ended \(ends.words), so it no longer runs, and any card it had was put away. It is under Ended in Jobs."
        }
        if !job.on { return "\(name) is off. Turn it on to have it run." }
        return nil
    }

    // MARK: lookups

    /// By id, by path, by name, or by the end of a path that only one job's has ("gm" for holiday/oct/gm).
    private func resolve(_ raw: Any?) throws -> FolderJob {
        let names = store.jobs.map { "“\(JobWords.clip($0.name, 60))” (\($0.path))" }.joined(separator: ", ")
        guard let key = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw FolderJobError(store.jobs.isEmpty ? "There are no jobs." : "Say which job: \(names).")
        }
        if let id = UUID(uuidString: key), let job = store.job(id: id) { return job }
        let path = key.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        for matching in [
            { (j: FolderJob) in j.path.lowercased() == path },
            { (j: FolderJob) in j.name.caseInsensitiveCompare(key) == .orderedSame },
            { (j: FolderJob) in !path.isEmpty && j.path.lowercased().hasSuffix("/" + path) },
        ] {
            let found = store.jobs.filter(matching)
            if found.count == 1 { return found[0] }
            if found.count > 1 {
                throw FolderJobError("Several jobs go by “\(JobWords.clip(key, 80))”: "
                    + found.map { "“\(JobWords.clip($0.name, 60))” (\($0.path))" }.joined(separator: ", ") + ". Say which.")
            }
        }
        throw FolderJobError(store.jobs.isEmpty ? "There are no jobs." : "No job is called “\(JobWords.clip(key, 80))”. Jobs: \(names).")
    }

    /// A job as the chat sees it.
    private func summary(_ job: FolderJob) -> [String: Any] {
        var result: [String: Any] = ["name": job.name, "id": job.id.uuidString, "path": job.path,
                                     "from": job.isTeam ? "your team's tools" : "your own jobs folder",
                                     "runs": FolderJobWords.every(job), "last_run": FolderJobWords.lastRun(job, now: now())]
        if !job.about.isEmpty { result["about"] = JobWords.clip(job.about, 400) }
        if let names = FolderJobWords.names(job.contributors) { result["shared_by"] = names }
        if job.isTeam { result["on"] = job.on }
        if let window = FolderJobWords.window(job, now: now()) { result["window"] = window }
        switch job.phase(at: now()) {
        case .upcoming: result["where_in_jobs"] = "under Upcoming"
        case .ended: result["where_in_jobs"] = "under Ended"
        case .live: break
        }
        if let error = job.state.error { result["last_run_failed"] = error }
        if runner.running == job.id { result["running_now"] = true }
        let missing = runner.missingSecrets(job)
        if !missing.isEmpty {
            result["setup"] = Jobs.needs(missing) + " Point to Open Settings in Jobs; never ask for a password in chat."
        }
        return result
    }

    /// A job's latest result for the chat: what it said, its preview files as they are (capped), and its other files.
    private func preview(_ job: FolderJob) -> Any {
        guard let result = store.result(for: job) else {
            return job.state.lastRunAt == nil ? "It hasn't run yet." : "No run has worked yet."
        }
        var out: [String: Any] = [:]
        if let said = job.state.said { out["said"] = said }
        if let success = job.state.lastSuccessAt { out["from_run_at"] = JobWords.time(success, now: now()) }
        var shown: [[String: Any]] = []
        for file in result.shown {
            var entry: [String: Any] = ["file": file.path]
            switch FolderJobPreview.read(file) {
            case .table(let rows, let total):
                let kept = Array(rows.prefix(Self.rowLimit + 1))
                entry["csv"] = kept.map { $0.map(Self.csvField).joined(separator: ",") }.joined(separator: "\n")
                let shownRows = max(0, kept.count - 1)
                if let total, total > shownRows { entry["rows_not_shown"] = total - shownRows }
                else if total == nil { entry["note"] = "Only its beginning was read." }
            case .text(let text, _):
                entry["text"] = JobWords.clip(text, Self.textLimit)
            case .unreadable(let why):
                entry["problem"] = why
            }
            shown.append(entry)
        }
        if !shown.isEmpty { out["preview"] = shown }
        let others = result.files.filter { !$0.shown }.map(\.path)
        if !others.isEmpty { out["other_files"] = Array(others.prefix(Self.fileLimit)) + (others.count > Self.fileLimit ? ["…and \(others.count - Self.fileLimit) more"] : []) }
        if result.files.isEmpty { out["files"] = "Its last run left no files." }
        return out
    }

    static func csvField(_ field: String) -> String {
        field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
    }

    static func json(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "\(object)" }
        return String(decoding: data, as: UTF8.self)
    }
}
