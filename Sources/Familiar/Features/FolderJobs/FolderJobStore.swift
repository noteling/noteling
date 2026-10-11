import Combine
import Foundation

/// The jobs kept as folders: yours, in `jobs/` in Noteling's folder, on as soon as they're there, so a job can be tried
/// before it's pushed; and your team's, in the linked tools' `jobs/`, which Noteling only reads and runs once you turn
/// them on. A job.json changed by hand or by an update is read again at the next look. What their runs leave is kept
/// apart from them, in `job-results/` in Noteling's folder: `<team|own>/<path>/output/` and `run.json` for each, and
/// which of your team's you turned on in `on.json`, since every update replaces the team's copy.
@MainActor
final class FolderJobStore: ObservableObject {
    @Published private(set) var jobs: [FolderJob] = []
    /// Your folders under `jobs/` that can't be a job, by path, with why.
    @Published private(set) var unreadable: [String: String] = [:]
    /// The same for your team's.
    @Published private(set) var teamUnreadable: [String: String] = [:]
    let directory: URL
    /// Your team's jobs, `jobs/` in the linked tools, when they are linked. Asked at every look.
    let teamDirectory: () -> URL?
    /// What the jobs' runs leave, and which of your team's are on.
    let results: URL

    /// Jobs listed at all, yours and your team's. A person turns on as many of the team's as are theirs.
    nonisolated static let teamLimit = 200
    nonisolated static let ownLimit = 50
    nonisolated static let teamReadOnly = "This job comes from your team's tools. Change it in the team repository."

    private struct Stamp: Equatable {
        var date: Date?
        var size: Int?
    }
    /// job.json as last read, by `team:<path>` or `own:<path>`, so an unchanged one isn't read again.
    private var read: [String: (stamp: Stamp, result: Result<FolderJob, FolderJobError>)] = [:]
    /// The team jobs you turned on, by path.
    private var teamOn: Set<String> = []
    /// How each job's runs went, read once and kept as they're recorded.
    private var states: [UUID: FolderJobState] = [:]

    init(directory: URL = Config.dir.appendingPathComponent("jobs"), results: URL = Config.dir.appendingPathComponent("job-results"),
         teamDirectory: @escaping () -> URL? = { nil }) {
        self.directory = directory
        self.results = results
        self.teamDirectory = teamDirectory
        teamOn = Self.readOn(results)
        refresh()
        cleanUpTeam()
    }

    func job(id: UUID) -> FolderJob? { jobs.first { $0.id == id } }

    /// The job's folder: yours, or the team's in the linked tools (which is only ever read).
    func folder(for job: FolderJob) -> URL? {
        (job.isTeam ? teamDirectory() : directory)?.appendingPathComponent(job.path)
    }

    /// Where its runs leave what they leave: `job-results/<team|own>/<path>/`.
    func resultFolder(for job: FolderJob) -> URL {
        results.appendingPathComponent(job.isTeam ? "team" : "own").appendingPathComponent(job.path)
    }

    /// Its latest output, from the last run that worked.
    func output(for job: FolderJob) -> URL { resultFolder(for: job).appendingPathComponent(FolderJobFiles.output) }

    /// What's in its latest output; nil before a run worked.
    func result(for job: FolderJob) -> FolderJobResult? { FolderJobFiles.result(output: output(for: job)) }

    /// Its input folder, in its own folder.
    func input(for job: FolderJob) -> URL? { folder(for: job)?.appendingPathComponent(FolderJobFiles.input) }

    /// Where watches were kept before jobs: `watches/` beside your `jobs/`, and beside your team's. Watches no longer
    /// run; Jobs says so while one of these still holds one.
    var retiredWatches: URL { directory.deletingLastPathComponent().appendingPathComponent(ToolRegistry.watchesFolder) }
    func teamRetiredWatches() -> URL? {
        teamDirectory()?.deletingLastPathComponent().appendingPathComponent(ToolRegistry.watchesFolder)
    }

    /// Looks at both `jobs/` folders and takes in what changed. Returns the jobs that went away.
    @discardableResult
    func refresh() -> [UUID] {
        var found: [FolderJob] = []
        var seen = Set<String>()
        for (source, root, limit) in [(JobSource.own, Optional(directory), Self.ownLimit), (.team, teamDirectory(), Self.teamLimit)] {
            guard let root else {
                if source == .team, !teamUnreadable.isEmpty { teamUnreadable = [:] }
                continue
            }
            let look = FolderJobFiles.jobFolders(in: root)
            var problems = look.unreadable
            for path in look.jobs {
                let key = (source == .team ? "team:" : "own:") + path
                seen.insert(key)
                let file = root.appendingPathComponent(path).appendingPathComponent(FolderJobFiles.definition)
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let stamp = Stamp(date: values?.contentModificationDate, size: values?.fileSize)
                let result: Result<FolderJob, FolderJobError>
                if let cached = read[key], cached.stamp == stamp { result = cached.result }
                else {
                    do { result = .success(try FolderJobFiles.parse(try Data(contentsOf: file), path: path, source: source)) }
                    catch { result = .failure(error as? FolderJobError ?? FolderJobError("Its job.json can't be read: \(error.localizedDescription)")) }
                    read[key] = (stamp, result)
                    if case .failure(let error) = result { Log.info("jobs: \(key) can't be read: \(error.message)") }
                }
                switch result {
                case .success(var job):
                    guard found.filter({ $0.source == source }).count < limit else {
                        problems[path] = "Not listed: up to \(limit) jobs are listed from one place."
                        continue
                    }
                    job.on = source == .own || teamOn.contains(path)
                    job.state = state(for: job)
                    found.append(job)
                case .failure(let error): problems[path] = error.message
                }
            }
            if source == .own { if unreadable != problems { unreadable = problems } }
            else if teamUnreadable != problems { teamUnreadable = problems }
        }
        read = read.filter { seen.contains($0.key) }
        let removed = jobs.map(\.id).filter { id in !found.contains { $0.id == id } }
        for job in found where !jobs.contains(where: { $0.id == job.id }) { Log.info("jobs: found \(job.isTeam ? "the team's " : "")\(job.path)") }
        if found != jobs { jobs = found }
        return removed
    }

    /// Turns a team job on or off for you. Off, it doesn't run or keep a card; what it left stays.
    func setOn(_ id: UUID, _ on: Bool) throws {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { throw FolderJobError("That job is gone.") }
        let job = jobs[index]
        guard job.isTeam else { throw FolderJobError("Only your team's jobs are turned on and off. Yours run while their folder is there.") }
        guard job.on != on else { return }
        var next = teamOn
        if on { next.insert(job.path) } else { next.remove(job.path) }
        try writeOn(next)
        teamOn = next
        jobs[index].on = on
    }

    /// Keeps how a run went, in its `run.json`.
    func record(_ id: UUID, _ state: FolderJobState) throws {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        states[id] = state
        jobs[index].state = state
        let folder = resultFolder(for: jobs[index])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try JobFiles.write(try encoder.encode(state), to: folder.appendingPathComponent(FolderJobFiles.state))
    }

    private func state(for job: FolderJob) -> FolderJobState {
        if let known = states[job.id] { return known }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = (try? Data(contentsOf: resultFolder(for: job).appendingPathComponent(FolderJobFiles.state)))
            .flatMap { try? decoder.decode(FolderJobState.self, from: $0) } ?? FolderJobState()
        states[job.id] = state
        return state
    }

    // MARK: on.json

    private static func onFile(_ results: URL) -> URL { results.appendingPathComponent("on.json") }

    private static func readOn(_ results: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: onFile(results)),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        return Set(object["on"] as? [String] ?? [])
    }

    private func writeOn(_ paths: Set<String>) throws {
        try FileManager.default.createDirectory(at: results, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JobFiles.write(JSONText.pretty(["on": paths.sorted()], indent: "") + "\n", to: Self.onFile(results))
    }

    /// At launch: what team jobs that are no longer in the team's tools left, and whether they were on, go. Only while
    /// the team's tools are there, so a copy that is missing for a moment takes nothing with it.
    private func cleanUpTeam() {
        guard let root = teamDirectory(), FileManager.default.fileExists(atPath: root.path) else { return }
        let paths = Set(FolderJobFiles.jobFolders(in: root).jobs)
        let team = results.appendingPathComponent("team")
        let manager = FileManager.default
        if let walk = manager.enumerator(at: team, includingPropertiesForKeys: nil) {
            let base = team.standardizedFileURL.path + "/"
            var gone: [URL] = []
            for case let url as URL in walk where url.lastPathComponent == FolderJobFiles.state {
                let folder = url.deletingLastPathComponent()
                let path = String(folder.standardizedFileURL.path.dropFirst(base.count))
                if !paths.contains(path) { gone.append(folder) }
            }
            for folder in gone {
                try? manager.removeItem(at: folder)
                Log.info("jobs: the team's \(folder.path.dropFirst(team.path.count + 1)) is gone from its tools, so what it left was deleted")
            }
        }
        let kept = teamOn.intersection(paths)
        if kept != teamOn, (try? writeOn(kept)) != nil { teamOn = kept }
    }
}
