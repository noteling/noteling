import Combine
import Foundation

/// Which finding of which job a matter is made of, named as the log names it: `team/holiday/oct/gm/4417`.
struct FindingRef: Hashable, Codable {
    /// The job, as `MemoryLog.name(of:)` has it: `team/<path>` or `own/<path>`.
    var job: String
    var id: String

    var key: String { job + "/" + id }

    init(job: String, id: String) {
        self.job = job
        self.id = id
    }

    init(job: FolderJob, id: String) { self.init(job: MemoryLog.name(of: job), id: id) }

    /// A key back into a reference: the id is what follows the job's path, which has no `/` in a job's id… except that
    /// an id may. The job's name is `team/…` or `own/…` with the path; the id is matched against the jobs that exist.
    static func parse(_ key: String, jobs: [String]) -> FindingRef? {
        for job in jobs.sorted(by: { $0.count > $1.count }) where key.hasPrefix(job + "/") {
            let id = String(key.dropFirst(job.count + 1))
            if !id.isEmpty { return FindingRef(job: job, id: id) }
        }
        return nil
    }
}

/// A sticker as the app renders it: the minister's words, one button at most, the page it lives on, and its tone.
struct MatterView: Codable, Equatable {
    enum Tone: String, Codable { case calm, urgent }
    struct Action: Codable, Equatable {
        var finding: FindingRef
        var run: String
        var label: String
    }
    var text: String
    var action: Action?
    /// The page it lives on, when a finding has one.
    var page: String?
    var tone: Tone = .calm
    /// When the sticker should leave even if its findings stay.
    var until: Date?

    static let textLimit = 240
}

/// One thing worth the person's attention, as the minister sees it: findings across jobs that are one thing, its sticker
/// (the view), its dossier (`notes.md` beside it) and its state. The minister writes the words; code keeps the state.
struct Matter: Codable, Equatable, Identifiable {
    enum State: String, Codable {
        /// On a sticker, or waiting for one to be written.
        case open
        /// Kept in memory: the minister said why, or the person put it away.
        case quiet
        /// Its findings are all gone.
        case closed
    }
    var id: String
    var findings: [FindingRef]
    var state: State
    var view: MatterView?
    /// Why it's quiet, in the minister's words, or that the person put it away.
    var why: String?
    /// The lead finding's job, for the sticker's heading, and who shared it.
    var jobName: String
    var byline: String?
    var createdAt: Date
    var updatedAt: Date
    var putAwayAt: Date?
    var closedAt: Date?
    /// An urgent sticker told the person once.
    var notified = false
    /// Its sticker and notes need writing, or writing again: a finding joined or left, or its verdict changed.
    var recompose = false
    /// What pressing its buttons came to, the last five.
    var presses: [FindingPress] = []

    var isShown: Bool { state == .open && view != nil }
    var isUrgent: Bool { view?.tone == .urgent }

    static let putAway = "You put it away."

    /// A new id: short, so the minister can name it back.
    static func newID() -> String { "m-" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(8)) }
}

/// A sticker beside the note, as the panel draws it.
struct Sticker: Identifiable, Equatable {
    /// The matter's id.
    let id: String
    /// The lead job's name.
    let title: String
    let text: String
    /// Who shared the job, "Yang" or "Yang and Ana"; nil for your own.
    let byline: String?
    let at: Date
    let urgent: Bool
}

/// The matters on this Mac: one folder each in `matters/`, with `matter.json` (what code keeps and the minister's
/// sticker) and `notes.md` (the minister's dossier). The stickers beside the note are the open matters with a sticker,
/// urgent ones first, newest next, three at most; the rest are "and N more".
@MainActor
final class Matters: ObservableObject {
    @Published private(set) var all: [Matter] = []
    let directory: URL?
    /// The person's own words about a matter's findings are the only thing that removes anything; the minister folds.
    var clock: () -> Date = Date.init

    static let folder = "matters"
    static let shownLimit = 3
    static let pressLimit = 5
    static let notesLimit = 6_000

    init(directory: URL?) {
        self.directory = directory
        all = Self.read(directory)
    }

    // MARK: reading

    func matter(id: String) -> Matter? { all.first { $0.id == id } }

    /// The matter a finding belongs to, open or quiet.
    func matter(containing ref: FindingRef) -> Matter? { all.first { $0.state != .closed && $0.findings.contains(ref) } }

    var open: [Matter] { all.filter { $0.state == .open } }
    /// Open or quiet: what the minister is told about.
    var current: [Matter] { all.filter { $0.state != .closed } }

    /// The stickers as they should be now: urgent first, then newest.
    var stickers: [Sticker] {
        all.filter(\.isShown).sorted { a, b in
            if a.isUrgent != b.isUrgent { return a.isUrgent }
            return a.updatedAt > b.updatedAt
        }.map { matter in
            Sticker(id: matter.id, title: matter.jobName, text: matter.view?.text ?? "", byline: matter.byline, at: matter.updatedAt,
                    urgent: matter.isUrgent)
        }
    }
    var shown: [Sticker] { Array(stickers.prefix(Self.shownLimit)) }
    var more: Int { max(0, stickers.count - Self.shownLimit) }

    func notes(for id: String) -> String? {
        guard let directory, let text = try? String(contentsOf: directory.appendingPathComponent(id).appendingPathComponent("notes.md"), encoding: .utf8) else { return nil }
        return text.isEmpty ? nil : text
    }

    // MARK: writing

    /// Keeps a matter, new or changed, and its notes when given.
    func save(_ matter: Matter, notes: String? = nil) {
        var matter = matter
        matter.updatedAt = clock()
        if let index = all.firstIndex(where: { $0.id == matter.id }) { all[index] = matter } else { all.append(matter) }
        all.sort { $0.updatedAt > $1.updatedAt }   // as they are read back: newest first
        guard let directory else { return }
        let folder = directory.appendingPathComponent(matter.id)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try JobFiles.write(try encoder.encode(matter), to: folder.appendingPathComponent("matter.json"))
            if let notes { try JobFiles.write(String(notes.prefix(Self.notesLimit)), to: folder.appendingPathComponent("notes.md")) }
        } catch {
            Log.info("matters: couldn't keep \(matter.id): \(error.localizedDescription)")
        }
    }

    /// The person put a sticker away: the matter is quiet until one of its findings changes and the minister says otherwise.
    func putAway(_ id: String) {
        guard var matter = matter(id: id), matter.state == .open else { return }
        matter.state = .quiet
        matter.why = Matter.putAway
        matter.putAwayAt = clock()
        save(matter)
    }

    /// A finding is gone: it leaves its matter. A matter left with nothing closes; one with findings left needs its
    /// sticker written again. The matter as it stands, or nil when no matter had the finding.
    @discardableResult
    func remove(_ ref: FindingRef) -> Matter? {
        guard var matter = matter(containing: ref) else { return nil }
        matter.findings.removeAll { $0 == ref }
        if matter.findings.isEmpty {
            matter.state = .closed
            matter.closedAt = clock()
            matter.view = nil
            matter.recompose = false
        } else {
            matter.recompose = true
        }
        save(matter)
        return matter
    }

    /// What pressing a button on a finding came to, on its matter.
    func record(_ press: FindingPress, on ref: FindingRef) {
        guard var matter = matter(containing: ref) else { return }
        matter.presses = Array((matter.presses + [press]).suffix(Self.pressLimit))
        save(matter)
    }

    // MARK: files

    private static func read(_ directory: URL?) -> [Matter] {
        guard let directory, let folders = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return folders.compactMap { folder -> Matter? in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(folder).appendingPathComponent("matter.json")) else { return nil }
            return try? decoder.decode(Matter.self, from: data)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
