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
    /// The run that found it.
    let at: Date
    /// The preview's digest: what the sticker is about. A new digest is a new finding.
    let digest: String
}

/// The stickers beside the bubble: one per job whose latest output has a preview, newest first. Putting one away
/// remembers its digest, so it stays away until the job finds something else; a job turned off, ended or without a
/// preview loses its sticker by itself.
@MainActor
final class RunStickers: ObservableObject {
    /// How many sit beside the bubble; the rest are "and N more".
    static let shown = 3
    /// What a sticker says when the run said nothing in words: the same as its notification.
    static let somethingNew = "Its preview has something new."
    /// Every current one, newest first.
    @Published private(set) var stickers: [RunSticker] = []
    /// Where the put-away digests are kept, `{"<job uuid>": "<digest>"}`; nil keeps them in memory.
    private let file: URL?
    /// The digest put away for each job, by the job's id.
    private var away: [String: String]

    var more: Int { max(0, stickers.count - Self.shown) }
    var shown: [RunSticker] { Array(stickers.prefix(Self.shown)) }

    init(file: URL?) {
        self.file = file
        away = Self.read(file)
    }

    /// The stickers as they should be at `now`: at launch, at each tick and when the cards change. Publishes only when
    /// the list changed, so the bubble doesn't redraw at every tick. Put-aways for jobs that are gone are forgotten.
    func update(_ jobs: [FolderJob], at now: Date = Date()) {
        let current = jobs.compactMap { Self.sticker(for: $0, at: now) }
            .filter { away[$0.id.uuidString] != $0.digest }
            .sorted { $0.at == $1.at ? $0.jobName < $1.jobName : $0.at > $1.at }
        if current != stickers { stickers = current }
        let present = Set(jobs.map(\.id.uuidString))
        let kept = away.filter { present.contains($0.key) }
        if kept != away {
            away = kept
            write()
        }
    }

    /// The person dismissed it: its digest is remembered, so it stays away until the job finds something else.
    func putAway(_ id: UUID) {
        guard let sticker = stickers.first(where: { $0.id == id }) else { return }
        away[id.uuidString] = sticker.digest
        write()
        stickers.removeAll { $0.id == id }
    }

    /// What the job's sticker says, or nil when it has no card (`FolderJobCards.hasCard`): off, before its start, after
    /// its end, not run yet, or without a preview.
    static func sticker(for job: FolderJob, at now: Date) -> RunSticker? {
        guard FolderJobCards.hasCard(job, at: now), let success = job.state.lastSuccessAt, let digest = job.state.preview else { return nil }
        return RunSticker(id: job.id, jobName: job.name, byline: FolderJobWords.names(job.contributors),
                          said: job.state.said ?? somethingNew, at: success, digest: digest)
    }

    // MARK: stickers.json

    /// A missing or unreadable file is empty.
    private static func read(_ file: URL?) -> [String: String] {
        guard let file, let data = try? Data(contentsOf: file),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        return object.compactMapValues { $0 as? String }
    }

    private func write() {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JobFiles.write(JSONText.pretty(away, indent: "") + "\n", to: file)
        } catch {
            Log.info("jobs: couldn't keep the put-away stickers: \(error.localizedDescription)")
        }
    }
}
