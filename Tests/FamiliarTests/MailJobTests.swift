import Foundation
import Testing
@testable import Familiar

/// Noteling's own Mail job: shipped into the person's jobs/ once, reading the inbox through the Mail over IMAP pack's
/// script, and reporting the unread messages of the last two days as findings.
@Suite @MainActor
struct MailJobTests {
    /// The job as the repository has it, `jobs/mail`.
    static let mail = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("jobs/mail")

    @Test func theMailJobSaysWhatItIsAndWhichColumnsMeanWhat() throws {
        let job = try FolderJobFiles.parse(try Data(contentsOf: Self.mail.appendingPathComponent("job.json")), path: "mail", source: .own)
        #expect(job.name == "Mail" && job.everyMinutes == 10 && job.requires == ["MAIL_ADDRESS", "MAIL_APP_PASSWORD"] && job.contributors.isEmpty)
        #expect(job.map?.id == "id" && job.map?.about == ["from"] && job.map?.page == "url" && job.map?.since == "received" && job.map?.what == "subject")
        let description = try String(contentsOf: Self.mail.appendingPathComponent("job.md"), encoding: .utf8)
        #expect(description.hasPrefix("Each row is a message in the inbox that is still unread") && description.contains("nothing is marked read, moved or deleted"))
    }

    @Test func theBundledJobsReachAJobsFolderOnceAndADeletedOneStaysDeleted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bundled-jobs-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = root.appendingPathComponent("bundle/jobs"), jobs = root.appendingPathComponent("jobs")
        for name in ["mail", "weather"] {
            try FileManager.default.createDirectory(at: bundled.appendingPathComponent(name), withIntermediateDirectories: true)
            try "{}".write(to: bundled.appendingPathComponent(name).appendingPathComponent("job.json"), atomically: true, encoding: .utf8)
        }
        // A folder of the person's own with a bundled job's name is theirs, and stays as it is.
        try FileManager.default.createDirectory(at: jobs.appendingPathComponent("weather"), withIntermediateDirectories: true)
        try "mine".write(to: jobs.appendingPathComponent("weather/job.md"), atomically: true, encoding: .utf8)

        #expect(FolderJobFiles.addBundledJobs(from: bundled, to: jobs) == ["mail"])
        #expect(FileManager.default.fileExists(atPath: jobs.appendingPathComponent("mail/job.json").path))
        #expect(try String(contentsOf: jobs.appendingPathComponent("weather/job.md"), encoding: .utf8) == "mine")
        #expect(try String(contentsOf: jobs.appendingPathComponent(FolderJobFiles.bundledRecord), encoding: .utf8) == "mail\nweather\n")
        #expect(FolderJobFiles.addBundledJobs(from: bundled, to: jobs).isEmpty)
        try FileManager.default.removeItem(at: jobs.appendingPathComponent("mail"))
        #expect(FolderJobFiles.addBundledJobs(from: bundled, to: jobs).isEmpty && !FileManager.default.fileExists(atPath: jobs.appendingPathComponent("mail").path))
        #expect(FolderJobFiles.addBundledJobs(from: root.appendingPathComponent("nowhere"), to: jobs).isEmpty)
        #expect(FolderJobFiles.jobFolders(in: jobs).jobs.isEmpty)   // the record is no job
    }

    @Test func theMailJobReportsTheUnreadMessagesThroughThePacksScript() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mail-job-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        // The pack's script, standing in: what the inbox has, as today.py gives it.
        let scripts = root.appendingPathComponent("tools/imap-mail/scripts")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try """
        import os

        def run(since_hours=24, mailbox="INBOX", limit=200, last_read=""):
            if os.environ.get("MAIL_STUB") == "error":
                return {"error": "Mail isn't connected yet: add MAIL_ADDRESS and MAIL_APP_PASSWORD in Noteling Settings."}
            assert since_hours == 48 and limit == 200, (since_hours, limit)
            return {"account": "yang@example.com", "mailbox": mailbox, "returned": 3, "items": [
                {"key": "<a@x>", "title": "Invoice due Friday", "from": "Lena Park <lena@acme.example>", "received": "2026-11-02T09:00:00+00:00",
                 "unread": True, "tab": "primary", "important": True, "bulk": False, "preview": "Hi, the invoice for October is attached.",
                 "url": "https://mail.google.com/mail/u/yang%40example.com/#search/rfc822msgid%3Aa%40x"},
                {"key": "<b@x>", "title": "Weekly digest", "from": "News <news@list.example>", "received": "2026-11-02T08:00:00+00:00",
                 "unread": True, "tab": "promotions", "important": False, "bulk": True, "preview": "This week in widgets.", "url": ""},
                {"key": "<c@x>", "title": "Read already", "from": "Ana <ana@example.com>", "received": "2026-11-01T08:00:00+00:00",
                 "unread": False, "tab": "", "important": False, "bulk": False, "preview": "", "url": ""},
            ]}
        """.write(to: scripts.appendingPathComponent("today.py"), atomically: true, encoding: .utf8)
        let folder = root.appendingPathComponent("jobs/mail")
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.mail, to: folder)

        let runner = ScriptRunner(config: Config())
        let registry = ToolRegistry(root: root.appendingPathComponent("tools"), runner: runner)   // held: the job's import path is its folders
        let feature = FolderJobsFeature(registry: registry, notifier: JobNotifier(),
                                        store: FolderJobStore(directory: root.appendingPathComponent("jobs"), results: root.appendingPathComponent("job-results")),
                                        memory: root.appendingPathComponent("memory"))
        feature.runner.hasSecret = { _ in true }   // as if entered in Settings; the stand-in needs none
        let job = try #require(feature.store.jobs.first)
        #expect(job.name == "Mail" && !job.isTeam)

        feature.runner.run(job.id)
        await feature.runner.finish()
        let state = try #require(feature.store.job(id: job.id)?.state)
        #expect(state.error == nil && state.source == "the inbox at yang@example.com" && state.read == 3 && state.found == 2)
        let result = try #require(feature.store.result(for: job))
        #expect(FolderJobPreview.read(try #require(result.shown.first)) == .table(rows: [
            ["id", "from", "subject", "received", "preview", "tab", "important", "bulk", "url"],
            ["<a@x>", "Lena Park <lena@acme.example>", "Invoice due Friday", "2026-11-02T09:00:00+00:00", "Hi, the invoice for October is attached.", "primary", "yes", "",
             "https://mail.google.com/mail/u/yang%40example.com/#search/rfc822msgid%3Aa%40x"],
            ["<b@x>", "News <news@list.example>", "Weekly digest", "2026-11-02T08:00:00+00:00", "This week in widgets.", "promotions", "", "yes", ""],
        ], total: 2))
        let memory = try #require(feature.runner.memory)
        #expect(memory.lines(on: Date()).compactMap { $0["new"] as? String } == ["<a@x>", "<b@x>"])
        let latest = try #require(feature.store.job(id: job.id))
        #expect(latest.map?.place(of: FindingRow(id: "<b@x>", values: ["url": ""], columns: ["url"])) == nil)   // no page without a link

        // The script's own error (mail not connected, a sign-in refused) is the run's failure, in its words.
        runner.extraEnv = ["MAIL_STUB": "error"]
        feature.runner.run(job.id)
        await feature.runner.finish()
        #expect(feature.store.job(id: job.id)?.state.error?.hasPrefix("Mail isn't connected yet") == true)
    }

    @Test func aJobThatNeedsASecretWaitsForItInsteadOfFailingEveryTime() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("waits-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("jobs/needy")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #"{"name": "Needy", "every_minutes": 5, "requires": ["X_TOKEN"]}"#.write(to: folder.appendingPathComponent("job.json"), atomically: true, encoding: .utf8)
        try "def run():\n    return 'ran'\n".write(to: folder.appendingPathComponent("job.py"), atomically: true, encoding: .utf8)
        let store = FolderJobStore(directory: root.appendingPathComponent("jobs"), results: root.appendingPathComponent("job-results"))
        var runs = 0
        let runner = FolderJobRunner(store: store, execute: { _ in runs += 1; return "ran" })
        runner.hasSecret = { _ in false }
        runner.tick()
        await runner.finish()
        #expect(runs == 0 && store.jobs.first?.state.lastRunAt == nil && runner.missingSecrets(store.jobs[0]) == ["X_TOKEN"])

        runner.hasSecret = { _ in true }   // entered in Settings
        runner.tick()
        await runner.finish()
        #expect(runs == 1 && store.jobs.first?.state.lastRunAt != nil && store.jobs.first?.state.said == "ran")
    }
}
