import Foundation
import Testing
@testable import Familiar

/// The cards inbox: one JSON file per card in `cards/inbox/<source>/`, taken into Morning Files with no model. Writing a
/// file again changes its card's words and nothing the person decided; deleting it resolves a card nobody took; a file
/// that can't be read is said and left alone; and a card from the inbox never runs anything. Temp folders only.
@Suite @MainActor
struct CardInboxTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func parse(_ text: String) throws -> CardInboxEntry {
        try CardInboxFormat.parse(Data(text.utf8), source: "pack-shop", id: "order-1", modifiedAt: at)
    }

    // MARK: the format

    @Test func aCardFileNeedsOnlyATitleAndKeysItDoesntKnowAreLeftOut() throws {
        let bare = try parse(#"{"title": "  Refund ready  "}"#)
        #expect(bare == CardInboxEntry(source: "pack-shop", id: "order-1", title: "Refund ready", modifiedAt: at))
        #expect(bare.key == "pack-shop/order-1" && bare.severity == "normal" && bare.actions.isEmpty)

        let full = try parse("""
        {"title": "Price went up", "body": "Was $10, now $12.", "url": "https://shop.example.com/item/123", "severity": "HIGH",
         "actions": [{"label": "Open item", "url": "https://shop.example.com/item/123"}, {"label": "Why?", "ask": "Why did the price go up?"}],
         "details": {"seller": "Acme", "price": 12.5}, "owner": "someone", "run": "rm -rf ~"}
        """)
        #expect(full.title == "Price went up" && full.body == "Was $10, now $12." && full.url == "https://shop.example.com/item/123")
        #expect(full.severity == "high")
        #expect(full.actions == [CardInboxAction(label: "Open item", url: "https://shop.example.com/item/123"),
                                 CardInboxAction(label: "Why?", ask: "Why did the price go up?")])
        #expect(full.details == #"{"price":12.5,"seller":"Acme"}"#)
        #expect(try parse(#"{"title": "T", "severity": "urgent!"}"#).severity == "normal")
        #expect(try parse(#"{"title": "T", "severity": "low"}"#).severity == "low")
        #expect(try parse(#"{"title": 42}"#).title == "42")
        #expect(try parse(#"{"title": "\#(String(repeating: "x", count: 300))"}"#).title.count == CardInboxFormat.titleLimit)
    }

    @Test func aButtonOnlyEverOpensAWebPageOrAsksAQuestion() throws {
        let entry = try parse("""
        {"title": "T", "url": "file:///etc/hosts",
         "actions": [{"label": "Run it", "run": "open -a Terminal"}, {"label": "Local file", "url": "file:///Users/me/report.pdf"},
                     {"label": "Script", "url": "javascript:alert(1)"}, {"label": "App", "url": "x-apple.systempreferences:com.apple.Keyboard"},
                     {"label": "", "url": "https://shop.example.com/a"}, {"label": "Shell", "command": "rm -rf ~", "ask": "  "},
                     {"label": "Page", "url": "https://shop.example.com/item/1"}, {"label": "Ask", "ask": "What changed?"},
                     {"label": "Both", "url": "ftp://shop.example.com/x", "ask": "Is this safe?"}]}
        """)
        #expect(entry.url == "")   // not a web page: no page at all
        #expect(entry.actions == [CardInboxAction(label: "Page", url: "https://shop.example.com/item/1"),
                                  CardInboxAction(label: "Ask", ask: "What changed?"), CardInboxAction(label: "Both", ask: "Is this safe?")])
        let go = Array(repeating: #"{"label": "Go", "url": "https://shop.example.com"}"#, count: 9).joined(separator: ",")
        #expect(try parse(#"{"title": "T", "actions": ["# + go + "]}").actions.count == CardInboxFormat.actionLimit)
        #expect(CardInboxFormat.webAddress("https://shop.example.com/item/1") == "https://shop.example.com/item/1")
        #expect(CardInboxFormat.webAddress("http:///no-host") == "" && CardInboxFormat.webAddress("mailto:a@example.com") == "")
    }

    @Test func aFileThatIsntACardSaysWhyInPlainWords() {
        #expect(throws: CardInboxError("it needs a title.")) { try parse(#"{"body": "No title"}"#) }
        #expect(throws: CardInboxError("it needs a title.")) { try parse(#"{"title": "   "}"#) }
        #expect(throws: CardInboxError("it must be one JSON object: { … }.")) { try parse(#"[{"title": "In a list"}]"#) }
        #expect(throws: CardInboxError.self) { try parse(#"{"title": "Cut off"#) }
        #expect((try? parse("not json")) == nil)
    }

    // MARK: identity and deletion

    @Test func writingTheSameFileAgainUpdatesTheSameCardAndKeepsWhatThePersonDid() throws {
        let fixture = InboxFixture()
        defer { fixture.remove() }
        try fixture.write("pack-shop", "order-1", #"{"title": "Refund ready", "body": "Order 1 qualifies."}"#)
        fixture.inbox.scan(at: at)

        let card = try #require(fixture.store.cards.first)
        #expect(fixture.store.cards.count == 1)
        #expect(card.id == CardInboxFormat.cardID("pack-shop/order-1") && card.isFromInbox && card.tracking == nil)
        #expect(card.title == "Refund ready" && card.meaning == "Order 1 qualifies." && card.disposition == .unreviewed)
        #expect(fixture.store.folders.first { $0.id == card.folderID }?.name == "pack-shop")
        try fixture.store.setDisposition(cardID: card.id, to: .mine)
        try fixture.store.updateCardContext(cardID: card.id, context: "Claim it on Friday.")

        try fixture.write("pack-shop", "order-1", #"{"title": "Refund ready · $12", "body": "Order 1 qualifies for $12.", "severity": "high"}"#)
        let later = at.addingTimeInterval(60)
        fixture.inbox.scan(at: later)

        let updated = try #require(fixture.store.cards.first)
        #expect(fixture.store.cards.count == 1 && updated.id == card.id)
        #expect(updated.title == "Refund ready · $12" && updated.meaning == "Order 1 qualifies for $12." && updated.inbox?.severity == "high")
        #expect(updated.disposition == .mine && updated.personalContext == "Claim it on Friday." && updated.updatedAt == later)

        // Nothing changed: nothing is saved.
        fixture.inbox.scan(at: later.addingTimeInterval(60))
        #expect(fixture.store.cards.first == updated)
        // What the person renamed the folder to stays.
        try fixture.store.saveFolder(MorningFolder(id: card.folderID, name: "Refunds"))
        try fixture.write("pack-shop", "order-2", #"{"title": "Second refund"}"#)
        fixture.inbox.scan(at: later.addingTimeInterval(120))
        #expect(fixture.store.folders.first { $0.id == card.folderID }?.name == "Refunds")
        #expect(fixture.store.cards.count == 2)
        #expect(MorningStore(directory: fixture.morning).workspace == fixture.store.workspace)   // saved
    }

    @Test func aDeletedFileResolvesACardNobodyTookAndMarksATakenOneGone() throws {
        let fixture = InboxFixture()
        defer { fixture.remove() }
        try fixture.write("deals", "new", #"{"title": "Nobody looked"}"#)
        try fixture.write("deals", "taken", #"{"title": "I took this one"}"#)
        fixture.inbox.scan(at: at)
        let new = CardInboxFormat.cardID("deals/new"), taken = CardInboxFormat.cardID("deals/taken")
        try fixture.store.setDisposition(cardID: taken, to: .mine)

        try fixture.delete("deals", "new")
        try fixture.delete("deals", "taken")
        let gone = at.addingTimeInterval(60)
        fixture.inbox.scan(at: gone)

        let resolved = try #require(fixture.store.cards.first { $0.id == new })
        #expect(resolved.disposition == .resolved && resolved.inbox?.goneAt == gone && resolved.isResolved)
        let kept = try #require(fixture.store.cards.first { $0.id == taken })
        #expect(kept.disposition == .mine && kept.inbox?.goneAt == gone)
        #expect(fixture.store.cards.count == 2)   // never removed

        // Back again: the card its deletion resolved is open again; the person's own decision stays theirs.
        try fixture.write("deals", "new", #"{"title": "Nobody looked"}"#)
        try fixture.write("deals", "taken", #"{"title": "I took this one"}"#)
        fixture.inbox.scan(at: gone.addingTimeInterval(60))
        #expect(fixture.store.cards.first { $0.id == new }?.disposition == .unreviewed)
        #expect(fixture.store.cards.first { $0.id == new }?.inbox?.goneAt == nil)
        #expect(fixture.store.cards.first { $0.id == taken }?.disposition == .mine)

        // A card the person resolved stays resolved when its file comes and goes.
        try fixture.store.setCardResolution(cardID: taken, resolved: true)
        try fixture.delete("deals", "taken")
        fixture.inbox.scan(at: gone.addingTimeInterval(120))
        try fixture.write("deals", "taken", #"{"title": "I took this one"}"#)
        fixture.inbox.scan(at: gone.addingTimeInterval(180))
        #expect(fixture.store.cards.first { $0.id == taken }?.disposition == .resolved)

        // A whole folder gone is every card in it gone.
        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("deals"))
        fixture.inbox.scan(at: gone.addingTimeInterval(240))
        #expect(fixture.store.cards.allSatisfy { $0.inbox?.goneAt != nil })
    }

    @Test func aFileThatCantBeReadIsSaidOnceAndNeverResolvesOrDeletesAnything() throws {
        let fixture = InboxFixture()
        defer { fixture.remove() }
        try fixture.write("deals", "one", #"{"title": "Fine for now"}"#)
        fixture.inbox.scan(at: at)
        try fixture.write("deals", "one", #"{"title": "Half written"#)
        try fixture.write("deals", "two", #"{"body": "No title"}"#)
        try fixture.write("deals", "big", #"{"title": "Too big", "body": "\#(String(repeating: "x", count: 70_000))"}"#)

        fixture.inbox.scan(at: at.addingTimeInterval(60))
        fixture.inbox.scan(at: at.addingTimeInterval(120))

        let card = try #require(fixture.store.cards.first)
        #expect(fixture.store.cards.count == 1)
        #expect(card.title == "Fine for now" && card.disposition == .unreviewed && card.inbox?.goneAt == nil)
        let notes = fixture.store.inboxNotes[CardInboxFormat.folderID("deals")] ?? []
        #expect(notes.count == 3)
        #expect(notes.contains("big.json is bigger than 64 KB, so it wasn't read."))
        #expect(notes.contains("two.json can't be read: it needs a title."))
        #expect(notes.contains { $0.hasPrefix("one.json can't be read: it isn't valid JSON") })
        for name in ["one", "two", "big"] {
            #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("deals/\(name).json").path))
        }

        try fixture.write("deals", "one", #"{"title": "Fixed"}"#)
        try fixture.delete("deals", "two")
        try fixture.delete("deals", "big")
        fixture.inbox.scan(at: at.addingTimeInterval(180))
        #expect(fixture.store.cards.first?.title == "Fixed")
        #expect(fixture.store.inboxNotes[CardInboxFormat.folderID("deals")] == nil)
    }

    // MARK: folders and limits

    @Test func eachSourceIsAFolderNamedByItsWatchOrElseByItsFolder() throws {
        let fixture = InboxFixture()
        defer { fixture.remove() }
        try fixture.write("watch-sale-items", "item-1", #"{"title": "Not as expected · Kettle"}"#)
        try fixture.write("pack-shop", "a", #"{"title": "A"}"#)
        try fixture.write("deals", "b", #"{"title": "B"}"#)
        try FileManager.default.createDirectory(at: fixture.directory.appendingPathComponent("empty"), withIntermediateDirectories: true)
        try "not a card".write(to: fixture.directory.appendingPathComponent("deals/notes.txt"), atomically: true, encoding: .utf8)
        fixture.inbox.folderName = { $0 == "watch-sale-items" ? "Sale items" : nil }

        fixture.inbox.scan(at: at)

        func folder(_ source: String) -> String? { fixture.store.folders.first { $0.id == CardInboxFormat.folderID(source) }?.name }
        #expect(folder("watch-sale-items") == "Sale items" && folder("pack-shop") == "pack-shop" && folder("deals") == "deals")
        #expect(folder("empty") == nil)   // no cards, no folder
        #expect(fixture.store.cards.count == 3)
        #expect(fixture.store.cards.first { $0.title == "B" }?.folderID == CardInboxFormat.folderID("deals"))
        #expect(fixture.store.cards.first { $0.title.hasPrefix("Not as expected") }?.sources.first?.kind == "Watch")
        #expect(fixture.store.cards.first { $0.title == "A" }?.sources.first?.kind == "Card")
        #expect(fixture.store.folders.map(\.name).prefix(3) == ["Replies", "Unfinished", "Housekeeping"])   // the person's folders stay
    }

    @Test func aFolderShowsAtMost500CardsAndNoneOfItsOthersAreResolved() throws {
        let fixture = InboxFixture()
        defer { fixture.remove() }
        let folder = fixture.directory.appendingPathComponent("bulk")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<502 {
            try Data(#"{"title": "Card \#(index)"}"#.utf8).write(to: folder.appendingPathComponent(String(format: "c%03d.json", index)))
        }
        fixture.inbox.scan(at: at)
        #expect(fixture.store.cards.count == 500)
        #expect(fixture.store.inboxNotes[CardInboxFormat.folderID("bulk")] == ["2 more cards weren't read: a folder shows up to 500."])

        // A file past the limit is still there, so a card from before it isn't resolved.
        try fixture.delete("bulk", "c000")
        fixture.inbox.scan(at: at.addingTimeInterval(60))
        #expect(fixture.store.cards.filter { $0.inbox?.goneAt != nil }.map(\.title) == ["Card 0"])
        #expect(fixture.store.cards.filter { $0.inbox?.goneAt == nil }.count == 500)   // the 500 read now, one of them new
        #expect(fixture.store.inboxNotes[CardInboxFormat.folderID("bulk")] == ["1 more card wasn't read: a folder shows up to 500."])
    }

    // MARK: kept apart

    @Test func theCardStepAndTheAttentionTestNeverTouchOrCountInboxCards() throws {
        let fixture = InboxFixture()
        defer { fixture.remove() }
        try fixture.write("mail", "message", #"{"title": "Reply to Avery", "url": "https://mail.example.com/?q=rfc822msgid%3Aabc%40example.com"}"#)
        fixture.inbox.scan(at: at)
        let inboxCard = try #require(fixture.store.cards.first)

        // A card step that observes items, one of them keyed like the inbox card, leaves it as it was.
        let run = UUID(), source = UUID()
        let observation = CardObservation(runID: run, sourceID: source, itemKey: "mail/message", sourceName: "Mail", kind: "Mail",
            title: "Reply to Avery", excerpt: "Avery asked for a date.", url: "https://mail.example.com/1", identityEvidence: "Message 1",
            observedAt: at, state: .open, stateEvidence: "Unanswered")
        let proposal = CardProposal(observationKey: observation.id, title: "Reply to Avery", meaning: "They are waiting.",
                                    action: MorningAction(title: "Draft a reply", instruction: "Draft a short reply."))
        var workspace = fixture.store.workspace
        let summary = try MorningCardReconciliation.apply(observations: [observation], proposals: [proposal], runIDs: [run],
                                                          at: at.addingTimeInterval(60), to: &workspace)
        #expect(summary.created == 1)
        #expect(workspace.cards.count == 2 && workspace.cards.first { $0.id == inboxCard.id } == inboxCard)
        #expect(fixture.store.trackedItems(sourceID: source).isEmpty)

        // The attention test: nothing the person does to an inbox card is a signal, it names no message, and it isn't
        // on the desk the test counts.
        var after = fixture.store.workspace
        after.cards[0].disposition = .mine
        after.cards[0].personalContext = "Mine"
        #expect(AttentionImplicit.signals(from: fixture.store.workspace, to: after).isEmpty)
        #expect(AttentionMessageID.named(by: fixture.store.cards).isEmpty)
        #expect(fixture.store.attentionDesk == 0)
        try fixture.store.saveCard(MorningCard(folderID: try #require(fixture.store.folders.first).id, title: "My own note",
                                               action: MorningAction(title: "Do it", instruction: "Do it.")))
        #expect(fixture.store.attentionDesk == 1)
        #expect(fixture.store.cards.filter { $0.displayDisposition == .unreviewed }.count == 2)

        // Looking at the inbox again leaves the card as it was.
        fixture.inbox.scan(at: at.addingTimeInterval(120))
        #expect(fixture.store.cards.first { $0.id == inboxCard.id } == inboxCard)
    }

    @Test func aCardFromTheInboxNeverRunsAnything() throws {
        let fixture = InboxFixture()
        defer { fixture.remove() }
        try fixture.write("pack-shop", "order-1", """
        {"title": "Refund ready", "actions": [{"label": "Claim", "ask": "Claim the refund for me."}],
         "action": {"title": "Claim", "instruction": "Open the shop and claim the refund.", "mode": "desktop"}}
        """)
        fixture.inbox.scan(at: at)
        let card = try #require(fixture.store.cards.first)
        #expect(card.action.mode == .prepare && card.alternatives == nil && card.contextAction == nil)

        #expect(throws: MorningStoreError.self) { try fixture.store.enqueue(cardID: card.id) }
        #expect(throws: MorningStoreError.self) { try fixture.store.enqueue(cardID: card.id, kind: .context) }
        #expect(throws: MorningStoreError.self) {
            try fixture.store.updateCardContext(cardID: card.id, context: "", actionInstruction: "Open the shop and claim it.")
        }
        #expect(fixture.store.workItems.isEmpty)
        #expect(fixture.store.cards.first?.action == card.action)

        // The person's own context is still theirs to keep, and editing the card keeps where it came from.
        try fixture.store.updateCardContext(cardID: card.id, context: "Claim it Friday.")
        var edited = try #require(fixture.store.cards.first)
        edited.inbox = nil
        try fixture.store.saveCard(edited)
        #expect(fixture.store.cards.first?.inbox?.key == "pack-shop/order-1")
        #expect(throws: MorningStoreError.self) { try fixture.store.enqueue(cardID: card.id) }

        // Its buttons: Ask from the file, and Open page in front when it has a page and no button opens it.
        #expect(MorningFilesView.inboxActions(card) == [CardInboxAction(label: "Claim", ask: "Claim the refund for me.")])
        try fixture.write("pack-shop", "order-1", #"{"title": "Refund ready", "url": "https://shop.example.com/order/1"}"#)
        fixture.inbox.scan(at: at.addingTimeInterval(60))
        #expect(MorningFilesView.inboxActions(try #require(fixture.store.cards.first)) == [CardInboxAction(label: "Open page", url: "https://shop.example.com/order/1")])
        #expect(MorningFilesView.tileLabel(try #require(fixture.store.cards.first)) == "CARD")
    }

    // MARK: NOTELING_CARDS_DIR

    @Test func eachScriptGetsAFolderOfItsOwnAndNoNameReachesAnothers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cards-dir-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = ScriptRunner(config: Config())
        runner.cardsRoot = root

        let pack = try #require(runner.cardsFolder("pack-shop"))
        #expect(pack.standardizedFileURL == root.appendingPathComponent("pack-shop").standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: pack.path))
        #expect(try FileManager.default.attributesOfItem(atPath: pack.path)[.posixPermissions] as? Int == 0o700)
        #expect(try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? Int == 0o700)   // the inbox too

        for hostile in ["../../outside", "..", ".", "", "/", "pack-../watch-sale-items", "watch-a/../../b", ".hidden", "a/b", "pack-\u{0}x"] {
            let folder = try #require(runner.cardsFolder(hostile))
            #expect(folder.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL, "\(hostile)")
            #expect(!folder.lastPathComponent.hasPrefix(".") && !folder.lastPathComponent.isEmpty, "\(hostile)")
        }
        #expect(runner.cardsFolder("pack-../watch-sale-items")?.lastPathComponent != "watch-sale-items")
        #expect(CardInboxFormat.safe("pack-" + "my pack") == "pack-my-pack")
        var watch = WatchListWatch(name: "Fashion", check: "", items: [])
        watch.path = "holiday/oct/fashion"
        #expect(WatchListCards.source(for: watch) == "watch-holiday-oct-fashion")
        watch.source = .team
        #expect(WatchListCards.source(for: watch) == "watch-team-holiday-oct-fashion")

        runner.cardsRoot = nil
        #expect(runner.cardsFolder("pack-shop") == nil)
    }

    /// The guide's five lines, run by a real script: a card reaches Morning Files with no model.
    @Test func aPackScriptWritesACardWithTheGuidesFiveLines() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cards-script-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = root.appendingPathComponent("tools/shop")
        try FileManager.default.createDirectory(at: pack.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try "---\nname: Shop\n---\nFixture.".write(to: pack.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try """
        def run() -> str:
            \"\"\"Writes one card.\"\"\"
            \(Self.guideExample.replacingOccurrences(of: "\n", with: "\n    "))
            return os.environ["NOTELING_CARDS_DIR"]
        """.write(to: pack.appendingPathComponent("scripts/refunds.py"), atomically: true, encoding: .utf8)
        let runner = ScriptRunner(config: Config())
        let inbox = root.appendingPathComponent("cards/inbox")
        runner.cardsRoot = inbox
        let registry = ToolRegistry(root: root.appendingPathComponent("tools"), runner: runner)
        await registry.reload()
        let script = try #require(registry.script(named: "shop__refunds"))

        let folder = try #require(try await runner.result(script) as? String)
        #expect(URL(fileURLWithPath: folder).standardizedFileURL == inbox.appendingPathComponent("pack-shop").standardizedFileURL)
        let watched = try #require(try await runner.result(script, cardsSource: "watch-sale-items") as? String)
        #expect(URL(fileURLWithPath: watched).lastPathComponent == "watch-sale-items")

        let store = MorningStore(directory: root.appendingPathComponent("morning"))
        CardInbox(store: store, directory: inbox).scan(at: at)
        let card = try #require(store.cards.first { $0.inbox?.key == "pack-shop/order-123" })
        #expect(card.title == "Refund ready · Order 123" && card.meaning == "The price dropped by $10 after you paid.")
        #expect(card.sources.first?.url == "https://shop.example.com/order/123")
        #expect(store.cards.filter(\.isFromInbox).count == 2)   // one per folder: the pack's and the watch's
        #expect(!FileManager.default.fileExists(atPath: inbox.appendingPathComponent("pack-shop/order-123.json.tmp").path))
    }

    /// The example in the guide, line for line.
    static let guideExample = """
    import json, os
    card = {"title": "Refund ready · Order 123", "body": "The price dropped by $10 after you paid.", "url": "https://shop.example.com/order/123"}
    path = os.path.join(os.environ["NOTELING_CARDS_DIR"], "order-123.json")   # this script's own folder in the inbox
    with open(path + ".tmp", "w") as f: json.dump(card, f)
    os.replace(path + ".tmp", path)   # the whole file at once, so Noteling never reads half of it
    """
}

/// A cards inbox and a Morning store in a temp folder of their own.
@MainActor
struct InboxFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("card-inbox-\(UUID().uuidString)")
    var directory: URL { root.appendingPathComponent("cards/inbox") }
    var morning: URL { root.appendingPathComponent("morning") }
    let store: MorningStore
    let inbox: CardInbox
    private static var stamp = Date(timeIntervalSince1970: 1_700_000_000)

    init() {
        store = MorningStore(directory: root.appendingPathComponent("morning"))
        inbox = CardInbox(store: store, directory: root.appendingPathComponent("cards/inbox"))
    }

    /// Writes a card file, each with a later modification time, as a script writing it again would.
    func write(_ source: String, _ id: String, _ text: String) throws {
        let folder = directory.appendingPathComponent(source)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(id + ".json")
        try Data(text.utf8).write(to: file)
        Self.stamp += 1
        try FileManager.default.setAttributes([.modificationDate: Self.stamp], ofItemAtPath: file.path)
    }

    func delete(_ source: String, _ id: String) throws {
        try FileManager.default.removeItem(at: directory.appendingPathComponent(source).appendingPathComponent(id + ".json"))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
