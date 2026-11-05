import Foundation
import Testing
@testable import Familiar

/// The receipt: today's tally and lists, read from the memory log and the matters, and the deck's end after the last card.
@Suite @MainActor struct ReceiptTests {
    /// 2026-09-21, 10:13 AM in New York.
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func fixture() -> (matters: Matters, log: MemoryLog, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("receipt-\(UUID().uuidString)")
        let log = MemoryLog(directory: dir.appendingPathComponent("memory"))
        log.clock = { self.at }
        let matters = Matters(directory: nil)
        matters.clock = { self.at }
        matters.memory = log
        return (matters, log, dir)
    }

    private func matter(_ id: String, _ headline: String, action: Bool = true) -> Matter {
        let ref = FindingRef(job: "team/pages", id: id)
        let view = MatterView(headline: headline, text: "Words.", action: action ? MatterView.Action(finding: ref, run: "nudge", label: "Nudge warehouse") : nil, tone: .calm)
        var matter = Matter(id: id, findings: [ref], state: .open, view: view, jobName: "Pages up", byline: "Yang", createdAt: at, updatedAt: at)
        matter.writtenAt = at
        return matter
    }

    @Test func anEmptyDayReadsAsOne() {
        let (matters, log, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let receipt = Receipt.today(log: log, matters: matters, now: at)
        #expect(receipt.isEmpty && receipt.tally == "Nothing came through the deck today." && receipt.lookedLine(now: at) == nil)
        #expect(Receipt.today(log: nil, matters: matters, now: at).isEmpty)
    }

    @Test func theTallyAndTheListsComeFromTheLogAndTheMatters() async throws {
        let (matters, log, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        for id in ["m-1", "m-2", "m-3", "m-4"] { matters.save(matter(id, "Thing \(id)")) }
        // A job looked, twice; the later time is the one.
        log.append(["job": "team/pages", "name": "Pages up", "ran": ["found": 4]])
        log.clock = { self.at.addingTimeInterval(600) }
        log.append(["job": "team/pages", "name": "Pages up", "ran": ["found": 4]])
        log.append(["job": "own/orders", "name": "Orders", "ran": ["found": 1]])
        // The person's stamps, as the deck writes them.
        let model = DeckModel(matters: matters)
        model.clock = { self.at.addingTimeInterval(700) }
        model.stampSeconds = 0
        model.undoSeconds = 0
        model.press = { _, action in FindingPress(label: action.label, at: self.at.addingTimeInterval(700), said: "Nudged.", failed: false) }
        model.stamp(.notNow, on: "m-1")
        model.stamp(.mine, on: "m-2")
        model.stamp(.doIt, on: "m-3")
        model.undo()
        model.stamp(.doIt, on: "m-3")
        await model.flush()
        matters.record(FindingPress(label: "Nudge warehouse", at: at.addingTimeInterval(700), said: "Nudged.", failed: false), on: FindingRef(job: "team/pages", id: "m-3"))

        let now = at.addingTimeInterval(800)
        let receipt = Receipt.today(log: log, matters: matters, now: now)
        #expect(receipt.decided == 3 && receipt.undone == 1 && receipt.did.count == 1)
        #expect(receipt.tally == "Noteling did 1 · you decided 3 · 1 taken back")
        #expect(receipt.did.first?.headline == "Thing m-3" && receipt.did.first?.label == "Nudge warehouse" && receipt.did.first?.said == "Nudged." && receipt.did.first?.failed == false)
        #expect(receipt.yours.map(\.id) == ["m-2"] && receipt.putAway.map(\.id) == ["m-1"])
        #expect(receipt.looked.map(\.name) == ["Orders", "Pages up"] || receipt.looked.map(\.name) == ["Pages up", "Orders"])
        #expect(receipt.lookedLine(now: now)?.contains("Pages up") == true && receipt.looked.first { $0.job == "team/pages" }?.at == at.addingTimeInterval(600))
        #expect(!receipt.isEmpty)
        // The deck's end says the same.
        #expect(model.tally == "Noteling did 1 · you decided 3 · 1 taken back")
    }

    @Test func theDeckEndsForAMomentAfterTheLastCard() {
        let (matters, _, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        matters.save(matter("m-1", "One", action: false))
        matters.save(matter("m-2", "Two", action: false))
        let model = DeckModel(matters: matters)
        model.clock = { self.at }
        model.stampSeconds = 0
        model.endSeconds = 60
        model.stamp(.notNow, on: "m-1")
        #expect(!model.ended && model.hasSomethingToShow)
        model.stamp(.notNow, on: "m-2")
        #expect(model.ended && model.card == nil && model.hasSomethingToShow)
        #expect(JobsNavigation.title(for: .receipt, jobName: { _ in nil }) == "What's been handled" && JobsWindowView.symbol(.receipt) == "checkmark.seal")
    }
}
