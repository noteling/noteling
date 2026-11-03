import Foundation
import Testing
@testable import Familiar

/// The buttons on a job's findings: functions of its own job.py, named in job.json, with arguments filled from the row.
@Suite @MainActor
struct FolderJobButtonsTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    /// Pressed the way the app presses them, through a real job.py: a function it imported isn't one of its buttons, nor
    /// is one it doesn't have; one that fails says why; one that works says what it said, with the row's values filled in.
    @Test func aButtonRunsAFunctionOfItsOwnJobPyWithTheRowsValuesAndNothingElse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("buttons-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("jobs/gm")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #"""
        {"name": "GM", "map": {"id": "item"},
         "actions": [{"label": "Mark as fixed", "run": "mark_fixed", "args": {"item": "{item}", "price": "{price}"}},
                     {"label": "Remove", "run": "remove", "args": {"path": "/tmp/x"}},
                     {"label": "Missing", "run": "nowhere"},
                     {"label": "Break", "run": "broken"}]}
        """#.write(to: folder.appendingPathComponent("job.json"), atomically: true, encoding: .utf8)
        try """
        from os import remove

        def run():
            return {"source": "the price list", "read": 1, "findings": [{"item": "4417", "price": 9.99}]}

        def mark_fixed(item, price):
            return f"Marked {item} as fixed at {price}."

        def broken():
            raise ValueError("The pricing service said no.")
        """.write(to: folder.appendingPathComponent("job.py"), atomically: true, encoding: .utf8)
        let feature = FolderJobsFeature(registry: ToolRegistry(root: root.appendingPathComponent("tools"), runner: ScriptRunner(config: Config())),
                                        notifier: JobNotifier(),
                                        store: FolderJobStore(directory: root.appendingPathComponent("jobs"), results: root.appendingPathComponent("job-results")),
                                        memory: root.appendingPathComponent("memory"))
        var presses: [FindingPress] = []
        feature.buttons.record = { _, _, _, press in presses.append(press) }
        let job = try #require(feature.store.jobs.first)
        feature.runner.run(job.id)
        await feature.runner.finish()
        let row = try #require(FindingsSnapshot.read(feature.store.findingsFile(for: job)).rows["4417"]?.row)
        func press(_ label: String) async throws -> FindingPress {
            await feature.buttons.press(job, try #require(job.actions.first { $0.label == label }), for: row)
        }

        #expect(feature.buttons.unavailable(job) == nil)
        let fixed = try await press("Mark as fixed")
        #expect(fixed.said == "Marked 4417 as fixed at 9.99." && !fixed.failed && fixed.label == "Mark as fixed")
        #expect(try await press("Remove").said == "job.py has no function remove() of its own.")
        #expect(try await press("Missing").said == "job.py has no function nowhere() of its own.")
        let broken = try await press("Break")
        #expect(broken.said == "The pricing service said no." && broken.failed)
        #expect(presses.map(\.failed) == [false, true, true, true] && feature.buttons.pressing.isEmpty)
        let stranger = FolderJobAction(label: "Delete all", run: "delete_all")
        #expect(await feature.buttons.press(job, stranger, for: row).said == "Its job no longer has this button.")
    }

    /// A button runs only while its job could: on, between its start and its end, with its secrets in Settings. It runs
    /// that job's job.py, with the row's arguments and no output folder.
    @Test func aButtonRunsOnlyWhileItsJobCould() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("buttons-when-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let team = root.appendingPathComponent("linked/jobs")
        for (path, json) in [("holiday/gm", #"{"name": "GM", "requires": ["PRICING_TOKEN"], "map": {"id": "item"}, "actions": [{"label": "Fix", "run": "fix", "args": {"item": "{item}"}}]}"#),
                             ("autumn", #"{"name": "Autumn", "ends": "2020-09-01T00:00:00Z", "map": {"id": "item"}, "actions": [{"label": "Fix", "run": "fix"}]}"#),
                             ("winter", #"{"name": "Winter", "starts": "2099-12-01T00:00:00Z", "map": {"id": "item"}, "actions": [{"label": "Fix", "run": "fix"}]}"#)] {
            let folder = team.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try json.write(to: folder.appendingPathComponent("job.json"), atomically: true, encoding: .utf8)
            try "def run():\n    return None\n".write(to: folder.appendingPathComponent("job.py"), atomically: true, encoding: .utf8)
        }
        let store = FolderJobStore(directory: root.appendingPathComponent("jobs"), results: root.appendingPathComponent("job-results"), teamDirectory: { team })
        var runs: [FolderJobRun] = []
        let buttons = FolderJobButtons(store: store, execute: { run in runs.append(run); return "Fixed." }, now: { at })
        var hasToken = false
        buttons.hasSecret = { _ in hasToken }
        let row = FindingRow(id: "4417", values: ["item": "4417"], columns: ["item"])
        func job(_ path: String) throws -> FolderJob { try #require(store.jobs.first { $0.path == path }) }
        let fix = FolderJobAction(label: "Fix", run: "fix", args: ["item": "{item}"])

        #expect(buttons.unavailable(try job("holiday/gm")) == "Turn its job on in Jobs to use this button.")
        for path in ["holiday/gm", "autumn", "winter"] { try store.setOn(try job(path).id, true) }
        #expect(buttons.unavailable(try job("autumn")) == "Its job has ended, so this button can't run.")
        #expect(buttons.unavailable(try job("winter")) == "Its job hasn't started yet, so this button can't run.")
        #expect(buttons.unavailable(try job("holiday/gm")) == "Needs PRICING_TOKEN in Settings.")
        let refused = await buttons.press(try job("holiday/gm"), fix, for: row)
        #expect(runs.isEmpty && refused.said == "Needs PRICING_TOKEN in Settings." && refused.failed)
        var gone = try job("holiday/gm")
        gone.id = UUID()
        #expect(buttons.unavailable(gone) == "Its job isn't here any more, so this button can't run.")

        hasToken = true
        #expect(buttons.unavailable(try job("holiday/gm")) == nil)
        let pressed = await buttons.press(try job("holiday/gm"), fix, for: row)
        let run = try #require(runs.first)
        #expect(run.job.path == "holiday/gm" && run.function == "fix" && run.arguments["item"] as? String == "4417")
        #expect(run.script == team.appendingPathComponent("holiday/gm/job.py") && run.env["NOTELING_OUTPUT"] == nil && run.timeout == FolderJobButtons.timeLimit)
        #expect(pressed == FindingPress(label: "Fix", at: at, said: "Fixed.", failed: false))
        #expect(FolderJobButtons.key(try job("holiday/gm"), row) == "team/holiday/gm/4417")
    }
}
