import AppKit
import SwiftUI

/// Jobs, from fictional reading jobs and watches: the home's Jobs box, the list with every kind and state (a mail job
/// that made cards, a web job whose last run failed, a calendar not run yet, a job that needs review and one that needs
/// a secret in Settings; a watch with items not as expected, a paused one, a team job that's on and one that's off),
/// a watch's page, and reading jobs' pages. Nothing reads a real source, runs a script or reaches a provider.
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

        // Watches: yours, and your team's.
        let team = root.appendingPathComponent("team-tools/watches")
        for (path, json) in [("holiday/oct/fashion", #"{"name": "Fashion (fictional)", "items": ["F-1", "F-2", "F-3"], "every_minutes": 120, "ends": "2026-10-31T23:59:00"}"#),
                             ("kitchen", #"{"name": "Kitchen (fictional)", "items": ["K-1", "K-2"], "every_minutes": 60}"#)] {
            try FileManager.default.createDirectory(at: team.appendingPathComponent(path), withIntermediateDirectories: true)
            try json.write(to: team.appendingPathComponent(path).appendingPathComponent("watch.json"), atomically: true, encoding: .utf8)
        }
        let watches = WatchListStore(directory: root.appendingPathComponent("watches"), legacyFile: nil,
                                     teamResults: root.appendingPathComponent("team-results"), teamDirectory: { team })
        let checks = WatchListRunner(store: watches, prepare: { _ in .unavailable("Not checked in the render.") })
        func item(_ key: String, _ title: String, price: Double, expected: Double) -> WatchListItem {
            var item = WatchListItem(key: key, expect: ["price": .number(expected)])
            item.title = title
            item.url = "https://shop.example.com/item/\(key)"
            item.state = ["price": .number(price)]
            item.checkedAt = ran
            item.status = price == expected ? .asExpected
                : .notAsExpected([WatchListDifference(field: "price", now: .number(price), expected: .number(expected))])
            return item
        }
        try watches.add(WatchListWatch(name: "Sale items", check: "shop__watch_item", items: ["123", "456", "789", "790"].map { WatchListItem(key: $0) }))
        try watches.add(WatchListWatch(name: "Gift guide", check: "shop__watch_item", items: ["G-1", "G-2"].map { WatchListItem(key: $0) },
                                       everyMinutes: 60, paused: true))
        guard let sale = watches.watches.first(where: { $0.name == "Sale items" }),
              let kitchen = watches.watches.first(where: { $0.path == "kitchen" }) else { return }
        try watches.change(sale.id, persist: false) { watch in
            watch.items = [item("123", "Blue kettle (fictional)", price: 12, expected: 10), item("456", "Red mug (fictional)", price: 8, expected: 8),
                           item("789", "Tea towel (fictional)", price: 5, expected: 5)]
            var grey = WatchListItem(key: "790")
            grey.checkedAt = ran
            grey.status = .couldNotCheck("The page took longer than 60 seconds.")
            watch.items.append(grey)
            watch.lastRunAt = ran
        }
        try watches.setOn(kitchen.id, true)
        try watches.change(kitchen.id, persist: false) { watch in   // what its checks found; its definition is the team's
            for (index, title) in zip(watch.items.indices, ["Bread tin (fictional)", "Teapot (fictional)"]) {
                watch.items[index].title = title
                watch.items[index].state = ["price": .number(9)]
                watch.items[index].status = .asExpected
                watch.items[index].checkedAt = ran
            }
            watch.lastRunAt = ran
        }
        let inboxFolder = root.appendingPathComponent("cards-inbox")
        WatchListCards(root: inboxFolder).reconcile(watches.watches)
        let inbox = CardInbox(store: store, directory: inboxFolder)
        inbox.folderName = { source in watches.watches.first { WatchListCards.source(for: $0) == source }?.name }
        inbox.scan()

        let panel = WatchListPanel(store: watches, runner: checks, notifier: WatchListNotifier())
        let setup = JobsSetup(missingSecrets: { $0.id == bank.id ? ["BANK_MAIL_PASSWORD"] : [] }, openSettings: {})
        let navigation = MorningNavigation()
        func save(_ name: String, _ route: MorningNavigation.Route, height: CGFloat? = nil) throws {
            navigation.route = route
            try image(MorningFilesView(store: store, navigation: navigation, close: {}, filed: {}, handoff: { _ in },
                                       calendarSources: sources, calendarRunner: runner, teachCalendar: {}, discussCard: { _ in },
                                       askAboutCard: { _, _ in }, watches: panel, jobs: setup),
                      size: NSSize(width: MorningPanelController.preferredWidth(for: route),
                                   height: height ?? MorningPanelController.preferredHeight(for: route, isEmpty: false)),
                      to: directory.appendingPathComponent(name))
        }
        try save("jobs-home.png", .folders)
        try save("jobs.png", .jobs)
        try save("jobs-all.png", .jobs, height: 1_400)
        try save("job-watch.png", .watch(sale.id))
        try save("job-team-watch.png", .watch(kitchen.id))
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
