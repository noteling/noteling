import Foundation
import Testing
@testable import Familiar

/// The deck: the card on top and what each stamp does. Not now puts the matter away; Mine takes it and makes it a note;
/// Do it holds the card off the deck while its press waits, can be taken back, and runs after the seconds pass.
@Suite @MainActor struct DeckModelTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func fixture() -> (model: DeckModel, matters: Matters, log: MemoryLog, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deck-\(UUID().uuidString)")
        let log = MemoryLog(directory: dir.appendingPathComponent("memory"))
        log.clock = { self.at }
        let matters = Matters(directory: nil)
        matters.clock = { self.at }
        matters.memory = log
        let model = DeckModel(matters: matters)
        model.clock = { self.at }
        model.stampSeconds = 0
        model.undoSeconds = 0
        return (model, matters, log, dir)
    }

    private func matter(_ id: String, _ headline: String, urgent: Bool = false, action: Bool = true, minutesAgo: Double = 0) -> Matter {
        let ref = FindingRef(job: "team/pages", id: id)
        let view = MatterView(headline: headline, text: "Words about \(headline).", action: action ? MatterView.Action(finding: ref, run: "nudge", label: "Nudge warehouse") : nil,
                              page: "https://shop.example.com/\(id)", tone: urgent ? .urgent : .calm)
        var matter = Matter(id: id, findings: [ref], state: .open, view: view, jobName: "Pages up", byline: "Yang", createdAt: at, updatedAt: at)
        matter.writtenAt = at.addingTimeInterval(-minutesAgo * 60)
        return matter
    }

    private func lines(_ dir: URL) throws -> [[String: Any]] {
        let file = dir.appendingPathComponent("memory").appendingPathComponent("2026-09-21.jsonl")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return try text.split(separator: "\n").map { try #require(try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
    }

    @Test func theCardOnTopIsUrgentFirstThenNewestAndTheRestWait() {
        let (model, matters, _, _) = fixture()
        matters.save(matter("m-old", "Old", minutesAgo: 60))
        matters.save(matter("m-new", "New", minutesAgo: 1))
        matters.save(matter("m-urgent", "Urgent", urgent: true, minutesAgo: 30))
        #expect(model.cards.map(\.id) == ["m-urgent", "m-new", "m-old"] && model.card?.headline == "Urgent" && model.more == 2 && model.count == 3)
    }

    @Test func notNowPutsTheMatterAwayAndMineMakesItANote() throws {
        let (model, matters, _, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        matters.save(matter("m-1", "One"))
        matters.save(matter("m-2", "Two", minutesAgo: 5))
        var mine: [Matter] = []
        model.mine = { mine.append($0) }
        model.stamp(.notNow, on: "m-1")
        #expect(matters.matter(id: "m-1")?.state == .quiet && matters.matter(id: "m-1")?.why == Matter.putAway && model.card?.id == "m-2")
        model.stamp(.mine, on: "m-2")
        let taken = try #require(matters.matter(id: "m-2"))
        #expect(taken.state == .yours && taken.why == Matter.taken && mine.map(\.id) == ["m-2"] && model.card == nil)
        // A card already off the deck takes no stamp; a card with no action takes no Do it.
        model.stamp(.mine, on: "m-1")
        #expect(mine.count == 1)
        matters.save(matter("m-3", "Three", action: false))
        model.stamp(.doIt, on: "m-3")
        #expect(model.pending == nil && model.card?.id == "m-3")
        let stamps = try lines(dir).compactMap { $0["stamp"] as? String }
        #expect(stamps == ["not now", "mine"])
    }

    @Test func doItWaitsCanBeTakenBackAndThenRuns() async throws {
        let (model, matters, _, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        matters.save(matter("m-1", "One"))
        matters.save(matter("m-2", "Two", minutesAgo: 5))
        var pressed: [String] = []
        model.press = { matter, action in
            pressed.append(matter.id + ":" + action.run)
            return FindingPress(label: action.label, at: self.at, said: "Nudged.", failed: false)
        }
        model.undoSeconds = 60
        model.stamp(.doIt, on: "m-1")
        // Off the deck while it waits; the matter is still open underneath; nothing has run.
        #expect(model.pending == PendingPress(id: "m-1", label: "Nudge warehouse", until: at.addingTimeInterval(60)))
        #expect(model.card?.id == "m-2" && model.count == 1 && matters.matter(id: "m-1")?.state == .open && pressed.isEmpty)
        model.undo()
        #expect(model.pending == nil && model.card?.id == "m-1" && model.count == 2 && pressed.isEmpty)

        // Stamped again and left alone: it runs, the matter goes quiet with what was done, and the result shows.
        model.stamp(.doIt, on: "m-1")
        await model.flush()
        #expect(pressed == ["m-1:nudge"] && model.pending == nil)
        #expect(matters.matter(id: "m-1")?.state == .quiet && matters.matter(id: "m-1")?.why == Matter.done("Nudge warehouse"))
        #expect(model.said == "Nudge warehouse · 10:13 AM" && model.card?.id == "m-2")
        let stamps = try lines(dir).compactMap { $0["stamp"] as? String }
        #expect(stamps == ["do", "undo", "do", "do"])

        // A press that fails says so.
        model.press = { _, action in FindingPress(label: action.label, at: self.at, said: "job.py failed: KeyError: 'order'", failed: true) }
        model.stamp(.doIt, on: "m-2")
        await model.flush()
        #expect(model.said == "Couldn't nudge warehouse: job.py failed: KeyError: 'order'")
    }
}
