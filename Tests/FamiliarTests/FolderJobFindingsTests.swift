import Foundation
import Testing
@testable import Familiar

/// A job reports its findings as rows of its own columns, and job.json's map says which column is which. Noteling keeps
/// them as a table in the job's output, tells new, changed and gone apart by the id, and writes each run and each change
/// to the memory log, by day, with secrets hidden.
@Suite @MainActor
struct FolderJobFindingsTests {
    /// 2026-09-21, 10:13 AM in New York.
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: the map and the actions

    @Test func theMapSaysWhichColumnIsWhichAndTheActionsAreFunctionsOfJobPy() throws {
        func parse(_ text: String) throws -> FolderJob { try FolderJobFiles.parse(Data(text.utf8), path: "stuck-orders", source: .team) }
        let job = try parse(#"""
        {"name": "Stuck orders",
         "map": {"id": "order_id", "about": ["customer", "owner"], "where": "https://orders.example.com/{order_id}", "since": "paid_on"},
         "actions": [{"label": "Nudge the warehouse", "run": "nudge", "args": {"order": "{order_id}", "note": "from Noteling"}, "confirm": true}]}
        """#)
        let map = try #require(job.map)
        #expect(map.id == "order_id" && map.about == ["customer", "owner"] && map.page == "https://orders.example.com/{order_id}" && map.since == "paid_on")
        #expect(!map.isEvents && map.due == nil && map.what == nil && map.files == nil)
        let action = try #require(job.actions.first)
        #expect(action.label == "Nudge the warehouse" && action.run == "nudge" && action.confirm)
        let row = FindingRow(id: "4417", values: ["order_id": 4417, "customer": "Acme Ltd", "owner": "Lena Park", "paid_on": "2026-10-30"],
                             columns: ["order_id", "customer", "owner", "paid_on"])
        #expect(map.place(of: row) == "https://orders.example.com/4417")
        #expect(map.about(of: row) == ["Acme Ltd", "Lena Park"])
        let arguments = action.arguments(for: row)
        #expect(arguments["order"] as? String == "4417" && arguments["note"] as? String == "from Noteling")
        #expect(FolderJobFindings.fill("{customer} / {missing}", row: row) == nil)
        #expect(try parse(#"{"map": {"id": "page", "at": "finished_at"}}"#).map?.isEvents == true)
        #expect(try parse(#"{"map": {"id": "page", "where": "page"}}"#).map?.place(of: FindingRow(id: "x", values: ["page": "https://a.example/"], columns: ["page"])) == "https://a.example/")
        let bare = try parse("{}")
        #expect(bare.map == nil && bare.actions.isEmpty)

        func refusal(_ text: String) -> String? {
            do { _ = try parse(text); return nil } catch { return (error as? FolderJobError)?.message }
        }
        #expect(refusal(#"{"map": "order_id"}"#)?.hasPrefix("In its job.json, map must be an object") == true)
        #expect(refusal(#"{"map": {"about": ["customer"]}}"#)?.hasPrefix("In its job.json, map needs id") == true)
        #expect(refusal(#"{"map": {"id": "order_id", "about": "customer"}}"#) == "In its job.json, map's about must be a list of column names in quotes.")
        #expect(refusal(#"{"map": {"id": "order_id", "since": 3}}"#) == "In its job.json, map's since must be a column name in quotes.")
        #expect(refusal(#"{"actions": {"label": "x"}}"#)?.hasPrefix("In its job.json, actions must be a list") == true)
        #expect(refusal(#"{"actions": [{"label": "Nudge"}]}"#)?.hasPrefix("In its job.json, an action's run must name a function") == true)
        #expect(refusal(#"{"actions": [{"label": "Nudge", "run": "run"}]}"#)?.hasPrefix("In its job.json, an action's run must name") == true)
        #expect(refusal(#"{"actions": [{"label": "Nudge", "run": "_hidden"}]}"#)?.hasPrefix("In its job.json, an action's run must name") == true)
        #expect(refusal(#"{"actions": [{"run": "nudge"}]}"#)?.hasPrefix("In its job.json, an action needs a label") == true)
        #expect(refusal(#"{"actions": [{"label": "Nudge", "run": "nudge", "args": [1]}]}"#)?.hasPrefix("In its job.json, an action's args must be one JSON object") == true)
        #expect(refusal(#"{"actions": [{"label": "Nudge", "run": "nudge", "confirm": "yes"}]}"#) == "In its job.json, an action's confirm must be true or false.")
        let seven = (1...7).map { #"{"label": "B\#($0)", "run": "f\#($0)"}"# }.joined(separator: ",")
        #expect(refusal(#"{"actions": [\#(seven)]}"#)?.hasPrefix("In its job.json, up to 6 actions") == true)
    }

    // MARK: what run() returned

    @Test func whatRunReturnedIsWordsOrAReportOfFindings() throws {
        let map = FindingsMap(id: "order_id")
        #expect(try FindingsOutcome.parse("2 of 8 wrong", map: map) == FindingsOutcome(said: "2 of 8 wrong"))
        #expect(try FindingsOutcome.parse(NSNull(), map: map) == FindingsOutcome())
        let report: [String: Any] = [
            "source": "Orders API", "read": 2113, "said": "3 stuck",
            "findings": [["order_id": 4417, "customer": "Acme Ltd", "waiting_days": 3],
                         ["order_id": "4390", "customer": "Beta Corp", "waiting_days": 5, "paid": true],
                         ["customer": "No id"],
                         ["order_id": 4417, "customer": "Acme Ltd (again)", "waiting_days": 4]],
            "_columns": ["order_id", "customer", "waiting_days", "paid"],
        ]
        let outcome = try FindingsOutcome.parse(report, map: map)
        #expect(outcome.source == "Orders API" && outcome.read == 2113 && outcome.said == "3 stuck")
        #expect(outcome.columns == ["order_id", "customer", "waiting_days", "paid"])
        let rows = try #require(outcome.rows)
        #expect(rows.map(\.id) == ["4417", "4390"])   // the later 4417 took the first one's place
        #expect(rows[0].text("customer") == "Acme Ltd (again)" && rows[0].text("waiting_days") == "4" && rows[1].text("paid") == "true")
        #expect(outcome.notes == ["1 finding had no order_id, so it was left out.", "1 finding repeated an earlier order_id; the last one counts."])

        // A report without findings says nothing about the rows: nil, not none.
        #expect(try FindingsOutcome.parse(["source": "Orders API", "read": 0], map: map).rows == nil)
        #expect(try FindingsOutcome.parse(["findings": []], map: map).rows?.isEmpty == true)
        #expect(try FindingsOutcome.parse(["findings": []], map: map).columns == ["order_id"])

        func refusal(_ value: Any, map: FindingsMap? = FindingsMap(id: "order_id")) -> String? {
            do { _ = try FindingsOutcome.parse(value, map: map); return nil } catch { return (error as? FolderJobError)?.message }
        }
        #expect(refusal(["findings": [["order_id": 1]]], map: nil)?.hasPrefix("job.py returned findings, but its job.json has no map") == true)
        #expect(refusal(["findings": "none"]) == "job.py's findings must be a list of rows, each a JSON object.")
        #expect(refusal(["findings": [1, 2]]) == "job.py's findings must be a list of rows, each a JSON object.")
        #expect(refusal(["read": "many"]) == "job.py's read must be how many it read: a whole number, 0 or more.")
        #expect(refusal(["source": 3]) == "job.py's source must be the name of what it read, in quotes.")

        // Limits: the first 500 rows, and values cut at 4,000 characters.
        let many: [String: Any] = ["findings": (1...600).map { ["order_id": $0, "note": String(repeating: "x", count: 5_000)] }]
        let clipped = try FindingsOutcome.parse(many, map: map)
        #expect(clipped.rows?.count == 500 && clipped.rows?.first?.text("note")?.count == 4_001)
        #expect(clipped.notes == ["Kept the first 500 of 600 findings.", "A value longer than 4,000 characters was cut."])
    }

    // MARK: new, changed and gone

    @Test func theDiffTellsNewChangedAndGoneApartByTheId() throws {
        let map = FindingsMap(id: "order_id")
        func row(_ id: Int, _ days: Int) -> FindingRow {
            FindingRow(id: "\(id)", values: ["order_id": id, "customer": "Acme Ltd", "waiting_days": days], columns: ["order_id", "customer", "waiting_days"])
        }
        let first = FolderJobFindings.diff(previous: FindingsSnapshot(), rows: [row(4417, 3), row(4390, 4)], map: map, at: at)
        #expect(first.change.new.map(\.id) == ["4417", "4390"] && first.change.changed.isEmpty && first.change.gone.isEmpty)
        #expect(first.snapshot.rows["4417"]?.firstSeen == at && first.snapshot.rows["4417"]?.changedAt == nil)

        let later = at.addingTimeInterval(3_600)
        let second = FolderJobFindings.diff(previous: first.snapshot, rows: [row(4390, 5), row(4402, 1)], map: map, at: later)
        #expect(second.change.new.map(\.id) == ["4402"])
        #expect(second.change.changed.map(\.row.id) == ["4390"] && second.change.changed.first?.columns == ["waiting_days"])
        #expect(second.change.gone == ["4417"] && second.change.unchanged == 0)
        #expect(second.snapshot.rows["4390"]?.firstSeen == at && second.snapshot.rows["4390"]?.changedAt == later && second.snapshot.rows["4417"] == nil)

        let third = FolderJobFindings.diff(previous: second.snapshot, rows: [row(4390, 5), row(4402, 1)], map: map, at: later.addingTimeInterval(3_600))
        #expect(third.change.isEmpty && third.change.unchanged == 2 && third.snapshot == second.snapshot)

        // The snapshot survives a relaunch as it is.
        let place = FileManager.default.temporaryDirectory.appendingPathComponent("findings-\(UUID())")
        defer { try? FileManager.default.removeItem(at: place) }
        let file = place.appendingPathComponent("job-results/own/x/findings.json")
        try second.snapshot.write(to: file)
        #expect(FindingsSnapshot.read(file) == second.snapshot)
        #expect(FindingsSnapshot.read(place.appendingPathComponent("none.json")) == FindingsSnapshot())

        // Events are only ever new.
        let events = FindingsMap(id: "order_id", at: "finished_at")
        let e1 = FolderJobFindings.diff(previous: FindingsSnapshot(), rows: [row(1, 0), row(2, 0)], map: events, at: at)
        let e2 = FolderJobFindings.diff(previous: e1.snapshot, rows: [row(2, 9), row(3, 0)], map: events, at: later)
        #expect(e1.change.new.count == 2 && e2.change.new.map(\.id) == ["3"] && e2.change.gone.isEmpty && e2.change.changed.isEmpty)
        #expect(e2.snapshot.events == ["1", "2", "3"] && e2.snapshot.rows.isEmpty && e2.change.unchanged == 1)
    }

    // MARK: the table

    @Test func theFindingsAreATableWithTheJobsColumns() {
        let rows = [FindingRow(id: "4417", values: ["order_id": 4417, "customer": "Acme, Ltd", "note": "said \"soon\"\nmaybe", "paid": true, "owner": NSNull()],
                               columns: ["order_id", "customer", "note", "paid", "owner"])]
        let csv = FolderJobFindings.csv(rows, columns: ["order_id", "customer", "note", "paid", "owner", "missing"])
        #expect(csv == "order_id,customer,note,paid,owner,missing\n4417,\"Acme, Ltd\",\"said \"\"soon\"\"\nmaybe\",true,,\n")
        #expect(FolderJobFindings.csv([], columns: ["order_id"]) == "order_id\n")
        let (parsed, total) = FolderJobPreview.table(csv, separator: ",", limit: 200)
        #expect(parsed == [["order_id", "customer", "note", "paid", "owner", "missing"], ["4417", "Acme, Ltd", "said \"soon\"\nmaybe", "true", "", ""]] && total == 1)
        #expect(FolderJobFindings.text(["b": 1, "a": [1, 2]]) == #"{"a":[1,2],"b":1}"#)
    }

    // MARK: the memory log

    @Test func theLogWritesEachRunAndEachChangeByDayWithSecretsHidden() throws {
        let place = FileManager.default.temporaryDirectory.appendingPathComponent("memory-\(UUID())")
        defer { try? FileManager.default.removeItem(at: place) }
        let memory = MemoryLog(directory: place)
        memory.timeZone = TimeZone(identifier: "America/New_York")!
        var now = at
        memory.clock = { now }
        let job = FolderJob(id: UUID(), source: .team, path: "sales/stuck-orders", name: "Stuck orders")
        let row = FindingRow(id: "4417", values: ["order_id": 4417, "customer": "Acme Ltd", "api_key": "abc", "note": "card 4111111111111111", "tags": ["a", "b"]],
                             columns: ["order_id", "customer", "api_key", "note", "tags"])
        memory.ran(job, outcome: FindingsOutcome(said: "3 stuck", source: "Orders API", read: 2113, rows: [row]))
        memory.record(job, change: FindingsChange(new: [row], changed: [.init(row: row, columns: ["note"])], gone: ["4402"]))
        now = at.addingTimeInterval(86_400)
        memory.append(["job": "own/x", "gone": "1"])

        let lines = memory.lines(on: at)
        #expect(lines.count == 4 && memory.lines(on: now).count == 1 && memory.lines(on: at.addingTimeInterval(-86_400)).isEmpty)
        #expect(lines[0]["t"] as? String == "2026-09-21T10:13:20-04:00" && lines[0]["job"] as? String == "team/sales/stuck-orders" && lines[0]["name"] as? String == "Stuck orders")
        let ran = try #require(lines[0]["ran"] as? [String: Any])
        #expect(ran["source"] as? String == "Orders API" && ran["read"] as? Int == 2113 && ran["found"] as? Int == 1 && ran["said"] as? String == "3 stuck")
        #expect(lines[1]["new"] as? String == "4417" && lines[2]["changed"] as? String == "4417" && lines[2]["columns"] as? [String] == ["note"] && lines[3]["gone"] as? String == "4402")
        let logged = try #require(lines[1]["row"] as? [String: Any])
        #expect(logged["customer"] as? String == "Acme Ltd" && logged["order_id"] as? Int == 4417 && logged["tags"] as? [String] == ["a", "b"])
        #expect(logged["api_key"] as? String == "(hidden)" && logged["note"] as? String == "(hidden)")   // a secret's name; a card number
        let file = memory.file(for: at)
        #expect(file.lastPathComponent == "2026-09-21.jsonl")
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
    }

    // MARK: a run

    @Test func aRunThatReportsFindingsLeavesATableAReceiptASnapshotAndLogLines() async throws {
        let place = Place()
        defer { place.remove() }
        try place.job("stuck-orders", #"{"name": "Stuck orders", "every_minutes": 60, "map": {"id": "order_id", "about": ["customer"]}}"#)
        let store = place.store()
        var rows: [[String: Any]] = [["order_id": 4417, "customer": "Acme Ltd", "waiting_days": 3], ["order_id": 4390, "customer": "Beta Corp", "waiting_days": 4]]
        var fail = false
        let runner = FolderJobRunner(store: store, execute: { run in
            if fail { throw ScriptRunnerError(message: "job.py failed: RuntimeError: The orders service asked to sign in again.") }
            try place.write(run.output.appendingPathComponent("all.csv"), "order_id\n1\n")
            return ["source": "Orders API", "read": 2113, "findings": rows, "_columns": ["order_id", "customer", "waiting_days"]] as [String: Any]
        }, now: { at })
        let memory = MemoryLog(directory: place.root.appendingPathComponent("memory"))
        memory.clock = { at }
        runner.memory = memory
        var changes: [FindingsChange] = []
        runner.onFindings = { _, change in changes.append(change) }
        let id = try #require(store.jobs.first?.id)

        runner.run(id)
        await runner.finish()

        let job = try #require(store.job(id: id))
        #expect(job.state.error == nil && job.state.source == "Orders API" && job.state.read == 2113 && job.state.found == 2 && job.state.said == nil && job.state.note == nil)
        let result = try #require(store.result(for: job))
        #expect(result.files.map(\.path) == ["findings.csv", "all.csv"] && result.shown.map(\.path) == ["findings.csv"] && result.shown[0].heading == "findings.csv")
        #expect(FolderJobPreview.read(result.shown[0]) == .table(rows: [["order_id", "customer", "waiting_days"], ["4417", "Acme Ltd", "3"], ["4390", "Beta Corp", "4"]], total: 2))
        #expect(!result.hasPreview)   // the card and the sticker still hinge on preview/, which this leaves alone
        #expect(changes.count == 1 && changes[0].new.map(\.id) == ["4417", "4390"])
        #expect(FindingsSnapshot.read(store.findingsFile(for: job)).rows.keys.sorted() == ["4390", "4417"])
        #expect(memory.lines(on: at).compactMap { $0["new"] as? String } == ["4417", "4390"])
        #expect(memory.lines(on: at).first?["ran"] as? [String: Any] != nil)
        #expect(FolderJobWords.lastRun(job, now: at) == "Last run \(JobWords.time(at, now: at)) · checked Orders API: read 2,113, found 2")
        #expect(FolderJobWords.receipt(job) == "“Stuck orders” ran: checked Orders API: read 2,113, found 2.")
        #expect(FolderJobWords.receiptLine(job, now: at) == "Checked Orders API: read 2,113, found 2 · \(JobWords.time(at, now: at)) · next \(JobWords.time(at.addingTimeInterval(3_600), now: at))")
        #expect(FolderJobWords.checked(FolderJobState(found: 0)) == "Found 0" && FolderJobWords.checked(FolderJobState(read: 12, found: 0)) == "Read 12, found 0")
        #expect(FolderJobWords.checked(FolderJobState(said: "words")) == nil)
        #expect(Jobs.folderJob(job, Jobs.Input(at: at)).lastRun.hasSuffix("checked Orders API: read 2,113, found 2"))

        // The next run: one changed, one gone, one new.
        rows = [["order_id": 4390, "customer": "Beta Corp", "waiting_days": 5], ["order_id": 4402, "customer": "Cora", "waiting_days": 1]]
        runner.run(id)
        await runner.finish()
        let change = try #require(changes.last)
        #expect(change.new.map(\.id) == ["4402"] && change.changed.map(\.row.id) == ["4390"] && change.changed[0].columns == ["waiting_days"] && change.gone == ["4417"])
        #expect(memory.lines(on: at).compactMap { $0["gone"] as? String } == ["4417"])
        #expect(store.job(id: id)?.state.found == 2)

        // A run that fails keeps the last findings and their snapshot as they were.
        fail = true
        runner.run(id)
        await runner.finish()
        #expect(store.job(id: id)?.state.error == "The orders service asked to sign in again." && store.job(id: id)?.state.found == 2)
        #expect(FindingsSnapshot.read(store.findingsFile(for: job)).rows.keys.sorted() == ["4390", "4402"] && changes.count == 2)
    }

    @Test func aRunThatReturnsWordsLeavesTheFindingsAsTheyWereAndABadReportFails() async throws {
        let place = Place()
        defer { place.remove() }
        try place.job("gm", #"{"name": "GM", "map": {"id": "item"}}"#)
        try place.job("plain", #"{"name": "Plain"}"#)
        let store = place.store()
        var value: Any = ["findings": [["item": 1]]] as [String: Any]
        let runner = FolderJobRunner(store: store, execute: { _ in value }, now: { at })
        let gm = try #require(store.jobs.first { $0.path == "gm" })
        let plain = try #require(store.jobs.first { $0.path == "plain" })
        runner.run(gm.id)
        await runner.finish()
        #expect(FindingsSnapshot.read(store.findingsFile(for: gm)).rows.count == 1 && store.job(id: gm.id)?.state.found == 1)

        value = "Nothing to report"
        runner.run(gm.id)
        await runner.finish()
        #expect(store.job(id: gm.id)?.state.said == "Nothing to report" && store.job(id: gm.id)?.state.reportsFindings == false)
        #expect(FindingsSnapshot.read(store.findingsFile(for: gm)).rows.count == 1)   // words say nothing about the rows
        #expect(store.result(for: gm)?.files.isEmpty == true)   // and this run left no table

        value = ["findings": [["item": 2]]] as [String: Any]
        runner.run(plain.id)   // no map in its job.json
        await runner.finish()
        #expect(store.job(id: plain.id)?.state.error?.hasPrefix("job.py returned findings, but its job.json has no map") == true)
        #expect(store.result(for: plain) == nil)   // the run failed, so nothing was put in place

        value = ["findings": "x"] as [String: Any]
        runner.run(gm.id)
        await runner.finish()
        #expect(store.job(id: gm.id)?.state.error == "job.py's findings must be a list of rows, each a JSON object." && store.job(id: gm.id)?.state.said == "Nothing to report")
    }

    // MARK: fixtures

    private struct Place {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("folder-job-findings-\(UUID())")
        var own: URL { root.appendingPathComponent("jobs") }
        var team: URL { root.appendingPathComponent("linked/jobs") }
        var results: URL { root.appendingPathComponent("job-results") }

        @MainActor func store() -> FolderJobStore {
            let team = self.team
            return FolderJobStore(directory: own, results: results, teamDirectory: { team })
        }

        func job(_ path: String, _ json: String, team: Bool = false, py: String = "def run():\n    return None\n") throws {
            let folder = (team ? self.team : own).appendingPathComponent(path)
            try write(folder.appendingPathComponent("job.json"), json)
            try write(folder.appendingPathComponent("job.py"), py)
        }

        func write(_ url: URL, _ text: String) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
