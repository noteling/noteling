import Foundation
import Testing
@testable import Familiar

/// A watch's card carries its run's full results for Excel, as its watch.json's `files` say: `problems.csv` by default,
/// `all.csv` too when asked, or none. One row per item with exactly these columns, RFC 4180, a byte order mark, numbers
/// as the check wrote them, and files split where Excel stops. The checks are fakes: no Python, no network; temp
/// folders only.
@Suite @MainActor
struct WatchListExportTests {
    private let checked = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09-21 14:13:20 UTC
    private let utc = TimeZone(identifier: "UTC")!
    private let bom = Data([0xEF, 0xBB, 0xBF])

    /// An item as a run left it.
    private func item(_ key: String, title: String? = nil, state: [String: WatchListValue]? = nil, expected: [String: WatchListValue]? = nil,
                      _ status: WatchListStatus?, why: [String]? = nil) -> WatchListItem {
        var item = WatchListItem(key: key)
        item.title = title
        item.url = title == nil ? nil : "https://shop.example.com/item/\(key)"
        item.state = state
        item.expected = expected
        item.why = why
        item.checkedAt = status == nil ? nil : checked
        item.status = status
        return item
    }

    /// One run of each kind: couldn't check, not as expected (twice), as expected, and not checked yet, in that order.
    private func mixed() -> WatchListWatch {
        let price = WatchListDifference(field: "price", now: .number(12.5), expected: .number(19.99))
        let stock = WatchListDifference(field: "in_stock", now: .flag(false), expected: .flag(true))
        var watch = WatchListWatch(name: "Sale items", check: "shop__watch_item", items: [
            item("790", title: "Red mug", state: ["price": .number(5), "seller": .text("Earlier seller")], expected: ["price": .number(5)],
                 .couldNotCheck("It took longer than 60 seconds."), why: ["An earlier check's words"]),
            item("123", title: "Blue kettle",
                 state: ["price": .number(12.5), "badges": .list(["Deal", "New"]), "in_stock": .flag(true), "seller": .text("Acme")],
                 expected: ["price": .number(19.99), "badges": .text("Deal")], .notAsExpected([price]),
                 why: ["The sale price ended early.", "It may come back on Friday."]),
            item("g1", title: "Mug, \"tall\"\nwhite", state: ["price": .number(19.99), "badges": .list([]), "in_stock": .flag(true)],
                 expected: ["price": .number(19.99)], .asExpected, why: ["Matches the list."]),
            item("456", state: ["price": .number(13.95), "in_stock": .flag(false), "seller": .none],
                 expected: ["price": .number(13.95), "in_stock": .flag(true)], .notAsExpected([stock])),
            item("https://shop.example.com/item/999", nil),
        ])
        watch.path = "sale-items"
        watch.fields = ["Price"]
        watch.files = [.problems, .all]
        return watch
    }

    /// A temp cards inbox, and what its watch folder holds.
    private struct Inbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("watch-export-\(UUID().uuidString)")
        var folder: URL { root.appendingPathComponent("watch-sale-items") }
        func names() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() }
        func data(_ name: String) throws -> Data { try Data(contentsOf: folder.appendingPathComponent(name)) }
        func job() throws -> [String: Any] { try #require(try JSONSerialization.jsonObject(with: data("job.json")) as? [String: Any]) }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private func row(_ cells: String...) -> String { cells.joined(separator: ",") + "\r\n" }

    // MARK: what the files say

    @Test func aMixedRunsFilesHaveExactlyTheseColumnsAndRows() throws {
        let inbox = Inbox()
        defer { inbox.remove() }
        let cards = WatchListCards(root: inbox.root)
        cards.timeZone = utc

        cards.reconcile([mixed()])

        // The fields the watch names first, then the rest alphabetically; what it shows now, then what counts as right.
        let header = row("item", "title", "url", "status", "symptoms", "price", "badges", "in_stock", "seller",
                         "expected price", "expected badges", "expected in_stock", "why", "checked_at", "check")
        let at = "2026-09-21 14:13:20", check = "shop__watch_item"
        let kettle = row("123", "Blue kettle", "https://shop.example.com/item/123", "not as expected", "price", "12.5", "Deal; New", "yes", "Acme",
                         "19.99", "Deal", "", "The sale price ended early. / It may come back on Friday.", at, check)
        let untitled = row("456", "", "", "not as expected", "in_stock", "13.95", "", "no", "none", "13.95", "", "yes", "", at, check)
        // Couldn't check: nothing from an earlier check, only what counts as right and why it couldn't.
        let mug = row("790", "Red mug", "https://shop.example.com/item/790", "couldn't check", "", "", "", "", "", "5", "", "",
                      "It took longer than 60 seconds.", at, check)
        let green = row("g1", "\"Mug, \"\"tall\"\"\nwhite\"", "https://shop.example.com/item/g1", "as expected", "", "19.99", "none", "yes", "",
                        "19.99", "", "", "Matches the list.", at, check)
        let unchecked = row("https://shop.example.com/item/999", "", "https://shop.example.com/item/999", "not checked yet",
                            "", "", "", "", "", "", "", "", "", "", check)
        // Problems: not as expected first, then couldn't check. All: the watch's own order.
        #expect(try inbox.data("problems.csv") == bom + Data((header + kettle + untitled + mug).utf8))
        #expect(try inbox.data("all.csv") == bom + Data((header + mug + kettle + green + untitled + unchecked).utf8))
        #expect(try inbox.job()["files"] as? [String] == ["problems.csv", "all.csv"])
        #expect(try inbox.names() == ["all.csv", "job.json", "problems.csv"])
    }

    @Test func cellsAreWrittenAsRFC4180SaysWithNumbersAsTheCheckWroteThem() throws {
        #expect(WatchListExport.field("plain words") == "plain words")
        #expect(WatchListExport.field("a, b") == "\"a, b\"")
        #expect(WatchListExport.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(WatchListExport.field("two\nlines") == "\"two\nlines\"" && WatchListExport.field("two\r\nlines") == "\"two\r\nlines\"")

        // Numbers as the check wrote them, from its JSON.
        let reading = WatchListReading.parse(try JSONSerialization.jsonObject(with: Data(#"{"title": "T", "state": {"price": 19.99, "was": 13.95, "count": 3, "tiny": 0.000012}}"#.utf8)))
        guard case .checked(let found) = reading else { Issue.record("not read"); return }
        #expect(WatchListExport.value(found.state["price"]) == "19.99" && WatchListExport.value(found.state["was"]) == "13.95")
        #expect(WatchListExport.value(found.state["count"]) == "3" && WatchListExport.value(found.state["tiny"]) == "1.2e-05")
        #expect(WatchListExport.value(.number(-5)) == "-5" && WatchListExport.value(.flag(false)) == "no")
        #expect(WatchListExport.value(.list(["Deal", "New"])) == "Deal; New" && WatchListExport.value(.list([])) == "none")
        #expect(WatchListExport.value(WatchListValue.none) == "none" && WatchListExport.value(nil) == "")

        // Text Excel would run as a formula shows as written instead; plain numbers and other text stay as they are.
        #expect(WatchListExport.text("=HYPERLINK(\"https://evil.example.com\")") == "'=HYPERLINK(\"https://evil.example.com\")")
        #expect(WatchListExport.text("-20% off today") == "'-20% off today" && WatchListExport.text("+1 colour") == "'+1 colour")
        #expect(WatchListExport.text("@sum") == "'@sum" && WatchListExport.text("-5") == "-5" && WatchListExport.text("+1.5e3") == "+1.5e3")
        #expect(WatchListExport.text("Blue kettle") == "Blue kettle" && WatchListExport.text("") == "")

        // A whole file: a byte order mark, so Excel reads every language, then lines ending in CRLF.
        var watch = WatchListWatch(name: "Sale items", check: "c", items: [
            item("1", title: "Überraschung, ca. 3 €", state: ["price": .number(19.99)], expected: ["price": .number(9.99)],
                 .notAsExpected([WatchListDifference(field: "price", now: .number(19.99), expected: .number(9.99))])),
        ])
        watch.files = [.problems]
        let part = try #require(WatchListExport.parts(for: watch).first)
        let data = WatchListExport.csv(part, columns: WatchListExport.columns(for: watch), check: "c", timeZone: utc)
        #expect(data.prefix(3) == bom)
        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        #expect(text == "item,title,url,status,symptoms,price,expected price,why,checked_at,check\r\n"
                + "1,\"Überraschung, ca. 3 €\",https://shop.example.com/item/1,not as expected,price,19.99,9.99,,2026-09-21 14:13:20,c\r\n")
    }

    // MARK: which files

    @Test func aWatchSaysWhichFilesItsCardCarries() throws {
        let inbox = Inbox()
        defer { inbox.remove() }
        let cards = WatchListCards(root: inbox.root)
        var watch = mixed()

        cards.reconcile([watch])
        #expect(try inbox.names() == ["all.csv", "job.json", "problems.csv"])

        watch.files = [.problems]   // the default
        cards.reconcile([watch])
        #expect(try inbox.names() == ["job.json", "problems.csv"])
        #expect(try inbox.job()["files"] as? [String] == ["problems.csv"])

        watch.files = []
        cards.reconcile([watch])
        #expect(try inbox.names() == ["job.json"])
        #expect(try inbox.job()["files"] == nil)

        // With "cards": "all" and nothing wrong, there are no problems to carry; every item, when asked.
        watch.cards = .all
        watch.items = [item("1", title: "Blue kettle", state: ["price": .number(10)], expected: ["price": .number(10)], .asExpected)]
        watch.files = [.problems]
        cards.reconcile([watch])
        #expect(try inbox.names() == ["job.json"])
        watch.files = [.problems, .all]
        cards.reconcile([watch])
        #expect(try inbox.names() == ["all.csv", "job.json"])
        #expect(try inbox.job()["files"] as? [String] == ["all.csv"])

        // "cards": false: no card and no files.
        watch.cards = .off
        #expect(cards.reconcile([watch]))
        #expect(try inbox.names().isEmpty)
    }

    @Test func theFilesOptionIsReadAndWritten() throws {
        func files(_ value: String?) throws -> [WatchListCardFile] {
            let json = value.map { #"{"items": ["1"], "files": \#($0)}"# } ?? #"{"items": ["1"]}"#
            return try WatchListFiles.parseDefinition(Data(json.utf8), folder: "sale", created: checked).definition.files
        }
        #expect(try files(nil) == [.problems] && files("null") == [.problems])
        #expect(try files("[]") == [])
        #expect(try files(#"["problems", "all"]"#) == [.problems, .all])
        #expect(try files(#"["all", " Problems ", "all"]"#) == [.problems, .all])
        #expect(try files(#"["all.csv"]"#) == [.all])
        let wrong = WatchListError(#"files must list "problems", "all" or both, or be [] for none."#)
        #expect(throws: wrong) { try files(#"["everything"]"#) }
        #expect(throws: wrong) { try files(#""all""#) }
        #expect(throws: wrong) { try files("[1]") }

        var definition = try WatchListFiles.parseDefinition(Data(#"{"items": ["1"], "files": ["all", "problems"]}"#.utf8), folder: "sale",
                                                             created: checked).definition
        #expect(WatchListFiles.definitionText(definition).contains(#""files": ["problems", "all"]"#))
        definition.files = []
        #expect(WatchListFiles.definitionText(definition).contains(#""files": []"#))
        definition.files = [.problems]
        #expect(!WatchListFiles.definitionText(definition).contains("files"))

        // Kept in the watch's folder, and read back.
        let place = Place()
        defer { place.remove() }
        var watch = WatchListWatch(name: "Sale items", check: "shop__watch_item", items: [WatchListItem(key: "1")])
        watch.files = [.all]
        try place.store().add(watch)
        #expect(place.store().watches.first?.files == [.all])
        try place.edit("sale-items") { $0["files"] = ["problems", "all"] }
        let store = place.store()
        #expect(store.watches.first?.files == [.problems, .all])
    }

    // MARK: Excel's limit

    @Test func aListLongerThanExcelOpensIsSplitAndTheCardSaysSo() throws {
        let inbox = Inbox()
        defer { inbox.remove() }
        let cards = WatchListCards(root: inbox.root)
        cards.rowLimit = 2
        let wrong = WatchListStatus.notAsExpected([WatchListDifference(field: "price", now: .number(12), expected: .number(10))])
        var watch = WatchListWatch(name: "Sale items", check: "c", items: (1...5).map {
            item("k\($0)", state: ["price": .number(12)], expected: ["price": .number(10)], wrong)
        })
        watch.path = "sale-items"
        watch.files = [.problems, .all]

        cards.reconcile([watch])

        let parts = ["problems-1.csv", "problems-2.csv", "problems-3.csv", "all-1.csv", "all-2.csv", "all-3.csv"]
        #expect(try inbox.job()["files"] as? [String] == parts)
        #expect(try inbox.names() == (parts + ["job.json"]).sorted())
        let body = try #require(try inbox.job()["body"] as? String)
        #expect(body.hasPrefix("5 not as expected · checked \(WatchListCards.time(checked)) by c\n"
                               + "The problems are in 3 files: Excel opens at most 1,048,576 rows per file.\n"
                               + "All results are in 3 files: Excel opens at most 1,048,576 rows per file.\n\nk1\n"))
        // Each part has its header and its share of the items, in order.
        for (index, keys) in [["k1", "k2"], ["k3", "k4"], ["k5"]].enumerated() {
            let lines = String(decoding: try inbox.data("all-\(index + 1).csv").dropFirst(3), as: UTF8.self)
                .components(separatedBy: "\r\n").dropLast()
            #expect(lines.first?.hasPrefix("item,title,url,status") == true)
            #expect(lines.dropFirst().map { String($0.prefix(while: { $0 != "," })) } == keys)
        }

        // Fewer items: one file of each kind again, and the parts go.
        watch.items = Array(watch.items.prefix(2))
        cards.reconcile([watch])
        #expect(try inbox.names() == ["all.csv", "job.json", "problems.csv"])
        #expect(try (inbox.job()["body"] as? String)?.contains("Excel") == false)
        // What Excel opens, a header and 1,048,575 rows, is the limit.
        #expect(WatchListExport.rowLimit == 1_048_575 && WatchListCards(root: nil).rowLimit == 1_048_575)
        watch.items = (1...4).map { item("k\($0)", wrong) }
        #expect(WatchListExport.parts(for: watch, rowLimit: 2).map(\.name) == ["problems-1.csv", "problems-2.csv", "all-1.csv", "all-2.csv"])
        #expect(WatchListExport.parts(for: watch, rowLimit: 4).map(\.name) == ["problems.csv", "all.csv"])
        #expect(WatchListExport.isOwn("all-12.csv") && !WatchListExport.isOwn("all-.csv") && !WatchListExport.isOwn("prices.csv"))
    }

    // MARK: with the runner and the inbox

    @Test func theInboxTakesTheFilesWithTheCardAndTheLatestWhenOnlyTheyChange() async throws {
        let fixture = try CardsFixture()
        defer { fixture.remove() }
        let watch = WatchListWatch(name: "Sale items", check: "shop__watch_item", items: [WatchListItem(key: "1", expect: ["price": .number(10)])])
        try fixture.store.add(watch)
        func reading(_ seller: String) -> WatchListOutcome {
            .checked(WatchListReading(title: "Item 1", url: "https://shop.example.com/item/1", state: ["price": .number(12), "seller": .text(seller)],
                                      facts: nil))
        }
        fixture.checks.next["1"] = [reading("Acme")]
        await fixture.runner.run(watch.id)?.value

        let folder = fixture.inbox.appendingPathComponent("watch-sale-items")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["job.json", "problems.csv"])
        #expect(try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("problems.csv").path)[.posixPermissions] as? Int == 0o600)
        let morning = MorningStore(directory: fixture.place.root.appendingPathComponent("morning"))
        let inbox = CardInbox(store: morning, directory: fixture.inbox)
        inbox.scan()
        let card = try #require(morning.cards.first)
        #expect(card.files.map(\.name) == ["problems.csv"])
        let copy = CardFiles.folder(for: card.id, in: fixture.place.root.appendingPathComponent("cards/files")).appendingPathComponent("problems.csv")
        #expect(try Data(contentsOf: copy) == Data(contentsOf: folder.appendingPathComponent("problems.csv")))
        #expect(String(decoding: try Data(contentsOf: copy), as: UTF8.self).contains(",Acme,"))

        // The next run finds the same problem and another seller: the card's words stay the same, its file doesn't, so
        // the card file is written again and the inbox takes the latest.
        let job = try Data(contentsOf: folder.appendingPathComponent("job.json"))
        fixture.checks.next["1"] = [reading("Other")]
        await fixture.runner.run(watch.id)?.value
        #expect(try Data(contentsOf: folder.appendingPathComponent("job.json")) == job)
        #expect(fixture.changes == 2)
        inbox.scan()
        #expect(String(decoding: try Data(contentsOf: copy), as: UTF8.self).contains(",Other,"))
        #expect(morning.cards.count == 1 && morning.cards.first?.files.map(\.name) == ["problems.csv"])

        // Nothing new: nothing is written.
        fixture.checks.next["1"] = [reading("Other")]
        await fixture.runner.run(watch.id)?.value
        #expect(fixture.changes == 2)
    }
}
