import Combine
import Foundation

/// What the person taught the minister by stamping: two Not now on cards of one job within a week, and the deck asks
/// "Stop showing these?"; Yes is a lesson, kept in `matters/taught.json`, read by the minister at every turn and listed
/// on the receipt, where it can be forgotten; No is remembered for a week so the question isn't asked again at once.
struct Lesson: Codable, Equatable, Identifiable {
    var id: String { job }
    /// The job as the log names it: `team/holiday/oct/gm`.
    let job: String
    let name: String
    let at: Date

    /// What the minister is told: "keep the findings of Holiday Oct · GM quiet unless one can't wait".
    var words: String { "Keep the findings of \(name) quiet unless one can't wait." }
}

/// The deck's question, when there is one to ask.
struct LessonQuestion: Equatable {
    let job: String
    let name: String
    /// How many cards of this job were put away lately.
    let putAway: Int

    var text: String { "You've put away \(putAway) cards from \(name) lately. Stop showing its findings unless one can't wait?" }
}

@MainActor
final class Lessons: ObservableObject {
    @Published private(set) var all: [Lesson] = []
    /// Jobs whose question the person said No to, and when; asked again only after `declineDays`.
    @Published private(set) var declined: [String: Date] = [:]
    let file: URL?
    var clock: () -> Date = Date.init

    static let fileName = "taught.json"
    static let askAfter = 2
    static let lookBackDays = 7
    static let declineDays = 7

    private struct Kept: Codable {
        var lessons: [Lesson] = []
        var declined: [String: Date] = [:]
    }

    init(file: URL?) {
        self.file = file
        read()
    }

    func lesson(for job: String) -> Lesson? { all.first { $0.job == job } }

    /// Yes: the lesson is kept, and told to the minister from its next turn.
    func teach(job: String, name: String) {
        guard lesson(for: job) == nil else { return }
        all.append(Lesson(job: job, name: name, at: clock()))
        all.sort { $0.at > $1.at }
        write()
    }

    /// No: not asked again about this job for a week.
    func decline(job: String) {
        declined[job] = clock()
        write()
    }

    /// The receipt's Forget: the minister stops keeping it quiet.
    func forget(job: String) {
        all.removeAll { $0.job == job }
        write()
    }

    /// The question to ask, if any: the job with the most cards put away lately (two at least), with no lesson and
    /// no No within the week. `putAway` lists the jobs of the cards put away, newest first, from the log.
    func question(putAway: [(job: String, name: String, at: Date)]) -> LessonQuestion? {
        let now = clock()
        let recent = putAway.filter { now.timeIntervalSince($0.at) <= Double(Self.lookBackDays) * 86_400 }
        var counts: [String: (name: String, count: Int)] = [:]
        for item in recent { counts[item.job] = (item.name, (counts[item.job]?.count ?? 0) + 1) }
        let candidates = counts.filter { job, entry in
            entry.count >= Self.askAfter && lesson(for: job) == nil
                && (declined[job].map { now.timeIntervalSince($0) > Double(Self.declineDays) * 86_400 } ?? true)
        }
        guard let best = candidates.max(by: { $0.value.count != $1.value.count ? $0.value.count < $1.value.count : $0.key > $1.key }) else { return nil }
        return LessonQuestion(job: best.key, name: best.value.name, putAway: best.value.count)
    }

    /// The cards put away lately, from the log's last week: each Not now stamp with its matter's job.
    static func putAway(log: MemoryLog?, matters: Matters, now: Date, calendar: Calendar = .current) -> [(job: String, name: String, at: Date)] {
        guard let log else { return [] }
        var out: [(job: String, name: String, at: Date)] = []
        for back in 0..<lookBackDays {
            guard let day = calendar.date(byAdding: .day, value: -back, to: now) else { continue }
            for line in log.lines(on: day) where line["stamp"] as? String == "not now" {
                guard let id = line["matter"] as? String, let matter = matters.matter(id: id), let job = matter.findings.first?.job,
                      let stamp = line["t"] as? String, let at = JobMoment.parse(stamp)?.date else { continue }
                out.append((job, matter.jobName, at))
            }
        }
        return out.sorted { $0.at > $1.at }
    }

    // MARK: the file

    private func read() {
        guard let file, let data = try? Data(contentsOf: file) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let kept = try? decoder.decode(Kept.self, from: data) else {
            Log.info("lessons: \(file.lastPathComponent) can't be read, so it is left alone")
            return
        }
        all = kept.lessons.sorted { $0.at > $1.at }
        declined = kept.declined
    }

    private func write() {
        guard let file else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JobFiles.write(try encoder.encode(Kept(lessons: all, declined: declined)), to: file)
        } catch {
            Log.info("lessons: couldn't keep \(file.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
