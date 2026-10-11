import Foundation
import Testing
@testable import Familiar

/// Jobs kept as folders: `job.json` (only what a job is and when it runs), `job.py` (its one entry point) and `input/`,
/// yours in `jobs/` and your team's in the linked tools' `jobs/`. A run gets a fresh output folder on this Mac; the
/// files in its `preview/` are shown as they are, every file can be taken away, and the job keeps one card while its
/// preview has something.
@Suite @MainActor
struct FolderJobsTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: finding jobs

    @Test func aFolderWithAJobJsonAndAJobPyIsAJob() throws {
        let place = Place()
        defer { place.remove() }
        try place.job("gm", #"{"name": "GM"}"#)
        try place.job("holiday/oct/fashion", #"{}"#)
        try place.job("gm/input/old", #"{"name": "Inside a job's folder"}"#)   // a job's folder is the job's
        try place.write(place.own.appendingPathComponent("drafts/job.json"), #"{"name": "Still being written"}"#)
        try place.write(place.own.appendingPathComponent("helpers/job.py"), "def run(): pass\n")
        try place.job("holiday/oct/gm", #"{"name": "Holiday Oct · GM"}"#, team: true)

        let store = place.store()

        #expect(store.jobs.filter { !$0.isTeam }.map(\.path).sorted() == ["gm", "holiday/oct/fashion"])
        #expect(store.jobs.filter(\.isTeam).map(\.path) == ["holiday/oct/gm"])
        #expect(store.job(id: FolderJobFiles.id(.own, "holiday/oct/fashion"))?.name == "holiday/oct/fashion")   // no name: its path
        #expect(store.jobs.filter { !$0.isTeam }.allSatisfy { $0.on })                                          // yours run at once
        #expect(store.jobs.filter(\.isTeam).allSatisfy { !$0.on })                                              // your team's wait
        #expect(store.unreadable == ["drafts": "It has a job.json but no job.py beside it."])
        #expect(FolderJobFiles.id(.team, "holiday/oct/gm") == FolderJobFiles.id(.team, "holiday/oct/gm"))
        #expect(FolderJobFiles.id(.team, "gm") != FolderJobFiles.id(.own, "gm"))
        #expect(NotelingSetup.teamJobCount(in: place.linked) == 1)
    }

    @Test func aJobsFolderInAToolsFolderIsNeverAPack() throws {
        let place = Place()
        defer { place.remove() }
        for pack in ["shop", "jobs", "watches"] {
            try place.write(place.linked.appendingPathComponent("\(pack)/SKILL.md"), "---\nname: \(pack)\n---\n")
        }
        #expect(ToolRegistry.packFolders(in: place.linked).map(\.lastPathComponent) == ["shop"])
    }

    @Test func jobJsonSaysOnlyWhatTheJobIsAndWhenItRuns() throws {
        func parse(_ text: String) throws -> FolderJob { try FolderJobFiles.parse(Data(text.utf8), path: "holiday/oct/gm", source: .team) }
        let job = try parse(#"""
        {"name": "Holiday Oct · GM", "about": "Prices on the GM event items", "every_minutes": 60,
         "starts": "2026-10-05T00:00:00-04:00", "ends": "2026-10-08T23:59:00-04:00", "requires": ["SHOP_KEY", "NOTELING_TOOLS_REPO_TOKEN"],
         "items": ["not a job's business"]}
        """#)
        #expect(job.name == "Holiday Oct · GM" && job.about == "Prices on the GM event items" && job.everyMinutes == 60)
        #expect(job.starts?.text == "2026-10-05T00:00:00-04:00" && job.ends != nil)
        #expect(job.requires == ["SHOP_KEY"])   // Noteling's own token is never a job's
        #expect(job.id == FolderJobFiles.id(.team, "holiday/oct/gm") && job.isTeam)

        let bare = try parse("{}")
        #expect(bare.name == "holiday/oct/gm" && bare.everyMinutes == nil && bare.requires.isEmpty)
        #expect(try parse(#"{"every_minutes": 2}"#).everyMinutes == 5)
        #expect(try parse(#"{"every_minutes": "5000"}"#).everyMinutes == 1_440)

        func refusal(_ text: String) -> String? {
            do { _ = try parse(text); return nil } catch { return (error as? FolderJobError)?.message }
        }
        #expect(refusal("{ name: 1 }")?.hasPrefix("Its job.json isn't valid JSON") == true)
        #expect(refusal("[1]") == "Its job.json must be one JSON object: { … }.")
        #expect(refusal(#"{"name": 3}"#) == "In its job.json, name must be text in quotes.")
        #expect(refusal(#"{"every_minutes": "soon"}"#) == "In its job.json, every_minutes must be a number of minutes, 5 to 1440.")
        #expect(refusal(#"{"starts": "tomorrow"}"#)?.hasPrefix("In its job.json, starts must be a date and time") == true)
        #expect(refusal(#"{"requires": "SHOP_KEY"}"#) == "In its job.json, requires must be a list of secret names in quotes.")
    }

    // MARK: running

    @Test func aRunGetsItsInputAFreshOutputItsOwnCardsFolderAndTheToolsOnItsPath() async throws {
        let place = Place()
        defer { place.remove() }
        try place.job("gm", #"{"name": "GM", "every_minutes": 60}"#, input: ["items.csv": "item\n1\n"])
        let store = place.store()
        var seen: FolderJobRun?
        var outputWasEmpty = false
        let runner = FolderJobRunner(store: store, execute: { run in
            seen = run
            outputWasEmpty = (try? FileManager.default.contentsOfDirectory(atPath: run.output.path))?.isEmpty == true
            return NSNull()
        }, now: { at })
        runner.importPaths = { [place.root.appendingPathComponent("tools"), place.linked] }

        runner.tick()
        await runner.finish()

        let run = try #require(seen)
        let job = try #require(store.jobs.first)
        #expect(run.env["NOTELING_INPUT"] == place.own.appendingPathComponent("gm/input").path)
        #expect(run.env["PYTHONPATH"] == place.root.appendingPathComponent("tools").path + ":" + place.linked.path)
        #expect(outputWasEmpty && run.output.path.hasPrefix(store.resultFolder(for: job).path))
        #expect(!run.output.path.hasPrefix(place.own.path))   // never in the job's own folder
        #expect(run.script == place.own.appendingPathComponent("gm/job.py") && run.timeout == 600)
        #expect(run.cardsSource == "jobcards-own-gm" && run.cardsSource != FolderJobCards.source(for: job))
        #expect(CardInboxFormat.folderID(run.cardsSource) == CardInboxFormat.folderID(FolderJobCards.source(for: job)))   // one folder
        #expect(store.jobs.first?.state.lastRunAt == at && store.jobs.first?.state.lastSuccessAt == at)
    }

    @Test func aRunThatWorksReplacesTheOutputAndOneThatFailsKeepsIt() async throws {
        let place = Place()
        defer { place.remove() }
        try place.job("gm", #"{"name": "GM"}"#)
        let store = place.store()
        var attempt = 0
        let runner = FolderJobRunner(store: store, execute: { run in
            attempt += 1
            if attempt == 1 {
                try place.write(run.output.appendingPathComponent("preview/problems.csv"), "item,why\n1,price\n")
                try place.write(run.output.appendingPathComponent("all.csv"), "item,why\n1,price\n2,\n")
                return "1 of 2 wrong"
            }
            try place.write(run.output.appendingPathComponent("half.csv"), "item\n")
            throw ScriptRunnerError(message: "job.py failed: ValueError: The price service didn't answer\nTraceback …")
        }, now: { at })
        let id = try #require(store.jobs.first?.id)

        #expect(runner.run(id) == nil)
        await runner.finish()
        let output = store.output(for: try #require(store.job(id: id)))
        #expect(FolderJobFiles.result(output: output)?.files.map(\.path) == ["preview/problems.csv", "all.csv"])
        let worked = try #require(store.job(id: id)?.state)
        #expect(worked.said == "1 of 2 wrong" && worked.error == nil && worked.lastSuccessAt == at && worked.preview != nil)

        runner.run(id)
        await runner.finish()
        #expect(FolderJobFiles.result(output: output)?.files.map(\.path) == ["preview/problems.csv", "all.csv"])   // kept
        let failed = try #require(store.job(id: id)?.state)
        #expect(failed.error == "The price service didn't answer" && failed.said == "1 of 2 wrong" && failed.preview == worked.preview)
        let left = try FileManager.default.contentsOfDirectory(atPath: store.resultFolder(for: try #require(store.job(id: id))).path)
        #expect(left.sorted() == ["output", "run.json"])   // no half-written output left behind

        // How it went is kept for the next launch.
        #expect(place.store().job(id: id)?.state == failed)
        let row = Jobs.folderJob(try #require(store.job(id: id)), Jobs.Input(at: at))
        #expect(row.lastRun.hasSuffix(" · failed") && row.runProblem == "The price service didn't answer" && row.needsAttention)
        #expect(row.status == .failed && row.resultIsProblem)
    }

    @Test func aJobThatNeedsASecretSaysSoInsteadOfRunning() async throws {
        let place = Place()
        defer { place.remove() }
        try place.job("gm", #"{"name": "GM", "requires": ["SHOP_KEY"]}"#)
        let store = place.store()
        var ran = false
        let runner = FolderJobRunner(store: store, execute: { _ in ran = true; return NSNull() }, now: { at })
        runner.hasSecret = { _ in false }
        let id = try #require(store.jobs.first?.id)

        runner.run(id)
        await runner.finish()

        #expect(!ran && store.job(id: id)?.state.error == "Needs SHOP_KEY in Settings.")
        let input = Jobs.Input(at: at, panel: FolderJobsPanel(store: store, runner: runner))
        let row = Jobs.folderJob(try #require(store.job(id: id)), input)
        #expect(row.status == .needsSettings && row.problems == ["Needs SHOP_KEY in Settings."])
    }

    // MARK: what a run left

    @Test func previewFilesAreShownAsTheyAreAndEveryFileCanBeTakenAway() throws {
        let place = Place()
        defer { place.remove() }
        let output = place.root.appendingPathComponent("output")
        for name in ["preview/problems.csv", "preview/notes.txt", "preview/chart.png", "all.csv", "raw/2026-10-05.tsv", "run.command", ".hidden.csv"] {
            try place.write(output.appendingPathComponent(name), "x\n")
        }
        try FileManager.default.createSymbolicLink(at: output.appendingPathComponent("preview/link.csv"),
                                                   withDestinationURL: output.appendingPathComponent("all.csv"))

        let result = try #require(FolderJobFiles.result(output: output))

        #expect(result.files.map(\.path) == ["preview/chart.png", "preview/notes.txt", "preview/problems.csv", "all.csv",
                                             "raw/2026-10-05.tsv", "run.command"])
        #expect(result.shown.map(\.path) == ["preview/notes.txt", "preview/problems.csv"])   // tables and texts, as they are
        #expect(result.hasPreview)
        #expect(result.files.first { $0.path == "all.csv" }?.opens == true)
        #expect(result.files.first { $0.path == "run.command" }?.opens == false)   // only saved or shown in Finder
        #expect(FolderJobFiles.result(output: place.root.appendingPathComponent("none")) == nil)
    }

    @Test func aPreviewDrawsTheFirstRowsAndSaysHowManyMore() throws {
        let csv = "item,title,why\r\n1,\"Kettle, blue\",\"Shows \"\"$12\"\"\nnot $10\"\r\n\n2,Mug,\n"
        let (rows, total) = FolderJobPreview.table(csv, separator: ",", limit: 200)
        #expect(rows == [["item", "title", "why"], ["1", "Kettle, blue", "Shows \"$12\"\nnot $10"], ["2", "Mug", ""]])
        #expect(total == 2)

        let place = Place()
        defer { place.remove() }
        func file(_ name: String, _ text: String) throws -> FolderJobFile {
            let url = place.root.appendingPathComponent("preview/" + name)
            try place.write(url, text)
            return try #require(FolderJobFiles.files(in: place.root).files.first { $0.path == "preview/" + name })
        }
        let long = try file("problems.csv", "item\n" + (1...250).map(String.init).joined(separator: "\n"))
        let table = FolderJobPreview.read(long)
        guard case .table(let shown, let count) = table else { Issue.record("not a table"); return }
        #expect(shown.count == 201 && shown[0] == ["item"] && count == 250)
        #expect(FolderJobPreview.more(table) == "Open the file for all 250 rows.")

        let tabs = FolderJobPreview.read(try file("by-seller.tsv", "\u{FEFF}seller\tcount\nACME\t3\n"))
        #expect(tabs == .table(rows: [["seller", "count"], ["ACME", "3"]], total: 1) && FolderJobPreview.more(tabs) == nil)

        let text = FolderJobPreview.read(try file("notes.txt", String(repeating: "a", count: 20_500)))
        guard case .text(let words, _) = text else { Issue.record("not a text"); return }
        #expect(words.count == 20_000 && FolderJobPreview.more(text) == "Open the file for all 20,500 characters.")

        // Too big to read whole: its beginning, without a count.
        let big = try file("big.csv", "item\n" + String(repeating: "12345678\n", count: 600_000))
        let bigTable = FolderJobPreview.read(big)
        guard case .table(let first, nil) = bigTable else { Issue.record("not a table cut short"); return }
        #expect(first.count == 201 && FolderJobPreview.more(bigTable) == "Open the file for all its rows.")
    }

    // MARK: its card

    @Test func aJobHasACardWhileItsPreviewHasSomethingAndItOpensAgainOnlyWhenThatChanges() async throws {
        let place = Place()
        defer { place.remove() }
        try place.job("holiday/oct/gm", #"{"name": "Holiday Oct · GM"}"#)
        let store = place.store()
        var preview: String? = "item,why\n1,price\n"
        let runner = FolderJobRunner(store: store, execute: { run in
            if let preview { try place.write(run.output.appendingPathComponent("preview/problems.csv"), preview) }
            try place.write(run.output.appendingPathComponent("all.csv"), "item,checked_at\n1,\(Date().timeIntervalSince1970)\n")
            return "1 of 1 wrong"
        }, now: { at })
        let cards = FolderJobCards(root: place.inbox)
        cards.timeZone = TimeZone(identifier: "America/New_York")!
        runner.cards = cards
        var news: [String] = []
        runner.onNews = { news.append($0.name) }
        let morning = MorningStore(directory: place.root.appendingPathComponent("morning"))
        let inbox = CardInbox(store: morning, directory: place.inbox)
        inbox.folderName = { _ in "Holiday Oct · GM" }
        runner.onCardsChanged = { inbox.scan(at: at) }
        let job = try #require(store.jobs.first)
        let cardID = CardInboxFormat.cardID(FolderJobCards.key(for: job))
        func card() -> MorningCard? { morning.cards.first { $0.id == cardID } }

        runner.run(job.id)
        await runner.finish()
        #expect(card()?.title == "Holiday Oct · GM · 10:13 AM" && card()?.meaning == "1 of 1 wrong")
        #expect(card()?.disposition == .unreviewed && card()?.sources.first?.kind == "Job")
        #expect(morning.folders.contains { $0.id == card()?.folderID && $0.name == "Holiday Oct · GM" })
        #expect(news == ["Holiday Oct · GM"])

        try morning.setCardResolution(cardID: cardID, resolved: true)
        runner.run(job.id)   // the same preview, though all.csv changed: still resolved, and nobody is told
        await runner.finish()
        #expect(card()?.disposition == .resolved && news.count == 1)

        preview = "item,why\n1,price\n2,badge\n"
        runner.run(job.id)
        await runner.finish()
        #expect(card()?.disposition == .unreviewed && news.count == 2)

        preview = nil   // nothing to look at: the card goes
        runner.run(job.id)
        await runner.finish()
        #expect(card()?.disposition == .resolved && card()?.inbox?.goneAt != nil && news.count == 2)
        #expect(!FileManager.default.fileExists(atPath: place.inbox.appendingPathComponent("job-own-holiday-oct-gm/job.json").path))
    }

    @Test func outsideItsWindowAJobDoesntRunOrKeepACard() async throws {
        let place = Place()
        defer { place.remove() }
        try place.job("autumn", #"{"name": "Autumn", "every_minutes": 5, "ends": "2026-09-01T00:00:00Z"}"#, team: true)
        try place.job("winter", #"{"name": "Winter", "every_minutes": 5, "starts": "2026-12-01T00:00:00Z"}"#, team: true)
        let store = place.store()
        let runner = FolderJobRunner(store: store, execute: { _ in Issue.record("it ran"); return NSNull() }, now: { at })
        let autumn = try #require(store.jobs.first { $0.name == "Autumn" })
        let winter = try #require(store.jobs.first { $0.name == "Winter" })
        try runner.turn(autumn.id, on: true)
        try runner.turn(winter.id, on: true)
        var ended = try #require(store.job(id: autumn.id))
        ended.state = FolderJobState(lastRunAt: at, lastSuccessAt: at, preview: "abc")

        runner.tick()
        await runner.finish()

        #expect(!ended.isDue(at: at) && FolderJobCards.card(for: ended, at: at) == nil)
        #expect(runner.run(winter.id) == "It runs only between its start and its end.")
        let jobs = Jobs.list(Jobs.Input(at: at, panel: FolderJobsPanel(store: store, runner: runner)))
        #expect(jobs.map(\.phase).sorted { "\($0)" < "\($1)" } == [.ended, .upcoming])
        #expect(Jobs.controls(try #require(jobs.first { $0.name == "Winter" }), canOpenSettings: true) == [.onOff])
        #expect(Jobs.controls(try #require(jobs.first { $0.name == "Autumn" }), canOpenSettings: true).isEmpty)
        #expect(Jobs.summary(jobs, now: at) == Jobs.noneLive)
    }

    @Test func aPersonTurnsOnAsManyTeamJobsAsAreTheirsAndItIsKept() throws {
        let place = Place()
        defer { place.remove() }
        for index in 1...25 { try place.job("live/\(index)", #"{"name": "Live \#(index)"}"#, team: true) }
        try place.job("mine", "{}")
        let store = place.store()

        for job in store.jobs where job.isTeam { try store.setOn(job.id, true) }   // no limit: as many as are theirs

        #expect(place.store().jobs.filter { $0.isTeam && $0.on }.count == 25)   // kept for the person
        #expect(throws: FolderJobError("Only your team's jobs are turned on and off. Yours run while their folder is there.")) {
            try store.setOn(try #require(store.jobs.first { !$0.isTeam }).id, false)
        }
    }

    // MARK: a real job.py

    /// A job.py run the way the app runs it: it reads its input, imports a helper from the tools folder, writes its
    /// preview and a file to take away, and a card of its own for a follow-up. Both cards land in the job's one folder.
    @Test func aRealJobPyWritesItsOutputAndACardOfItsOwn() async throws {
        let place = Place()
        defer { place.remove() }
        let tools = place.root.appendingPathComponent("tools")
        try place.write(tools.appendingPathComponent("shared/prices.py"), "def wrong(price):\n    return float(price) > 10\n")
        try place.job("gm", #"{"name": "GM", "about": "Prices on the GM items"}"#, py: """
        import csv, json, os
        from shared import prices

        def run():
            with open(os.path.join(os.environ["NOTELING_INPUT"], "items.csv")) as f:
                rows = list(csv.DictReader(f))
            out = os.environ["NOTELING_OUTPUT"]
            os.makedirs(os.path.join(out, "preview"))
            wrong = [row for row in rows if prices.wrong(row["price"])]
            with open(os.path.join(out, "preview", "problems.csv"), "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(["item", "price"])
                writer.writerows([[row["item"], row["price"]] for row in wrong])
            with open(os.path.join(out, "all.csv"), "w") as f:
                f.write("item,price,checked_at\\n" + "".join(row["item"] + "," + row["price"] + ",now\\n" for row in rows))
            card = {"title": "Ask pricing about item 2", "body": "It has been wrong since Monday."}
            with open(os.path.join(os.environ["NOTELING_CARDS_DIR"], "follow-up.json"), "w") as f:
                json.dump(card, f)
            return f"{len(wrong)} of {len(rows)} wrong"
        """, input: ["items.csv": "item,price\n1,9.99\n2,12.50\n"])
        let scripts = ScriptRunner(config: Config())
        scripts.cardsRoot = place.inbox
        let registry = ToolRegistry(root: tools, runner: scripts)
        let feature = FolderJobsFeature(registry: registry, notifier: JobNotifier(), store: place.store(), inbox: place.inbox)
        let morning = MorningStore(directory: place.root.appendingPathComponent("morning"))
        let inbox = CardInbox(store: morning, directory: place.inbox)
        inbox.folderName = { feature.cardFolderName($0) }
        feature.runner.onCardsChanged = { inbox.scan(at: at) }
        let job = try #require(feature.store.jobs.first)

        feature.runner.run(job.id)
        await feature.runner.finish()

        let state = try #require(feature.store.job(id: job.id)?.state)
        #expect(state.error == nil && state.said == "1 of 2 wrong")
        let result = try #require(feature.store.result(for: job))
        #expect(result.files.map(\.path) == ["preview/problems.csv", "all.csv"])
        #expect(FolderJobPreview.read(result.shown[0]) == .table(rows: [["item", "price"], ["2", "12.50"]], total: 1))
        let cards = morning.cards.filter(\.isFromInbox)
        #expect(cards.map { $0.inbox?.key ?? "" }.sorted() == ["job-own-gm/job", "jobcards-own-gm/follow-up"])
        #expect(Set(cards.map(\.folderID)).count == 1 && morning.folders.contains { $0.id == cards[0].folderID && $0.name == "GM" })
        let row = Jobs.folderJob(try #require(feature.store.job(id: job.id)), Jobs.Input(at: Date(), panel: feature.panel))
        #expect(row.does == "Prices on the GM items" && row.lastRun.hasSuffix(" · 1 of 2 wrong") && row.every == "When you run it")
        #expect(Jobs.cards(for: row, Jobs.Input(at: Date(), cards: morning.cards, panel: feature.panel)).count == 2)
    }

    // MARK: fixtures

    private struct Place {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("folder-jobs-\(UUID())")
        var own: URL { root.appendingPathComponent("jobs") }
        var linked: URL { root.appendingPathComponent("linked") }
        var team: URL { linked.appendingPathComponent("jobs") }
        var results: URL { root.appendingPathComponent("job-results") }
        var inbox: URL { root.appendingPathComponent("cards/inbox") }

        @MainActor func store() -> FolderJobStore {
            let team = self.team
            return FolderJobStore(directory: own, results: results, teamDirectory: { team })
        }

        func job(_ path: String, _ json: String, team: Bool = false, py: String = "def run():\n    return None\n",
                 input: [String: String] = [:]) throws {
            let folder = (team ? self.team : own).appendingPathComponent(path)
            try write(folder.appendingPathComponent("job.json"), json)
            try write(folder.appendingPathComponent("job.py"), py)
            for (name, text) in input { try write(folder.appendingPathComponent("input/" + name), text) }
        }

        func write(_ url: URL, _ text: String) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}

extension Jobs.Input {
    /// The jobs kept as folders, as the pages see them.
    @MainActor
    init(at now: Date, cards: [MorningCard] = [], panel: FolderJobsPanel? = nil) {
        self.init()
        self.cards = cards
        self.now = now
        if let panel {
            folderJobs = panel.store.jobs
            runningJob = panel.runner.running
            queuedJobs = Set(panel.runner.queued)
            let runner = panel.runner
            setup.missingJobSecrets = { runner.missingSecrets($0) }
        }
    }
}
