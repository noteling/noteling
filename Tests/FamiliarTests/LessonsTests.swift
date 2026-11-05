import Foundation
import Testing
@testable import Familiar

/// What the person teaches by stamping: two Not now on one job's cards within a week and the deck asks; Yes is a lesson
/// the minister reads and the receipt can forget, No holds the question for a week. Good news comes last, with Thanks.
@Suite @MainActor struct LessonsTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func fixture() -> (matters: Matters, log: MemoryLog, lessons: Lessons, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lessons-\(UUID().uuidString)")
        let log = MemoryLog(directory: dir.appendingPathComponent("memory"))
        log.clock = { self.at }
        let matters = Matters(directory: nil)
        matters.clock = { self.at }
        matters.memory = log
        let lessons = Lessons(file: dir.appendingPathComponent("taught.json"))
        lessons.clock = { self.at }
        return (matters, log, lessons, dir)
    }

    private func matter(_ id: String, job: String, name: String, tone: MatterView.Tone = .calm) -> Matter {
        let ref = FindingRef(job: job, id: id)
        var matter = Matter(id: id, findings: [ref], state: .open, view: MatterView(headline: "Thing \(id)", text: "Words.", tone: tone),
                            jobName: name, byline: nil, createdAt: at, updatedAt: at)
        matter.writtenAt = at
        return matter
    }

    @Test func twoNotNowsOnOneJobWithinAWeekAskTheQuestionOnceAndYesIsALesson() throws {
        let (matters, log, lessons, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        for id in ["r-1", "r-2", "r-3"] { matters.save(matter(id, job: "team/reviews", name: "Reviews")) }
        matters.save(matter("p-1", job: "team/pages", name: "Pages up"))
        let model = DeckModel(matters: matters)
        model.clock = { self.at }
        model.stampSeconds = 0
        model.lessons = lessons
        #expect(model.question == nil)

        model.stamp(.notNow, on: "p-1")
        model.stamp(.notNow, on: "r-1")
        #expect(model.question == nil)   // one each: nothing to ask
        model.stamp(.notNow, on: "r-2")
        let question = try #require(model.question)
        #expect(question.job == "team/reviews" && question.name == "Reviews" && question.putAway == 2)
        #expect(question.text == "You've put away 2 cards from Reviews lately. Stop showing its findings unless one can't wait?")
        #expect(model.card?.id == "r-3" && model.needs == 2 && model.hasSomethingToShow)   // the card first, the question after it

        model.answer(true)
        #expect(model.question == nil && lessons.all.map(\.job) == ["team/reviews"])
        #expect(lessons.lesson(for: "team/reviews")?.words == "Keep the findings of Reviews quiet unless one can't wait.")
        // Kept on disk, told to the minister, and gone again from the receipt's Forget.
        let again = Lessons(file: dir.appendingPathComponent("taught.json"))
        #expect(again.all == lessons.all)
        let shown = MinisterPrompt.Shown(ref: FindingRef(job: "team/reviews", id: "r-9"), job: FolderJob(id: UUID(), source: .team, path: "reviews", name: "Reviews"),
                                         row: FindingRow(id: "r-9", values: [:], columns: []), changed: nil, putAwayAt: nil)
        let prompt = MinisterPrompt.triage([shown], descriptions: [:], matters: [], now: at, lessons: lessons.all)
        #expect(prompt.contains("Taught by the person:\n- Keep the findings of Reviews quiet unless one can't wait. (team/reviews)"))
        #expect(MinisterPrompt.triageSystem.contains("Taught") && MinisterPrompt.triageSystem.contains("good news"))
        lessons.forget(job: "team/reviews")
        #expect(lessons.all.isEmpty && Lessons(file: dir.appendingPathComponent("taught.json")).all.isEmpty)
        // A thanked card never counts as put away.
        #expect(Lessons.putAway(log: log, matters: matters, now: at).map(\.job).sorted() == ["team/pages", "team/reviews", "team/reviews"])
        let stamps = log.lines(on: at).compactMap { $0["stamp"] as? String }
        #expect(stamps == ["not now", "not now", "not now", "taught"])
    }

    @Test func noHoldsTheQuestionForAWeekAndOldPutAwaysDontCount() throws {
        let (matters, _, lessons, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let putAway = [("team/reviews", "Reviews", at), ("team/reviews", "Reviews", at.addingTimeInterval(-3 * 86_400)),
                       ("team/pages", "Pages up", at), ("team/pages", "Pages up", at.addingTimeInterval(-8 * 86_400))]
        #expect(lessons.question(putAway: putAway)?.job == "team/reviews")   // pages' second one is too old
        lessons.decline(job: "team/reviews")
        #expect(lessons.question(putAway: putAway) == nil)
        lessons.clock = { self.at.addingTimeInterval(8 * 86_400) }
        #expect(lessons.question(putAway: putAway) == nil)   // by then the put-aways themselves are old
        lessons.clock = { self.at.addingTimeInterval(6 * 86_400) }
        let fresh = putAway.map { ($0.0, $0.1, self.at.addingTimeInterval(6 * 86_400)) }
        #expect(lessons.question(putAway: fresh.filter { $0.0 == "team/reviews" }) == nil)   // still within the week of the No
        #expect(lessons.question(putAway: fresh)?.job == "team/pages")                        // another job may be asked about meanwhile
        lessons.clock = { self.at.addingTimeInterval(8 * 86_400) }
        #expect(lessons.question(putAway: putAway.map { ($0.0, $0.1, self.at.addingTimeInterval(8 * 86_400)) }.filter { $0.0 == "team/reviews" })?.job == "team/reviews")
    }

    @Test func goodNewsComesLastOnGreenPaperWithThanksAndNeverLightsTheLampAlone() throws {
        let (matters, log, _, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        matters.save(matter("g-1", job: "team/payments", name: "Payments", tone: .good))
        let model = DeckModel(matters: matters)
        model.clock = { self.at }
        model.stampSeconds = 0
        #expect(model.card?.good == true && model.card?.action == nil && model.needs == 0 && model.count == 1 && model.hasSomethingToShow)
        matters.save(matter("c-1", job: "team/pages", name: "Pages up"))
        #expect(model.cards.map(\.id) == ["c-1", "g-1"] && model.needs == 1)
        let good = try #require(model.cards.last)
        #expect(StickersPanel.key(126, card: good) == .thanks("g-1") && StickersPanel.key(123, card: good) == nil)
        #expect(StickersPanel.menu(pointing: good, detached: false, scale: 1).map { $0?.title } == ["Open", "Mine", "Thanks", nil, "Bigger", "Smaller", nil, "Hide stickers"])
        model.stamp(.doIt, on: "g-1")   // nothing to do on good news
        #expect(model.pending == nil)
        model.stamp(.thanks, on: "g-1")
        #expect(matters.matter(id: "g-1")?.state == .quiet && log.lines(on: at).compactMap { $0["stamp"] as? String } == ["thanks"])
        #expect(StampView(verdict: .thanks).words == "THANKS")
        // Compose takes the good tone, and refuses any other.
        let shown = MinisterPrompt.Shown(ref: FindingRef(job: "team/payments", id: "P-1"), job: FolderJob(id: UUID(), source: .team, path: "payments", name: "Payments"),
                                         row: FindingRow(id: "P-1", values: [:], columns: []), changed: nil, putAwayAt: nil)
        let parsed = try MinisterPrompt.parseCompose(["headline": "Acme paid", "text": "Paid in full.", "tone": "good", "notes": ""], findings: [shown])
        #expect(parsed.view.tone == .good)
        #expect(throws: MinisterError.self) { try MinisterPrompt.parseCompose(["headline": "x", "text": "y", "tone": "loud", "notes": ""], findings: [shown]) }
    }
}
