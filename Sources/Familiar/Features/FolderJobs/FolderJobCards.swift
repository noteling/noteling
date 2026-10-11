import Foundation

/// A job's card in Morning Files, through the cards inbox (`CardInbox`): one per job, `job.json` in the job's folder of
/// the inbox, there while its latest output has a preview, and gone (so the card resolves) when it has none, when the
/// job is off, or before its start and after its end. Its words are the job's name, when its last run worked, and what
/// that run's `run()` said; the card shows the preview and the files from the job's output itself. Its one part is the
/// preview's digest, so a card the person resolved opens again only when what the preview shows changes. A job's
/// script writes cards of its own into another folder of the inbox (`scriptSource`), so the two never collide; both
/// show in the job's one folder in Morning Files.
@MainActor
final class FolderJobCards {
    /// The cards inbox; nil writes no cards.
    let root: URL?
    /// The time zone of the card's time.
    var timeZone = TimeZone.autoupdatingCurrent
    /// What Noteling last wrote, by `<source>/job.json`, so an unchanged card isn't written again.
    private var written: [String: String] = [:]
    /// The card files of Noteling's that are there.
    private var present: Set<String> = []
    private var listed = false

    static let fileName = "job.json"
    static let prefix = "job-"
    static let scriptPrefix = "jobcards-"

    init(root: URL? = Config.dir.appendingPathComponent("cards/inbox")) { self.root = root }

    /// The job's folder in the inbox, for its preview card: `job-<team|own>-<path>`, the path's `/` made `-`.
    static func source(for job: FolderJob) -> String {
        CardInboxFormat.safe(prefix + (job.isTeam ? "team-" : "own-") + job.path.replacingOccurrences(of: "/", with: "-"))
    }

    /// The folder its job.py writes cards of its own into, as NOTELING_CARDS_DIR: `jobcards-<team|own>-<path>`.
    static func scriptSource(for job: FolderJob) -> String {
        CardInboxFormat.safe(scriptPrefix + (job.isTeam ? "team-" : "own-") + job.path.replacingOccurrences(of: "/", with: "-"))
    }

    /// The preview card's key in the inbox: `<source>/job`.
    static func key(for job: FolderJob) -> String { source(for: job) + "/job" }

    /// Whether the job has a card at `now`: it's on, between its start and end, and its latest output has a preview.
    static func hasCard(_ job: FolderJob, at now: Date) -> Bool {
        job.running(at: now) && job.state.lastSuccessAt != nil && job.state.preview != nil
    }

    /// What its card says, or nil when it has none: "Holiday Oct · GM · 6:31 PM", what its `run()` said, and the
    /// preview's digest as its one part.
    static func card(for job: FolderJob, at now: Date, timeZone: TimeZone = .current) -> [String: Any]? {
        guard hasCard(job, at: now), let success = job.state.lastSuccessAt, let digest = job.state.preview else { return nil }
        return ["title": job.name + " · " + WatchListCards.time(success, in: timeZone), "body": job.state.said ?? "",
                "severity": "normal", "parts": [digest]]
    }

    /// Every job's card as it should be at `now`, and none for jobs that are gone, off, out of their window or without
    /// a preview: at launch, at each tick and at the end of each run. Cheap when nothing changed. True when a file
    /// changed.
    @discardableResult
    func reconcile(_ jobs: [FolderJob], at now: Date = Date()) -> Bool {
        guard let root else { return false }
        if !listed { list(root) }
        var wanted: [String: String] = [:]
        for job in jobs {
            guard let card = Self.card(for: job, at: now, timeZone: timeZone) else { continue }
            wanted[Self.source(for: job) + "/" + Self.fileName] = JSONText.pretty(card, indent: "") + "\n"
        }
        var changed = false
        for (file, text) in wanted.sorted(by: { $0.key < $1.key }) where written[file] != text || !present.contains(file) {
            let url = root.appendingPathComponent(file)
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                try WatchListFiles.write(text, to: url)
                written[file] = text
                present.insert(file)
                changed = true
            } catch {
                Log.info("jobs: couldn't write the card \(file): \(error.localizedDescription)")
            }
        }
        for file in present.subtracting(wanted.keys).sorted() {
            do {
                try FileManager.default.removeItem(at: root.appendingPathComponent(file))
            } catch where (error as NSError).code != NSFileNoSuchFileError {
                Log.info("jobs: couldn't delete the card \(file): \(error.localizedDescription)")
                continue
            } catch {}
            present.remove(file)
            written[file] = nil
            changed = true
        }
        return changed
    }

    /// The card files of Noteling's already in the inbox, once: what an earlier launch wrote.
    private func list(_ root: URL) {
        listed = true
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for folder in folders where folder.hasPrefix(Self.prefix) {
            let file = folder + "/" + Self.fileName
            if FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path) { present.insert(file) }
        }
    }
}
