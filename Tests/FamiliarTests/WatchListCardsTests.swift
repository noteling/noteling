import Foundation
import Testing
@testable import Familiar

/// A watch's items as cards, through the cards inbox: a red or grey item gets a file right after the check that found
/// it, saying what the notification says, the check's why, every field and which check; the file goes when the item is
/// back to as expected. `"cards": "all"` gives every item one, `"cards": false` none, and a team job that's off has
/// none. The checks are fakes: no Python, no network; temp folders only.
@Suite @MainActor
struct WatchListCardsTests {
    private let checked = Date(timeIntervalSince1970: 1_790_000_000)

    /// A kettle that cost 10 and costs 12 now, as its check found it.
    private func kettle(_ status: WatchListStatus?) -> WatchListItem {
        var item = WatchListItem(key: "123", expect: ["price": .number(10)])
        item.title = "Blue kettle"
        item.url = "https://shop.example.com/item/123"
        item.state = ["price": .number(12), "badge": .text("Deal"), "in_stock": .flag(true)]
        item.why = ["The sale price ended early.", "It may come back on Friday."]
        item.facts = #"{"seller":"Acme"}"#
        item.checkedAt = checked
        item.status = status
        return item
    }

    private let differences = [WatchListDifference(field: "price", now: .number(12), expected: .number(10))]

    @Test func aRedItemsCardSaysWhatTheNotificationSaysThenWhyEveryFieldAndTheCheck() throws {
        let item = kettle(.notAsExpected(differences))
        let watch = WatchListWatch(name: "Sale items", check: "shop__watch_item", items: [item])

        let card = try #require(WatchListCards.card(for: item, in: watch, checkedBy: "shop__watch_item"))

        #expect(card["title"] as? String == "Not as expected · Blue kettle")
        #expect(card["severity"] as? String == "high")
        #expect(card["body"] as? String == """
        Price: 12 — expected 10
        The sale price ended early.
        It may come back on Friday.
        badge: Deal
        in_stock: yes
        price: 12
        Checked \(WatchListCards.time(checked)) by shop__watch_item
        """)
        let alert = WatchListAlert(watchID: watch.id, watchName: watch.name, itemKey: item.key, title: item.label,
                                   kind: .notAsExpected(differences), why: item.whyNow)
        #expect(alert.body.hasPrefix("Price: 12 — expected 10\n"))   // the same difference line as the notification
        #expect(card["url"] as? String == "https://shop.example.com/item/123")
        #expect(card["details"] as? String == #"{"seller":"Acme"}"#)
        #expect(WatchListCards.time(checked, in: try #require(TimeZone(identifier: "UTC"))) == "Sep 21, 2:13 PM")

        // As the inbox reads it: Open page and Why?, which asks what a notification's Why? asks.
        let file = Data(JSONText.pretty(card, indent: "").utf8)
        let entry = try CardInboxFormat.parse(file, source: "watch-sale-items", id: "item-123", modifiedAt: checked)
        #expect(entry.title == "Not as expected · Blue kettle" && entry.severity == "high" && entry.details == #"{"seller":"Acme"}"#)
        #expect(entry.actions == [CardInboxAction(label: "Open page", url: "https://shop.example.com/item/123"),
                                  CardInboxAction(label: "Why?", ask: "Why is “Blue kettle” not as expected?")])
    }

    @Test func aGreyItemGetsACardAndAGreenOrUncheckedOneNone() throws {
        let watch = WatchListWatch(name: "Sale items", check: "shop__watch_item", items: [])
        let grey = kettle(.couldNotCheck("It took longer than 60 seconds."))

        let card = try #require(WatchListCards.card(for: grey, in: watch, checkedBy: "its own check.py"))

        #expect(card["title"] as? String == "Couldn't check · Blue kettle")
        #expect(card["severity"] as? String == "normal")
        #expect(card["body"] as? String == "Couldn't check: It took longer than 60 seconds.\nChecked \(WatchListCards.time(checked)) by its own check.py")
        #expect(card["details"] == nil)   // the facts are from an earlier check
        #expect((card["actions"] as? [[String: Any]])?.compactMap { $0["label"] as? String } == ["Open page", "Why?"])
        #expect(WatchListCards.card(for: kettle(.asExpected), in: watch, checkedBy: "x") == nil)
        #expect(WatchListCards.card(for: kettle(nil), in: watch, checkedBy: "x") == nil)
        var never = kettle(.notAsExpected(differences))
        never.checkedAt = nil
        #expect(WatchListCards.card(for: never, in: watch, checkedBy: "x") == nil)
    }

    @Test func cardsAllGivesEveryItemACardAndFalseNone() throws {
        var watch = WatchListWatch(name: "Sale items", check: "shop__watch_item", items: [])
        watch.cards = .all
        let green = try #require(WatchListCards.card(for: kettle(.asExpected), in: watch, checkedBy: "shop__watch_item"))
        #expect(green["title"] as? String == "As expected · Blue kettle")
        #expect(green["severity"] as? String == "low")
        #expect((green["body"] as? String)?.hasPrefix("As expected\nThe sale price ended early.\n") == true)
        #expect((green["actions"] as? [[String: Any]])?.compactMap { $0["label"] as? String } == ["Open page"])   // nothing to explain

        watch.cards = .off
        #expect(WatchListCards.card(for: kettle(.notAsExpected(differences)), in: watch, checkedBy: "x") == nil)

        // In watch.json: "all", false, or true for the default; anything else is said.
        func cards(_ value: String) throws -> WatchListCardsMode {
            try WatchListFiles.parseDefinition(Data(#"{"items": ["1"], "cards": \#(value)}"#.utf8), folder: "sale", created: checked).definition.cards
        }
        #expect(try cards(#""all""#) == .all && cards("false") == .off && cards("true") == .problems && cards("null") == .problems)
        #expect(throws: WatchListError(#"cards must be true, false or "all"."#)) { try cards(#""often""#) }
        var definition = try WatchListFiles.parseDefinition(Data(#"{"items": ["1"], "cards": "all"}"#.utf8), folder: "sale", created: checked).definition
        #expect(WatchListFiles.definitionText(definition).contains(#""cards": "all""#))
        definition.cards = .off
        #expect(WatchListFiles.definitionText(definition).contains(#""cards": false"#))
        definition.cards = .problems
        #expect(!WatchListFiles.definitionText(definition).contains("cards"))
    }

    // MARK: with the runner

    @Test func aChecksCardIsWrittenRightAfterItAndDeletedWhenTheItemIsBackToExpected() async throws {
        let fixture = try CardsFixture()
        defer { fixture.remove() }
        let watch = WatchListWatch(name: "Sale items", check: "shop__watch_item",
                                   items: ["1", "2"].map { WatchListItem(key: $0, expect: ["price": .number(10)]) })
        try fixture.store.add(watch)
        fixture.checks.next["1"] = [fixture.checks.reading(price: 12, key: "1")]

        await fixture.runner.run(watch.id)?.value

        let folder = fixture.inbox.appendingPathComponent("watch-sale-items")
        let one = folder.appendingPathComponent(WatchListCards.fileName(for: "1"))
        let listed = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(listed == [one.lastPathComponent])
        #expect(fixture.changes == 1)
        #expect(try FileManager.default.attributesOfItem(atPath: one.path)[.posixPermissions] as? Int == 0o600)
        let morning = MorningStore(directory: fixture.place.root.appendingPathComponent("morning"))
        let inbox = CardInbox(store: morning, directory: fixture.inbox)
        inbox.folderName = { source in fixture.store.watches.first { WatchListCards.source(for: $0) == source }?.name }
        inbox.scan()
        let card = try #require(morning.cards.first)
        #expect(card.title == "Not as expected · Item 1" && card.inbox?.severity == "high")
        #expect(card.meaning.hasPrefix("Price: 12 — expected 10\nprice: 12\nChecked "))
        #expect(card.sources.map(\.title) == ["Not as expected · Item 1", "Details"] && card.sources[1].excerpt == #"{"seller":"Acme"}"#)
        #expect(morning.folders.first { $0.id == card.folderID }?.name == "Sale items")

        // The same again: nothing to write. Back to as expected: its file goes, and so does its card.
        fixture.checks.next["1"] = [fixture.checks.reading(price: 12, key: "1")]
        await fixture.runner.run(watch.id)?.value
        #expect(fixture.changes == 1)
        await fixture.runner.run(watch.id)?.value
        #expect(!FileManager.default.fileExists(atPath: one.path))
        #expect(fixture.changes == 2)
        inbox.scan()
        #expect(morning.cards.first?.disposition == .resolved && morning.cards.first?.inbox?.goneAt != nil)

        // A watch that's gone has no cards, and a script's own files beside them are left alone.
        fixture.checks.next["2"] = [.failed("Gone from the shop")]
        await fixture.runner.run(watch.id)?.value
        let two = folder.appendingPathComponent(WatchListCards.fileName(for: "2"))
        #expect(FileManager.default.fileExists(atPath: two.path))
        try Data(#"{"title": "A deal the check found"}"#.utf8).write(to: folder.appendingPathComponent("deal-9.json"))
        try fixture.store.remove(watch.id)
        fixture.runner.tick()
        #expect(!FileManager.default.fileExists(atPath: two.path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("deal-9.json").path))
    }

    @Test func cardsLeftFromBeforeAreTidiedAtLaunch() async throws {
        let fixture = try CardsFixture()
        defer { fixture.remove() }
        let watch = WatchListWatch(name: "Sale items", check: "shop__watch_item", items: [WatchListItem(key: "1", expect: ["price": .number(10)])])
        try fixture.store.add(watch)
        let folder = fixture.inbox.appendingPathComponent("watch-sale-items")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stale = folder.appendingPathComponent(WatchListCards.fileName(for: "old"))
        try Data(#"{"title": "Not as expected · Old"}"#.utf8).write(to: stale)

        #expect(WatchListCards(root: fixture.inbox).reconcile(fixture.store.watches))   // a new launch
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(!WatchListCards(root: fixture.inbox).reconcile(fixture.store.watches))
    }

    @Test func aTeamJobThatsOffHasNoCardsAndTurningItOffDeletesThem() async throws {
        let fixture = try CardsFixture()
        defer { fixture.remove() }
        try fixture.place.job("holiday/oct/fashion", #"{"name": "Fashion", "items": ["1"], "expect": {"price": 11}}"#)
        fixture.store.refresh()
        let id = WatchListStore.teamID("holiday/oct/fashion")
        let folder = fixture.inbox.appendingPathComponent("watch-team-holiday-oct-fashion")
        let file = folder.appendingPathComponent(WatchListCards.fileName(for: "1"))

        fixture.runner.tick()
        #expect(!FileManager.default.fileExists(atPath: file.path) && fixture.checks.calls.isEmpty)

        await (try fixture.runner.turn(id, on: true))?.value
        #expect(fixture.checks.calls == ["1"])
        #expect(FileManager.default.fileExists(atPath: file.path))
        let changes = fixture.changes

        _ = try fixture.runner.turn(id, on: false)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(fixture.changes == changes + 1)
        let off = try #require(fixture.store.watch(id: id))
        #expect(off.item("1")?.needsExplaining == true)   // it is still red; a job that's off just has no card
        #expect(WatchListCards.card(for: try #require(off.item("1")), in: off, checkedBy: "x") == nil)
        fixture.runner.tick()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}

/// A watch list whose runner writes cards into a cards inbox of its own, checked by fakes.
@MainActor
final class CardsFixture {
    let place = Place()
    let store: WatchListStore
    let runner: WatchListRunner
    let checks = FakeWatchChecks()
    let clock = TestClock()
    var changes = 0
    var inbox: URL { place.root.appendingPathComponent("cards/inbox") }

    init() throws {
        store = place.store()
        let checks = checks, clock = clock
        runner = WatchListRunner(store: store, prepare: { watch in .eachItem { item in await checks.check(watch, item) } }, now: { clock.now })
        runner.cards = WatchListCards(root: place.root.appendingPathComponent("cards/inbox"))
        runner.onCardsChanged = { [unowned self] in self.changes += 1 }
    }

    func remove() { place.remove() }
}
