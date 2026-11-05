import Foundation
import Testing
@testable import Familiar

/// The minister's receipt on a job's page: what became of each finding, in words checked without a view. Matters kept
/// in memory only; nothing runs a script or reaches a model.
@Suite @MainActor
struct FindingVerdictsTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// Stickers first, urgent before calm; then one waiting for its sticker; then one the minister hasn't seen; the
    /// quiet last, with why. Each line names its matter, to open.
    @Test func eachFindingSaysWhatBecameOfIt() throws {
        var job = FolderJob(id: UUID(), source: .team, path: "holiday/oct/gm", name: "GM", about: "", everyMinutes: 60)
        job.map = try FindingsMap.parse(["id": "item", "what": "problem"] as [String: Any])
        let columns = ["item", "problem"]
        func kept(_ id: String, _ problem: String, seen: TimeInterval) -> FindingsSnapshot.Kept {
            FindingsSnapshot.Kept(row: FindingRow(id: id, values: ["item": id, "problem": problem], columns: columns), firstSeen: now - seen, changedAt: nil)
        }
        var snapshot = FindingsSnapshot()
        snapshot.columns = columns
        snapshot.rows = ["K-1": kept("K-1", "price shows 18.99", seen: 60), "K-2": kept("K-2", "a test item", seen: 30),
                         "K-3": kept("K-3", "couldn't check", seen: 120), "K-4": kept("K-4", "badge missing", seen: 10),
                         "K-5": kept("K-5", "seller changed", seen: 20)]
        let matters = Matters(directory: nil)
        matters.clock = { now }
        func ref(_ id: String) -> FindingRef { FindingRef(job: job, id: id) }
        matters.save(Matter(id: "m-1", findings: [ref("K-1")], state: .open, view: MatterView(text: "K-1 shows 18.99.", tone: .urgent),
                            jobName: job.name, createdAt: now, updatedAt: now))
        matters.save(Matter(id: "m-2", findings: [ref("K-2")], state: .quiet, why: "A test item.", jobName: job.name, createdAt: now, updatedAt: now))
        matters.save(Matter(id: "m-3", findings: [ref("K-3")], state: .open, jobName: job.name, createdAt: now, updatedAt: now))   // not written yet
        matters.save(Matter(id: "m-5", findings: [ref("K-5")], state: .open, view: MatterView(text: "The seller changed."), jobName: job.name,
                            createdAt: now, updatedAt: now))

        let lines = FindingVerdicts.lines(for: job, snapshot: snapshot, matters: matters, now: now)
        #expect(lines.map(\.id) == ["K-1", "K-5", "K-3", "K-4", "K-2"])
        #expect(lines.map(\.verdict) == [.shown(urgent: true), .shown(urgent: false), .waiting, .unjudged, .quiet("A test item.")])
        #expect(lines.map(\.matter) == ["m-1", "m-5", "m-3", nil, "m-2"])
        #expect(lines[0].label == "K-1 · price shows 18.99")
        #expect(FindingVerdicts.summary(lines) == "5 findings: 2 on stickers, 1 waiting for its sticker, 1 not judged yet, 1 kept quiet")

        #expect(FindingVerdicts.words(.shown(urgent: true)) == "On a sticker, urgent")
        #expect(FindingVerdicts.words(.shown(urgent: false)) == "On a sticker")
        #expect(FindingVerdicts.words(.waiting) == "Its sticker is being written")
        #expect(FindingVerdicts.words(.quiet("You put it away.")) == "Kept quiet: You put it away.")
        #expect(FindingVerdicts.words(.quiet(nil)) == "Kept quiet: no reason kept.")
        #expect(FindingVerdicts.words(.unjudged) == "Not judged yet")

        // A sticker past its time counts as quiet until the minister's tick says so; one not written yet is waiting.
        var passed = Matter(id: "m-6", findings: [ref("K-6")], state: .open, view: MatterView(text: "Soon.", until: now - 1),
                            jobName: job.name, createdAt: now, updatedAt: now)
        #expect(FindingVerdicts.verdict(passed, now: now) == .quiet(Matter.timePassed))
        passed.view = nil
        #expect(FindingVerdicts.verdict(passed, now: now) == .waiting)
        #expect(FindingVerdicts.verdict(nil, now: now) == .unjudged)
    }

    /// The summary reads as a sentence whatever the mix; a finding's label says whom and what, never a Message-ID
    /// when the row says whom.
    @Test func theSummaryAndTheLabelsReadAsSentences() throws {
        func line(_ id: String, _ verdict: FindingVerdicts.Verdict) -> FindingVerdicts.Line { FindingVerdicts.Line(id: id, label: id, verdict: verdict, matter: nil) }
        #expect(FindingVerdicts.summary([]) == nil)
        #expect(FindingVerdicts.summary([line("a", .quiet(nil))]) == "1 finding: kept quiet")
        #expect(FindingVerdicts.summary([line("a", .shown(urgent: false))]) == "1 finding: on a sticker")
        #expect(FindingVerdicts.summary([line("a", .quiet(nil)), line("b", .quiet("x"))]) == "2 findings: all kept quiet")
        #expect(FindingVerdicts.summary([line("a", .unjudged), line("b", .unjudged)]) == "2 findings: none judged yet")
        #expect(FindingVerdicts.summary([line("a", .shown(urgent: true)), line("b", .quiet(nil)), line("c", .quiet(nil))]) == "3 findings: 1 on a sticker, 2 kept quiet")
        #expect(FindingVerdicts.more(Array(repeating: line("a", .quiet(nil)), count: 15)) == "and 3 more")
        #expect(FindingVerdicts.more([line("a", .quiet(nil))]) == nil)

        let mail = try FindingsMap.parse(["id": "id", "about": ["from"], "what": "subject"] as [String: Any])
        let columns = ["id", "from", "subject"]
        #expect(FindingVerdicts.label(FindingRow(id: "<a1@x>", values: ["id": "<a1@x>", "from": "Lena Park", "subject": "Deck by 3?"], columns: columns), map: mail)
                == "Lena Park · Deck by 3?")
        #expect(FindingVerdicts.label(FindingRow(id: "<a1@x>", values: ["id": "<a1@x>", "from": "", "subject": ""], columns: columns), map: mail) == "<a1@x>")
        #expect(FindingVerdicts.label(FindingRow(id: "K-1", values: ["item": "K-1"], columns: ["item"]), map: nil) == "K-1")
        let long = String(repeating: "y", count: 120)
        let gm = try FindingsMap.parse(["id": "item", "what": "problem"] as [String: Any])
        #expect(FindingVerdicts.label(FindingRow(id: "K-1", values: ["item": "K-1", "problem": long], columns: ["item", "problem"]), map: gm)
                == "K-1 · " + String(repeating: "y", count: 84) + "…")
    }

    /// A matter's heading in the Jobs window says whether it is on a sticker, kept quiet, or over.
    @Test func theMatterHeadingFollowsItsState() {
        #expect(JobsNavigation.title(for: .matter("m-1"), jobName: { _ in nil }) == "On your note")
        #expect(JobsNavigation.title(for: .matter("m-1"), jobName: { _ in nil }, matterState: { _ in .quiet }) == "Kept quiet")
        #expect(JobsNavigation.title(for: .matter("m-1"), jobName: { _ in nil }, matterState: { _ in .closed }) == "Over")
        #expect(JobsNavigation.title(for: .matter("m-1"), jobName: { _ in nil }, matterState: { _ in .yours }) == "Yours")
    }
}
