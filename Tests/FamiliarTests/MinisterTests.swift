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
        /// What happens on the Mac while the model is thinking, given the prompt it was sent.
        var onPrompt: (@MainActor (String) -> Void)?
        /// The tools each turn was given, by name, the answering one first.
        var toolNames: [[String]] = []
        /// What the reading tools gave back: an answer with `_call` names one of them instead of the answering tool.
        var lookups: [(tool: String, text: String, isError: Bool)] = []

        func converse(system: String, tools: [[String: Any]], messages: inout [[String: Any]], executor: @escaping ToolExecutor,
                      onStatus: @escaping (String) -> Void) async throws -> ClaudeReply {
            systems.append(system)
            efforts.append(effort)
            toolNames.append(tools.compactMap { $0["name"] as? String })
            let prompt = ((messages.last?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
            prompts.append(prompt)
            await onPrompt?(prompt)
            guard callsTool, let name = tools.first?["name"] as? String else {
                return ClaudeReply(text: "I have nothing to say.", inputTokens: 1, outputTokens: 1, cacheRead: 0, toolCalls: 0)
            }
            var calls = 0
            while !answers.isEmpty, calls < maxToolRounds {
                var input = answers.removeFirst()
                calls += 1
                if let other = input.removeValue(forKey: "_call") as? String {
                    let result = await executor(other, input, nil)
                    lookups.append((other, result.content as? String ?? "", result.isError))
                    continue
                }
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
        var out: [String: Any] = ["headline": "Acme's order 4417", "text": text, "tone": tone, "notes": notes, "until": NSNull()]
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
        #expect(place.matters.stickers.map(\.title) == ["Stuck orders"] && place.matters.stickers.first?.byline == "Lena Park")
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

    // MARK: what moves, and what happens meanwhile

    @Test func aFindingMovingToAnotherMatterLeavesTheOneItWasInEvenWhenThatOneIsJudgedToo() async throws {
        let place = try Place(at: at)
        defer { place.remove() }
        var rows = [row(4417, "Acme Ltd", 3), row(4390, "Acme Ltd", 5)]
        place.rows = { rows }
        // Two findings under one new label make one matter, which shows if any of them should.
        place.client.answers = [
            triage([("4417", "new:acme", true, "Theirs, past the SLA."), ("4390", "new:acme", false, "Same customer; the other order tells the story.")]),
            compose("Acme has two orders waiting; 4417 is past the SLA."),
        ]
        try await place.run()
        let acme = try #require(place.matters.open.first)
        #expect(acme.findings.map(\.id) == ["4417", "4390"] && acme.why == nil && place.matters.current.count == 1)

        // 4390 turns out to be its own thing: it leaves Acme's matter, and both are written again (the new one first:
        // same age, lower finding).
        rows = [row(4417, "Acme Ltd", 4), row(4390, "Acme Ltd", 6)]
        place.client.answers = [
            triage([("4390", "new:beta", true, "The other warehouse's, as the row now says."), ("4417", acme.id, true, "Still past the SLA.")]),
            compose("Order 4390 waits on the other warehouse.", action: nil, on: "4390", page: nil),
            compose("Acme's order 4417: four days now."),
        ]
        try await place.run()
        let after = try #require(place.matters.matter(id: acme.id))
        let beta = try #require(place.matters.open.first { $0.id != acme.id })
        #expect(after.findings.map(\.id) == ["4417"] && after.view?.text == "Acme's order 4417: four days now." && !after.recompose)
        #expect(beta.findings.map(\.id) == ["4390"] && beta.view?.text == "Order 4390 waits on the other warehouse." && !beta.recompose)
        #expect(place.matters.matter(containing: FindingRef(job: Self.key, id: "4390"))?.id == beta.id && place.matters.stickers.count == 2)
        let left = place.memory.lines(on: at).first { $0["left"] != nil }
        #expect(left?["matter"] as? String == acme.id && left?["why"] as? String == "it belongs with \(beta.id)")
    }

    @Test func whatHappensWhileTheMinisterWritesWins() async throws {
        let place = try Place(at: at)
        defer { place.remove() }
        var rows = [row(4417, "Acme Ltd", 3), row(4390, "Beta", 5)]
        place.rows = { rows }
        place.client.answers = [triage([("4417", "new:acme", true, "Theirs."), ("4390", "new:acme", true, "Theirs too.")]), compose("Two orders wait.")]
        try await place.run()
        let id = try #require(place.matters.open.first?.id)

        // Put away while the sticker is written again (the minister asked for that): what was written is dropped, and
        // the matter stays put away.
        rows = [row(4417, "Acme Ltd", 4), row(4390, "Beta", 6)]
        place.client.answers = [triage([("4417", id, true, "A day more."), ("4390", id, true, "A day more.")], recompose: [id]), compose("Both a day older.")]
        place.client.onPrompt = { [matters = place.matters] prompt in if prompt.hasPrefix("Matter ") { matters.putAway(id) } }
        try await place.run()
        let putAway = try #require(place.matters.matter(id: id))
        #expect(putAway.state == .quiet && putAway.why == Matter.putAway && putAway.view?.text == "Two orders wait." && !putAway.recompose)
        #expect(place.memory.lines(on: at).contains { $0["overtaken"] != nil } && place.matters.stickers.isEmpty && place.minister.status.isEmpty)

        // A finding gone while the sticker is written: what was written is for a matter made of something else now, so
        // it is written again, at the next turn.
        rows = [row(4417, "Acme Ltd", 5), row(4390, "Beta", 7)]
        let gone = FindingRef(job: Self.key, id: "4390")
        place.client.answers = [triage([("4417", id, true, "Back."), ("4390", id, true, "Back.")]), compose("Both, again."), compose("Only 4417 now.")]
        place.client.onPrompt = { [matters = place.matters] prompt in if prompt.hasPrefix("Matter ") { matters.remove(gone) } }
        try await place.run()
        let between = try #require(place.matters.matter(id: id))
        #expect(between.state == .open && between.recompose && between.view?.text == "Two orders wait." && between.findings.map(\.id) == ["4417"])
        await place.minister.flush()
        let written = try #require(place.matters.matter(id: id))
        #expect(!written.recompose && written.view?.text == "Only 4417 now." && place.matters.stickers.map(\.text) == ["Only 4417 now."])
        #expect(place.client.prompts.count == 7 && place.client.answers.isEmpty)
    }

    @Test func aStickerThatCouldntBeWrittenIsWrittenAtTheNextTurnWithoutJudgingAgain() async throws {
        let place = try Place(at: at)
        defer { place.remove() }
        place.rows = { [self.row(4417, "Acme Ltd", 3)] }
        place.client.answers = [triage([("4417", "new:acme", true, "Theirs.")])]   // nothing for the sticker
        try await place.run()
        let open = try #require(place.matters.open.first)
        #expect(open.view == nil && open.recompose && place.minister.status == "The minister wrote no sticker for \(open.id).")
        #expect(place.memory.lines(on: at).filter { $0["verdict"] != nil }.count == 1 && place.client.prompts.count == 2)

        place.client.answers = [compose("Acme's order 4417 waits.")]
        await place.minister.flush()
        #expect(place.matters.open.first?.view?.text == "Acme's order 4417 waits." && place.minister.status.isEmpty)
        #expect(place.client.prompts.count == 3 && place.client.systems.last == MinisterPrompt.composeSystem)
        #expect(!place.memory.lines(on: at).contains { $0["verdict"] as? String == "unjudged" })
    }

    @Test func twoFlushesAtOnceTakeOneTurn() async throws {
        let place = try Place(at: at)
        defer { place.remove() }
        place.rows = { [self.row(4417, "Acme Ltd", 3)] }
        place.client.answers = [triage([("4417", "new:acme", true, "Theirs.")]), compose("Acme's order 4417 waits.")]
        place.runner.run(place.job.id)
        await place.runner.finish()
        let first = Task { await place.minister.flush() }
        let second = Task { await place.minister.flush() }
        await first.value
        await second.value
        #expect(place.client.prompts.count == 2 && place.matters.open.count == 1 && !place.minister.isRunning)
    }

    // MARK: the jobs' side

    @Test func aStickerLeavesWithItsJobOffEndedOrGoneAndComesBackJudgedAfresh() async throws {
        let place = try Place(at: at)
        defer { place.remove() }
        place.rows = { [self.row(4417, "Acme Ltd", 3)] }
        place.client.answers = [triage([("4417", "new:acme", true, "Theirs.")]), compose("Acme's order 4417 waits.")]
        try await place.run()
        let id = try #require(place.matters.open.first?.id)

        try place.store.setOn(place.job.id, false)
        place.minister.reconcile()
        #expect(place.matters.stickers.isEmpty && place.matters.matter(id: id)?.state == .closed)
        #expect(place.memory.lines(on: at).last?["closed"] as? String == "its job is off")

        // On again: its next run reports everything anew, and the minister judges it afresh.
        try place.store.setOn(place.job.id, true)
        place.client.answers = [triage([("4417", "new:acme", true, "Theirs, still.")]), compose("Acme's order 4417 still waits.")]
        try await place.run()
        #expect(place.matters.stickers.map(\.text) == ["Acme's order 4417 still waits."] && place.matters.current.count == 1 && place.matters.all.count == 2)

        // Its end came.
        let jobJSON = place.root.appendingPathComponent("linked/jobs/sales/stuck-orders/job.json")
        let json = try String(contentsOf: jobJSON, encoding: .utf8).replacingOccurrences(of: #""every_minutes": 60,"#, with: #""every_minutes": 60, "ends": "2026-09-20","#)
        try json.write(to: jobJSON, atomically: true, encoding: .utf8)
        _ = place.store.refresh()
        place.minister.reconcile()
        #expect(place.matters.stickers.isEmpty && place.matters.current.isEmpty && place.memory.lines(on: at).last?["closed"] as? String == "its job ended")

        // Gone: a matter (here a quiet one) of a job that is no longer there closes too.
        place.matters.save(Matter(id: "m-quiet", findings: [FindingRef(job: Self.key, id: "4417")], state: .quiet, jobName: "Stuck orders", byline: nil, createdAt: at, updatedAt: at))
        try FileManager.default.removeItem(at: place.root.appendingPathComponent("linked/jobs/sales/stuck-orders"))
        _ = place.store.refresh()
        place.minister.reconcile()
        #expect(place.matters.current.isEmpty && place.memory.lines(on: at).last?["closed"] as? String == "its job is gone")
    }

    @Test func aStickerWithAnUntilLeavesWhenItsTimeComes() async throws {
        let place = try Place(at: at)
        defer { place.remove() }
        var now = at
        place.minister.clock = { now }
        place.matters.clock = { now }
        place.rows = { [self.row(4417, "Acme Ltd", 3)] }
        var meeting = compose("Acme's order review is at 11.")
        meeting["until"] = "2026-09-21T11:00:00-04:00"
        place.client.answers = [triage([("4417", "new:acme", true, "A meeting of theirs.")]), meeting]
        try await place.run()
        let id = try #require(place.matters.open.first?.id)
        #expect(place.matters.stickers.count == 1 && MinisterPrompt.composeSystem.contains("always give its sticker an until"))
        now = at.addingTimeInterval(3_600)   // 11:13
        #expect(place.matters.stickers.isEmpty)   // the sticker leaves by itself
        place.minister.reconcile()
        let quiet = try #require(place.matters.matter(id: id))
        #expect(quiet.state == .quiet && quiet.why == Matter.timePassed && place.memory.lines(on: at).last?["quiet"] as? String == Matter.timePassed)
    }

    // MARK: the batch timer

    /// The timer takes the turn by itself, `batchSeconds` after a report, with no one calling `flush()`.
    @Test func theBatchTimerTakesTheTurnByItself() async throws {
        let place = try Place(at: at)
        defer { place.remove() }
        place.rows = { [self.row(4417, "Acme Ltd", 3)] }
        place.client.answers = [triage([("4417", "new:acme", true, "Theirs.")]), compose("Acme's order 4417 waits.")]
        place.minister.batchSeconds = 0.3
        place.runner.run(place.job.id)
        await place.runner.finish()
        #expect(place.client.prompts.isEmpty)   // the batch waits
        try await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(place.client.prompts.count == 2 && place.matters.open.first?.view?.text == "Acme's order 4417 waits.")
    }

    /// Issue #90: the jobs' tick, every 30 s, ends in `reconcile()`, which restarted the 60 s batch timer, so it never
    /// fired and no finding ever reached the minister. Here 0.6 s stands for the 60 and 0.3 s for the 30.
    @Test func theJobsTickDoesNotKeepTheBatchTimerFromFiring() async throws {
        let place = try Place(at: at)
        defer { place.remove() }
        place.rows = { [self.row(4417, "Acme Ltd", 3)] }
        place.client.answers = [triage([("4417", "new:acme", true, "Theirs.")]), compose("Acme's order 4417 waits.")]
        place.minister.batchSeconds = 0.6
        place.runner.run(place.job.id)
        await place.runner.finish()
        for _ in 0..<7 {
            try await Task.sleep(nanoseconds: 300_000_000)
            place.minister.reconcile()   // what each tick does
        }
        #expect(place.client.prompts.count == 2 && place.matters.open.count == 1)
    }

    /// A report restarts the timer, so a run of several jobs is one turn; the limit sees to it that findings which
    /// keep coming can't put the turn off for ever. Here 1.2 s stands for the two minutes.
    @Test func findingsThatKeepComingCannotPutTheTurnOffForEver() async throws {
        let place = try Place(at: at)
        defer { place.remove() }
        place.minister.clock = Date.init   // the limit is measured in real time here
        place.rows = { [self.row(4417, "Acme Ltd", 3)] }
        place.client.answers = [triage([("4417", "new:acme", true, "Theirs.")]), compose("Acme's order 4417 waits."),
                                triage([("4417", "new:acme-again", true, "Still theirs.")]), compose("Acme's order 4417 still waits.")]
        place.minister.batchSeconds = 0.6
        place.minister.batchLimitSeconds = 1.2
        place.runner.run(place.job.id)
        await place.runner.finish()
        var firstTurnAtTick: Int?
        for tick in 1...8 {   // every 0.3 s the row changes again, and the jobs tick
            try await Task.sleep(nanoseconds: 300_000_000)
            if firstTurnAtTick == nil, !place.client.prompts.isEmpty { firstTurnAtTick = tick }
            let row = FindingRow(id: "4417", values: row(4417, "Acme Ltd", 3 + tick), columns: ["order_id", "customer", "paid_on", "waiting_days"])
            place.minister.notice(place.job, change: FindingsChange(changed: [.init(row: row, columns: ["waiting_days"])]))
            place.minister.reconcile()
        }
        #expect(place.client.prompts.count >= 2 && place.client.prompts.first?.contains("team/sales/stuck-orders/4417") == true)
        #expect(firstTurnAtTick != nil && (firstTurnAtTick ?? 9) <= 5)   // by the limit at 1.2 s, with slack, not never
    }

    // MARK: what it reads with

    @Test func theMinisterMayLookThingsUpBeforeItAnswers() async throws {
        let place = try Place(at: at)
        defer { place.remove() }
        let root = place.root
        place.minister.recall = Recall.standard(home: root, tools: root.appendingPathComponent("tools"), team: { root.appendingPathComponent("linked") })
        // The log from an earlier day: the minister can find the finding's history before judging it.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("memory"), withIntermediateDirectories: true)
        try #"{"at":"2026-09-20T09:00:00-04:00","finding":"team/sales/stuck-orders/4417","matter":"m-old","verdict":"show","why":"Past the SLA."}"#
            .write(to: root.appendingPathComponent("memory/2026-09-20.jsonl"), atomically: true, encoding: .utf8)
        place.rows = { [self.row(4417, "Acme Ltd", 3)] }
        place.client.answers = [
            ["_call": "search", "pattern": "stuck-orders/4417", "path": "memory"],
            ["_call": "read", "path": "team/jobs/sales/stuck-orders/job.md"],
            triage([("4417", "new:acme", true, "Shown before, and still past the SLA.")]),
            ["_call": "rows", "path": "results/team/sales/stuck-orders/output/findings.csv", "where": ["customer": "acme"]],
            ["_call": "list", "path": "nowhere"],
            compose("Acme's order 4417 has waited 3 days, as it did in September."),
        ]
        try await place.run()
        #expect(place.client.toolNames == [["triage", "list", "read", "search", "rows"], ["compose", "list", "read", "search", "rows"]])
        #expect(place.client.lookups.map(\.tool) == ["search", "read", "rows", "list"] && place.client.lookups.map(\.isError) == [false, false, false, true])
        #expect(place.client.lookups[0].text.contains("memory/2026-09-20.jsonl:1: ") && place.client.lookups[0].text.contains(#""verdict":"show""#))
        #expect(place.client.lookups[1].text.hasPrefix("Each row is a paid order the warehouse hasn't packed."))
        #expect(place.client.lookups[2].text == "order_id,customer,paid_on,waiting_days\n4417,Acme Ltd,2026-10-30,3\n(1 of 1 matching rows; 1 in the file)")
        #expect(place.client.lookups[3].text.hasPrefix("No root called nowhere."))
        #expect(place.matters.stickers.map(\.text) == ["Acme's order 4417 has waited 3 days, as it did in September."] && place.client.answers.isEmpty)
        #expect(MinisterPrompt.triageSystem.contains("look things up") && MinisterPrompt.composeSystem.contains("look things up"))
    }

    // MARK: what the minister and the page are shown

    @Test func thePromptsHideSecretsInRowsTheirRolesAndWhatAButtonSaid() throws {
        var job = FolderJob(id: UUID(), source: .team, path: "sales/stuck-orders", name: "Stuck orders")
        job.map = FindingsMap(id: "order_id", about: ["customer"], at: "when", what: "note")
        let token = "ghp_abcdefghijklmnopqrstuvwxyz0123456789"
        let row = FindingRow(id: "4417", values: ["order_id": 4417, "customer": token, "note": "card 4111-1111-1111-1111 on file", "api_key": "plain", "when": "2026-09-21T11:00"],
                             columns: ["order_id", "customer", "note", "api_key", "when"])
        let shown = MinisterPrompt.Shown(ref: FindingRef(job: Self.key, id: "4417"), job: job, row: row, changed: nil, putAwayAt: nil)
        let prompt = MinisterPrompt.triage([shown], descriptions: [:], matters: [], now: at)
        #expect(!prompt.contains(token) && !prompt.contains("4111-1111") && !prompt.contains("plain"))
        #expect(prompt.contains("about: (hidden)") && prompt.contains("what: (hidden)") && prompt.contains("at: 2026-09-21T11:00 (an event)"))
        var matter = Matter(id: "m-1", findings: [shown.ref], state: .open, jobName: "Stuck orders", byline: nil, createdAt: at, updatedAt: at)
        matter.presses = [FindingPress(label: "Nudge", at: at, said: "sent with " + token, failed: false)]
        let compose = MinisterPrompt.compose(matter, findings: [shown], descriptions: [:], notes: nil, now: at)
        #expect(!compose.contains(token) && compose.contains("Pressed: Nudge · (hidden)"))
    }

    @Test func theMatterPageSaysWhenAStickerWasWrittenAndWhyAMatterIsntShown() {
        let later = at.addingTimeInterval(600)
        var matter = Matter(id: "m-1", findings: [], state: .open, view: MatterView(text: "Hi", tone: .urgent), jobName: "Stuck orders", byline: "Lena Park",
                            createdAt: at, updatedAt: later)
        #expect(MatterPage.byline(matter, now: later) == "Stuck orders · shared by Lena Park · " + JobWords.time(at, now: later))
        matter.writtenAt = at.addingTimeInterval(300)
        #expect(MatterPage.byline(matter, now: later).hasSuffix(JobWords.time(at.addingTimeInterval(300), now: later)))
        #expect(MatterPage.stateLine(matter) == "Urgent")
        matter.view?.tone = .calm
        #expect(MatterPage.stateLine(matter) == nil)
        matter.state = .quiet
        matter.why = Matter.putAway
        #expect(MatterPage.stateLine(matter) == "Kept quiet: You put it away.")
        matter.state = .closed
        #expect(MatterPage.stateLine(matter) == "Over: its findings are gone.")

        // In place of the sticker's words when there are none: a quiet matter has none by choice, not because it waits.
        #expect(MatterPage.noSticker(matter) == "This is over.")
        matter.state = .quiet
        #expect(MatterPage.noSticker(matter) == "Not on a sticker.")
        matter.state = .open
        #expect(MatterPage.noSticker(matter) == "The minister hasn't written this one up yet.")
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
        #expect(composeRefusal(compose("Ok", tone: "loud")) == "tone must be calm, urgent or good.")
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

        #expect(matters.stickers.map(\.id) == ["m-urgent", "m-newest", "m-calm-new", "m-calm-old"])   // every card is on the deck, one at a time
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
