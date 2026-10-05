import Foundation
import Testing
@testable import Familiar

/// The watches in Morning Files: among the jobs, each watch's page, the line on a watch's cards folder, and every way in
/// (a notification, its card, its cards folder) leading there, not to a window of their own. Temp folders only.
@Suite @MainActor
struct WatchesPageTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func item(_ key: String, _ status: WatchListStatus?) -> WatchListItem {
        var item = WatchListItem(key: key)
        item.status = status
        item.checkedAt = status == nil ? nil : now
        return item
    }

    private let red = WatchListStatus.notAsExpected([WatchListDifference(field: "price", now: .number(12), expected: .number(10))])

    // MARK: routes

    @Test func theWatchRoutesHaveTitlesHeightsAndThePanelsOneWidth() throws {
        let id = UUID()
        func title(_ route: MorningNavigation.Route) -> String {
            MorningFilesView.title(for: route, folderName: { _ in nil }, jobName: { $0 == id ? "Sale items" : nil })
        }
        #expect(title(.watches) == "Jobs")   // the old Watches route shows Jobs
        #expect(title(.watch(id)) == "Sale items")
        #expect(title(.watch(UUID())) == "Job")
        #expect(title(.sources) == "Manage sources" && title(.folders) == "A little room for your day")
        #expect(MorningPanelController.preferredHeight(for: .watches) == 680 && MorningPanelController.preferredHeight(for: .watch(id)) == 680)
        let routes: [MorningNavigation.Route] = [.folders, .folder(id), .card(id), .sources, .sourceRuns, .watches, .watch(id), .people]
        #expect(routes.allSatisfy { MorningPanelController.preferredWidth(for: $0) == 650 })
        #expect(MorningPanelController.route(afterHiding: .watch(id)) == .watch(id))

        // Back: from a watch's page to Jobs, from Jobs to the folders.
        let fixture = try PanelFixture()
        defer { fixture.remove() }
        fixture.navigation.route = .watch(id)
        fixture.files().back()
        #expect(fixture.navigation.route == .jobs)
        fixture.files().back()
        #expect(fixture.navigation.route == .folders)
    }

    @Test func morningFilesHasTheWatchPagesOnlyWhenItHasTheWatches() throws {
        let fixture = try PanelFixture()
        defer { fixture.remove() }
        let watch = try fixture.add(WatchListWatch(name: "Sale items", check: "c", items: [WatchListItem(key: "1")]))

        fixture.navigation.route = .folders
        #expect(find(JobsEntry.self, in: fixture.files().body) != nil)
        fixture.navigation.route = .watches
        #expect(find(JobsPage.self, in: fixture.files().body) != nil)
        fixture.navigation.route = .watch(watch.id)
        let page = try #require(find(WatchJobPage.self, in: fixture.files().body))
        #expect(page.id == watch.id)

        let plain = MorningFilesView(store: fixture.morning, navigation: fixture.navigation, close: {}, filed: {}, handoff: { _ in })
        #expect(find(WatchJobPage.self, in: plain.body) == nil)
        fixture.navigation.route = .folders
        #expect(find(JobsEntry.self, in: plain.body) == nil)
    }

    // MARK: how a watch stands

    @Test func theWatchesPageSaysHowEachWatchStands() throws {
        var watch = WatchListWatch(name: "Sale items", check: "c", items: [], everyMinutes: 15)
        watch.items = [item("1", .asExpected), item("2", .asExpected), item("3", .asExpected), item("4", red), item("5", red),
                       item("6", .couldNotCheck("Signed out"))]
        #expect(WatchListWords.counts(watch) == "3 as expected · 2 not as expected · 1 couldn't check")
        watch.items.append(item("7", nil))
        #expect(WatchListWords.counts(watch) == "3 as expected · 2 not as expected · 1 couldn't check · 1 not checked yet")
        #expect(WatchListWords.counts(WatchListWatch(name: "N", check: "c", items: [item("1", nil), item("2", nil)])) == "2 items")
        #expect(WatchListWords.counts(WatchListWatch(name: "N", check: "c", items: [])) == "No items")

        // How often, and its start or end.
        #expect(WatchListWords.schedule(watch, now: now) == "Every 15 minutes")
        watch.starts = WatchListMoment.parse("2026-10-05")
        watch.ends = WatchListMoment.parse("2026-10-31T23:59:00")
        let before = try #require(watch.starts?.date).addingTimeInterval(-60)
        let during = try #require(watch.starts?.date).addingTimeInterval(3_600)
        let after = try #require(watch.ends?.date).addingTimeInterval(60)
        #expect(WatchListWords.schedule(watch, now: before) == "Every 15 minutes · Starts Mon Oct 5, 12:00 AM")
        #expect(WatchListWords.schedule(watch, now: during) == "Every 15 minutes · Ends Sat Oct 31, 11:59 PM")
        #expect(WatchListWords.schedule(watch, now: after) == "Every 15 minutes · Ended Sat Oct 31, 11:59 PM")

        // When it last checked, then how it stands.
        #expect(WatchListWords.status(watch, checking: false, now: during) == "Not checked yet · " + WatchListWords.counts(watch))
        #expect(WatchListWords.status(watch, checking: true, now: during).hasPrefix("Checking now · "))
        watch.lastRunAt = during
        #expect(WatchListWords.status(watch, checking: false, now: during) == "Checked \(WatchListWords.time(during, now: during)) · "
                + WatchListWords.counts(watch))
        watch.paused = true
        #expect(WatchListWords.status(watch, checking: false, now: during).hasPrefix("Paused · "))

        // A team job: off says how many items it has; paused is the team's.
        var team = WatchListWatch(name: "Fashion", check: "c", items: [item("1", red), item("2", nil)], everyMinutes: 120)
        team.source = .team
        team.path = "holiday/oct/fashion"
        team.on = false
        #expect(WatchListWords.status(team, checking: false, now: now) == "Off · 2 items")
        team.on = true
        team.paused = true
        #expect(WatchListWords.status(team, checking: false, now: now) == "Paused in the team's tools · 1 not as expected · 1 not checked yet")
        #expect(WatchListWords.fromTeam == "From your team's tools")

        // What's wrong with its files is on its row.
        #expect(WatchListWords.problem("Can't read watch.json: it isn't valid JSON.")
                == "Can't read watch.json: it isn't valid JSON. Until it's fixed, the job keeps what it had.")
        #expect(WatchListWords.problem(nil) == nil)
    }

    // MARK: a watch's page

    @Test func aWatchsPageSaysWhatItIsAndHowItStands() throws {
        // Its page starts with the header every job's page has, made from the same job as its row in Jobs.
        var watch = WatchListWatch(name: "Sale items", check: "c", items: [item("1", .asExpected), item("2", red)], everyMinutes: 15)
        watch.lastRunAt = now
        let job = Jobs.watchJob(watch, Jobs.Input(watches: [watch], now: now))
        #expect(job.line == "Checks 2 items · Every 15 minutes")
        #expect(job.lastRun == "Last run \(WatchListWords.time(now, now: now)) · 1 of 2 not as expected")

        var team = WatchListWatch(name: "Fashion", check: "c", items: [item("1", nil), item("2", nil)], everyMinutes: 120)
        team.source = .team
        team.path = "holiday/oct/fashion"
        team.on = false
        team.ends = WatchListMoment.parse("2026-10-31T23:59:00")
        let during = try #require(team.ends?.date).addingTimeInterval(-3_600)
        let teamJob = Jobs.watchJob(team, Jobs.Input(watches: [team], now: during))
        #expect(teamJob.path == "holiday/oct/fashion")
        #expect(teamJob.line == "Checks 2 items · from your team's tools · Every 2 hours · Ends Sat Oct 31, 11:59 PM")
        #expect(teamJob.lastRun == "Not run yet" && teamJob.status == .off)

        // Check now: a watch of your own between its start and end, even paused; a team job only while it's on and running.
        #expect(WatchListWords.canCheckNow(watch, checking: false, now: now))
        #expect(!WatchListWords.canCheckNow(watch, checking: true, now: now))
        watch.paused = true
        #expect(WatchListWords.canCheckNow(watch, checking: false, now: now))
        watch.starts = WatchListMoment.parse("2099-01-01")
        #expect(!WatchListWords.canCheckNow(watch, checking: false, now: now))
        #expect(!WatchListWords.canCheckNow(team, checking: false, now: during))
        team.on = true
        #expect(WatchListWords.canCheckNow(team, checking: false, now: during))
    }

    @Test func aWatchsCardsAreOneTapFromItsPage() throws {
        let fixture = try PanelFixture()
        defer { fixture.remove() }
        let watch = try fixture.add(WatchListWatch(name: "Sale items", check: "c", items: [WatchListItem(key: "1")]))
        #expect(WatchListWords.cardsLink(for: watch, folders: fixture.morning.folders, cards: fixture.morning.cards) == nil)   // no card yet

        let key = WatchListCards.key(for: watch)
        let source = String(key.split(separator: "/")[0])
        try fixture.card(source, "job", #"{"title": "Sale items: 1 of 1 not as expected"}"#)
        try fixture.card(source, "deal", #"{"title": "A deal the check found"}"#)
        let folderID = CardInboxFormat.folderID(source)
        func link() -> WatchCardsLink? { WatchListWords.cardsLink(for: watch, folders: fixture.morning.folders, cards: fixture.morning.cards) }
        #expect(link() == WatchCardsLink(folderID: folderID, open: 2, disposition: .unreviewed))
        #expect(link()?.label == "Cards folder (2)")

        try fixture.morning.setDisposition(cardID: CardInboxFormat.cardID(key), to: .mine)
        try fixture.morning.setCardResolution(cardID: CardInboxFormat.cardID(source + "/deal"), resolved: true)
        #expect(link() == WatchCardsLink(folderID: folderID, open: 1, disposition: .mine))
        try fixture.morning.setCardResolution(cardID: CardInboxFormat.cardID(key), resolved: true)
        #expect(link() == WatchCardsLink(folderID: folderID, open: 0, disposition: .resolved))
    }

    @Test func aWatchsCardsFolderLeadsBackToItsPageAndNoOtherFolderDoes() throws {
        let fixture = try PanelFixture()
        defer { fixture.remove() }
        var watch = try fixture.add(WatchListWatch(name: "Sale items", check: "c", items: [WatchListItem(key: "1")]))
        let source = WatchListCards.source(for: watch)
        try fixture.card(source, "job", #"{"title": "Sale items: 1 of 1 not as expected"}"#)
        try fixture.card("pack-shop", "order-1", #"{"title": "Refund ready"}"#)

        fixture.navigation.route = .folder(CardInboxFormat.folderID(source))
        let line = try #require(find(WatchCardsFolderLine.self, in: fixture.files().body))
        #expect(line.watchID == watch.id)
        line.openJob()
        #expect(fixture.navigation.route == .watch(watch.id))
        fixture.files().back()
        #expect(fixture.navigation.route == .folder(CardInboxFormat.folderID(source)), "Back from its job comes back to its cards.")
        fixture.navigation.route = .folder(CardInboxFormat.folderID("pack-shop"))
        #expect(find(WatchCardsFolderLine.self, in: fixture.files().body) == nil)
        fixture.navigation.route = .folder(try #require(fixture.morning.folders.first).id)
        #expect(find(WatchCardsFolderLine.self, in: fixture.files().body) == nil)
        #expect(WatchListWords.watch(forFolder: CardInboxFormat.folderID(source), in: fixture.watches.watches)?.id == watch.id)
        #expect(WatchListWords.watch(forFolder: CardInboxFormat.folderID("pack-shop"), in: fixture.watches.watches) == nil)

        // "Checked 6:31 PM · every 15 minutes", then Run now and Open job.
        #expect(WatchListWords.cardsFolderLine(watch, checking: false, now: now) == "Not checked yet · every 15 minutes")
        watch.lastRunAt = now
        #expect(WatchListWords.cardsFolderLine(watch, checking: false, now: now) == "Checked \(WatchListWords.time(now, now: now)) · every 15 minutes")
        #expect(WatchListWords.cardsFolderLine(watch, checking: true, now: now) == "Checking now · every 15 minutes")
    }

    // MARK: ways in

    @Test func aNotificationOpensItsWatchsPageOrJobsOnceItIsGone() throws {
        let place = Place()
        defer { place.remove() }
        let registry = ToolRegistry(root: place.root.appendingPathComponent("tools"), runner: ScriptRunner(config: Config()))
        let feature = WatchListFeature(registry: registry, store: place.store())
        var opened: [String] = []
        feature.showJobs = { opened.append("Jobs") }
        feature.showWatch = { opened.append("page \(feature.store.watch(id: $0)?.name ?? "?")") }
        feature.explain = { opened.append("explain \(feature.store.watch(id: $0)?.name ?? "?") \($1)") }
        let watch = WatchListWatch(name: "Sale items", check: "c", items: [WatchListItem(key: "1"), WatchListItem(key: "2")])
        try feature.store.add(watch)
        try feature.store.change(watch.id, persist: false) { $0.items = [item("1", red), item("2", .asExpected)] }

        feature.openNotification(watchID: watch.id, key: "1")           // still red: the chat explains it
        feature.openNotification(watchID: watch.id, key: "2")           // back to as expected: its watch's page
        feature.openNotification(watchID: watch.id, key: "")            // about several items: its watch's page
        feature.openNotification(watchID: UUID(), key: "1")             // a watch that's gone: Jobs
        feature.panel.why(watch.id, "1")                                // Why? on an item's row
        #expect(opened == ["explain Sale items 1", "page Sale items", "page Sale items", "Jobs", "explain Sale items 1"])
    }
}

/// A watch list and a Morning store in temp folders, and Morning Files over them.
@MainActor
private final class PanelFixture {
    let place = Place()
    let watches: WatchListStore
    let runner: WatchListRunner
    let morning: MorningStore
    let navigation = MorningNavigation()
    let inbox: CardInbox

    init() throws {
        watches = place.store()
        runner = WatchListRunner(store: watches, prepare: { _ in .unavailable("Not in tests.") })
        morning = MorningStore(directory: place.root.appendingPathComponent("morning"))
        inbox = CardInbox(store: morning, directory: place.root.appendingPathComponent("cards/inbox"))
    }

    func files() -> MorningFilesView {
        MorningFilesView(store: morning, navigation: navigation, close: {}, filed: {}, handoff: { _ in },
                         watches: WatchListPanel(store: watches, runner: runner, notifier: WatchListNotifier()))
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
