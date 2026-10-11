import Foundation
import Testing
@testable import Familiar

/// Finding your team's jobs, thanking whoever shared one, and keeping a job's own cards out of sight while it's off or
/// outside its window. Temp folders only; no script runs and no model is reached.
@Suite @MainActor
struct JobSearchAndThanksTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func team(_ name: String, path: String, on: Bool = false) -> Job {
        Job(id: UUID(), kind: .teamJob, name: name, path: path, does: "", every: "", lastRun: "", status: on ? .ready : .off, on: on)
    }

    // MARK: finding them

    @Test func aSearchFindsTeamJobsByNameOrFolderAndNeverHidesOnesThatAreOn() {
        let mail = Job(id: UUID(), kind: .mail, name: "Morning mail", does: "", every: "", lastRun: "", status: .ready)
        let gm = team("Holiday Oct · GM", path: "holiday/oct/gm")
        let fashion = team("Holiday Oct · Fashion", path: "holiday/oct/fashion")
        let kitchen = team("Kitchen", path: "home/kitchen", on: true)
        let shoes = team("Shoes", path: "spring/shoes")
        let all = [mail, gm, fashion, kitchen, shoes]

        #expect(Jobs.searched(all, "") == all && Jobs.searched(all, "   ") == all)
        // Its name or its folder, ignoring case; every word must match. Yours and the ones you turned on always show.
        #expect(Jobs.searched(all, "GM").map(\.name) == ["Morning mail", "Holiday Oct · GM", "Kitchen"])
        #expect(Jobs.searched(all, "holiday oct").map(\.name) == ["Morning mail", "Holiday Oct · GM", "Holiday Oct · Fashion", "Kitchen"])
        #expect(Jobs.searched(all, "spring").map(\.name) == ["Morning mail", "Kitchen", "Shoes"])
        #expect(Jobs.searched(all, "holiday shoes").map(\.name) == ["Morning mail", "Kitchen"])

        // The line under the box, and when the box shows: past a handful, or whenever a search is kept.
        #expect(Jobs.searchLine(shown: 5, of: 100, search: "gm") == "Showing 5 of 100")
        #expect(Jobs.searchLine(shown: 100, of: 100, search: " ") == nil)
        #expect(!Jobs.showsSearch(teamJobs: Jobs.searchFrom, search: "") && Jobs.showsSearch(teamJobs: Jobs.searchFrom + 1, search: ""))
        #expect(Jobs.showsSearch(teamJobs: 1, search: "gm"))
    }

    @Test func theSearchIsKeptUntilItsCleared() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("job-search-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        func store() -> FolderJobStore {
            FolderJobStore(directory: root.appendingPathComponent("jobs"), results: root.appendingPathComponent("job-results"))
        }
        let first = store()
        #expect(first.search == "")
        first.setSearch("holiday gm")
        #expect(first.search == "holiday gm")
        #expect(store().search == "holiday gm")   // the next time Jobs opens, or the next launch
        #expect(try String(contentsOf: root.appendingPathComponent("job-results/search.json"), encoding: .utf8).contains("holiday gm"))
        first.setSearch("")
        #expect(store().search == "")
    }

    // MARK: thanking whoever shared it

    @Test func jobJsonNamesWhoSharedItAndTheJobThanksThem() throws {
        func parse(_ text: String) throws -> FolderJob { try FolderJobFiles.parse(Data(text.utf8), path: "holiday/oct/gm", source: .team) }
        #expect(try parse(#"{"contributor": "Yang"}"#).contributors == ["Yang"])
        #expect(try parse(#"{"contributor": [" Yang ", "Ana", "yang", ""]}"#).contributors == ["Yang", "Ana"])
        #expect(try parse(#"{"name": "GM"}"#).contributors == [])
        #expect(throws: FolderJobError("In its job.json, contributor must be a name in quotes, or a list of them.")) {
            try parse(#"{"contributor": 7}"#)
        }

        #expect(FolderJobWords.names([]) == nil && FolderJobWords.names(["Yang"]) == "Yang")
        #expect(FolderJobWords.names(["Yang", "Ana"]) == "Yang and Ana" && FolderJobWords.names(["Yang", "Ana", "Sam"]) == "Yang, Ana and Sam")

        var job = try parse(#"{"name": "Holiday Oct · GM", "contributor": "Yang"}"#)
        #expect(FolderJobWords.sharedBy(job) == "Shared by Yang")
        #expect(Jobs.folderJob(job, Jobs.Input(now: now)).sharedBy == "Shared by Yang")
        #expect(JobRow.place(Jobs.folderJob(job, Jobs.Input(now: now))) == "holiday/oct/gm · Shared by Yang")

        // One line per run, from the set: the same while that run's result shows, and not always the same one.
        let first = try #require(FolderJobWords.thanks(job, run: now))
        #expect(FolderJobWords.thanks(job, run: now) == first)
        let lines = Set((0..<40).compactMap { FolderJobWords.thanks(job, run: now.addingTimeInterval(Double($0) * 3_600)) })
        #expect(lines.count > 1 && lines.allSatisfy { line in FolderJobWords.thanks.contains { $0.replacingOccurrences(of: "{name}", with: "Yang") == line } })
        #expect(FolderJobWords.thanks(job, run: nil) == nil)   // before a run worked
        job.contributors = []
        #expect(FolderJobWords.thanks(job, run: now) == nil && FolderJobWords.sharedBy(job) == nil)
    }

    @Test func runNowLeavesAReceiptThatThanksWhoSharedTheJob() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("job-receipt-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let team = root.appendingPathComponent("linked/jobs")
        for (path, json) in [("gm", #"{"name": "GM", "contributor": "Yang"}"#), ("shoes", #"{"name": "Shoes"}"#)] {
            let folder = team.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try json.write(to: folder.appendingPathComponent("job.json"), atomically: true, encoding: .utf8)
            try "def run():\n    return None\n".write(to: folder.appendingPathComponent("job.py"), atomically: true, encoding: .utf8)
        }
        let store = FolderJobStore(directory: root.appendingPathComponent("jobs"), results: root.appendingPathComponent("job-results"),
                                   teamDirectory: { team })
        var fail = false
        let runner = FolderJobRunner(store: store, execute: { _ in
            if fail { throw FolderJobError("The price service didn't answer.") }
            return "2 of 8 items need a look"
        })
        let gm = try #require(store.jobs.first { $0.path == "gm" }), shoes = try #require(store.jobs.first { $0.path == "shoes" })

        // Turning a job on runs it, quietly: no receipt.
        try runner.turn(gm.id, on: true)
        await runner.finish()
        #expect(runner.receipt == nil)

        // Run now does, with what it said and a thank-you.
        #expect(runner.run(gm.id) == nil)
        await runner.finish()
        let receipt = try #require(runner.receipt)
        #expect(receipt.jobID == gm.id && receipt.text.hasPrefix("“GM” ran: 2 of 8 items need a look. "))
        let ran = try #require(store.job(id: gm.id))
        let thanks = try #require(FolderJobWords.thanks(ran, run: ran.state.lastSuccessAt))
        #expect(receipt.text.hasSuffix(thanks))
        runner.dismissReceipt()
        #expect(runner.receipt == nil)

        // A run that fails says why, and thanks nobody; a job nobody's named in just says what it found.
        fail = true
        runner.run(gm.id)
        await runner.finish()
        #expect(runner.receipt?.text == "“GM” couldn't finish: The price service didn't answer.")
        fail = false
        try runner.turn(shoes.id, on: true)
        await runner.finish()
        runner.run(shoes.id)
        await runner.finish()
        #expect(runner.receipt?.text == "“Shoes” ran: 2 of 8 items need a look.")
    }

    // MARK: a job's own cards

    @Test func aJobsOwnCardsArePutAwayWhileItsOffOrOutsideItsWindowAndComeBack() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("job-held-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("cards/inbox")
        let morning = MorningStore(directory: root.appendingPathComponent("morning"))
        let scan = CardInbox(store: morning, directory: inbox)
        var held = false
        scan.held = { $0 == "jobcards-team-gm" && held }
        let folder = inbox.appendingPathComponent("jobcards-team-gm")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #"{"title": "Ask the seller about item 3"}"#.write(to: folder.appendingPathComponent("follow-up.json"), atomically: true, encoding: .utf8)
        let card = CardInboxFormat.cardID("jobcards-team-gm/follow-up")

        scan.scan(at: now)
        #expect(morning.cards.first { $0.id == card }?.isResolved == false)
        held = true                                   // the job ended, or was turned off
        scan.scan(at: now.addingTimeInterval(60))
        #expect(morning.cards.first { $0.id == card }?.isResolved == true)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("follow-up.json").path))   // its file stays
        held = false                                  // its end moved later, or it was turned on again
        scan.scan(at: now.addingTimeInterval(120))
        #expect(morning.cards.first { $0.id == card }?.isResolved == false)

        // Which folders the jobs hold: a job's own cards while it's off or outside its window; nothing else.
        let team = root.appendingPathComponent("linked/jobs")
        for (path, json) in [("gm", #"{"name": "GM"}"#), ("sale", #"{"name": "Sale", "ends": "2020-01-01T00:00:00Z"}"#)] {
            let job = team.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
            try json.write(to: job.appendingPathComponent("job.json"), atomically: true, encoding: .utf8)
            try "def run():\n    return None\n".write(to: job.appendingPathComponent("job.py"), atomically: true, encoding: .utf8)
        }
        let config = Config()
        let feature = FolderJobsFeature(registry: ToolRegistry(root: root.appendingPathComponent("tools"), runner: ScriptRunner(config: config)),
                                        notifier: JobNotifier(),
                                        store: FolderJobStore(directory: root.appendingPathComponent("jobs"),
                                                              results: root.appendingPathComponent("job-results"), teamDirectory: { team }),
                                        inbox: inbox)
        let gm = try #require(feature.store.jobs.first { $0.path == "gm" }), sale = try #require(feature.store.jobs.first { $0.path == "sale" })
        #expect(feature.holds(FolderJobCards.scriptSource(for: gm)))    // off
        try feature.store.setOn(gm.id, true)
        #expect(!feature.holds(FolderJobCards.scriptSource(for: gm)))   // on and running
        try feature.store.setOn(sale.id, true)
        #expect(feature.holds(FolderJobCards.scriptSource(for: sale)))  // on, but ended
        #expect(!feature.holds(FolderJobCards.source(for: gm)) && !feature.holds("pack-shop"))
    }

    @Test func aTableTooWideForThePageSaysItScrolls() {
        #expect(FolderJobTable.wideLine(columns: 6) == "Scroll sideways for all 6 columns.")
    }
}
