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
}

/// A sticker as the app renders it: the minister's words, one button at most, the page it lives on, and its tone.
struct MatterView: Codable, Equatable {
    enum Tone: String, Codable { case calm, urgent, good }
    struct Action: Codable, Equatable {
        var finding: FindingRef
        var run: String
        var label: String
    }
    /// The thing, in a few words, as a person would head a sticky: "Checkout is down". Older matters have none.
    var headline: String?
    var text: String
    var action: Action?
    /// The page it lives on, when a finding has one.
    var page: String?
    var tone: Tone = .calm
    /// When the sticker should leave even if its findings stay.
    var until: Date?

    static let textLimit = 240
    static let headlineLimit = 40
}

/// One thing worth the person's attention, as the minister sees it: findings across jobs that are one thing, its sticker
/// (the view), its dossier (`notes.md` beside it) and its state. The minister writes the words; code keeps the state.
struct Matter: Codable, Equatable, Identifiable {
    enum State: String, Codable {
        /// On a sticker, or waiting for one to be written.
        case open
        /// Kept in memory: the minister said why, or the person put it away.
        case quiet
        /// The person took it: its card became one of their notes. Shown again only if a finding changes and the minister says so.
        case yours
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
    /// When anything about it last changed; the sticker's own time is `writtenAt`.
    var updatedAt: Date
    /// When its sticker was last written.
    var writtenAt: Date?
    var putAwayAt: Date?
    var closedAt: Date?
    /// An urgent sticker told the person once.
    var notified = false
    /// Its sticker and notes need writing, or writing again: a finding joined or left, or its verdict changed.
    var recompose = false
    /// What pressing its buttons came to, the last five.
    var presses: [FindingPress] = []

    /// On a sticker at `now`: open, written, and not past its `until`.
    func isShown(at now: Date) -> Bool {
        guard state == .open, let view else { return false }
        return view.until.map { $0 > now } ?? true
    }
    var isUrgent: Bool { view?.tone == .urgent }
    /// Good news: needs nothing of the person, shown last.
    var isGood: Bool { view?.tone == .good }
    /// The sticker's time: when it was written, or when the matter was made.
    var shownAt: Date { writtenAt ?? createdAt }

    static let putAway = "You put it away."
    static let timePassed = "Its time passed."
    static let taken = "You took it."
    /// "Noteling did it: Nudge warehouse."
    static func done(_ label: String) -> String { "Noteling did it: \(label)." }

    /// A new id: short, so the minister can name it back.
    static func newID() -> String { "m-" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(8)) }
}

/// A sticker beside the note, as the panel draws it.
struct Sticker: Identifiable, Equatable {
    /// The matter's id.
    let id: String
    /// The lead job's name.
    let title: String
    /// The thing in a few words, when the minister wrote one.
    var headline: String?
    let text: String
    /// Who shared the job, "Yang" or "Yang and Ana"; nil for your own.
    let byline: String?
    let at: Date
    let urgent: Bool
    /// Good news: on green paper, last, with a Thanks and no action.
    var good = false
    /// The page it lives on, and the action the minister picked, when there is one.
    var page: String?
    var action: MatterView.Action?

    /// "Stuck orders · shared by Lena Park · 9:02 AM", the card's byline.
    func line(now: Date) -> String {
        [title, byline.map { "shared by " + $0 }, JobWords.time(at, now: now)].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The matters on this Mac: one folder each in `matters/`, with `matter.json` (what code keeps and the minister's
/// sticker) and `notes.md` (the minister's dossier). The deck's cards are the open matters with a sticker, urgent ones
/// first, newest next, one at a time; the minister keeps the deck to `deckLimit`.
@MainActor
final class Matters: ObservableObject {
    @Published private(set) var all: [Matter] = []
    let directory: URL?
    var clock: () -> Date = Date.init
    /// Where what the person does with a matter is written down.
    var memory: MemoryLog?

    static let folder = "matters"
    /// How many cards the minister may have on the deck at once: told to it at triage, so the rest stay quiet with a why.
    static let deckLimit = 6
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

    /// The stickers as they should be now: urgent first, good news last, the most recently written first between.
    var stickers: [Sticker] {
        let now = clock()
        return all.filter { $0.isShown(at: now) }.sorted { a, b in
            if a.isUrgent != b.isUrgent { return a.isUrgent }
            if a.isGood != b.isGood { return !a.isGood }
            return a.shownAt > b.shownAt
        }.map { matter in
            Sticker(id: matter.id, title: matter.jobName, headline: matter.view?.headline, text: matter.view?.text ?? "", byline: matter.byline,
                    at: matter.shownAt, urgent: matter.isUrgent, good: matter.isGood, page: matter.view?.page, action: matter.isGood ? nil : matter.view?.action)
        }
    }

    /// An id no matter has.
    func freshID() -> String {
        var id = Matter.newID()
        while all.contains(where: { $0.id == id }) { id = Matter.newID() }
        return id
    }

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
        matter.recompose = false   // nothing to write for a sticker that is down
        save(matter)
        memory?.append(["matter": id, "stamp": "not now", "put_away": true])
    }

    /// The person took the matter: its card became one of their notes. Yours until a finding changes and the minister
    /// says it should be seen again; the note stays theirs whatever happens here.
    @discardableResult
    func take(_ id: String) -> Matter? {
        guard var matter = matter(id: id), matter.state == .open else { return nil }
        matter.state = .yours
        matter.why = Matter.taken
        matter.putAwayAt = clock()
        matter.recompose = false
        save(matter)
        memory?.append(["matter": id, "stamp": "mine", "taken": matter.view?.headline ?? matter.view?.text ?? ""])
        return matter
    }

    /// The person thanked a good-news card: quiet, like put away, but no lesson is drawn from it.
    func thank(_ id: String) {
        guard var matter = matter(id: id), matter.state == .open else { return }
        matter.state = .quiet
        matter.why = Matter.putAway
        matter.putAwayAt = clock()
        matter.recompose = false
        save(matter)
        memory?.append(["matter": id, "stamp": "thanks", "put_away": true])
    }

    /// The person had Noteling press the card's action: the matter is quiet, with what was done, until a finding changes.
    func did(_ id: String, _ label: String) {
        guard var matter = matter(id: id), matter.state == .open else { return }
        matter.state = .quiet
        matter.why = Matter.done(label)
        matter.putAwayAt = clock()
        matter.recompose = false
        save(matter)
        memory?.append(["matter": id, "stamp": "do", "did": label])
    }

    /// A sticker's time passed: the matter is quiet, in memory, until a finding changes and the minister says otherwise.
    func timePassed(_ id: String) {
        guard var matter = matter(id: id), matter.state == .open else { return }
        matter.state = .quiet
        matter.why = Matter.timePassed
        matter.recompose = false
        save(matter)
        memory?.append(["matter": id, "quiet": Matter.timePassed])
    }

    /// A finding is gone (or its job is off, ended or gone): it leaves its matter. A matter left with nothing closes;
    /// one with findings left needs its sticker written again. The matter as it stands, or nil when no matter had the
    /// finding.
    @discardableResult
    func remove(_ ref: FindingRef, why: String = "its findings are gone") -> Matter? {
        guard var matter = matter(containing: ref) else { return nil }
        matter.findings.removeAll { $0 == ref }
        if matter.findings.isEmpty {
            matter.state = .closed
            matter.closedAt = clock()
            matter.view = nil
            matter.recompose = false
            memory?.append(["matter": matter.id, "closed": why])
        } else {
            matter.recompose = true
            memory?.append(["matter": matter.id, "left": ref.key, "why": why])
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
            do { return try decoder.decode(Matter.self, from: data) } catch {
                Log.info("matters: \(folder)/matter.json can't be read, so it is left alone: \(error.localizedDescription)")
                return nil
            }
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
