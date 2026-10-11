import AppKit
import Foundation
import Testing
import FamiliarContracts
@testable import Familiar

/// Jobs: every reading job and every job kept as a folder in one list, each row's words, a job's page and its card, the
/// home's Jobs box, and every way in. Temp folders only; nothing reads a real source, runs a script or reaches a model.
@Suite @MainActor
struct JobsPageTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var time: String { JobWords.time(now, now: now) }

    /// A job kept as a folder, as its store would have it.
    private func folderJob(_ name: String, path: String, team: Bool = false, on: Bool = true, every: Int? = 120, about: String = "",
                           state: FolderJobState = FolderJobState()) -> FolderJob {
        var job = FolderJob(id: UUID(), source: team ? .team : .own, path: path, name: name, about: about, everyMinutes: every)
        job.on = on
        job.state = state
        return job
    }

    private func failed(_ why: String, at: Date? = nil) -> FolderJobState { FolderJobState(lastRunAt: at ?? now, error: why) }
    private func found(_ said: String, at: Date? = nil) -> FolderJobState {
        FolderJobState(lastRunAt: at ?? now, lastSuccessAt: at ?? now, said: said, preview: "digest")
    }

    private func mail(_ name: String = "Morning mail") -> LearnedReadingSource {
        LearnedReadingSource(kind: .mail, name: name, meaning: "What came in overnight", application: "Mail",
                             scope: "Everything that arrived, skipping newsletters", script: "mail__today")
    }

    private func web(_ name: String = "School portal") -> LearnedReadingSource {
        LearnedReadingSource(kind: .web, name: name, meaning: "Notes from the class", application: "Safari",
                             url: "https://school.example.test/news", scope: "New posts on the first page")
    }

    private func calendar(_ name: String = "Work calendar") -> LearnedCalendarSource {
        LearnedCalendarSource(name: name, meaning: "My meetings", application: "Calendar", account: "alex@example.test",
                              calendarName: "Work", timeZoneID: "America/New_York")
    }

    /// One reading job's part of a run that has ended: what it read, or why not.
    private func part(_ source: LearnedReadingSource, _ state: SourceRunEntry.State, items: Int = 0, arrived: Int? = nil,
                      truncated: Bool = false, message: String = "", notes: [String] = []) -> SourceRunEntry {
        let request = ReadingReadRequest(source: source, requestedAt: now)
        var entry = SourceRunEntry(reading: request, state: state, message: message)
        entry.startedAt = now
        if ![.waiting, .reading].contains(state) { entry.finishedAt = now }
        if state == .complete || state == .partial {
            entry.readingSnapshot = ReadingSnapshot(requestID: request.id, sourceID: source.id, source: source, collectedAt: now,
                items: (0..<items).map { ReadingItem(id: "item-\($0)", title: "Item \($0)", text: "What it says", evidence: "A row") },
                coverage: state == .partial ? .partial : .complete, coverageNotes: notes, accountEvidence: "The account",
                sourceEvidence: "The inbox", scopeEvidence: "Everything new",
                scriptRead: arrived.map { ScriptReadCounts(arrived: $0, returned: items, truncated: truncated) })
        }
        return entry
    }

    private func calendarPart(_ source: LearnedCalendarSource, events: Int) -> SourceRunEntry {
        let day = now
        var entry = SourceRunEntry(calendar: CalendarReadRequest(source: source, day: day), state: .complete)
        entry.finishedAt = now
        let start = calendarInZone(source.timeZoneID).startOfDay(for: day).addingTimeInterval(9 * 3_600)
        entry.calendarSnapshot = CalendarSnapshot(sourceID: source.id, day: day, timeZoneID: source.timeZoneID,
            events: (0..<events).map { CalendarEventRecord(id: "event-\($0)", title: "Meeting \($0)", start: start.addingTimeInterval(Double($0) * 3_600),
                                                            end: start.addingTimeInterval(Double($0) * 3_600 + 1_800), evidence: "On the calendar") },
            coverage: .complete, accountEvidence: "The account", calendarEvidence: "Work", dateEvidence: "Today")
        return entry
    }

    private func run(_ entries: [SourceRunEntry], at: Date? = nil, status: SourceRunStatus = .completed) -> SourceRunRecord {
        SourceRunRecord(origin: .single, startedAt: at ?? now, finishedAt: status == .running ? nil : (at ?? now).addingTimeInterval(60),
                        timeZoneID: "UTC", status: status, entries: entries)
    }

    /// A card the card step made from a run of a reading job.
    private func card(_ title: String, source: UUID, run: UUID, resolved: Bool = false, updated: Date? = nil) -> MorningCard {
        var card = MorningCard(folderID: UUID(), title: title, action: MorningAction(title: "Draft a reply", instruction: "Draft it."),
                               updatedAt: updated ?? now)
        card.tracking = CardTracking(sourceID: source, itemKey: title.lowercased(), sourceName: "Morning mail", identityEvidence: "Its id",
                                     firstSeenAt: now, lastSeenAt: now, lastRunID: run, contentFingerprint: title,
                                     resolution: resolved ? .resolved : .open)
        return card
    }

    // MARK: one list

    @Test func everyReadingJobAndEveryJobKeptAsAFolderIsInOneList() throws {
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        let mail = mail(), web = web(), calendar = calendar()
        try fixture.sources.saveReadingSource(mail)
        try fixture.sources.saveReadingSource(web)
        try fixture.sources.saveSource(calendar)
        let own = try fixture.job("stuck-orders", #"{"name": "Stuck orders", "about": "Orders waiting on me", "every_minutes": 15}"#)
        let fashion = try fixture.job("holiday/oct/fashion", #"{"name": "Fashion", "about": "Prices on the fashion items", "every_minutes": 120}"#, team: true)
        let shoes = try fixture.job("holiday/oct/shoes", #"{"name": "Shoes", "every_minutes": 60}"#, team: true)
        try fixture.jobs.setOn(fashion.id, true)

        // Every reading job (calendars and the rest) and every job kept as a folder, yours and your team's, on or off.
        let jobs = Jobs.list(fixture.input())
        #expect(jobs.map(\.name) == ["Morning mail", "School portal", "Stuck orders", "Work calendar", "Fashion", "Shoes"])
        #expect(jobs.map(\.kind) == [.mail, .web, .job, .calendar, .teamJob, .teamJob])
        #expect(Set(jobs.map(\.id)) == Set([mail.id, web.id, calendar.id, own.id, fashion.id, shoes.id]))
        #expect(jobs.map(\.does) == ["Reads mail", "Reads a web page", "Orders waiting on me", "Reads your calendar",
                                     "Prices on the fashion items · from your team's tools", "Runs its job.py · from your team's tools"])
        #expect(jobs.map(\.every) == ["When you run it", "When you run it", "Every 15 minutes", "When you run it", "Every 2 hours", "Every hour"])
        #expect(jobs.map(\.lastRun) == Array(repeating: "Not run yet", count: 6))
        #expect(jobs.map(\.status) == [.ready, .ready, .ready, .ready, .ready, .off])
        #expect(jobs.first { $0.name == "Fashion" }?.path == "holiday/oct/fashion")
        #expect(jobs.first { $0.name == "Morning mail" }?.meaning == "What came in overnight")

        // The Jobs page lists them, around the bar that runs the reading jobs.
        fixture.navigation.route = .jobs
        let page = try #require(find(JobsPage.self, in: fixture.files().body))
        #expect(find(CalendarBatchControls.self, in: page.body)?.sourceCount == 3)
    }

    @Test func jobsThatNeedAttentionComeFirstThenYoursThenTheTeamsByName() {
        let mail = mail(), web = web(), calendar = calendar()
        let stuck = folderJob("Stuck orders", path: "stuck", state: failed("The orders service asked to sign in again."))
        let gift = folderJob("Gift guide", path: "gift", state: found("Nothing to look at"))
        let zeta = folderJob("Zeta", path: "zeta", team: true, state: failed("Signed out"))
        let alpha = folderJob("Alpha", path: "alpha", team: true, state: found("1 of 2 wrong"))
        let off = folderJob("Off and failed", path: "off", team: true, on: false, state: failed("Signed out"))
        var input = Jobs.Input(calendars: [calendar], readings: [mail, web],
                               runs: [run([part(web, .failed, message: "The portal asked to sign in again.")])],
                               folderJobs: [stuck, gift, zeta, alpha, off], now: now)
        input.setup.missingSecrets = { $0.id == mail.id ? ["MAIL_APP_PASSWORD"] : [] }

        let jobs = Jobs.list(input)
        // A failed read, a secret missing and a job whose last run failed first (yours, then the team's); then the
        // rest of yours, then the rest of the team's, each by name. A team job that's off never needs attention.
        #expect(jobs.map(\.name) == ["Morning mail", "School portal", "Stuck orders", "Zeta", "Gift guide", "Work calendar", "Alpha", "Off and failed"])
        #expect(jobs.map(\.needsAttention) == [true, true, true, true, false, false, false, false])
        let portal = jobs.first { $0.name == "School portal" }
        #expect(portal?.runProblem == "The portal asked to sign in again." && portal?.problems == [])
        let failedJob = jobs.first { $0.name == "Stuck orders" }
        #expect(failedJob?.status == .failed && failedJob?.runProblem == "The orders service asked to sign in again.")
        #expect(failedJob?.lastRun == "Last run \(time) · failed" && failedJob?.resultIsProblem == true)

        // Sorting alone: by name within each group, whatever came first.
        let a = Job(id: UUID(), kind: .mail, name: "b job", does: "", every: "", lastRun: "", status: .ready)
        let b = Job(id: UUID(), kind: .job, name: "A job", does: "", every: "", lastRun: "", status: .ready)
        let c = Job(id: UUID(), kind: .teamJob, name: "a team job", does: "", every: "", lastRun: "", status: .ready)
        let d = Job(id: UUID(), kind: .teamJob, name: "z team job", does: "", every: "", lastRun: "", status: .failed, needsAttention: true)
        #expect(Jobs.sorted([c, a, d, b]).map(\.name) == ["z team job", "A job", "b job", "a team job"])
    }

    @Test func teamJobsSayWhereTheyComeFromAndShowTheirSwitch() async throws {
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        let fashion = try fixture.job("holiday/oct/fashion", #"{"name": "Fashion", "about": "Prices on the fashion items", "every_minutes": 120}"#, team: true)
        func job() throws -> Job { try #require(Jobs.list(fixture.input()).first { $0.id == fashion.id }) }

        // Off: what it is, and the switch, nothing to run.
        #expect(try job().status == .off && job().status.label == "Off")
        #expect(try job().does == "Prices on the fashion items · from your team's tools")
        #expect(try Jobs.controls(job(), canOpenSettings: true) == [.onOff])
        #expect(try !job().needsAttention)

        // The switch turns it on; then it runs at once and has Run now.
        #expect(try fixture.actions.turn(job(), on: true) == nil)
        #expect(fixture.jobs.job(id: fashion.id)?.on == true)
        #expect(try Jobs.controls(job(), canOpenSettings: true) == [.runNow, .onOff])
        await fixture.jobRunner.finish()   // turning it on runs it at once
        #expect(fixture.jobs.job(id: fashion.id)?.state.said == "Ran in the test.")
        #expect(Jobs.teamIntro == "From your team's tools. Turn on the ones that are yours: only those run and tell you.")

        // One of yours has no switch: it runs while its folder is there.
        let own = try fixture.job("mine", #"{"name": "Mine"}"#)
        let mine = try #require(Jobs.list(fixture.input()).first { $0.id == own.id })
        #expect(Jobs.controls(mine, canOpenSettings: true) == [.runNow])
        #expect(fixture.actions.turn(mine, on: false) == "Only your team's jobs are turned on and off. Yours run while their folder is there.")
    }

    @Test func nothingTheOldListsShowedIsLost() throws {
        // Jobs kept as folders: how often and when it ends, how its last run went, folders that can't be a job, and
        // where the team's jobs come from.
        var gm = folderJob("GM", path: "holiday/oct/gm", team: true, state: found("2 of 8 prices wrong"))
        gm.ends = JobMoment.parse("2026-10-31T23:59:00")
        let job = Jobs.folderJob(gm, Jobs.Input(now: now))
        #expect(job.every == "Every 2 hours · Ends Sat Oct 31, 11:59 PM")
        #expect(job.lastRun == "Last run \(time) · 2 of 8 prices wrong")
        // What it's for: its first line on the row, without a closing full stop; its page says all of it when that's more.
        var about = folderJob("Orders", path: "orders", about: "Orders waiting on me for more than a day.")
        #expect(Jobs.folderJob(about, Jobs.Input(now: now)).does == "Orders waiting on me for more than a day" && !Jobs.aboutShortened(about))
        about.about = "Orders waiting on me.\nThe orders service lists those older than a day."
        #expect(Jobs.aboutLine(about) == "Orders waiting on me" && Jobs.aboutShortened(about))
        about.about = ""
        #expect(Jobs.folderJob(about, Jobs.Input(now: now)).does == "Runs its job.py" && !Jobs.aboutShortened(about))
        let folders = URL(fileURLWithPath: "/jobs")
        #expect(Jobs.unreadable(own: ["sale": "It has a job.json but no job.py beside it."], team: ["shoes": "Not listed."], directory: folders)
                == [Jobs.Unreadable(id: "own-job:sale", text: "The job in the “sale” folder can't run. It has a job.json but no job.py beside it.",
                                    folder: folders.appendingPathComponent("sale")),
                    Jobs.Unreadable(id: "team-job:shoes", text: "Not listing your team's job shoes. Not listed.")])
        #expect(Jobs.emptyTeam(linked: false) == "Your team's jobs show here once your team's tools are linked in Settings.")
        #expect(Jobs.emptyTeam(linked: true) == "Your team's tools have no jobs yet.")

        // Manage sources: each job's kind and meaning, one that needs review, one that can't run yet.
        var review = web("Saved inbox reading")
        review.requiresReview = true
        var empty = mail("No rules")
        empty.scope = ""
        var noAccount = calendar("Shared calendar")
        noAccount.account = ""
        let jobs = Jobs.list(Jobs.Input(calendars: [noAccount], readings: [review, empty], now: now))
        let reviewJob = try #require(jobs.first { $0.id == review.id })
        #expect(reviewJob.status == .needsReview && reviewJob.status.label == "Needs review")
        #expect(reviewJob.problems == ["Confirm its address and what to read before it runs."])
        let emptyJob = try #require(jobs.first { $0.id == empty.id })
        #expect(emptyJob.status == .cantRunYet && emptyJob.status.label == "Can't run yet")
        #expect(emptyJob.problems.first?.hasPrefix("Its reading rules are empty") == true)
        #expect(jobs.first { $0.id == noAccount.id }?.problems == ["Confirm the account for this calendar before collecting it."])
        let allNeedAttention = jobs.allSatisfy(\.needsAttention)
        #expect(allNeedAttention)
        #expect(reviewJob.meaning == "Notes from the class")
    }

    @Test func aWatchesFolderLeftBehindIsSaidOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("retired-watches-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let own = root.appendingPathComponent("watches"), team = root.appendingPathComponent("linked/watches")
        #expect(Jobs.retiredWatches(own: own, team: team).isEmpty)   // none there: nothing said
        try FileManager.default.createDirectory(at: own.appendingPathComponent("empty"), withIntermediateDirectories: true)
        #expect(Jobs.retiredWatches(own: own, team: team).isEmpty)   // a folder with no watch in it: nothing either
        try FileManager.default.createDirectory(at: team.appendingPathComponent("holiday/oct/gm"), withIntermediateDirectories: true)
        try "{}".write(to: team.appendingPathComponent("holiday/oct/gm/watch.json"), atomically: true, encoding: .utf8)
        #expect(Jobs.retiredWatches(own: own, team: team).map(\.id) == ["team-watches"])
        #expect(Jobs.retiredWatches(own: own, team: team)[0].folder == nil)   // the team's: only to know, not to open
        try "{}".write(to: own.appendingPathComponent("empty/watch.json"), atomically: true, encoding: .utf8)
        let rows = Jobs.retiredWatches(own: own, team: team)
        #expect(rows.map(\.id) == ["team-watches", "own-watches"] && rows[1].folder == own)
        #expect(rows[0].text.hasPrefix("Your team's tools still have a watches/ folder. Watches no longer run"))

        // A store's watches/ is beside its jobs/, and the team's beside theirs.
        let store = FolderJobStore(directory: root.appendingPathComponent("jobs"), results: root.appendingPathComponent("results"),
                                   teamDirectory: { root.appendingPathComponent("linked/jobs") })
        #expect(store.retiredWatches.standardizedFileURL.path == own.standardizedFileURL.path)
        #expect(store.teamRetiredWatches()?.standardizedFileURL.path == team.standardizedFileURL.path)
    }

    @Test func theJobsPageKeepsRemovedJobsSavedDemonstrationsAndTeaching() throws {
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        let mail = mail()
        try fixture.sources.saveReadingSource(mail)
        try fixture.sources.removeSource(id: mail.id)
        let pack = fixture.root.appendingPathComponent("tools/sample")
        try FileManager.default.createDirectory(at: pack.appendingPathComponent("docs/workflows"), withIntermediateDirectories: true)
        try "# Sample\nLearned by watching.".write(to: pack.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "# Read the class page\nRead the new posts at `school.example.test/news` in the browser."
            .write(to: pack.appendingPathComponent("docs/workflows/class.md"), atomically: true, encoding: .utf8)
        fixture.sources.refreshSavedWorkflows(root: fixture.root.appendingPathComponent("tools"))
        #expect(Jobs.demonstrations(fixture.sources).count == 1)

        fixture.navigation.route = .jobs
        var taught = 0
        let page = try #require(find(JobsPage.self, in: fixture.files(teach: { taught += 1 }).body))
        #expect(find(RemovedSourcesList.self, in: page.body)?.sources.map(\.id) == [mail.id])
        page.teach?()
        #expect(taught == 1)
        #expect(Jobs.summary(Jobs.list(fixture.input()), demonstrations: Jobs.demonstrations(fixture.sources).count, now: now)
                == "No jobs yet · 1 demonstration to review")
    }

    // MARK: each row

    @Test func aReadingJobsRowSaysWhatItReadAndHowItStands() {
        let mail = mail(), web = web(), calendar = calendar()
        func job(_ runs: [SourceRunRecord], cards: [MorningCard] = [], sorted: Set<UUID> = [], setup: JobsSetup = JobsSetup(),
                 _ id: UUID? = nil) -> Job {
            Jobs.list(Jobs.Input(calendars: [calendar], readings: [mail, web], runs: runs, cards: cards, sorted: sorted, setup: setup, now: now))
                .first { $0.id == (id ?? mail.id) }!
        }
        // Read through a script: how many arrived, and the cards they became, once the card step sorted the run.
        let read = run([part(mail, .complete, items: 12, arrived: 12)])
        #expect(job([read]).lastRun == "Last run \(time) · 12 new")
        #expect(job([read], sorted: [read.id]).lastRun == "Last run \(time) · 12 new · no cards")
        let cards = (1...3).map { card("Card \($0)", source: mail.id, run: read.id) } + [card("Earlier", source: mail.id, run: UUID())]
        #expect(job([read], cards: cards, sorted: [read.id]).lastRun == "Last run \(time) · 12 new · 3 cards")
        #expect(job([run([part(mail, .complete, arrived: 0)])]).lastRun == "Last run \(time) · nothing new")
        let cut = job([run([part(mail, .partial, items: 200, arrived: 350, truncated: true, notes: ["350 messages arrived; the newest 200 are here."])])])
        #expect(cut.lastRun == "Last run \(time) · 200 of 350 new")
        #expect(cut.resultIsProblem && cut.needsAttention && cut.runProblem == "350 messages arrived; the newest 200 are here.")

        // From the screen: what it found, or that it found part; a calendar's events.
        #expect(job([run([part(web, .complete, items: 2)])], web.id).lastRun == "Last run \(time) · 2 found")
        #expect(job([run([part(web, .partial, items: 2, notes: ["Older rows couldn't be checked."])])], web.id).lastRun
                == "Last run \(time) · partial · 2 found")
        #expect(job([run([calendarPart(calendar, events: 3)])], calendar.id).lastRun == "Last run \(time) · 3 events")
        #expect(job([run([calendarPart(calendar, events: 1)])], calendar.id).lastRun == "Last run \(time) · 1 event")

        // Failed, stopped, or never started.
        let failed = job([run([part(mail, .failed, message: "Noteling couldn't read this source: Signed out.")], status: .failed)])
        #expect(failed.lastRun == "Last run \(time) · nothing saved" && failed.status == .failed && failed.status.label == "Failed")
        // Its row says why; its page shows that with the run's results, so it isn't one of the problems its page lists.
        #expect(failed.allProblems == ["Noteling couldn't read this source: Signed out."] && failed.problems.isEmpty && failed.needsAttention)
        let stopped = job([run([part(mail, .stopped, message: "Stopped.")], status: .stopped)])
        #expect(stopped.lastRun == "Last run \(time) · stopped" && stopped.status == .ready && !stopped.needsAttention)
        let notRun = job([run([part(mail, .notRun, message: "Another desktop task is active.")], status: .failed)])
        #expect(notRun.lastRun == "Last run \(time) · didn't run" && notRun.needsAttention)

        // Running now, or waiting for its turn in Run all: the last run shown is the one that ended.
        let reading = run([part(mail, .reading), part(web, .waiting)], at: now.addingTimeInterval(600), status: .running)
        #expect(job([reading, read]).status == .running && job([reading, read]).status.label == "Running")
        #expect(job([reading, read]).lastRun == "Last run \(time) · 12 new")
        #expect(job([reading], web.id).status == .waiting && job([reading], web.id).lastRun == "Not run yet")

        // Needs Settings: a secret its script needs, or control for one that reads from the screen.
        var setup = JobsSetup()
        setup.missingSecrets = { _ in ["MAIL_ADDRESS", "MAIL_APP_PASSWORD"] }
        let secrets = job([], setup: setup)
        #expect(secrets.status == .needsSettings && secrets.status.label == "Needs Settings")
        #expect(secrets.problems == ["Needs MAIL_ADDRESS and MAIL_APP_PASSWORD in Settings."])
        #expect(Jobs.controls(secrets, canOpenSettings: true) == [.openSettings])
        #expect(Jobs.controls(secrets, canOpenSettings: false) == [.runNow])
        setup.controlAllowed = { false }
        #expect(job([], setup: setup, web.id).problems == [Jobs.readsFromScreen])
        #expect(job([], setup: setup, calendar.id).status == .needsSettings)
        #expect(Jobs.controls(job([reading]), canOpenSettings: true) == [.stop])
    }

    @Test func everyStateHasItsWordAndOnlyAProblemIsRed() {
        let labels = [Job.Status.ready, .running, .waiting, .off, .needsSettings, .needsReview, .cantRunYet, .failed]
        #expect(labels.map(\.label) == [nil, "Running", "Waiting to run", "Off", "Needs Settings", "Needs review", "Can't run yet", "Failed"])
        #expect(labels.filter(\.isProblem) == [.needsSettings, .needsReview, .cantRunYet, .failed])

        // A job kept as a folder: running, waiting its turn, or needing a secret.
        let job = folderJob("Sale items", path: "sale", state: found("Nothing to look at"))
        #expect(Jobs.folderJob(job, Jobs.Input(folderJobs: [job], runningJob: job.id, now: now)).status == .running)
        #expect(Jobs.folderJob(job, Jobs.Input(folderJobs: [job], queuedJobs: [job.id], now: now)).status == .waiting)
        var input = Jobs.Input(folderJobs: [job], now: now)
        input.setup.missingJobSecrets = { _ in ["SHOP_TOKEN"] }
        let settings = Jobs.folderJob(job, input)
        #expect(settings.status == .needsSettings && settings.problems == ["Needs SHOP_TOKEN in Settings."] && settings.needsAttention)
        #expect(Jobs.controls(settings, canOpenSettings: true) == [.openSettings])
    }

    @Test func theHomeBoxSumsTheJobsUpInOneLine() throws {
        func job(_ name: String, _ status: Job.Status = .ready, attention: Bool = false, at: Date? = nil, kind: Job.Kind = .mail) -> Job {
            Job(id: UUID(), kind: kind, name: name, does: "", every: "", lastRun: "", lastRunAt: at, status: status, needsAttention: attention)
        }
        let earlier = now.addingTimeInterval(-3_600)
        #expect(Jobs.summary([], now: now) == "No jobs yet")
        #expect(Jobs.summary([job("Off", .off, kind: .teamJob)], now: now) == "1 team job you can turn on")
        #expect(Jobs.summary([job("A", .off, kind: .teamJob), job("B", .off, kind: .teamJob)], now: now) == "2 team jobs you can turn on")
        let five = [job("Mail", .failed, attention: true, at: earlier), job("Sale", attention: true, at: now), job("Calendar"),
                    job("Portal", at: earlier), job("Gifts", .waiting), job("Shoes", .off, kind: .teamJob)]
        #expect(Jobs.summary(five, now: now) == "5 jobs · 2 need attention · last run \(time)")
        #expect(Jobs.summary([job("Mail", .running), job("Sale", attention: true)], now: now) == "2 jobs · 1 running · 1 needs attention")
        #expect(Jobs.summary([job("Mail")], demonstrations: 2, now: now) == "1 job · 2 demonstrations to review")
        #expect(Jobs.summary([{ var ended = job("Ended"); ended.phase = .ended; return ended }()], now: now) == "No jobs running now")

        // The home has the one box, and it opens Jobs; the boxes it replaces are gone.
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        fixture.navigation.route = .folders
        let entry = try #require(find(JobsEntry.self, in: fixture.files().body))
        entry.open()
        #expect(fixture.navigation.route == .jobs)
        #expect(find(CalendarBatchControls.self, in: fixture.files(route: .folders).body) == nil)
    }

    // MARK: routes

    // MARK: before the start and after the end

    private func moment(_ date: Date) -> JobMoment { JobMoment(text: "", date: date) }

    @Test func jobsBeforeTheirStartOrPastTheirEndWaitUnderOneLineOnlyToBeLookedAt() throws {
        var live = folderJob("Live sale", path: "live", state: failed("Signed out"))
        live.ends = moment(now + 3_600)
        var soon = folderJob("Soon", path: "soon", team: true, on: false)
        soon.starts = moment(now + 7_200)
        var later = folderJob("Later", path: "later")
        later.starts = moment(now + 86_400)
        let ranBefore = now - 7_200
        var ended = folderJob("Ended red", path: "ended", team: true, state: found("1 of 1 wrong", at: ranBefore))
        ended.ends = moment(now - 3_600)
        var gone = folderJob("Long gone", path: "gone", state: failed("Signed out", at: now - 2 * 86_400))
        gone.ends = moment(now - 86_400)
        var input = Jobs.Input(readings: [mail()], folderJobs: [live, soon, later, ended, gone], now: now)
        input.setup.missingJobSecrets = { ["Soon", "Ended red"].contains($0.name) ? ["SHOP_API_KEY"] : [] }

        // The list holds the live jobs; the rest wait, the soonest to start first and the latest to end first.
        let jobs = Jobs.list(input)
        #expect(jobs.filter(\.isLive).map(\.name) == ["Live sale", "Morning mail"])
        let outside = Jobs.outside(jobs)
        #expect(outside.upcoming.map(\.name) == ["Soon", "Later"])
        #expect(outside.ended.map(\.name) == ["Ended red", "Long gone"])

        // Nothing out of the way asks for the person: no red, no problem, never first.
        for job in outside.upcoming + outside.ended {
            #expect(!job.needsAttention && !job.resultIsProblem && !job.status.isProblem && job.runProblem == nil)
        }
        let endedRed = outside.ended[0]
        #expect(endedRed.status == .ready && endedRed.problems.isEmpty)
        #expect(endedRed.every == "Every 2 hours · Ended " + (ended.ends?.words ?? ""))
        #expect(endedRed.lastRun == "Last run \(JobWords.time(ranBefore, now: now)) · 1 of 1 wrong")   // still there to look at
        #expect(outside.ended[1].status == .ready)                                                    // its last run failed: not Failed
        // An upcoming one still says, quietly, what it lacks, so it can be put right before it starts.
        #expect(outside.upcoming[0].status == .off && outside.upcoming[0].problems == ["Needs SHOP_API_KEY in Settings."])

        // No buttons, but an upcoming team job's switch, to turn it on ahead of its start.
        #expect(Jobs.controls(outside.upcoming[0], canOpenSettings: true) == [.onOff])
        #expect(Jobs.controls(outside.upcoming[1], canOpenSettings: true) == [])
        #expect(Jobs.controls(endedRed, canOpenSettings: true) == [] && Jobs.controls(outside.ended[1], canOpenSettings: true) == [])

        // One quiet line for them; the home's box counts only the live ones.
        #expect(Jobs.outsideLine(upcoming: 2, ended: 2, showing: false) == "Upcoming (2) · Ended (2) · Show")
        #expect(Jobs.outsideLine(upcoming: 0, ended: 1, showing: false) == "Ended (1) · Show")
        #expect(Jobs.outsideLine(upcoming: 2, ended: 2, showing: true) == "Hide upcoming and ended jobs")
        #expect(Jobs.outsideLine(upcoming: 1, ended: 0, showing: true) == "Hide upcoming jobs")
        #expect(Jobs.outsideLine(upcoming: 0, ended: 0, showing: false) == nil)
        #expect(Jobs.summary(jobs, now: now) == "2 jobs · 1 needs attention · last run \(time)")
        #expect(Jobs.summary(outside.upcoming + outside.ended, now: now) == "No jobs running now")

        // A card put away says why: the job ended, hasn't started, or is off.
        #expect(FolderJobWords.putAway(ended, gone: now, now: now) == "This job ended \(ended.ends?.words ?? ""), so its card was put away.")
        #expect(FolderJobWords.putAway(ended, gone: now - 86_400, now: now) == nil)   // it went before the job ended, for another reason
        #expect(FolderJobWords.putAway(later, gone: now, now: now) == "This job starts \(later.starts?.words ?? ""); its card is put away until then.")
        var off = folderJob("Off", path: "off", team: true, on: false)
        #expect(FolderJobWords.putAway(off, gone: now, now: now) == "This job is off, so its card was put away.")
        off.on = true
        #expect(FolderJobWords.putAway(off, gone: now, now: now) == nil)
    }

    @Test func jobsRoutesHaveTitlesHeightsAndBackLeadsToJobs() throws {
        let id = UUID()
        func title(_ route: MorningNavigation.Route) -> String {
            MorningFilesView.title(for: route, folderName: { _ in nil }, jobName: { $0 == id ? "Morning mail" : nil })
        }
        #expect(title(.jobs) == "Jobs")
        #expect(title(.sourceJob(id)) == "Morning mail" && title(.sourceJob(UUID())) == "Job")
        #expect(title(.sources) == "Manage sources")   // the old screen still works for anything that opens it
        for route: MorningNavigation.Route in [.jobs, .sourceJob(id)] {
            #expect(MorningPanelController.preferredHeight(for: route) == 680 && MorningPanelController.preferredWidth(for: route) == 650)
        }
        #expect(AttentionOpen.route(.jobs) == "jobs" && AttentionOpen.route(.sourceJob(id)) == "job")

        let fixture = try JobsFixture()
        defer { fixture.remove() }
        let mail = mail()
        try fixture.sources.saveReadingSource(mail)
        let own = try fixture.job("stuck-orders", #"{"name": "Stuck orders"}"#)
        #expect(MorningFilesView.title(for: .sourceJob(mail.id), folderName: { _ in nil }, jobName: { _ in nil }) == "Job")
        fixture.navigation.route = .sourceJob(mail.id)
        #expect(find(SourceJobPage.self, in: fixture.files().body)?.id == mail.id)
        fixture.navigation.route = .folderJob(own.id)
        #expect(find(FolderJobPage.self, in: fixture.files().body)?.id == own.id)

        // Back: a job's page, the latest run, Run history and the old Manage sources go to Jobs; Jobs to the home.
        for route: MorningNavigation.Route in [.sourceJob(mail.id), .folderJob(own.id), .latestRun, .sourceRuns, .sources] {
            fixture.navigation.route = route
            fixture.files().back()
            #expect(fixture.navigation.route == .jobs, "Back from \(route)")
        }
        fixture.files().back()
        #expect(fixture.navigation.route == .folders)

        // A run opened from a job's page comes back to it; anything else forgets that.
        let runID = UUID()
        fixture.navigation.open(.sourceRun(runID: runID, sourceID: mail.id), returningTo: .sourceJob(mail.id))
        fixture.files().back()
        #expect(fixture.navigation.route == .sourceJob(mail.id))
        fixture.navigation.open(.sourceRun(runID: runID, sourceID: mail.id), returningTo: .sourceJob(mail.id))
        fixture.navigation.route = .sourceRuns
        fixture.navigation.route = .sourceRun(runID: runID, sourceID: mail.id)
        fixture.files().back()
        #expect(fixture.navigation.route == .sourceRuns)

        // Without reading jobs or jobs kept as folders there is no Jobs to go back to.
        let plain = MorningFilesView(store: fixture.morning, navigation: fixture.navigation, close: {}, filed: {}, handoff: { _ in })
        fixture.navigation.route = .latestRun
        plain.back()
        #expect(fixture.navigation.route == .folders)
        fixture.navigation.route = .jobs
        #expect(find(JobsPage.self, in: plain.body) == nil)
    }

    @Test func removingAJobOnItsPageGoesBackToJobsWhichCanUndoIt() throws {
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        let mail = mail()
        try fixture.sources.saveReadingSource(mail)
        fixture.navigation.route = .sourceJob(mail.id)
        let page = try #require(find(SourceJobPage.self, in: fixture.files().body))
        try fixture.sources.removeSource(id: mail.id)
        page.removed(mail.id)
        #expect(fixture.navigation.route == .jobs && fixture.navigation.removedJob == mail.id)
        #expect(fixture.sources.removedSources.map(\.id) == [mail.id])

        // Undo brings it back with its results; leaving Jobs forgets the Undo.
        let jobs = try #require(find(JobsPage.self, in: fixture.files().body))
        jobs.restore(mail.id)
        #expect(fixture.sources.readingSources.map(\.id) == [mail.id] && fixture.navigation.removedJob == nil)
        try fixture.sources.removeSource(id: mail.id)
        fixture.navigation.removedJob = mail.id
        fixture.navigation.route = .folders
        #expect(fixture.navigation.removedJob == nil)
    }

    // MARK: ways in

    @Test func theMenusTheChatTabAndRunNowOpenJobs() throws {
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        let mail = mail()
        try fixture.sources.saveReadingSource(mail)
        let own = try fixture.job("stuck-orders", #"{"name": "Stuck orders"}"#)

        // The panel's ⋯ menu has Jobs instead of Manage sources and Run history.
        let files = fixture.files()
        #expect(files.menuItems().map(\.title) == ["Jobs", "Create a note", "Who’s Who", "Add folder"])
        files.menuItems()[0].action()
        #expect(fixture.navigation.route == .jobs)
        let plain = MorningFilesView(store: fixture.morning, navigation: fixture.navigation, close: {}, filed: {}, handoff: { _ in })
        #expect(plain.menuItems().map(\.title) == ["Create a note", "Who’s Who", "Add folder"])

        // The menu bar's Jobs…, the chat's Open Jobs tab and its Run now tab open the panel on Jobs, or on the job.
        #expect(AppDelegate.jobsMenuTitle == "Jobs…")
        let panel = MorningPanelController(store: fixture.morning, hideFromScreenShare: true, calendarSources: fixture.sources,
                                           calendarRunner: fixture.runner, showLauncher: false, folderJobs: fixture.panel)
        defer { panel.close() }
        panel.setHiddenForForegroundGrant(true)   // nothing comes on screen in a test
        panel.showJobs()
        #expect(panel.route == .jobs)
        panel.showSourceJob(id: mail.id)
        #expect(panel.route == .sourceJob(mail.id))
        panel.showFolderJob(id: own.id)
        #expect(panel.route == .folderJob(own.id))
        panel.showJobs(trigger: .chat)
        #expect(panel.route == .jobs)

        let chat = ChatFixture()
        defer { chat.remove() }
        var opened = 0
        chat.assistant.onOpenJobs = { opened += 1 }
        #expect(Assistant.openJobsTab == "Open Jobs")
        chat.assistant.askSuggestion(Assistant.openJobsTab)
        #expect(opened == 1 && chat.assistant.transcript.isEmpty)   // never sent as a question
    }

    // MARK: a job's card

    @Test func aJobsCardsAreOneTapFromItsPageAndBackReturnsThere() throws {
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        let own = try fixture.job("sale", #"{"name": "Sale items"}"#)
        func job() throws -> Job { try #require(Jobs.list(fixture.input()).first) }
        #expect(try Jobs.cards(for: job(), fixture.input()).isEmpty && Jobs.cardLabel([]) == nil)   // no card yet: no link

        // Its preview card, job.json in its folder of the cards inbox, and the open cards its job.py wrote itself.
        try fixture.card(FolderJobCards.source(for: own), "job", #"{"title": "Sale items · 9:41 AM"}"#)
        let cardID = CardInboxFormat.cardID(FolderJobCards.key(for: own))
        #expect(try Jobs.cards(for: job(), fixture.input()).map(\.id) == [cardID])
        #expect(try Jobs.cardLabel(Jobs.cards(for: job(), fixture.input())) == "Card")
        try fixture.card(FolderJobCards.scriptSource(for: own), "follow-up", #"{"title": "Ask the seller about item 3"}"#)
        #expect(try Jobs.cards(for: job(), fixture.input()).map(\.id) == [cardID, CardInboxFormat.cardID(FolderJobCards.scriptSource(for: own) + "/follow-up")])
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("cards/inbox").appendingPathComponent(FolderJobCards.scriptSource(for: own)))
        fixture.inbox.scan()   // the one it wrote went away: it resolved, so it isn't listed

        // The Card link opens it, and Back from it returns to the job.
        fixture.navigation.route = .folderJob(own.id)
        let page = try #require(find(FolderJobPage.self, in: fixture.files().body))
        page.openCard(cardID)
        #expect(fixture.navigation.route == .card(cardID))
        fixture.files().back()
        #expect(fixture.navigation.route == .folderJob(own.id))

        // Resolved, it is still its card.
        try fixture.morning.setCardResolution(cardID: cardID, resolved: true)
        #expect(try Jobs.cardLabel(Jobs.cards(for: job(), fixture.input())) == "Card (resolved)")
    }

    @Test func aReadingJobsCardsAreOneTapFromItsPage() throws {
        let mail = mail()
        let latest = run([part(mail, .complete, items: 3, arrived: 3)])
        let older = run([part(mail, .complete, items: 1, arrived: 1)], at: now.addingTimeInterval(-86_400))
        let fromLatest = card("Sign the lease", source: mail.id, run: latest.id, updated: now.addingTimeInterval(-60))
        let fromOlder = card("Pay the bill", source: mail.id, run: older.id, updated: now)
        let done = card("Done already", source: mail.id, run: latest.id, resolved: true)
        let other = card("Someone else's", source: UUID(), run: latest.id)
        let input = Jobs.Input(readings: [mail], runs: [latest, older], cards: [fromOlder, done, other, fromLatest], now: now)
        let job = Jobs.list(input)[0]
        // Its open cards, those its latest run made first: a menu of two.
        #expect(Jobs.cards(for: job, input).map(\.title) == ["Sign the lease", "Pay the bill"])
        #expect(Jobs.cardLabel(Jobs.cards(for: job, input)) == "Cards (2)")
        #expect(Jobs.cardLabel([fromLatest]) == "Card")
    }

    @Test func aReadingJobsPageOpensItsCardAndBackReturnsThere() throws {
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        let mail = mail()
        try fixture.sources.saveReadingSource(mail)
        fixture.navigation.route = .sourceJob(mail.id)
        let page = try #require(find(SourceJobPage.self, in: fixture.files().body))
        let cardID = UUID()
        page.openCard(cardID)
        #expect(fixture.navigation.route == .card(cardID))
        fixture.files().back()
        #expect(fixture.navigation.route == .sourceJob(mail.id))
        page.openHistory()
        #expect(fixture.navigation.route == .sourceRuns)
        fixture.files().back()
        #expect(fixture.navigation.route == .sourceJob(mail.id))
    }

    // MARK: Run now and the switches

    @Test func runNowReadsAReadingJobAndRunsAJobKeptAsAFolder() async throws {
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        let mail = mail()
        try fixture.sources.saveReadingSource(mail)
        fixture.runner.readScript = { _ in
            ["mailbox": "INBOX", "arrived": 2, "items": [["key": "a@example.test", "title": "Invoice due Friday"],
                                                          ["key": "b@example.test", "title": "Lunch?"]]] as [String: Any]
        }
        func job(_ id: UUID) throws -> Job { try #require(Jobs.list(fixture.input()).first { $0.id == id }) }
        #expect(try fixture.actions.canRun(job(mail.id)))
        #expect(try fixture.actions.runNow(job(mail.id)) == nil)
        #expect(try fixture.actions.runNow(job(mail.id)) == "Another job is reading now. Run this one when it ends.")
        let deadline = Date().addingTimeInterval(10)
        while fixture.runner.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(fixture.sources.runStore.runs.first?.entries.map(\.state) == [.complete])
        #expect(try job(mail.id).lastRun.hasSuffix(" · 2 new"))

        // A job that needs review can't run until it's reviewed.
        var review = web()
        review.requiresReview = true
        try fixture.sources.saveReadingSource(review)
        #expect(try !fixture.actions.canRun(job(review.id)))

        // A job kept as a folder runs its job.py; while it runs or waits its turn, Run now waits.
        let own = try fixture.job("stuck-orders", #"{"name": "Stuck orders"}"#)
        #expect(try fixture.actions.canRun(job(own.id)))
        #expect(try fixture.actions.runNow(job(own.id)) == nil)   // started, and nothing to say
        await fixture.jobRunner.finish()
        #expect(try job(own.id).lastRun == "Last run \(JobWords.time(fixture.jobs.job(id: own.id)?.state.lastRunAt ?? now)) · Ran in the test.")
    }
}

/// Reading jobs, jobs kept as folders and a Morning store in a temp folder, with Morning Files over them. Reads go
/// through a stand-in script; a job's run only says it ran; no model is reached.
@MainActor
private final class JobsFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("jobs-page-\(UUID())")
    let morning: MorningStore
    let sources: CalendarStore
    let runner: CalendarCollectionRunner
    let jobs: FolderJobStore
    let jobRunner: FolderJobRunner
    let navigation = MorningNavigation()
    let inbox: CardInbox
    var own: URL { root.appendingPathComponent("jobs") }
    var team: URL { root.appendingPathComponent("linked/jobs") }

    init() throws {
        morning = MorningStore(directory: root.appendingPathComponent("morning"))
        sources = CalendarStore(directory: root.appendingPathComponent("sources"))
        var config = Config()
        config.allowControl = false
        let activities = NativeActivityGate()
        let tools = root.appendingPathComponent("tools")
        runner = CalendarCollectionRunner(store: sources, desktop: DesktopExecutionService(control: ComputerController(), activities: activities),
            registry: ToolRegistry(root: tools, runner: ScriptRunner(config: config)), activities: activities, config: { config },
            makeClient: { _ in StandInClient() })
        let team = root.appendingPathComponent("linked/jobs")
        jobs = FolderJobStore(directory: root.appendingPathComponent("jobs"), results: root.appendingPathComponent("job-results"),
                              teamDirectory: { team })
        jobRunner = FolderJobRunner(store: jobs, execute: { _ in "Ran in the test." })
        inbox = CardInbox(store: morning, directory: root.appendingPathComponent("cards/inbox"))
    }

    var panel: FolderJobsPanel { FolderJobsPanel(store: jobs, runner: jobRunner) }
    var actions: JobActions { JobActions(sources: sources, runner: runner, folderJobs: panel) }

    func input(now: Date = Date()) -> Jobs.Input { Jobs.Input(sources: sources, morning: morning, now: now, folderJobs: panel) }

    func files(route: MorningNavigation.Route? = nil, teach: (() -> Void)? = nil) -> MorningFilesView {
        if let route { navigation.route = route }
        return MorningFilesView(store: morning, navigation: navigation, close: {}, filed: {}, handoff: { _ in },
                                calendarSources: sources, calendarRunner: runner, teachCalendar: teach, folderJobs: panel)
    }

    /// A job's folder, yours or your team's, as found at once.
    @discardableResult
    func job(_ path: String, _ json: String, team: Bool = false) throws -> FolderJob {
        let folder = (team ? self.team : own).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try json.write(to: folder.appendingPathComponent("job.json"), atomically: true, encoding: .utf8)
        try "def run():\n    return None\n".write(to: folder.appendingPathComponent("job.py"), atomically: true, encoding: .utf8)
        jobs.refresh()
        return try #require(jobs.jobs.first { $0.path == path && $0.isTeam == team })
    }

    /// A card file in the inbox, taken in at once.
    func card(_ source: String, _ id: String, _ text: String) throws {
        let folder = root.appendingPathComponent("cards/inbox").appendingPathComponent(source)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: folder.appendingPathComponent(id + ".json"))
        inbox.scan()
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

/// An assistant with no screen, no network and no desktop: enough for its tabs.
@MainActor
private final class ChatFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("jobs-chat-\(UUID().uuidString)")
    let assistant: Assistant

    init() {
        var config = Config()
        config.apiKey = "fixture-no-network"
        config.screenshotMode = "never"
        let registry = ToolRegistry(root: root, runner: ScriptRunner(config: config))
        let root = root
        let learning = WatchLearnSession(operations: .init(
            start: { _ in }, stop: { Recording(dir: root, events: [], meta: WatchMeta(startedAt: "test", clicks: 0)) }, abandon: {},
            summarize: { _, _, _ in throw ClaudeError(message: "Not recording") }, write: { _ in [] }, reload: {}
        ))
        assistant = Assistant(config: config, watcher: ContextWatcher(), registry: registry, shell: ShellState(), learning: learning)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

/// A script job reads without the model, but a read still needs one connected.
private final class StandInClient: ConversationClient {
    var effort = "medium"
    var maxTokens = 1_024
    var maxToolRounds = 1
    var shouldStop: () -> Bool = { false }
    func converse(system: String, tools: [[String: Any]], messages: inout [[String: Any]],
                  executor: @escaping ToolExecutor, onStatus: @escaping (String) -> Void) async throws -> ClaudeReply {
        Issue.record("A script job's read asked the model.")
        return ClaudeReply(text: "", inputTokens: 0, outputTokens: 0, cacheRead: 0, toolCalls: 0)
    }
}

/// Finds a view composed inside a SwiftUI body, without GUI coordinates.
private func find<T>(_ type: T.Type, in value: Any, depth: Int = 0) -> T? {
    if let value = value as? T { return value }
    guard depth < 60 else { return nil }
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle != .class else { return nil }
    for child in mirror.children {
        if let result = find(type, in: child.value, depth: depth + 1) { return result }
    }
    return nil
}
