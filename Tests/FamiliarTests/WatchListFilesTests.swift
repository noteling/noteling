import Foundation
import Testing
@testable import Familiar

/// A watch's files as people meet them: a watch.json written by hand is read leniently and, when it can't be, says what
/// is wrong in plain words; folder names come from watch names; latest.json keeps exactly what was found.
@Suite @MainActor
struct WatchListFilesTests {
    private let created = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func aHandWrittenWatchJsonNeedsOnlyItsItems() throws {
        let json = """
        {"items": ["123", 456, {"key": "https://shop.example.com/item/789", "expect": {"price": 19.99}}, "123", "  "],
         "every_minutes": "1000", "fields": ["price", " badges ", "price"], "args": {"zip": "10001", "item": "x"},
         "requires": ["SHOP_TOKEN"], "check": " shop__watch_item ", "owner": "Pricing team"}
        """
        let (definition, hadID) = try WatchListFiles.parseDefinition(Data(json.utf8), folder: "weekend", created: created)
        #expect(!hadID && definition.id == WatchListFiles.derivedID(folder: "weekend"))
        #expect(definition.name == "weekend" && definition.check == "shop__watch_item")
        #expect(definition.items == [.init(key: "123"), .init(key: "456"),
                                     .init(key: "https://shop.example.com/item/789", expect: ["price": .number(19.99)])])
        #expect(definition.everyMinutes == 240 && !definition.paused && definition.createdAt == created)
        #expect(definition.fields == ["price", "badges"] && definition.args == ["zip": .text("10001")])
        #expect(definition.requires == ["SHOP_TOKEN"])
        #expect(definition.other == #"{"owner":"Pricing team"}"#)
        #expect(WatchListFiles.definitionText(definition).contains("  \"owner\": \"Pricing team\"\n}"))   // kept, at the end
    }

    @Test func aWatchJsonThatCantBeReadSaysWhyInPlainWords() {
        func problem(_ json: String) -> String? {
            do { _ = try WatchListFiles.parseDefinition(Data(json.utf8), folder: "f", created: created); return nil }
            catch { return WatchListStore.reason(error) }
        }
        #expect(problem("[1, 2]") == "it must be one JSON object: { … }.")
        #expect(problem("{\"name\": \"x\"}") == "it needs items: a list of item ids or page addresses, or an items file beside it.")
        #expect(problem("{\"items\": \"123\"}") == "items must be a list of item ids or page addresses, [ … ].")
        #expect(problem("{\"items\": [true]}") == "item 1 must be an id or page address in quotes, or an object with a key: { \"key\": … }.")
        #expect(problem("{\"items\": [\"1\"], \"every_minutes\": \"often\"}") == "every_minutes must be a number of minutes, 5 to 240.")
        #expect(problem("{\"items\": [\"1\"], \"paused\": \"maybe\"}") == "paused must be true or false.")
        #expect(problem("{\"items\": [\"1\"], \"expect\": [1]}") == "expect must be an object of field → value, { … }.")
        #expect(problem("{\"items\": [\"1\"], \"fields\": [1]}") == "fields must be a list of field names in quotes.")
        #expect(problem("{\"items\": [\"1\"], \"name\": 3}") == "name must be text in quotes.")
        #expect(problem("{\"items\": [" + (1...201).map { "\"\($0)\"" }.joined(separator: ",") + "]}") == "it lists 201 items, and a watch holds up to 200.")
        #expect(problem("{\"items\": [\"1\"")?.hasPrefix("it isn't valid JSON (") == true)
    }

    @Test func folderNamesComeFromWatchNames() {
        #expect(WatchListFiles.slug("Sale items", taken: []) == "sale-items")
        #expect(WatchListFiles.slug("  Crème brûlée / weekend!! ", taken: []) == "creme-brulee-weekend")
        #expect(WatchListFiles.slug("Sale items", taken: ["Sale-Items", "sale-items-2"]) == "sale-items-3")
        #expect(WatchListFiles.slug("…", taken: []) == "watch")
        #expect(WatchListFiles.slug(String(repeating: "long name ", count: 10), taken: []).count <= 40)
        #expect(WatchListFiles.derivedID(folder: "weekend") == WatchListFiles.derivedID(folder: "weekend"))
        #expect(WatchListFiles.derivedID(folder: "weekend") != WatchListFiles.derivedID(folder: "weekend copy"))
    }

    @Test func latestJsonKeepsExactlyWhatWasFound() throws {
        var item = WatchListItem(key: "123")
        item.title = "Blue kettle"
        item.captured = ["price": .number(12.33), "badges": .list(["Deal"]), "note": .none]
        item.expected = ["price": .number(12.33)]
        item.state = ["price": .number(13.95), "badges": .list([]), "in_stock": .flag(false)]
        item.facts = #"{"offers":[{"price":13.95,"seller":"Acme"}]}"#
        item.why = ["The page shows 13.95; the list says 12.33."]
        item.checkedAt = Date(timeIntervalSince1970: 1_790_000_123.456789)
        item.status = .notAsExpected([WatchListDifference(field: "price", now: .number(13.95), expected: .number(12.33))])
        item.notified = .asExpected
        var text = WatchListItem(key: "456")
        text.facts = "\"just words\""   // facts that are no object or list keep their text
        text.status = .couldNotCheck("Signed out")
        text.failures = 3
        text.notifiedCouldNotCheck = true
        let watch = WatchListWatch(name: "Sale items", check: "c", items: [item, text], createdAt: created,
                                   lastRunAt: Date(timeIntervalSince1970: 1_790_000_100.5))

        let written = WatchListFiles.resultsText(watch)
        #expect(written.contains("\"facts\": {\n        \"offers\": [\n"))   // readable, not a string of JSON
        var read = WatchListWatch(id: watch.id, name: "Sale items", check: "c", items: [WatchListItem(key: "123"), WatchListItem(key: "456")],
                                  createdAt: created)
        try WatchListFiles.readResults(Data(written.utf8), into: &read)
        #expect(read == watch)
    }

    @Test func anItemsFileIsReadWithTheDelimiterItsNameSays() throws {
        func rows(_ text: String, _ name: String) throws -> WatchListItemsFile {
            try WatchListFiles.parseItems(Data(text.utf8), name: name)
        }
        let psv = try rows("\u{FEFF}Item | Price | Badge | In stock\r\n123 | $1,299.00 | Deal | yes\r\n456 |  | none | no\r\n\r\n | 5 | x | y\r\n123 | 1 | 2 | 3\r\n789 | 12.5 | Deal; New | TRUE\r\n", "items.psv")
        #expect(psv.columns == ["Price", "Badge", "In stock"])
        #expect(psv.rows == [
            .init(key: "123", expect: ["Price": .number(1299), "Badge": .text("Deal"), "In stock": .flag(true)]),
            .init(key: "456", expect: ["Badge": WatchListValue.none, "In stock": .flag(false)]),   // an empty cell says nothing
            .init(key: "789", expect: ["Price": .number(12.5), "Badge": .list(["Deal", "New"]), "In stock": .flag(true)]),
        ])
        #expect(psv.skipped == ["row 5 has no item", "row 6 repeats 123"])

        let tsv = try rows("item\tbadges\n1\tnull\n2\t-\n", "items.tsv")
        #expect(tsv.rows.map(\.expect) == [["badges": WatchListValue.none], ["badges": WatchListValue.none]])
        let psvWithTabs = try rows("item\tprice\n1\t€5\n", "items.psv")   // a .psv may be separated by tabs
        #expect(psvWithTabs.rows == [.init(key: "1", expect: ["price": .number(5)])])
        let csv = try rows("item,price,note\n\"https://shop.example.com/item/1\",\"1,299.00\",\"Say \"\"hi\"\", then go\"\n", "items.csv")
        #expect(csv.rows == [.init(key: "https://shop.example.com/item/1", expect: ["price": .number(1299), "note": .text("Say \"hi\", then go")])])
        let plain = try rows("item\n1\n2\n", "items.csv")   // items only, nothing said about them
        #expect(plain.rows.map(\.key) == ["1", "2"] && plain.rows.allSatisfy { $0.expect.isEmpty })
        #expect(throws: WatchListError("items.csv is empty: it needs a header row, then one item per row.")) { try rows("\n\n", "items.csv") }
    }

    @Test func aCellSaysWhatCountsAsRightInPlainTerms() {
        #expect(WatchListFiles.cell("") == nil && WatchListFiles.cell("   ") == nil)
        #expect(WatchListFiles.cell("none") == WatchListValue.none && WatchListFiles.cell("NULL") == WatchListValue.none && WatchListFiles.cell("-") == WatchListValue.none)
        #expect(WatchListFiles.cell("$1,299.50") == .number(1299.5) && WatchListFiles.cell("-3") == .number(-3))
        #expect(WatchListFiles.cell("Yes") == .flag(true) && WatchListFiles.cell("false") == .flag(false))
        #expect(WatchListFiles.cell("Deal;New; ") == .list(["Deal", "New"]))
        #expect(WatchListFiles.cell("Overall winner") == .text("Overall winner"))
    }

    @Test func startsAndEndsAreReadWithOrWithoutAnOffset() throws {
        let offset = try #require(WatchListMoment.parse("2026-10-05T00:00:00-04:00"))
        #expect(offset.date == Date(timeIntervalSince1970: 1_791_172_800))
        #expect(WatchListMoment.parse("2026-10-05T04:00:00Z")?.date == offset.date)
        #expect(WatchListMoment.parse("2026-10-05T00:00:00-0400")?.date == offset.date)
        #expect(WatchListMoment.parse("2026-10-05T00:00-04:00")?.date == offset.date)
        var local = DateComponents()
        local.year = 2026; local.month = 10; local.day = 5
        let midnight = try #require(Calendar.current.date(from: local))   // without an offset: this Mac's time
        #expect(WatchListMoment.parse("2026-10-05T00:00:00")?.date == midnight)
        #expect(WatchListMoment.parse("2026-10-05")?.date == midnight)
        #expect(WatchListMoment.parse("2026-10-05")?.words == "Mon Oct 5, 12:00 AM")
        #expect(WatchListMoment.parse("soon") == nil)

        let json = #"{"items": ["1"], "starts": "2026-10-05", "ends": "2026-10-31T23:59:00-04:00"}"#
        let (definition, _) = try WatchListFiles.parseDefinition(Data(json.utf8), folder: "f", created: created)
        #expect(definition.starts?.date == midnight && definition.ends?.text == "2026-10-31T23:59:00-04:00")
        #expect(WatchListFiles.definitionText(definition).contains("\"starts\": \"2026-10-05\",\n  \"ends\": \"2026-10-31T23:59:00-04:00\""))
        #expect(throws: WatchListError("starts must be a date and time like 2026-10-05T00:00:00-04:00 (without the offset, it's this Mac's time).")) {
            try WatchListFiles.parseDefinition(Data(#"{"items": ["1"], "starts": "next week"}"#.utf8), folder: "f", created: created)
        }
    }

    @Test func numbersAreWrittenAsPeopleWriteThem() {
        #expect(WatchListJSON.pretty(["price": 19.99, "count": 3, "whole": 15.0, "flag": true, "none": NSNull()] as [String: Any], indent: "")
                == "{\n  \"count\": 3,\n  \"flag\": true,\n  \"none\": null,\n  \"price\": 19.99,\n  \"whole\": 15\n}")
        #expect(WatchListJSON.pretty([String](), indent: "") == "[]")
        #expect(WatchListJSON.pretty(["https://shop.example.com/a"], indent: "") == "[\"https://shop.example.com/a\"]")
    }
}
