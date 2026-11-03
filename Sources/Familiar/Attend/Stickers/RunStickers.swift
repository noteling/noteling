import Foundation

/// A job's latest finding, as the sticky note beside the bubble says it.
struct RunSticker: Identifiable, Equatable {
    /// The job's id.
    let id: UUID
    let jobName: String
    /// Who shared the job, "Yang" or "Yang and Ana"; nil for your own jobs.
    let byline: String?
    /// What its `run()` said, or "Its preview has something new."
    let said: String
    /// When this finding was first seen: the run that found it, not the latest run that found it again.
    let at: Date
    /// The preview's digest: what the sticker is about. A new digest is a new finding.
    let digest: String

    /// The same sticker, dated from when its finding was first seen.
    func found(at date: Date) -> RunSticker {
        RunSticker(id: id, jobName: jobName, byline: byline, said: said, at: date, digest: digest)
    }
}

/// The stickers beside the bubble: one per job whose latest output has a preview, newest finding first. A job that
/// keeps finding the same thing keeps its sticker's date, so an hourly job's new finding comes before a five-minute
/// job's old one. Putting one away remembers its digest, so it stays away until the job finds something else; a job
/// turned off, ended or without a preview loses its sticker by itself.
@MainActor
final class RunStickers: ObservableObject {
    /// How many sit beside the bubble; the rest are "and N more".
    static let shown = 3
    /// Every current one, newest first.
    @Published private(set) var stickers: [RunSticker] = []
    /// Where what is put away and when each finding was first seen are kept; nil keeps them in memory.
    private let file: URL?
    /// The digest put away for each job, by the job's id.
    private var away: [String: String]
    /// Each job's current finding and when it was first seen, by the job's id.
    private var found: [String: Found]

    struct Found: Equatable {
        var digest: String
        var at: Date
    }

    var more: Int { max(0, stickers.count - Self.shown) }
    var shown: [RunSticker] { Array(stickers.prefix(Self.shown)) }

    init(file: URL?) {
        self.file = file
        (away, found) = Self.read(file)
    }

    /// The stickers as they should be at `now`: at launch, at each tick and when the cards change. Publishes only when
    /// the list changed, so the bubble doesn't redraw at every tick. A finding seen for the first time takes the date
    /// of the run that found it; put-aways for jobs that are gone, and findings jobs no longer show, are forgotten.
    func update(_ jobs: [FolderJob], at now: Date = Date()) {
        var seen: [String: Found] = [:]
        var current: [RunSticker] = []
        for job in jobs {
            guard var sticker = Self.sticker(for: job, at: now) else { continue }
            let key = job.id.uuidString
            if let before = found[key], before.digest == sticker.digest { sticker = sticker.found(at: before.at) }
            seen[key] = Found(digest: sticker.digest, at: sticker.at)
            if away[key] != sticker.digest { current.append(sticker) }
        }
        current.sort { $0.at == $1.at ? $0.jobName < $1.jobName : $0.at > $1.at }
        if current != stickers { stickers = current }
        let present = Set(jobs.map(\.id.uuidString))
        let kept = away.filter { present.contains($0.key) }
        if kept != away || seen != found {
            away = kept
            found = seen
            write()
        }
    }

    /// The person dismissed it: its digest is remembered, so it stays away until the job finds something else. An id
    /// with no sticker (a late click on one that just left) changes nothing.
    func putAway(_ id: UUID) {
        guard let sticker = stickers.first(where: { $0.id == id }) else { return }
        away[id.uuidString] = sticker.digest
        write()
        stickers.removeAll { $0.id == id }
    }

    /// What the job's sticker says, dated by its latest run that worked, or nil when it has no card
    /// (`FolderJobCards.hasCard`): off, before its start, after its end, not run yet, or without a preview.
    static func sticker(for job: FolderJob, at now: Date) -> RunSticker? {
        guard FolderJobCards.hasCard(job, at: now), let success = job.state.lastSuccessAt, let digest = job.state.preview else { return nil }
        return RunSticker(id: job.id, jobName: job.name, byline: FolderJobWords.names(job.contributors),
                          said: job.state.said ?? FolderJobWords.somethingNew, at: success, digest: digest)
    }

    // MARK: stickers.json

    /// `{"away": {"<job uuid>": "<digest>"}, "found": {"<job uuid>": {"digest": "<digest>", "at": <seconds>}}}`. A
    /// missing or unreadable file is empty.
    private static func read(_ file: URL?) -> ([String: String], [String: Found]) {
        guard let file, let data = try? Data(contentsOf: file),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ([:], [:]) }
        let away = (object["away"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
        let found = (object["found"] as? [String: Any] ?? [:]).compactMapValues { value -> Found? in
            guard let entry = value as? [String: Any], let digest = entry["digest"] as? String,
                  let seconds = entry["at"] as? Double else { return nil }
            return Found(digest: digest, at: Date(timeIntervalSince1970: seconds))
        }
        return (away, found)
    }

    private func write() {
        guard let file else { return }
        let object: [String: Any] = [
            "away": away,
            "found": found.mapValues { ["digest": $0.digest, "at": $0.at.timeIntervalSince1970] },
        ]
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JobFiles.write(JSONText.pretty(object, indent: "") + "\n", to: file)
        } catch {
            Log.info("jobs: couldn't keep the stickers' file: \(error.localizedDescription)")
        }
    }
}
