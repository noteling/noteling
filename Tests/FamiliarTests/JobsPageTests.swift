import AppKit
import Foundation
import Testing
import FamiliarContracts
@testable import Familiar

/// Jobs: every reading job and every watch in one list, each row's words, a job's page and its card, the home's Jobs
/// box, and every way in. Temp folders only; nothing reads a real source, runs a script or reaches a model.
@Suite @MainActor
struct JobsPageTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var time: String { WatchListWords.time(now, now: now) }
    private let red = WatchListStatus.notAsExpected([WatchListDifference(field: "price", now: .number(12), expected: .number(10))])

    private func item(_ key: String, _ status: WatchListStatus?) -> WatchListItem {
        var item = WatchListItem(key: key)
        item.status = status
        item.checkedAt = status == nil ? nil : now
        return item
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

    private func team(_ name: String, path: String, on: Bool, items: [WatchListItem] = []) -> WatchListWatch {
        var watch = WatchListWatch(name: name, check: "c", items: items, everyMinutes: 120)
        watch.source = .team
        watch.path = path
        watch.on = on
        return watch
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

    @Test func everyReadingJobAndEveryWatchIsInOneList() throws {
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        let mail = mail(), web = web(), calendar = calendar()
        try fixture.sources.saveReadingSource(mail)
        try fixture.sources.saveReadingSource(web)
        try fixture.sources.saveSource(calendar)
        let own = try fixture.add(WatchListWatch(name: "Sale items", check: "c", items: [WatchListItem(key: "1"), WatchListItem(key: "2")]))
        try fixture.place.job("holiday/oct/fashion", #"{"name": "Fashion", "items": ["F-1", "F-2", "F-3"], "every_minutes": 120}"#)
        try fixture.place.job("holiday/oct/shoes", #"{"name": "Shoes", "items": ["S-1"], "every_minutes": 60}"#)
        fixture.watches.refresh()
        let fashion = try #require(fixture.watches.watches.first { $0.name == "Fashion" })
        try fixture.watches.setOn(fashion.id, true)

        // As Manage sources and Watches listed them: every reading job (calendars and the rest) and every watch, yours
        // and your team's, on or off.
        let jobs = Jobs.list(fixture.input())
        #expect(jobs.map(\.name) == ["Morning mail", "Sale items", "School portal", "Work calendar", "Fashion", "Shoes"])
        #expect(jobs.map(\.kind) == [.mail, .watch, .web, .calendar, .teamWatch, .teamWatch])
        #expect(Set(jobs.map(\.id)) == Set([mail.id, web.id, calendar.id, own.id, fashion.id] + fixture.watches.watches.filter { $0.name == "Shoes" }.map(\.id)))
        #expect(jobs.map(\.does) == ["Reads mail", "Checks 2 items", "Reads a web page", "Reads your calendar",
                                     "Checks 3 items · from your team's tools", "Checks 1 item · from your team's tools"])
        #expect(jobs.map(\.every) == ["When you run it", "Every 15 minutes", "When you run it", "When you run it", "Every 2 hours", "Every hour"])
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
        var sale = WatchListWatch(name: "Sale items", check: "c", items: [item("1", red), item("2", .asExpected)])
        sale.lastRunAt = now
        let gift = WatchListWatch(name: "Gift guide", check: "c", items: [item("1", .asExpected)])
        let zeta = team("Zeta", path: "zeta", on: true, items: [item("Z", .couldNotCheck("Signed out"))])
        let alpha = team("Alpha", path: "alpha", on: true, items: [item("A", .asExpected)])
        let off = team("Off and red", path: "off", on: false, items: [item("O", red)])
        var input = Jobs.Input(calendars: [calendar], readings: [mail, web],
                               runs: [run([part(web, .failed, message: "The portal asked to sign in again.")])],
                               watches: [sale, gift, zeta, alpha, off], now: now)
        input.setup.missingSecrets = { $0.id == mail.id ? ["MAIL_APP_PASSWORD"] : [] }

        let jobs = Jobs.list(input)
        // A failed read, items not as expected, a secret missing and an item that couldn't be checked first (yours,
        // then the team's); then the rest of yours, then the rest of the team's, each by name. A team job that's off
        // never needs attention.
        #expect(jobs.map(\.name) == ["Morning mail", "Sale items", "School portal", "Zeta", "Gift guide", "Work calendar", "Alpha", "Off and red"])
        #expect(jobs.map(\.needsAttention) == [true, true, true, true, false, false, false, false])
        let portal = jobs.first { $0.name == "School portal" }
        #expect(portal?.runProblem == "The portal asked to sign in again." && portal?.problems == [])

        // Sorting alone: by name within each group, whatever came first.
        let a = Job(id: UUID(), kind: .mail, name: "b job", does: "", every: "", lastRun: "", status: .ready)
        let b = Job(id: UUID(), kind: .watch, name: "A job", does: "", every: "", lastRun: "", status: .ready)
        let c = Job(id: UUID(), kind: .teamWatch, name: "a team job", does: "", every: "", lastRun: "", status: .ready)
        let d = Job(id: UUID(), kind: .teamWatch, name: "z team job", does: "", every: "", lastRun: "", status: .failed, needsAttention: true)
        #expect(Jobs.sorted([c, a, d, b]).map(\.name) == ["z team job", "A job", "b job", "a team job"])
    }

    @Test func teamJobsSayWhereTheyComeFromAndShowTheirSwitch() async throws {
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        try fixture.place.job("holiday/oct/fashion", #"{"name": "Fashion", "items": ["F-1", "F-2"], "every_minutes": 120}"#)
        fixture.watches.refresh()
        var fashion = try #require(fixture.watches.watches.first)
        func job() throws -> Job { try #require(Jobs.list(fixture.input()).first { $0.id == fashion.id }) }

        // Off: what it is, and the switch, nothing to run.
        #expect(try job().status == .off && job().status.label == "Off")
        #expect(try job().does == "Checks 2 items · from your team's tools")
        #expect(try Jobs.controls(job(), canOpenSettings: true) == [.onOff])
        #expect(try !job().needsAttention)

        // The switch turns it on, as Watches' did; then it runs and has Run now.
        #expect(try fixture.actions.turn(job(), on: true) == nil)
        fashion = try #require(fixture.watches.watch(id: fashion.id))
        #expect(fashion.on)
        #expect(try Jobs.controls(job(), canOpenSettings: true) == [.runNow, .onOff])
        await fixture.watchRunner.current(fashion.id)?.value   // turning it on checks it at once

        // Paused in the team's tools: said so, and still its switch.
        let paused = team("Fashion", path: "holiday/oct/fashion", on: true)
        var pausedJob = Jobs.watchJob({ var watch = paused; watch.paused = true; return watch }(), Jobs.Input(now: now))
        #expect(pausedJob.status == .pausedByTeam && pausedJob.status.label == "Paused in the team's tools")
        #expect(Jobs.controls(pausedJob, canOpenSettings: false) == [.runNow, .onOff])

        // Yours: Pause, or Resume while paused.
        pausedJob.kind = .watch
        #expect(Jobs.controls(pausedJob, canOpenSettings: false) == [.runNow, .resume])
        pausedJob.paused = false
        #expect(Jobs.controls(pausedJob, canOpenSettings: false) == [.runNow, .pause])
        #expect(Jobs.teamIntro == "From your team's tools. Turn on the ones that are yours: only those run and tell you.")
    }

    @Test func nothingTheOldListsShowedIsLost() throws {
        // Watches: how often and when it ends, how its items stand, what's wrong with its files and what to know about
        // them, folders it can't use, and where the team's jobs come from.
        var watch = WatchListWatch(name: "Sale items", check: "c", items: [item("1", red), item("2", .couldNotCheck("Offline")),
                                                                           item("3", .asExpected), item("4", nil)])
        watch.ends = WatchListMoment.parse("2026-10-31T23:59:00")
        watch.lastRunAt = now
        watch.file = WatchListItemsFile(name: "items.psv", columns: [], rows: [], skipped: ["row 3 has no item"])
        watch.fileNote = "There are two items files; items.psv is used."
        let job = Jobs.watchJob(watch, Jobs.Input(problems: [watch.id: "Can't read watch.json: it isn't valid JSON."], now: now))
        #expect(job.every == "Every 15 minutes · Ends Sat Oct 31, 11:59 PM")
        #expect(job.lastRun == "Last run \(time) · 1 of 4 not as expected · 1 couldn't check · 1 not checked yet")
        #expect(job.resultIsProblem && job.needsAttention)
        #expect(job.problems == ["Can't read watch.json: it isn't valid JSON. Until it's fixed, the job keeps what it had."])
        #expect(job.notes == ["Items from items.psv", "Left out: row 3 has no item", "There are two items files; items.psv is used."])
        let folders = URL(fileURLWithPath: "/watches")
        #expect(Jobs.unreadable(own: ["sale": "Can't read watch.json: it isn't valid JSON."], team: ["shoes": "Not listed."], directory: folders)
                == [Jobs.Unreadable(id: "own:sale", text: "The job in the “sale” folder can't run. Can't read watch.json: it isn't valid JSON.",
                                    folder: folders.appendingPathComponent("sale")),
                    Jobs.Unreadable(id: "team:shoes", text: "Not listing your team's job shoes. Not listed.")])
        #expect(Jobs.watchHint == "To check items on a schedule, ask in chat: “watch these items: …”")
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

    @Test func aWatchsRowSaysHowItsItemsStand() {
        func job(_ items: [WatchListItem], checking: Bool = false, missing: [String] = []) -> Job {
            var watch = WatchListWatch(name: "Sale items", check: "c", items: items)
            watch.lastRunAt = items.contains { $0.status != nil } ? now : nil
            var input = Jobs.Input(watches: [watch], checking: checking ? [watch.id] : [], now: now)
            input.setup.missingWatchSecrets = { _ in missing }
            return Jobs.list(input)[0]
        }
        let eight = (1...8).map { item("\($0)", .asExpected) }
        #expect(job(eight).lastRun == "Last run \(time) · all 8 as expected")
        #expect(!job(eight).needsAttention && !job(eight).resultIsProblem)
        #expect(job([item("1", red), item("2", red), item("3", .couldNotCheck("Offline"))] + eight.prefix(5)).lastRun
                == "Last run \(time) · 2 of 8 not as expected · 1 couldn't check")
        #expect(job([item("1", .couldNotCheck("Offline"))] + eight.prefix(7)).lastRun == "Last run \(time) · couldn't check 1 of 8")
        #expect(job(Array(eight.prefix(3)) + [item("4", nil)]).lastRun == "Last run \(time) · 3 of 4 as expected · 1 not checked yet")
        #expect(job([item("1", nil)]).lastRun == "Not run yet")

        // Nothing could be checked: failed, with why.
        let failed = job([item("1", .couldNotCheck("The page took too long.")), item("2", .couldNotCheck("The page took too long."))])
        #expect(failed.status == .failed && failed.runProblem == "Couldn't check: The page took too long." && failed.needsAttention)
        #expect(job(eight, checking: true).status == .running)
        let settings = job(eight, missing: ["SHOP_TOKEN"])
        #expect(settings.status == .needsSettings && settings.problems == ["Needs SHOP_TOKEN in Settings."] && settings.needsAttention)

        // Every state has its word, and only a problem is said in red.
        let labels = [Job.Status.ready, .running, .waiting, .paused, .pausedByTeam, .off, .needsSettings, .needsReview, .cantRunYet, .failed]
        #expect(labels.map(\.label) == [nil, "Running", "Waiting to run", "Paused", "Paused in the team's tools", "Off", "Needs Settings",
                                        "Needs review", "Can't run yet", "Failed"])
        #expect(labels.filter(\.isProblem) == [.needsSettings, .needsReview, .cantRunYet, .failed])
    }

    @Test func theHomeBoxSumsTheJobsUpInOneLine() throws {
        func job(_ name: String, _ status: Job.Status = .ready, attention: Bool = false, at: Date? = nil, kind: Job.Kind = .mail) -> Job {
            Job(id: UUID(), kind: kind, name: name, does: "", every: "", lastRun: "", lastRunAt: at, status: status, needsAttention: attention)
        }
        let earlier = now.addingTimeInterval(-3_600)
        #expect(Jobs.summary([], now: now) == "No jobs yet")
        #expect(Jobs.summary([job("Off", .off, kind: .teamWatch)], now: now) == "1 team job you can turn on")
        #expect(Jobs.summary([job("A", .off, kind: .teamWatch), job("B", .off, kind: .teamWatch)], now: now) == "2 team jobs you can turn on")
        let five = [job("Mail", .failed, attention: true, at: earlier), job("Sale", attention: true, at: now), job("Calendar"),
                    job("Portal", at: earlier), job("Gifts", .paused), job("Shoes", .off, kind: .teamWatch)]
        #expect(Jobs.summary(five, now: now) == "5 jobs · 2 need attention · last run \(time)")
        #expect(Jobs.summary([job("Mail", .running), job("Sale", attention: true)], now: now) == "2 jobs · 1 running · 1 needs attention")
        #expect(Jobs.summary([job("Mail")], demonstrations: 2, now: now) == "1 job · 2 demonstrations to review")

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

    @Test func jobsRoutesHaveTitlesHeightsAndBackLeadsToJobs() throws {
        let id = UUID()
        func title(_ route: MorningNavigation.Route) -> String {
            MorningFilesView.title(for: route, folderName: { _ in nil }, jobName: { $0 == id ? "Morning mail" : nil })
        }
        #expect(title(.jobs) == "Jobs" && title(.watches) == "Jobs")
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
        let watch = try fixture.add(WatchListWatch(name: "Sale items", check: "c", items: [WatchListItem(key: "1")]))
        #expect(MorningFilesView.title(for: .sourceJob(mail.id), folderName: { _ in nil }, jobName: { _ in nil }) == "Job")
        fixture.navigation.route = .sourceJob(mail.id)
        #expect(find(SourceJobPage.self, in: fixture.files().body)?.id == mail.id)
        fixture.navigation.route = .watch(watch.id)
        #expect(find(WatchJobPage.self, in: fixture.files().body)?.id == watch.id)

        // Back: a job's page, the latest run, Run history and the old Manage sources go to Jobs; Jobs to the home.
        for route: MorningNavigation.Route in [.sourceJob(mail.id), .watch(watch.id), .latestRun, .sourceRuns, .sources] {
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

        // Without reading jobs or watches there is no Jobs to go back to.
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
        let watch = try fixture.add(WatchListWatch(name: "Sale items", check: "c", items: [WatchListItem(key: "1")]))

        // The panel's ⋯ menu has Jobs instead of Manage sources, Run history and Watches.
        let files = fixture.files()
        #expect(files.menuItems().map(\.title) == ["Jobs", "Create a note", "Who’s Who", "Add folder"])
        files.menuItems()[0].action()
        #expect(fixture.navigation.route == .jobs)
        let plain = MorningFilesView(store: fixture.morning, navigation: fixture.navigation, close: {}, filed: {}, handoff: { _ in })
        #expect(plain.menuItems().map(\.title) == ["Create a note", "Who’s Who", "Add folder"])

        // The menu bar's Jobs…, the chat's Open Jobs tab and its Run now tab open the panel on Jobs, or on the job.
        #expect(AppDelegate.jobsMenuTitle == "Jobs…")
        let panel = MorningPanelController(store: fixture.morning, hideFromScreenShare: true, calendarSources: fixture.sources,
                                           calendarRunner: fixture.runner, watches: fixture.panel, showLauncher: false)
        defer { panel.close() }
        panel.setHiddenForForegroundGrant(true)   // nothing comes on screen in a test
        panel.showJobs()
        #expect(panel.route == .jobs)
        panel.showSourceJob(id: mail.id)
        #expect(panel.route == .sourceJob(mail.id))
        panel.showWatch(id: watch.id)
        #expect(panel.route == .watch(watch.id))
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

    @Test func aWatchsCardIsOneTapFromItsPageAndBackReturnsThere() throws {
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        let watch = try fixture.add(WatchListWatch(name: "Sale items", check: "c", items: [WatchListItem(key: "1")]))
        func job() throws -> Job { try #require(Jobs.list(fixture.input()).first) }
        #expect(try Jobs.cards(for: job(), fixture.input()).isEmpty && Jobs.cardLabel([]) == nil)   // no card yet: no link

        // Its card is the one its runs write, job.json in its folder of the cards inbox; another card there isn't.
        let source = WatchListCards.source(for: watch)
        try fixture.card(source, "job", #"{"title": "Sale items: 1 of 1 not as expected"}"#)
        try fixture.card(source, "deal", #"{"title": "A deal the check found"}"#)
        let cardID = CardInboxFormat.cardID(WatchListCards.key(for: watch))
        #expect(try Jobs.cards(for: job(), fixture.input()).map(\.id) == [cardID])
        #expect(try Jobs.cardLabel(Jobs.cards(for: job(), fixture.input())) == "Card")

        // The Card link opens it, and Back from it returns to the job.
        fixture.navigation.route = .watch(watch.id)
        let page = try #require(find(WatchJobPage.self, in: fixture.files().body))
        page.openCard(cardID)
        #expect(fixture.navigation.route == .card(cardID))
        fixture.files().back()
        #expect(fixture.navigation.route == .watch(watch.id))

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

    @Test func runNowReadsAReadingJobAndChecksAWatch() async throws {
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

        // A watch's Run now is its Check now; Pause and Resume as before.
        let watch = try fixture.add(WatchListWatch(name: "Sale items", check: "c", items: [WatchListItem(key: "1")]))
        #expect(try fixture.actions.canRun(job(watch.id)))
        #expect(try fixture.actions.runNow(job(watch.id)) == nil)
        await fixture.watchRunner.current(watch.id)?.value
        #expect(fixture.watches.watch(id: watch.id)?.items.first?.status == .couldNotCheck("Not in tests."))
        #expect(try fixture.actions.setPaused(job(watch.id), true) == nil)
        #expect(fixture.watches.watch(id: watch.id)?.paused == true)
        #expect(try Jobs.controls(job(watch.id), canOpenSettings: false) == [.runNow, .resume])
    }
}

/// Reading jobs, watches and a Morning store in a temp folder, with Morning Files over them. Reads go through a stand-in
/// script; checks find nothing; no model is reached.
@MainActor
private final class JobsFixture {
    let place = Place()
    var root: URL { place.root }
    let morning: MorningStore
    let sources: CalendarStore
    let runner: CalendarCollectionRunner
    let watches: WatchListStore
    let watchRunner: WatchListRunner
    let navigation = MorningNavigation()
    let inbox: CardInbox

    init() throws {
        morning = MorningStore(directory: place.root.appendingPathComponent("morning"))
        sources = CalendarStore(directory: place.root.appendingPathComponent("sources"))
        var config = Config()
        config.allowControl = false
        let activities = NativeActivityGate()
        let tools = place.root.appendingPathComponent("tools")
        runner = CalendarCollectionRunner(store: sources, desktop: DesktopExecutionService(control: ComputerController(), activities: activities),
            registry: ToolRegistry(root: tools, runner: ScriptRunner(config: config)), activities: activities, config: { config },
            makeClient: { _ in StandInClient() })
        watches = place.store()
        watchRunner = WatchListRunner(store: watches, prepare: { _ in .unavailable("Not in tests.") })
        inbox = CardInbox(store: morning, directory: place.root.appendingPathComponent("cards/inbox"))
    }

    var panel: WatchListPanel { WatchListPanel(store: watches, runner: watchRunner, notifier: WatchListNotifier()) }
    var actions: JobActions { JobActions(sources: sources, runner: runner, watches: panel) }

    func input(now: Date = Date()) -> Jobs.Input { Jobs.Input(sources: sources, watches: panel, morning: morning, now: now) }

    func files(route: MorningNavigation.Route? = nil, teach: (() -> Void)? = nil) -> MorningFilesView {
        if let route { navigation.route = route }
        return MorningFilesView(store: morning, navigation: navigation, close: {}, filed: {}, handoff: { _ in },
                                calendarSources: sources, calendarRunner: runner, teachCalendar: teach, watches: panel)
    }

    @discardableResult
    func add(_ watch: WatchListWatch) throws -> WatchListWatch {
        try watches.add(watch)
        return try #require(watches.watch(id: watch.id))
    }

    /// A card file in the inbox, taken in at once.
    func card(_ source: String, _ id: String, _ text: String) throws {
        let folder = place.root.appendingPathComponent("cards/inbox").appendingPathComponent(source)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: folder.appendingPathComponent(id + ".json"))
        inbox.scan()
    }

    func remove() { place.remove() }
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
