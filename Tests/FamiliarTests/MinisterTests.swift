import Foundation
import Testing
import FamiliarContracts
@testable import Familiar

/// The minister: the jobs' findings become matters and stickers in two turns, triage and compose, with code checking
/// every answer and keeping every state. A stand-in model answers as scripted.
@Suite @MainActor
struct MinisterTests {
    /// 2026-09-21, 10:13 AM in New York.
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    /// A model that calls the one tool it is given with the next scripted answer; a refusal makes it try the next.
    final class StandIn: ConversationClient {
        var effort = "medium"
        var maxTokens = 1_024
        var maxToolRounds = 8
        var shouldStop: () -> Bool = { false }
        var answers: [[String: Any]] = []
        var prompts: [String] = []
        var systems: [String] = []
        var efforts: [String] = []
        var callsTool = true

        func converse(system: String, tools: [[String: Any]], messages: inout [[String: Any]], executor: @escaping ToolExecutor,
                      onStatus: @escaping (String) -> Void) async throws -> ClaudeReply {
            systems.append(system)
            efforts.append(effort)
            prompts.append(((messages.last?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? "")
            guard callsTool, let name = tools.first?["name"] as? String else {
                return ClaudeReply(text: "I have nothing to say.", inputTokens: 1, outputTokens: 1, cacheRead: 0, toolCalls: 0)
            }
            var calls = 0
            while !answers.isEmpty, calls < maxToolRounds {
                let input = answers.removeFirst()
                calls += 1
                if !(await executor(name, input, nil)).isError { break }
            }
            return ClaudeReply(text: "", inputTokens: 1, outputTokens: 1, cacheRead: 0, toolCalls: calls)
        }
    }

    private static let key = "team/sales/stuck-orders"
    private static let page = "https://orders.example.com/"

    private func row(_ id: Int, _ customer: String, _ days: Int) -> [String: Any] {
        ["order_id": id, "customer": customer, "paid_on": "2026-10-30", "waiting_days": days]
    }

    private func triage(_ verdicts: [(String, String, Bool, String)], recompose: [String] = []) -> [String: Any] {
        ["verdicts": verdicts.map { ["finding": Self.key + "/" + $0.0, "matter": $0.1, "show": $0.2, "why": $0.3] }, "recompose": recompose]
    }

    private func compose(_ text: String, action: String? = "nudge", on id: String = "4417", page: String? = Self.page + "4417",
                         tone: String = "calm", notes: String = "## Acme order 4417\n- stuck 3 days") -> [String: Any] {
        var out: [String: Any] = ["text": text, "tone": tone, "notes": notes, "until": NSNull()]
        out["action"] = action.map { ["finding": Self.key + "/" + id, "run": $0] } ?? NSNull()
        out["where"] = page ?? NSNull()
        return out
    }

    // MARK: the two turns

    @Test func findingsBecomeMattersAndStickersInTwoTurns() async throws {
        let place = try Place(at: at)
        defer { place.remove() }
        var rows = [row(4417, "Acme Ltd", 3), row(4390, "Beta-TEST", 5)]
        place.rows = { rows }
        place.client.answers = [
            triage([("4417", "new:acme", true, "Past the 48h SLA and it's theirs."), ("4390", "new:test", false, "Test account, per job.md.")]),
            compose("Acme's order 4417 has sat unpacked for 3 days, a day past the SLA."),
        ]
        var urgent: [Matter] = []
        place.minister.onUrgent = { urgent.append($0) }

        try await place.run()

        let open = try #require(place.matters.open.first)
        let view = try #require(open.view)
        #expect(view.text == "Acme's order 4417 has sat unpacked for 3 days, a day past the SLA." && view.tone == .calm && view.until == nil)
        #expect(view.action?.label == "Nudge the warehouse" && view.action?.run == "nudge" && view.action?.finding.key == Self.key + "/4417")
        #expect(view.page == Self.page + "4417" && open.jobName == "Stuck orders" && open.byline == "Lena Park" && !open.recompose)
        #expect(place.matters.notes(for: open.id) == "## Acme order 4417\n- stuck 3 days")
        let quiet = try #require(place.matters.current.first { $0.state == .quiet })
        #expect(quiet.why == "Test account, per job.md." && quiet.view == nil && quiet.findings.map(\.key) == [Self.key + "/4390"])
        #expect(place.matters.stickers.map(\.title) == ["Stuck orders"] && place.matters.stickers.first?.byline == "Lena Park" && place.matters.more == 0)
        #expect(urgent.isEmpty && place.minister.status.isEmpty)

        // What the minister read: the job described, each finding with its roles and its row, and the matters so far.
        let first = try #require(place.client.prompts.first)
        #expect(first.contains("Job: Stuck orders (team/sales/stuck-orders) · shared by Lena Park"))
        #expect(first.contains("Description:\nEach row is a paid order the warehouse hasn't packed."))
        #expect(first.contains("- NEW team/sales/stuck-orders/4417 · about: Acme Ltd · page: https://orders.example.com/4417 · since: 2026-10-30"))
        #expect(first.contains(#""customer":"Acme Ltd""#) && first.contains("Matters now:\n(none)") && first.hasSuffix("Give a verdict for each of the 2 findings above."))
        let second = try #require(place.client.prompts.last)
        #expect(second.contains("Matter \(open.id).") && second.contains("- team/sales/stuck-orders/4417 · nudge · Nudge the warehouse (asks first)"))
        #expect(second.contains("Pages: https://orders.example.com/4417") && second.hasSuffix("Write the sticker and the notes."))
        #expect(place.client.systems == [MinisterPrompt.triageSystem, MinisterPrompt.composeSystem] && place.client.efforts.first == "low")

        // Every verdict and the sticker are in the log, with the reasons.
        let lines = place.memory.lines(on: at)
        #expect(lines.filter { $0["verdict"] as? String == "show" }.count == 1 && lines.filter { $0["verdict"] as? String == "quiet" }.first?["why"] as? String == "Test account, per job.md.")
        #expect(lines.last?["sticker"] as? String == view.text && lines.last?["findings"] as? [String] == [Self.key + "/4417"])

        // Put away: quiet until something changes and the minister says so; a changed row goes back to it, marked.
        place.matters.putAway(open.id)
        #expect(place.matters.stickers.isEmpty && place.matters.matter(id: open.id)?.why == Matter.putAway)
        rows = [row(4417, "Acme Ltd", 4), row(4390, "Beta-TEST", 6)]
        // Both matters are written again, the one with the lower finding first (they are the same age).
        place.client.answers = [
            triage([("4417", open.id, true, "Another day gone by, and they put it away before the SLA passed."), ("4390", quiet.id, true, "Still a test account, but the minister was asked to show it.")]),
            compose("Beta-TEST's order 4390 has waited 6 days.", action: nil, on: "4390", page: nil, tone: "urgent", notes: "test"),
            compose("Acme's order 4417: four days now.", tone: "calm"),
        ]
        try await place.run()
        #expect(place.client.prompts[2].contains("put away by the person"))
        let shown = place.matters.stickers
        #expect(shown.map(\.text) == ["Beta-TEST's order 4390 has waited 6 days.", "Acme's order 4417: four days now."])   // urgent first
        #expect(shown[0].urgent && !shown[1].urgent && place.matters.matter(id: open.id)?.putAwayAt == nil)
        #expect(urgent.map(\.id) == [quiet.id] && place.matters.matter(id: quiet.id)?.notified == true)

        // Gone findings close their matters in code, with no turn.
        rows = []
        place.client.answers = []
        try await place.run()
        #expect(place.matters.stickers.isEmpty && place.matters.current.isEmpty && place.matters.all.allSatisfy { $0.state == .closed })
        #expect(place.memory.lines(on: at).filter { $0["closed"] != nil }.count == 2 && place.client.prompts.count == 5)
    }

    @Test func aTurnThatFailsIsTriedOnceMoreThenItsFindingsAreLoggedAsUnjudged() async throws {
        let place = try Place(at: at)
        defer { place.remove() }
        place.rows = { [self.row(4417, "Acme Ltd", 3)] }
        place.client.callsTool = false

        try await place.run()
        #expect(place.minister.status == "The minister gave no verdicts." && place.matters.all.isEmpty)
        await place.minister.flush()   // the retry
        let unjudged = place.memory.lines(on: at).filter { $0["verdict"] as? String == "unjudged" }
        #expect(unjudged.count == 1 && (unjudged.first?["why"] as? String)?.hasPrefix("The minister couldn't judge it") == true)
        await place.minister.flush()   // nothing left
        #expect(place.client.prompts.count == 2)

        // Without a model connected, the findings wait for one.
        place.makeClient = { _ in nil }
        place.client.callsTool = true
        place.rows = { [self.row(4402, "Cora", 1)] }
        try await place.run()
        #expect(place.minister.status.hasPrefix("Add your API key") || place.minister.status.hasPrefix("Claude Code") || !place.minister.status.isEmpty)
        #expect(place.matters.all.isEmpty && place.client.prompts.count == 2)
    }

    // MARK: the checks on what the minister answers

    @Test func theTriageAndComposeAnswersAreCheckedInPlainWords() throws {
        let refs = [FindingRef(job: Self.key, id: "4417"), FindingRef(job: Self.key, id: "4390")]
        func triageRefusal(_ input: [String: Any]) -> String? {
            do { _ = try MinisterPrompt.parseTriage(input, findings: refs, matters: ["m-1"]); return nil } catch { return (error as? MinisterError)?.message }
        }
        let good = triage([("4417", "m-1", true, "Why."), ("4390", "new:x", false, "Why not.")])
        let parsed = try MinisterPrompt.parseTriage(good, findings: refs, matters: ["m-1"])
        #expect(parsed.verdicts.map(\.matter) == ["m-1", "new:x"] && parsed.verdicts[1].isNew && parsed.recompose.isEmpty)
        #expect(triageRefusal(["verdicts": "none"]) == "Give verdicts: a list, one per finding.")
        #expect(triageRefusal(triage([("4417", "m-1", true, "Why.")]))?.hasPrefix("No verdict for: team/sales/stuck-orders/4390") == true)
        #expect(triageRefusal(triage([("4417", "m-1", true, "Why."), ("4390", "m-1", true, "Why."), ("9999", "m-1", true, "Why.")]))?.hasPrefix("A verdict names a finding that isn't in this turn") == true)
        #expect(triageRefusal(triage([("4417", "m-1", true, "Why."), ("4417", "m-1", true, "Again."), ("4390", "m-1", true, "Why.")])) == "Two verdicts for team/sales/stuck-orders/4417. Give one.")
        #expect(triageRefusal(triage([("4417", "m-9", true, "Why."), ("4390", "m-1", true, "Why.")]))?.contains("m-9 isn't a matter that exists") == true)
        #expect(triageRefusal(triage([("4417", "new:", true, "Why."), ("4390", "m-1", true, "Why.")]))?.contains("isn't a matter that exists") == true)
        #expect(triageRefusal(triage([("4417", "m-1", true, ""), ("4390", "m-1", true, "Why.")])) == "team/sales/stuck-orders/4417: say why, in one sentence.")
        var noShow = triage([("4417", "m-1", true, "Why."), ("4390", "m-1", true, "Why.")])
        var verdicts = noShow["verdicts"] as! [[String: Any]]
        verdicts[0]["show"] = "yes"
        noShow["verdicts"] = verdicts
        #expect(triageRefusal(noShow) == "team/sales/stuck-orders/4417: say show true or false.")
        #expect(try MinisterPrompt.parseTriage(triage([("4417", "m-1", true, "Why."), ("4390", "m-1", true, "Why.")], recompose: ["m-1", "m-7"]),
                                               findings: refs, matters: ["m-1"]).recompose == ["m-1"])

        var job = FolderJob(id: UUID(), source: .team, path: "sales/stuck-orders", name: "Stuck orders")
        job.map = FindingsMap(id: "order_id", page: Self.page + "{order_id}")
        job.actions = [FolderJobAction(label: "Nudge the warehouse", run: "nudge", args: ["order": "{order_id}"], confirm: true)]
        let shown = [MinisterPrompt.Shown(ref: refs[0], job: job, row: FindingRow(id: "4417", values: ["order_id": 4417], columns: ["order_id"]), changed: nil, putAwayAt: nil)]
        func composeRefusal(_ input: [String: Any]) -> String? {
            do { _ = try MinisterPrompt.parseCompose(input, findings: shown); return nil } catch { return (error as? MinisterError)?.message }
        }
        let view = try MinisterPrompt.parseCompose(compose("Acme's order 4417\nhas waited.", notes: "  notes  "), findings: shown)
        #expect(view.view.text == "Acme's order 4417 has waited." && view.view.action?.label == "Nudge the warehouse" && view.view.page == Self.page + "4417" && view.notes == "notes")
        #expect(try MinisterPrompt.parseCompose(compose("Fine.", action: nil, page: nil, notes: ""), findings: shown).notes == nil)
        #expect(composeRefusal(compose("")) == "The sticker's text is empty.")
        #expect(composeRefusal(compose(String(repeating: "x", count: 241)))?.hasPrefix("The sticker's text is 241 characters") == true)
        #expect(composeRefusal(compose("Ok", action: "delete_all"))?.contains("has no action delete_all") == true)
        #expect(composeRefusal(compose("Ok", on: "4390"))?.contains("names a finding this matter doesn't have") == true)
        #expect(composeRefusal(compose("Ok", page: "https://elsewhere.example/")) == "where must be one of the pages listed, or null.")
        #expect(composeRefusal(compose("Ok", tone: "loud")) == "tone must be calm or urgent.")
        var until = compose("Ok")
        until["until"] = "soon"
        #expect(composeRefusal(until)?.hasPrefix("until must be a date and time") == true)
        until["until"] = "2026-11-27T18:00:00-05:00"
        #expect(try MinisterPrompt.parseCompose(until, findings: shown).view.until == JobMoment.parse("2026-11-27T18:00:00-05:00")?.date)
        #expect(composeRefusal(compose("Ok", notes: String(repeating: "n", count: 6_001)))?.hasPrefix("The notes are 6,001 characters") == true)
    }

    // MARK: matters on disk

    @Test func mattersAreKeptOnDiskWithTheirNotesAndTheStickersComeUrgentFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("matters-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let matters = Matters(directory: root)
        var now = at
        matters.clock = { now }
        func matter(_ id: String, _ job: String, state: Matter.State = .open, text: String? = "Text", tone: MatterView.Tone = .calm) -> Matter {
            Matter(id: id, findings: [FindingRef(job: job, id: "1")], state: state, view: text.map { MatterView(text: $0, tone: tone) },
                   jobName: id, byline: nil, createdAt: now, updatedAt: now)
        }
        matters.save(matter("m-calm-old", "team/a"), notes: "## Old")
        now = at.addingTimeInterval(60)
        matters.save(matter("m-urgent", "team/b", tone: .urgent))
        now = at.addingTimeInterval(120)
        matters.save(matter("m-calm-new", "team/c"))
        now = at.addingTimeInterval(180)
        matters.save(matter("m-quiet", "team/d", state: .quiet, text: nil))
        now = at.addingTimeInterval(240)
        matters.save(matter("m-newest", "team/e"))

        #expect(matters.stickers.map(\.id) == ["m-urgent", "m-newest", "m-calm-new", "m-calm-old"] && matters.shown.count == 3 && matters.more == 1)
        #expect(matters.notes(for: "m-calm-old") == "## Old" && matters.notes(for: "m-urgent") == nil)
        #expect(matters.matter(containing: FindingRef(job: "team/d", id: "1"))?.id == "m-quiet")
        #expect(Matters(directory: root).all == matters.all)   // read back as written

        // A finding leaving: the matter closes with none left, or waits to be written again.
        let left = matters.remove(FindingRef(job: "team/e", id: "1"))
        #expect(left?.state == .closed && left?.view == nil && matters.stickers.count == 3 && matters.matter(containing: FindingRef(job: "team/e", id: "1")) == nil)
        now = at.addingTimeInterval(300)
        var two = matter("m-two", "team/f")
        two.findings.append(FindingRef(job: "team/g", id: "2"))
        matters.save(two)
        #expect(matters.remove(FindingRef(job: "team/g", id: "2"))?.recompose == true && matters.matter(id: "m-two")?.state == .open)

        // Put away takes the sticker down; presses stay on the matter, the last five.
        matters.putAway("m-urgent")
        #expect(matters.matter(id: "m-urgent")?.state == .quiet && matters.matter(id: "m-urgent")?.why == Matter.putAway)
        #expect(matters.stickers.map(\.id) == ["m-two", "m-calm-new", "m-calm-old"])   // m-newest closed above
        matters.putAway("m-quiet")   // already quiet: nothing changes
        #expect(matters.matter(id: "m-quiet")?.putAwayAt == nil)
        for index in 1...6 { matters.record(FindingPress(label: "Press \(index)", at: now, said: "ok", failed: false), on: FindingRef(job: "team/c", id: "1")) }
        #expect(matters.matter(id: "m-calm-new")?.presses.map(\.label) == ["Press 2", "Press 3", "Press 4", "Press 5", "Press 6"])
        #expect(try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("m-urgent/matter.json").path)[.posixPermissions] as? Int == 0o600)
    }

    // MARK: fixture

    /// A team job that reports stuck orders, run by a runner whose job.py is a closure, with the minister listening and
    /// a stand-in model answering.
    @MainActor
    final class Place {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("minister-\(UUID())")
        let store: FolderJobStore
        let runner: FolderJobRunner
        let memory: MemoryLog
        let matters: Matters
        let minister: Minister
        let client = StandIn()
        /// What the next run reports, and which model answers; held apart so the closures made in `init` can hold them.
        final class Knobs {
            var rows: () -> [[String: Any]] = { [] }
            var makeClient: ((Config) -> (any ConversationClient)?)?
        }
        let knobs = Knobs()
        var rows: () -> [[String: Any]] { get { knobs.rows } set { knobs.rows = newValue } }
        var makeClient: ((Config) -> (any ConversationClient)?)? { get { knobs.makeClient } set { knobs.makeClient = newValue } }
        let job: FolderJob

        init(at: Date) throws {
            let team = root.appendingPathComponent("linked/jobs/sales/stuck-orders")
            try FileManager.default.createDirectory(at: team, withIntermediateDirectories: true)
            try #"""
            {"name": "Stuck orders", "about": "Paid orders the warehouse hasn't packed.", "every_minutes": 60, "contributor": "Lena Park",
             "map": {"id": "order_id", "about": ["customer"], "where": "https://orders.example.com/{order_id}", "since": "paid_on"},
             "actions": [{"label": "Nudge the warehouse", "run": "nudge", "args": {"order": "{order_id}"}, "confirm": true}]}
            """#.write(to: team.appendingPathComponent("job.json"), atomically: true, encoding: .utf8)
            try "def run():\n    return None\n".write(to: team.appendingPathComponent("job.py"), atomically: true, encoding: .utf8)
            try "Each row is a paid order the warehouse hasn't packed. `waiting_days` counts from payment; our SLA is 48 hours.\nCustomers ending in -TEST are test accounts.\n"
                .write(to: team.appendingPathComponent("job.md"), atomically: true, encoding: .utf8)
            let teamRoot = root.appendingPathComponent("linked/jobs")
            store = FolderJobStore(directory: root.appendingPathComponent("jobs"), results: root.appendingPathComponent("job-results"), teamDirectory: { teamRoot })
            job = store.jobs[0]
            try store.setOn(job.id, true)
            memory = MemoryLog(directory: root.appendingPathComponent("memory"))
            memory.clock = { at }
            matters = Matters(directory: root.appendingPathComponent("matters"))
            matters.clock = { at }
            let knobs = self.knobs, client = self.client
            let runner = FolderJobRunner(store: store, execute: { _ in
                ["source": "Orders API", "read": 2113, "findings": knobs.rows(), "_columns": ["order_id", "customer", "paid_on", "waiting_days"]] as [String: Any]
            }, now: { at })
            runner.memory = memory
            let minister = Minister(matters: matters, memory: memory, store: store, config: { Config() },
                                    makeClient: { config in knobs.makeClient.map { $0(config) } ?? client })
            minister.batchSeconds = nil   // the tests take the turns
            minister.clock = { at }
            runner.onFindings = { [weak minister] job, change in minister?.notice(job, change: change) }
            self.runner = runner
            self.minister = minister
        }

        /// One run of the job, and the minister's turn on what it reported.
        func run() async throws {
            runner.run(job.id)
            await runner.finish()
            await minister.flush()
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
