import Foundation
import Testing
@testable import Familiar

/// A watch's card: one per job, `job.json` in the watch's folder of the cards inbox, written at the end of each run
/// with what the run found, as it found it. A run with nothing wrong deletes it, so the card resolves; problems coming
/// back write it again. `"cards": "all"` keeps it always, `"cards": false` never, and a team job that's off has none.
/// The checks are fakes: no Python, no network; temp folders only.
@Suite @MainActor
struct WatchListCardsTests {
    private let checked = Date(timeIntervalSince1970: 1_790_000_000)

    private func item(_ key: String, title: String? = nil, _ status: WatchListStatus?, why: [String]? = nil,
                      facts: String? = nil) -> WatchListItem {
        var item = WatchListItem(key: key, expect: ["price": .number(10)])
        item.title = title
        item.state = ["price": .number(12)]
        item.why = why
        item.facts = facts
        item.checkedAt = status == nil ? nil : checked
        item.status = status
        return item
    }

    private func red(_ now: Double, _ expected: Double) -> WatchListStatus {
        .notAsExpected([WatchListDifference(field: "price", now: .number(now), expected: .number(expected))])
    }

    // MARK: what it says

    @Test func aMixedRunsCardSaysWhatTheRunFoundAsItFoundIt() throws {
        let items = [item("123", title: "Blue kettle", red(12, 10), why: ["The sale price ended early.", "It may come back on Friday."],
                          facts: #"{"seller":"Acme"}"#),
                     item("456", red(9, 8)),
                     item("790", title: "Red mug", .couldNotCheck("It took longer than 60 seconds."))]
            + (1...5).map { item("g\($0)", title: "Green \($0)", .asExpected) }
        let watch = WatchListWatch(name: "Sale items", check: "shop__watch_item", items: items)
        let time = WatchListCards.time(checked)

        let card = try #require(WatchListCards.card(for: watch, checkedBy: "shop__watch_item"))

        #expect(card["title"] as? String == "Sale items: 2 of 8 not as expected · \(time)")
        #expect(card["severity"] as? String == "high")
        #expect(card["body"] as? String == """
        2 not as expected · 1 couldn't check · 5 as expected · checked \(time) by shop__watch_item

        Blue kettle (123)
        Price: 12 — expected 10
        The sale price ended early.
        It may come back on Friday.

        456
        Price: 9 — expected 8

        Red mug (790)
        Couldn't check: It took longer than 60 seconds.
        """)
        #expect(card["details"] as? String == #"Blue kettle (123): {"seller":"Acme"}"#)
        #expect(card["parts"] as? [String] == ["123", "456", "790"].map(WatchListCards.part))
        #expect(card["url"] == nil)
        // The difference lines are the notification's own.
        let alert = WatchListAlert(watchID: watch.id, watchName: watch.name, itemKey: "456", title: "456", kind: .notAsExpected(
            [WatchListDifference(field: "price", now: .number(9), expected: .number(8))]))
        #expect(alert.body == "Price: 9 — expected 8")
        #expect(WatchListCards.time(checked, in: try #require(TimeZone(identifier: "UTC"))) == "2:13 PM")

        // As the inbox reads it: the whole body, Open job for this watch, and Why? for the chat.
        let entry = try CardInboxFormat.parse(Data(JSONText.pretty(card, indent: "").utf8), source: WatchListCards.source(for: watch),
                                              id: "job", modifiedAt: checked)
        #expect(entry.body == card["body"] as? String && entry.severity == "high")
        #expect(entry.actions == [CardInboxAction(label: "Open job", watch: watch.id.uuidString),
                                  CardInboxAction(label: "Why?", ask: "Why are items in Sale items not as expected right now?")])
        #expect(entry.parts == ["123", "456", "790"].map(WatchListCards.part))

        // Only some it couldn't check.
        let grey = WatchListWatch(name: "Sale items", check: "c", items: [items[2]] + items.suffix(5))
        let greyCard = try #require(WatchListCards.card(for: grey, checkedBy: "c"))
        #expect(greyCard["title"] as? String == "Sale items: couldn't check 1 of 6 · \(time)")
        #expect(greyCard["severity"] as? String == "normal")
        #expect((greyCard["body"] as? String)?.hasPrefix("1 couldn't check · 5 as expected · checked \(time) by c\n\nRed mug (790)\n") == true)
        #expect((greyCard["actions"] as? [[String: Any]])?.last?["ask"] as? String == "Why couldn't Noteling check items in Sale items?")
        // Nothing wrong: by default, no card.
        #expect(WatchListCards.card(for: WatchListWatch(name: "Sale items", check: "c", items: Array(items.suffix(5))), checkedBy: "c") == nil)
    }

    @Test func withCardsAllTheCardStaysAndListsEveryItemsLine() throws {
        var watch = WatchListWatch(name: "Sale items", check: "c", items: [item("123", title: "Blue kettle", .asExpected), item("456", .asExpected)])
        watch.cards = .all
        let time = WatchListCards.time(checked)

        let card = try #require(WatchListCards.card(for: watch, checkedBy: "shop__watch_item"))

        #expect(card["title"] as? String == "Sale items: all 2 as expected · \(time)")
        #expect(card["body"] as? String == "2 as expected · checked \(time) by shop__watch_item\n\nBlue kettle (123): As expected\n456: As expected")
        #expect(card["severity"] as? String == "low")
        #expect((card["actions"] as? [[String: Any]])?.compactMap { $0["label"] as? String } == ["Open job"])
        #expect(card["parts"] == nil && card["details"] == nil)

        // A problem comes first, as a block; the rest stay one line each.
        watch.items.insert(item("789", red(12, 10)), at: 0)
        watch.items.append(item("999", nil))
        let mixed = try #require(WatchListCards.card(for: watch, checkedBy: "c"))
        #expect(mixed["title"] as? String == "Sale items: 1 of 4 not as expected · \(time)")
        #expect(mixed["body"] as? String == "1 not as expected · 2 as expected · 1 not checked yet · checked \(time) by c\n\n"
                + "789\nPrice: 12 — expected 10\n\nBlue kettle (123): As expected\n456: As expected\n999: Not checked yet")

        // Not checked at all yet, and no items at all.
        watch.items = [item("1", nil)]
        #expect(WatchListCards.card(for: watch, checkedBy: "c")?["title"] as? String == "Sale items: not checked yet")
        watch.items = []
        #expect(WatchListCards.card(for: watch, checkedBy: "c")?["title"] as? String == "Sale items: no items yet")

        // "cards": false: none, whatever it found.
        watch.items = [item("789", red(12, 10))]
        watch.cards = .off
        #expect(WatchListCards.card(for: watch, checkedBy: "c") == nil)
    }

    @Test func aLongListIsCappedAt50AndAlwaysFitsWhatTheInboxShows() throws {
        let many = WatchListWatch(name: "Sale items", check: "c", items: (1...200).map { item("k\($0)", red(12, 10)) })
        let card = try #require(WatchListCards.card(for: many, checkedBy: "c"))
        let body = try #require(card["body"] as? String)
        #expect(card["title"] as? String == "Sale items: 200 of 200 not as expected · \(WatchListCards.time(checked))")
        #expect(body.components(separatedBy: "\n\n").count == 1 + 50 + 1)
        #expect(body.hasSuffix("\n\nk50\nPrice: 12 — expected 10\n\n…and 150 more. Open the job to see them all."))
        #expect((card["parts"] as? [String])?.count == 200)

        // Wordy items: as many as fit in what the inbox shows of a body, and the rest counted.
        let wordy = WatchListWatch(name: "Sale items", check: "c", items: (1...200).map {
            item("k\($0)", red(12, 10), why: Array(repeating: String(repeating: "x", count: 290), count: 5), facts: String(repeating: "f", count: 500))
        })
        let long = try #require(WatchListCards.card(for: wordy, checkedBy: "c"))
        let longBody = try #require(long["body"] as? String)
        let listed = longBody.components(separatedBy: "\n\n").count - 2
        #expect(longBody.count <= CardInboxFormat.bodyLimit)
        #expect(listed > 0 && listed < 50)
        #expect(longBody.hasSuffix("…and \(200 - listed) more. Open the job to see them all."))
        #expect((long["details"] as? String)?.components(separatedBy: "\n").count == listed)   // the listed items' facts
        let text = JSONText.pretty(long, indent: "")
        #expect(text.utf8.count < CardInboxFormat.fileLimit)
        #expect(try CardInboxFormat.parse(Data(text.utf8), source: "watch-sale-items", id: "job", modifiedAt: checked).body == longBody)
        #expect(WatchListCards.more(1_234) == "…and 1,234 more. Open the job to see them all.")
    }

    // MARK: with the runner

    @Test func aRunWithNothingWrongDeletesTheCardAndProblemsWriteItAgain() async throws {
        let fixture = try CardsFixture()
        defer { fixture.remove() }
        let watch = WatchListWatch(name: "Sale items", check: "shop__watch_item",
                                   items: ["1", "2"].map { WatchListItem(key: $0, expect: ["price": .number(10)]) })
        try fixture.store.add(watch)
        let file = fixture.inbox.appendingPathComponent("watch-sale-items/job.json")
        fixture.checks.next["1"] = [fixture.checks.reading(price: 12, key: "1")]

        await fixture.runner.run(watch.id)?.value

        #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path) == ["job.json"])
        #expect(fixture.changes == 1)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
        let morning = MorningStore(directory: fixture.place.root.appendingPathComponent("morning"))
        let inbox = CardInbox(store: morning, directory: fixture.inbox)
        inbox.folderName = { source in fixture.store.watches.first { WatchListCards.source(for: $0) == source }?.name }
        inbox.scan()
        let card = try #require(morning.cards.first)
        #expect(morning.cards.count == 1)
        #expect(card.title == "Sale items: 1 of 2 not as expected · \(WatchListCards.time(fixture.clock.now))")
        #expect(card.inbox?.key == WatchListCards.key(for: try #require(fixture.store.watch(id: watch.id))))
        #expect(card.inbox?.severity == "high" && card.sources.first?.kind == "Watch")
        #expect(card.sources.map(\.title) == [card.title, "Details"] && card.sources[1].excerpt == #"Item 1 (1): {"seller":"Acme"}"#)
        #expect(morning.folders.first { $0.id == card.folderID }?.name == "Sale items")

        // The same again: nothing to write.
        fixture.checks.next["1"] = [fixture.checks.reading(price: 12, key: "1")]
        await fixture.runner.run(watch.id)?.value
        #expect(fixture.changes == 1)

        // Nothing wrong: the file goes, so the card resolves.
        await fixture.runner.run(watch.id)?.value
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(fixture.changes == 2)
        inbox.scan()
        #expect(morning.cards.first?.disposition == .resolved && morning.cards.first?.inbox?.goneAt != nil)

        // Problems again: written again, and the same card opens again.
        fixture.checks.next["2"] = [fixture.checks.reading(price: 13, key: "2")]
        await fixture.runner.run(watch.id)?.value
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(fixture.changes == 3)
        inbox.scan()
        #expect(morning.cards.count == 1 && morning.cards.first?.id == card.id)
        #expect(morning.cards.first?.disposition == .unreviewed && morning.cards.first?.inbox?.goneAt == nil)
        #expect(morning.cards.first?.meaning.contains("Item 2 (2)\nPrice: 13 — expected 10") == true)
    }

    @Test func aWatchBeingCheckedKeepsItsCardAsItWasUntilTheRunEnds() async throws {
        let fixture = try CardsFixture()
        defer { fixture.remove() }
        let watch = WatchListWatch(name: "Sale items", check: "shop__watch_item", items: [WatchListItem(key: "1", expect: ["price": .number(10)])])
        try fixture.store.add(watch)
        let file = fixture.inbox.appendingPathComponent("watch-sale-items/job.json")
        fixture.checks.next["1"] = [fixture.checks.reading(price: 12, key: "1")]
        await fixture.runner.run(watch.id)?.value
        let before = try String(contentsOf: file, encoding: .utf8)

        fixture.checks.gate = Gate()
        let run = try #require(fixture.runner.run(watch.id))
        for _ in 0..<1_000 where fixture.checks.inFlight == 0 { await Task.yield() }
        fixture.clock.now += 3_600
        fixture.runner.tick()                                   // mid-run: the card waits
        #expect(try String(contentsOf: file, encoding: .utf8) == before)

        fixture.checks.gate?.open()
        await run.value
        #expect(!FileManager.default.fileExists(atPath: file.path))   // as expected now: at the run's end, the card goes
    }

    @Test func aTeamJobThatsOffHasNoCardAndTurningItOffDeletesIt() async throws {
        let fixture = try CardsFixture()
        defer { fixture.remove() }
        try fixture.place.job("holiday/oct/fashion", #"{"name": "Fashion", "items": ["1"], "expect": {"price": 11}}"#)
        fixture.store.refresh()
        let id = WatchListStore.teamID("holiday/oct/fashion")
        let file = fixture.inbox.appendingPathComponent("watch-team-holiday-oct-fashion/job.json")

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
        #expect(WatchListCards.card(for: off, checkedBy: "x") == nil)
        fixture.runner.tick()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func earlierPerItemFilesGoAndTheJobsCardTakesTheirPlace() throws {
        let fixture = try CardsFixture()
        defer { fixture.remove() }
        let watch = WatchListWatch(name: "Sale items", check: "shop__watch_item", items: [WatchListItem(key: "123", expect: ["price": .number(10)])])
        try fixture.store.add(watch)
        try fixture.store.change(watch.id, persist: false) { $0.items[0] = item("123", red(12, 10)) }
        let folder = fixture.inbox.appendingPathComponent("watch-sale-items")
        let gone = fixture.inbox.appendingPathComponent("watch-old-list")
        for (place, name) in [(folder, "item-123-6b86b273.json"), (folder, "item-456-00000000.json"), (folder, "deal-9.json"),
                              (gone, "item-1-11111111.json")] {
            try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
            try Data(#"{"title": "Not as expected · Old"}"#.utf8).write(to: place.appendingPathComponent(name))
        }

        #expect(WatchListCards(root: fixture.inbox).reconcile(fixture.store.watches))   // a launch after the update

        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["deal-9.json", "job.json"])   // a check's own file stays
        #expect(try FileManager.default.contentsOfDirectory(atPath: gone.path).isEmpty)
        #expect(!WatchListCards(root: fixture.inbox).reconcile(fixture.store.watches))
    }

    // MARK: resolved, and Open job

    @Test func aCardThePersonResolvedStaysResolvedUntilAnotherItemGoesWrong() throws {
        let fixture = InboxFixture()
        defer { fixture.remove() }
        let cards = WatchListCards(root: fixture.directory)
        var watch = WatchListWatch(name: "Sale items", check: "c", items: [item("123", red(12, 10)), item("456", .asExpected), item("789", .asExpected)])
        watch.path = "sale-items"
        let id = CardInboxFormat.cardID(WatchListCards.key(for: watch))
        func run(_ change: (inout WatchListWatch) -> Void) {
            change(&watch)
            cards.reconcile([watch])
            fixture.inbox.scan()
        }
        run { _ in }
        try fixture.store.setCardResolution(cardID: id, resolved: true)

        // The same item, still wrong, at later runs: it stays resolved.
        run { $0.items[0] = item("123", red(13, 10)) }
        #expect(fixture.store.cards.first?.disposition == .resolved)
        #expect(fixture.store.cards.first?.meaning.contains("Price: 13 — expected 10") == true)   // its words follow the runs
        // Everything fine, then that item wrong again: not a new one, so still resolved.
        run { $0.items[0] = item("123", .asExpected) }
        #expect(fixture.store.cards.first?.disposition == .resolved && fixture.store.cards.first?.inbox?.goneAt != nil)
        run { $0.items[0] = item("123", red(12, 10)) }
        #expect(fixture.store.cards.first?.disposition == .resolved && fixture.store.cards.first?.inbox?.goneAt == nil)
        // Another item goes wrong: it opens again.
        run { $0.items[1] = item("456", .couldNotCheck("Signed out")) }
        #expect(fixture.store.cards.first?.disposition == .unreviewed)
        #expect(fixture.store.cards.count == 1)

        // Resolved again, and a card the person took and then put back is theirs to decide.
        try fixture.store.setCardResolution(cardID: id, resolved: true)
        run { $0.items[2] = item("789", red(1, 10)) }
        #expect(fixture.store.cards.first?.disposition == .unreviewed)
        try fixture.store.setDisposition(cardID: id, to: .mine)
        run { $0.items[0] = item("123", .asExpected) }
        #expect(fixture.store.cards.first?.disposition == .mine)
    }

    @Test func openJobOnlyOpensAWatchThatIsThere() throws {
        let watch = WatchListWatch(name: "Sale items", check: "c", items: [])
        let entry = try CardInboxFormat.parse(Data("""
        {"title": "Sale items: 1 of 2 not as expected", "actions": [{"label": "Open job", "watch": "\(watch.id.uuidString)"},
         {"label": "Elsewhere", "watch": "../../etc/hosts"}, {"label": "Run", "watch": "open -a Terminal"},
         {"label": "Gone", "watch": "\(UUID().uuidString)"}]}
        """.utf8), source: "watch-sale-items", id: "job", modifiedAt: checked)

        #expect(entry.actions.map(\.label) == ["Open job", "Gone"])   // only a watch's id is kept
        #expect(MorningFilesView.openableWatch(entry.actions[0], in: [watch]) == watch.id)
        #expect(MorningFilesView.openableWatch(entry.actions[1], in: [watch]) == nil)   // no such watch: no button
        #expect(MorningFilesView.openableWatch(CardInboxAction(label: "Why?", ask: "Why?"), in: [watch]) == nil)
        // It is a way to a page, not something to do: a card with it still can't be handed to Noteling.
        let fixture = InboxFixture()
        defer { fixture.remove() }
        try fixture.write("watch-sale-items", "job", #"{"title": "T", "actions": [{"label": "Open job", "watch": "\#(watch.id.uuidString)"}]}"#)
        fixture.inbox.scan()
        let card = try #require(fixture.store.cards.first)
        #expect(card.inbox?.actions == [CardInboxAction(label: "Open job", watch: watch.id.uuidString)])
        #expect(throws: MorningStoreError.self) { try fixture.store.enqueue(cardID: card.id) }
    }

    @Test func theCardsOptionIsReadAndWritten() throws {
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
