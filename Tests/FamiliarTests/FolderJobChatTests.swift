import Foundation
import Testing
import FamiliarContracts
import FamiliarRuntime
@testable import Familiar

/// The jobs kept as folders in chat: list them, run one now, turn one of the team's on or off, read one's latest
/// result; and, now that watches are gone, what they left behind. Temp folders only; no script runs and no model is
/// reached.
@Suite @MainActor
struct FolderJobChatTests {
    @Test func theChatListsRunsTurnsAndReadsJobsButNeverMakesOne() async throws {
        let place = ChatPlace()
        defer { place.remove() }
        try place.job("stuck-orders", #"{"name": "Stuck orders", "about": "Orders waiting on me"}"#)
        try place.job("holiday/oct/gm", #"{"name": "Holiday Oct · GM", "about": "Prices on the GM items", "every_minutes": 60, "contributor": "Yang"}"#, team: true)
        try place.job("autumn/sale", #"{"name": "Autumn sale", "ends": "2020-01-01T00:00:00Z"}"#, team: true)
        let store = place.store()
        var said = "2 of 8 prices wrong"
        let runner = FolderJobRunner(store: store, execute: { run in
            try FileManager.default.createDirectory(at: run.output.appendingPathComponent("preview"), withIntermediateDirectories: true)
            try "item,what's wrong\nK-1,price 12 – expected 9\n".write(to: run.output.appendingPathComponent("preview/problems.csv"),
                                                                        atomically: true, encoding: .utf8)
            try "item,price\nK-1,12\nK-2,9\n".write(to: run.output.appendingPathComponent("all.csv"), atomically: true, encoding: .utf8)
            return said
        })
        let chat = FolderJobConversation(store: store, runner: runner)
        var receipts: [String] = []
        chat.onChange = { receipts.append($0) }
        let routes = chat.routes()
        #expect(routes.compactMap { $0.definition["name"] as? String } == ["list_jobs", "run_job_now", "turn_on_job", "turn_off_job", "read_job_result"])
        func call(_ name: String, _ input: [String: Any] = [:]) async throws -> (text: String, error: Bool) {
            let result = await (try ToolRouter(routes: routes)).execute(name, input)
            return (result.content as? String ?? "", result.isError)
        }
        func object(_ text: String) throws -> [String: Any] {
            try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        }

        // Every job, yours and your team's: on or not, how often, its window, and where it is in Jobs.
        let listed = try object(try await call("list_jobs").text)
        let jobs = try #require(listed["jobs"] as? [[String: Any]])
        #expect(jobs.map { $0["name"] as? String } == ["Stuck orders", "Autumn sale", "Holiday Oct · GM"])
        let gm = try #require(jobs.first { $0["path"] as? String == "holiday/oct/gm" })
        #expect(gm["on"] as? Bool == false && gm["runs"] as? String == "every hour" && gm["from"] as? String == "your team's tools")
        #expect(gm["about"] as? String == "Prices on the GM items" && gm["last_run"] as? String == "Not run yet")
        #expect(gm["shared_by"] as? String == "Yang")
        #expect(jobs.first { $0["name"] as? String == "Autumn sale" }?["where_in_jobs"] as? String == "under Ended")
        #expect(jobs.first { $0["name"] as? String == "Stuck orders" }?["on"] == nil)   // yours: no switch

        // A job that's off doesn't run; turning it on runs it at once, with a receipt on the pad.
        let off = try await call("run_job_now", ["job": "gm"])
        #expect(off.error && off.text == "“Holiday Oct · GM” is off. Turn it on to have it run.")
        let on = try object(try await call("turn_on_job", ["job": "gm"]).text)
        #expect(on["turned_on"] as? Bool == true && on["on"] as? Bool == true && on["last_run"] as? String != "Not run yet")
        #expect(receipts == ["Turned on “Holiday Oct · GM” from your team's tools."])
        #expect(try await call("turn_on_job", ["job": "Holiday Oct · GM"]).text == "“Holiday Oct · GM” is already on.")

        // Run now waits for the run and returns what it said and its preview, as a table, with the other files named.
        said = "1 of 8 prices wrong"
        let ran = try object(try await call("run_job_now", ["job": "holiday/oct/gm"]).text)
        let result = try #require(ran["latest_result"] as? [String: Any])
        #expect(result["said"] as? String == "1 of 8 prices wrong")
        let preview = try #require(result["preview"] as? [[String: Any]])
        #expect(preview.first?["file"] as? String == "preview/problems.csv")
        #expect(preview.first?["csv"] as? String == "item,what's wrong\nK-1,price 12 – expected 9")
        #expect(result["other_files"] as? [String] == ["all.csv"])
        #expect(receipts.last == "Running “Holiday Oct · GM” now.")
        #expect(try object(try await call("read_job_result", ["job": "gm"]).text)["latest_result"] != nil)

        // Out of its window, or one of yours to switch: said plainly. Turning off puts its card away.
        let ended = try await call("run_job_now", ["job": "Autumn sale"])
        #expect(ended.error && ended.text.contains("so it no longer runs") && ended.text.contains("under Ended in Jobs"))
        let yours = try await call("turn_off_job", ["job": "stuck-orders"])
        #expect(yours.error && yours.text.contains("one of the person's own jobs"))
        #expect(try await call("turn_off_job", ["job": "gm"]).text.hasPrefix("Turned off “Holiday Oct · GM”"))
        #expect(store.jobs.first { $0.path == "holiday/oct/gm" }?.on == false)

        // No job by that name: which there are.
        let missing = try await call("read_job_result", ["job": "shoes"])
        #expect(missing.error && missing.text.hasPrefix("No job is called “shoes”. Jobs:"))
        #expect(FolderJobConversation.csvField("a, b") == "\"a, b\"" && FolderJobConversation.csvField("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    @Test func whatWatchesWroteIntoTheInboxGoesAndTheirCardsResolve() throws {
        let place = ChatPlace()
        defer { place.remove() }
        let inbox = place.root.appendingPathComponent("cards/inbox")
        func write(_ path: String, _ text: String = "{\"title\": \"T\"}") throws {
            let url = inbox.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("watch-team-holiday-oct-gm/job.json", #"{"title": "Holiday Oct · GM: couldn't check 5 of 5", "files": ["problems.csv"]}"#)
        try write("watch-team-holiday-oct-gm/problems.csv", "item\n1\n")
        try write("watch-sale/job.json")
        try write("watch-sale/all-2.csv", "item\n")
        try write("watch-sale/item-ab12.json")
        try write("watch-sale/deal.json")                         // a card the watch's own check wrote: not Noteling's
        try write("pack-shop/job.json")                           // not a watch's folder at all
        let morning = MorningStore(directory: place.root.appendingPathComponent("morning"))
        let scan = CardInbox(store: morning, directory: inbox)
        scan.scan()
        #expect(morning.cards.filter { !$0.isResolved }.count == 5)

        #expect(RetiredWatchCards.cleanUp(inbox: inbox) == 5)
        let manager = FileManager.default
        #expect(!manager.fileExists(atPath: inbox.appendingPathComponent("watch-team-holiday-oct-gm").path))   // emptied, so gone
        #expect(try manager.contentsOfDirectory(atPath: inbox.appendingPathComponent("watch-sale").path) == ["deal.json"])
        #expect(manager.fileExists(atPath: inbox.appendingPathComponent("pack-shop/job.json").path))
        #expect(RetiredWatchCards.cleanUp(inbox: inbox) == 0)   // once they're gone, nothing more

        // Their cards resolve as any card whose file went away does; the others stay.
        scan.scan()
        let open = morning.cards.filter { !$0.isResolved }.compactMap { $0.inbox?.key }.sorted()
        #expect(open == ["pack-shop/job", "watch-sale/deal"])
        #expect(RetiredWatchCards.watchWrote("problems-3.csv") && RetiredWatchCards.watchWrote("all.csv"))
        #expect(!RetiredWatchCards.watchWrote("problems-x.csv") && !RetiredWatchCards.watchWrote("report.csv") && !RetiredWatchCards.watchWrote("deal.json"))
    }

    @Test func aCardsOldWatchButtonDecodesAndShowsNothing() throws {
        let saved = Data(#"{"label": "Open job", "watch": "63850AEF-35A5-55FF-B4C0-81B2263EB3DE"}"#.utf8)
        let action = try JSONDecoder().decode(CardInboxAction.self, from: saved)
        #expect(action.label == "Open job" && action.url == nil && action.ask == nil)
    }
}

/// Jobs folders, yours and your team's, in a temp folder.
private struct ChatPlace {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("job-chat-\(UUID())")
    var own: URL { root.appendingPathComponent("jobs") }
    var team: URL { root.appendingPathComponent("linked/jobs") }

    @MainActor func store() -> FolderJobStore {
        let team = self.team
        return FolderJobStore(directory: own, results: root.appendingPathComponent("job-results"), teamDirectory: { team })
    }

    func job(_ path: String, _ json: String, team: Bool = false) throws {
        let folder = (team ? self.team : own).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try json.write(to: folder.appendingPathComponent("job.json"), atomically: true, encoding: .utf8)
        try "def run():\n    return None\n".write(to: folder.appendingPathComponent("job.py"), atomically: true, encoding: .utf8)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
