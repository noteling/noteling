import Foundation
import Testing
@testable import Familiar

/// The chat as a source of findings: a report keeps its source among the jobs, diffs the rows against the last scan,
/// records the run, sets off the minister's turn, and tells the chat what became of each row.
@Suite @MainActor struct ChatFindingsTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func fixture() -> (scans: ChatFindings, store: FolderJobStore, matters: Matters, log: MemoryLog, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chat-findings-\(UUID().uuidString)")
        let store = FolderJobStore(directory: dir.appendingPathComponent("jobs"), results: dir.appendingPathComponent("results"))
        let matters = Matters(directory: nil)
        matters.clock = { self.at }
        let log = MemoryLog(directory: dir.appendingPathComponent("memory"))
        log.clock = { self.at }
        let scans = ChatFindings(store: store, matters: matters, memory: log)
        scans.clock = { self.at }
        return (scans, store, matters, log, dir)
    }

    private func meeting(_ id: String, _ title: String, start: String = "2026-09-21T10:00:00-04:00") -> [String: Any] {
        ["link": "https://cal.example.com/e/\(id)", "title": title, "start": start, "attendees": "Lena, Marco"]
    }

    @Test func aSourceIsNamedBySlugAndStandsAmongTheJobsWithoutAFolderOrASchedule() throws {
        #expect(ChatSource.slug("Slack #ops") == "slack-ops" && ChatSource.slug("  Calendar ") == "calendar" && ChatSource.slug("###") == "scan")
        #expect(ChatSource.slug(String(repeating: "a", count: 60)).count == 40)
        let (_, store, _, _, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let map = try FindingsMap.parse(["id": "link", "what": "title", "where": "link", "due": "start", "about": ["attendees"]])
        try store.addChatSource(ChatSource(slug: "calendar", name: "Calendar", about: "Each row is a meeting today.", map: map, raw: ["id": "link"]))
        let job = try #require(store.jobs.first { $0.source == .chat })
        #expect(job.path == "calendar" && job.name == "Calendar" && job.on && job.everyMinutes == nil && job.map?.id == "link")
        #expect(store.folder(for: job) == nil && store.resultFolder(for: job).path.hasSuffix("results/chat/calendar"))
        #expect(MemoryLog.name(of: job) == "chat/calendar" && FolderJobWords.every(job) == "when you ask the chat to look again")
        // Ids of the folder jobs are as they were: a chat source is its own kind.
        #expect(FolderJobFiles.id(.own, "x") == JobFiles.derivedID("job-own:x") && FolderJobFiles.id(.team, "y") == JobFiles.derivedID("job-team:y"))
        #expect(FolderJobFiles.id(.chat, "calendar") == job.id)
        // Read back from its file after a fresh look.
        let again = FolderJobStore(directory: dir.appendingPathComponent("jobs"), results: dir.appendingPathComponent("results"))
        #expect(again.jobs.map(\.path) == ["calendar"] && again.jobs.first?.about == "Each row is a meeting today.")
    }

    @Test func aReportHandsTheRowsToTheMinisterDiffsTheNextOneAndTellsWhatBecameOfEach() async throws {
        let (scans, store, _, log, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        var reported: [(String, FindingsChange)] = []
        var turns = 0
        scans.onFindings = { job, change in reported.append((MemoryLog.name(of: job), change)) }
        scans.takeTurn = { turns += 1 }
        let input: [String: Any] = ["source": "Calendar", "about": "Each row is a meeting on the person's calendar today; start is when it begins; link opens it.",
                                    "map": ["id": "link", "what": "title", "where": "link", "due": "start", "about": ["attendees"]],
                                    "rows": [meeting("1", "Design review"), meeting("2", "1:1 with Lena", start: "2026-09-21T14:00:00-04:00")]]
        let said = try await scans.report(input)
        #expect(said.hasPrefix("Handed to the minister: 2 rows from Calendar (the first scan of it).\n2 findings: none judged yet.\n"))
        #expect(said.contains("- Lena, Marco · Design review · Not judged yet") && said.hasSuffix("kept quiet on purpose."))
        #expect(reported.count == 1 && reported[0].0 == "chat/calendar" && reported[0].1.new.count == 2 && turns == 1)
        let job = try #require(store.jobs.first { $0.source == .chat })
        #expect(job.state.found == 2 && job.state.read == 2 && job.state.source == "Calendar" && job.state.lastRunAt == at)
        #expect(FindingsSnapshot.read(store.findingsFile(for: job)).rows.count == 2)
        #expect(FileManager.default.fileExists(atPath: store.output(for: job).appendingPathComponent(FolderJobFiles.findings).path))
        let lines = log.lines(on: at)
        #expect(lines.contains { $0["ran"] != nil && $0["job"] as? String == "chat/calendar" } && lines.filter { $0["new"] != nil }.count == 2)

        // The next scan of the same source: one row changed, one gone, one new; the minister hears only of those.
        var next = input
        next["rows"] = [meeting("1", "Design review (moved)"), meeting("3", "Lunch with Ana", start: "2026-09-21T12:30:00-04:00")]
        let again = try await scans.report(next)
        #expect(again.hasPrefix("Handed to the minister: 2 rows from Calendar (1 new, 1 changed, 1 gone since the last scan)."))
        #expect(reported.count == 2 && reported[1].1.new.map(\.id) == ["https://cal.example.com/e/3"] && reported[1].1.changed.count == 1
                && reported[1].1.gone == ["https://cal.example.com/e/2"] && turns == 2)
        #expect(store.jobs.filter { $0.source == .chat }.count == 1)
    }

    @Test func tellTheMinisterKeepsARuleAndForgetsIt() throws {
        let (scans, _, _, _, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(scans.routes().compactMap { $0.definition["name"] as? String } == ["report_findings", "tell_the_minister"])
        #expect(throws: MinisterError.self) { try scans.tell(["instruction": "x"]) }   // no lessons to keep it in
        let lessons = Lessons(file: dir.appendingPathComponent("taught.json"))
        scans.lessons = lessons
        #expect(try scans.tell(["instruction": "For all meetings, make the link the thing to open"]).hasPrefix("Told the minister: “For all meetings, make the link the thing to open”."))
        #expect(lessons.told.count == 1)
        #expect(throws: MinisterError.self) { try scans.tell([:]) }
        #expect(throws: MinisterError.self) { try scans.tell(["forget": "lunch"]) }
        #expect(try scans.tell(["forget": "meetings"]) == "The minister forgot: “For all meetings, make the link the thing to open”.")
        #expect(lessons.told.isEmpty)
    }

    @Test func whatTheChatHandsOverIsChecked() async {
        let (scans, _, _, _, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        func refusal(_ input: [String: Any]) async -> String? {
            do { _ = try await scans.report(input); return nil } catch { return error.localizedDescription }
        }
        let good: [String: Any] = ["source": "Inbox", "about": "Mail.", "map": ["id": "id"], "rows": [["id": "1"]]]
        #expect(await refusal(good) == nil)
        var bad = good; bad["source"] = " "
        #expect(await refusal(bad) == "Give source: what you read, in a few words.")
        bad = good; bad["about"] = ""
        #expect(await refusal(bad)?.hasPrefix("Give about:") == true)
        bad = good; bad["map"] = ["what": "x"]
        #expect(await refusal(bad)?.contains("map needs id") == true)
        bad = good; bad["rows"] = ["not a row"]
        #expect(await refusal(bad) == "rows must be a list of flat objects, each with the id column.")
        bad = good; bad["rows"] = Array(repeating: ["id": "1"], count: 201)
        #expect(await refusal(bad)?.hasPrefix("At most 200 rows") == true)
    }
}
