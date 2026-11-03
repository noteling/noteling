import AppKit
import SwiftUI

/// Jobs, from fictional reading jobs and jobs kept as folders: the home's Jobs box, the list with every kind and state
/// (a mail job that made cards, a web job whose last run failed, a calendar not run yet, a job that needs review and
/// one that needs a secret in Settings; a job of yours whose last run failed, a team job that's on and found something
/// and one that's off), the team jobs before their start and past their end, under their line and shown, with an
/// ended job's page and its card put away, a team job's page, and reading jobs' pages. Nothing reads a real source,
/// runs a script or reaches a provider.
extension MorningRender {
    @MainActor static func renderJobs(fixtures: URL, directory: URL) throws {
        let root = fixtures.appendingPathComponent("jobs")
        let store = MorningStore(directory: root.appendingPathComponent("morning"))
        let sources = CalendarStore(directory: root.appendingPathComponent("sources"))
        let config = Config(), activities = NativeActivityGate()
        let runner = CalendarCollectionRunner(store: sources, desktop: DesktopExecutionService(control: ComputerController(), activities: activities),
            registry: ToolRegistry(root: root.appendingPathComponent("tools"), runner: ScriptRunner(config: config)),
            activities: activities, config: { config }, makeClient: { _ in nil })
        let ran = Date().addingTimeInterval(-25 * 60)

        // Reading jobs.
        let mail = LearnedReadingSource(kind: .mail, name: "Morning mail", meaning: "What came in overnight · fictional example",
            application: "Mail over IMAP", account: "alex@example.com", scope: "Everything that arrived. Skip newsletters and receipts.",
            script: "imap-mail__today")
        let bank = LearnedReadingSource(kind: .mail, name: "Bank alerts", meaning: "Payments and statements · fictional example",
            application: "Mail over IMAP", scope: "Messages from the bank only.", script: "bank-mail__today")
        let portal = LearnedReadingSource(kind: .web, name: "School portal", meaning: "Notes from my kid’s class · fictional example",
            application: "Safari", url: "https://school.example.test/announcements", scope: "New announcements on the first page.")
        var review = portal
        review.id = UUID()
        review.name = "Saved inbox reading"
        review.meaning = "A demonstration recovered from an earlier version · fictional example"
        review.requiresReview = true
        let calendar = LearnedCalendarSource(name: "Work calendar", meaning: "My meetings · fictional example", application: "Calendar",
            account: "alex@example.com", calendarName: "Work", timeZoneID: TimeZone.current.identifier)
        for source in [mail, bank, portal, review] { try sources.saveReadingSource(source) }
        try sources.saveSource(calendar)

        // Morning mail read 12 messages and three became cards; the portal's last run failed.
        let messages = [("lease", "Lease renewal: sign by Friday", "Dana Ruiz"), ("trip", "Field trip form due Wednesday", "Ms. Park"),
                        ("dentist", "Your cleaning moved to 3 PM", "Dr. Lee’s office")]
            + (1...9).map { ("news-\($0)", "Weekly newsletter \($0)", "Example News") }
        let request = ReadingReadRequest(source: mail, requestedAt: ran)
        var read = SourceRunEntry(reading: request, state: .complete, message: "Saved 12 items.")
        read.startedAt = ran
        read.finishedAt = ran.addingTimeInterval(4)
        read.readingSnapshot = ReadingSnapshot(requestID: request.id, sourceID: mail.id, source: mail, collectedAt: read.finishedAt!,
            items: messages.map { key, title, from in
                ReadingItem(id: ObservedItemIdentity.id(sourceID: mail.id, key: key + "@example.test"), title: title,
                            text: "From \(from) · unread\nA fictional message.", evidence: "Read through imap-mail__today",
                            identityKey: key + "@example.test", identityEvidence: "Message-ID \(key)@example.test")
            }, coverage: .complete, accountEvidence: "Signed in as alex@example.com", sourceEvidence: "INBOX",
            scopeEvidence: "Everything since yesterday: 12 messages", summary: "Read all 12 messages that arrived in INBOX since yesterday.",
            scriptRead: ScriptReadCounts(arrived: 12, returned: 12, truncated: false))
        let mailRun = try sources.runStore.begin(entries: [read], origin: .single, startedAt: ran)
        try sources.runStore.finish(runID: mailRun.id, status: .completed, finishedAt: ran.addingTimeInterval(5))
        var failed = SourceRunEntry(reading: ReadingReadRequest(source: portal, requestedAt: ran), state: .failed,
            message: "The portal asked to sign in again. No new findings were saved in this run.")
        failed.startedAt = ran.addingTimeInterval(-3_600)
        failed.finishedAt = ran.addingTimeInterval(-3_590)
        let portalRun = try sources.runStore.begin(entries: [failed], origin: .single, startedAt: ran.addingTimeInterval(-3_600))
        try sources.runStore.finish(runID: portalRun.id, status: .failed, finishedAt: ran.addingTimeInterval(-3_590))
        let observations = messages.prefix(3).map { key, title, from in
            CardObservation(runID: mailRun.id, sourceID: mail.id, itemKey: key + "@example.test", sourceName: mail.name, kind: "mail",
                            title: title, excerpt: "From \(from). A fictional message.", url: "", identityEvidence: "Message-ID \(key)@example.test",
                            observedAt: ran, state: .open, stateEvidence: "Still waiting for you.")
        }
        let proposals = zip(observations, ["Dana needs the signed lease by Friday", "Sign the field trip form by Wednesday",
                                           "Dr. Lee moved your cleaning to 3 PM"]).map { observation, title in
            CardProposal(observationKey: observation.id, title: title, meaning: "A fictional card made from this morning’s mail.",
                         action: MorningAction(title: "Draft a reply", instruction: "Draft a short reply. Do not send it.", mode: .prepare))
        }
        try store.applyCardGeneration(observations: observations, proposals: proposals, runIDs: [mailRun.id], at: ran.addingTimeInterval(30))

        // Jobs kept as folders: one of yours that failed, and your team's: one on that found something, one off, one
        // that ended three days ago (its card was there until then), and one that starts in five days.
        let iso = ISO8601DateFormatter()
        let endedAt = iso.string(from: ran.addingTimeInterval(-3 * 86_400)), startsAt = iso.string(from: ran.addingTimeInterval(5 * 86_400))
        let ownJobs = root.appendingPathComponent("jobs"), team = root.appendingPathComponent("team-tools/jobs")
        for (folder, json) in [
            (team.appendingPathComponent("holiday/oct/fashion"), #"{"name": "Fashion (fictional)", "about": "Prices and badges on the fashion event items.", "every_minutes": 120, "ends": "2026-10-31T23:59:00"}"#),
            (team.appendingPathComponent("kitchen"), #"{"name": "Kitchen (fictional)", "about": "Prices on the kitchen items.", "every_minutes": 60}"#),
            (team.appendingPathComponent("autumn/sale"), #"{"name": "Autumn sale (fictional)", "about": "Prices on the autumn sale items.", "every_minutes": 60, "ends": "\#(endedAt)"}"#),
            (team.appendingPathComponent("winter/launch"), #"{"name": "Winter launch (fictional)", "about": "Badges on the winter launch items.", "every_minutes": 30, "starts": "\#(startsAt)"}"#),
            (ownJobs.appendingPathComponent("stuck-orders"), #"{"name": "Stuck orders (fictional)", "about": "Orders waiting on me for more than a day.", "every_minutes": 240}"#),
        ] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try json.write(to: folder.appendingPathComponent("job.json"), atomically: true, encoding: .utf8)
            try "def run():\n    return None\n".write(to: folder.appendingPathComponent("job.py"), atomically: true, encoding: .utf8)
        }
        let jobStore = FolderJobStore(directory: ownJobs, results: root.appendingPathComponent("job-results"), teamDirectory: { team })
        let jobRunner = FolderJobRunner(store: jobStore, execute: { _ in NSNull() })
        guard let kitchen = jobStore.jobs.first(where: { $0.path == "kitchen" }), let autumn = jobStore.jobs.first(where: { $0.path == "autumn/sale" }),
              let stuck = jobStore.jobs.first(where: { $0.path == "stuck-orders" }) else { return }
        let before = ran.addingTimeInterval(-4 * 86_400)
        func found(_ job: FolderJob, at: Date, said: String, rows: String) throws {
            let preview = jobStore.output(for: job).appendingPathComponent("preview")
            try FileManager.default.createDirectory(at: preview, withIntermediateDirectories: true)
            try rows.write(to: preview.appendingPathComponent("problems.csv"), atomically: true, encoding: .utf8)
            try jobStore.record(job.id, FolderJobState(lastRunAt: at, lastSuccessAt: at, said: said,
                                                       preview: FolderJobFiles.previewDigest(output: jobStore.output(for: job))))
        }
        try jobStore.setOn(kitchen.id, true)
        try found(kitchen, at: ran, said: "1 of 2 items needs a look", rows: "item,what's wrong\nK-1,price shows 12 – expected 9\n")
        try jobStore.setOn(autumn.id, true)
        try found(autumn, at: before, said: "1 of 3 items needs a look", rows: "item,what's wrong\nA-1,price shows 24 – expected 19\n")
        try jobStore.record(stuck.id, FolderJobState(lastRunAt: ran.addingTimeInterval(-3_600), error: "The orders service asked to sign in again."))
        let inboxFolder = root.appendingPathComponent("cards-inbox")
        let cards = FolderJobCards(root: inboxFolder)
        let inbox = CardInbox(store: store, directory: inboxFolder)
        inbox.folderName = { source in jobStore.jobs.first { FolderJobCards.source(for: $0) == source }?.name }
        cards.reconcile(jobStore.jobs, at: before)
        inbox.scan(at: before)
        cards.reconcile(jobStore.jobs)
        inbox.scan()

        let panel = FolderJobsPanel(store: jobStore, runner: jobRunner, notifier: JobNotifier())
        let setup = JobsSetup(missingSecrets: { $0.id == bank.id ? ["BANK_MAIL_PASSWORD"] : [] }, openSettings: {})
        let navigation = MorningNavigation()
        func save(_ name: String, _ route: MorningNavigation.Route, height: CGFloat? = nil) throws {
            navigation.route = route
            try image(MorningFilesView(store: store, navigation: navigation, close: {}, filed: {}, handoff: { _ in },
                                       calendarSources: sources, calendarRunner: runner, discussCard: { _ in },
                                       askAboutCard: { _, _ in }, jobs: setup, folderJobs: panel),
                      size: NSSize(width: MorningPanelController.preferredWidth(for: route),
                                   height: height ?? MorningPanelController.preferredHeight(for: route, isEmpty: false)),
                      to: directory.appendingPathComponent(name))
        }
        try save("jobs-home.png", .folders)
        try save("jobs.png", .jobs)
        try save("jobs-all.png", .jobs, height: 1_400)
        try save("job-team.png", .folderJob(kitchen.id))
        try save("job-ended.png", .folderJob(autumn.id))
        if let winter = jobStore.jobs.first(where: { $0.path == "winter/launch" }) { try save("job-upcoming.png", .folderJob(winter.id)) }
        let putAway = CardInboxFormat.cardID(FolderJobCards.key(for: autumn))
        if store.cards.contains(where: { $0.id == putAway }) { try save("card-put-away.png", .card(putAway)) }
        try image(JobsPage(morning: store, sources: sources, runner: runner, setup: setup, navigation: navigation,
                           showingOutside: true, folderJobs: panel)
            .foregroundStyle(Pad.ink).background(Pad.fieldPaper), size: NSSize(width: 650, height: 1_700),
            to: directory.appendingPathComponent("jobs-outside-shown.png"))
        try save("job-mail.png", .sourceJob(mail.id))
        try save("job-mail-all.png", .sourceJob(mail.id), height: 1_300)
        try save("job-failed.png", .sourceJob(portal.id))
        try save("job-calendar.png", .sourceJob(calendar.id))
        try save("job-needs-review.png", .sourceJob(review.id))
        try save("job-needs-settings.png", .sourceJob(bank.id))
        // Edit on a reading job's page: its editor, in place of its definition and results.
        try image(SourceJobPage(store: sources, runner: runner, morning: store, id: mail.id, setup: setup, openCard: { _ in },
                                openRun: { _, _ in }, openHistory: {}, removed: { _ in }, editing: true)
            .foregroundStyle(Pad.ink).background(Pad.fieldPaper), size: NSSize(width: 650, height: 1_200),
            to: directory.appendingPathComponent("job-editing.png"))
    }
}
