import Foundation
import Testing
@testable import Familiar

/// Team watches: jobs kept in the team's tools under `watches/`, at any depth, which Noteling only reads. Each person
/// turns on the ones that are theirs; what they find is kept in Noteling's own folder, so it outlasts every update of
/// the team's copy. And items files: a watch's items, and what counts as right for each, in a table beside watch.json.
@Suite @MainActor
struct WatchListTeamTests {
    @Test func everyFolderWithAWatchJsonUnderTheTeamsWatchesIsAJob() throws {
        let place = Place()
        defer { place.remove() }
        try place.job("holiday/oct/fashion", #"{"name": "Fashion", "items": ["1", "2"], "every_minutes": 120}"#)
        try place.job("holiday/oct/gm", #"{"items": ["3"]}"#)
        try place.job("holiday", #"{"name": "Holiday", "items": ["4"]}"#)   // a job's folder may hold others
        try FileManager.default.createDirectory(at: place.team.appendingPathComponent("spring/drafts"), withIntermediateDirectories: true)

        let store = place.store()

        let team = store.watches.filter(\.isTeam)
        #expect(team.map(\.path).sorted() == ["holiday", "holiday/oct/fashion", "holiday/oct/gm"])
        let fashion = try #require(team.first { $0.path == "holiday/oct/fashion" })
        #expect(fashion.name == "Fashion" && fashion.everyMinutes == 120 && fashion.id == WatchListStore.teamID("holiday/oct/fashion"))
        #expect(team.first { $0.path == "holiday/oct/gm" }?.name == "holiday/oct/gm")   // no name: its path
        #expect(team.allSatisfy { !$0.on })                                              // off until the person turns it on
        #expect(store.teamUnreadable.isEmpty && store.unreadable.isEmpty)
        #expect(place.store().watches.filter(\.isTeam).count == 3)
    }

    @Test func aWatchesFolderInAToolsFolderIsNeverAPack() async throws {
        let place = Place()
        defer { place.remove() }
        let tools = place.root.appendingPathComponent("tools")
        for pack in ["shop", "watches"] {
            try FileManager.default.createDirectory(at: tools.appendingPathComponent(pack), withIntermediateDirectories: true)
            try "---\nname: \(pack)\n---\n".write(to: tools.appendingPathComponent("\(pack)/SKILL.md"), atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: place.linked.appendingPathComponent("team"), withIntermediateDirectories: true)
        try "---\nname: Team\n---\n".write(to: place.linked.appendingPathComponent("team/SKILL.md"), atomically: true, encoding: .utf8)
        try place.job("holiday/oct/fashion", #"{"items": ["1"]}"#)

        let registry = ToolRegistry(root: tools, runner: ScriptRunner(config: Config()))
        registry.linkedRoot = place.linked
        await registry.reload()

        #expect(registry.packs.map(\.dirName) == ["shop", "team"])
        #expect(ToolRegistry.packFolders(in: place.linked).map(\.lastPathComponent) == ["team"])
    }

    @Test func turningATeamJobOnIsTheOnlyChangeAndIsKeptForThePerson() throws {
        let place = Place()
        defer { place.remove() }
        try place.job("holiday/oct/fashion", #"{"name": "Fashion", "items": ["1"]}"#)
        let store = place.store()
        let id = WatchListStore.teamID("holiday/oct/fashion")

        try store.setOn(id, true)

        let on = place.teamResults.appendingPathComponent("on.json")
        #expect(try String(contentsOf: on, encoding: .utf8) == "{\n  \"on\": [\"holiday/oct/fashion\"]\n}\n")
        #expect(try FileManager.default.attributesOfItem(atPath: on.path)[.posixPermissions] as? Int == 0o600)
        #expect(place.store().watch(id: id)?.on == true)

        // Read-only: no change to what it is, no Stop; what its checks find is kept in Noteling's folder.
        #expect(throws: WatchListError(WatchListStore.teamReadOnly)) { try store.change(id) { $0.everyMinutes = 30 } }
        #expect(throws: WatchListError(WatchListStore.teamReadOnly)) { try store.remove(id) }
        try store.change(id, persist: false) { $0.lastRunAt = Date() }
        try store.save(id)
        #expect(FileManager.default.fileExists(atPath: place.teamResults.appendingPathComponent("holiday/oct/fashion/latest.json").path))
        #expect(try FileManager.default.subpathsOfDirectory(atPath: place.team.path).sorted() == ["holiday", "holiday/oct", "holiday/oct/fashion",
                                                                                                     "holiday/oct/fashion/watch.json"])

        try store.setOn(id, false)
        #expect(place.store().watch(id: id)?.on == false)
        #expect(throws: WatchListError.self) { try store.setOn(UUID(), true) }
    }

    @Test func twentyTeamJobsAtMostAreOn() throws {
        let place = Place()
        defer { place.remove() }
        for n in 1...21 { try place.job("job-\(n)", #"{"items": ["1"]}"#) }
        let store = place.store()
        for n in 1...20 { try store.setOn(WatchListStore.teamID("job-\(n)"), true) }
        #expect(throws: WatchListError("You can have up to 20 team watches on. Turn one off first.")) {
            try store.setOn(WatchListStore.teamID("job-21"), true)
        }
    }

    @Test func whatATeamJobFoundOutlastsAnUpdateOfTheTeamsTools() throws {
        let place = Place()
        defer { place.remove() }
        try place.job("holiday/oct/fashion", #"{"name": "Fashion", "items": ["1"]}"#)
        try place.job("holiday/oct/gm", #"{"name": "GM", "items": ["2"]}"#)
        let store = place.store()
        let fashion = WatchListStore.teamID("holiday/oct/fashion"), gm = WatchListStore.teamID("holiday/oct/gm")
        try store.setOn(fashion, true)
        try store.setOn(gm, true)
        for (id, key) in [(fashion, "1"), (gm, "2")] {
            try store.change(id, persist: false) { watch in
                _ = WatchListRules.apply(.checked(WatchListReading(title: "Item \(key)", url: nil, state: ["price": .number(10)], facts: nil)),
                                         to: &watch.items[0], terms: watch.terms, at: Date())
            }
            try store.save(id)
        }

        // The update keeps fashion as it was, changes nothing else about it, and takes gm out.
        try place.update { watches in try FileManager.default.removeItem(at: watches.appendingPathComponent("holiday/oct/gm")) }
        let changes = store.refresh()

        #expect(changes.removed == [gm] && changes.added.isEmpty && changes.newItems.isEmpty)
        let kept = try #require(store.watch(id: fashion))
        #expect(kept.on && kept.items[0].status == .asExpected && kept.items[0].title == "Item 1")
        // gm's findings stay until the next launch, which clears them and forgets that it was on.
        #expect(FileManager.default.fileExists(atPath: place.teamResults.appendingPathComponent("holiday/oct/gm/latest.json").path))
        let next = place.store()
        #expect(!FileManager.default.fileExists(atPath: place.teamResults.appendingPathComponent("holiday/oct/gm/latest.json").path))
        #expect(next.watch(id: fashion)?.items[0].status == .asExpected)
        #expect(try String(contentsOf: place.teamResults.appendingPathComponent("on.json"), encoding: .utf8).contains("holiday/oct/gm") == false)

        // An update that changes a job is taken in; one that brings it back makes it a job again, off.
        try place.update { watches in
            try place.write(#"{"name": "Fashion", "items": ["1", "3"]}"#, to: watches.appendingPathComponent("holiday/oct/fashion/watch.json"))
        }
        #expect(store.refresh().newItems == [fashion: ["3"]])
        #expect(store.watch(id: fashion)?.items.map(\.key) == ["1", "3"])
    }

    @Test func yourOwnWatchesMayBeInFoldersOfFoldersToo() throws {
        let place = Place()
        defer { place.remove() }
        let folder = place.watches.appendingPathComponent("holiday/oct/shoes")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try place.write(#"{"name": "Shoes", "items": ["1"]}"#, to: folder.appendingPathComponent("watch.json"))
        let store = place.store()
        let shoes = try #require(store.watches.first)
        #expect(shoes.path == "holiday/oct/shoes" && !shoes.isTeam && shoes.on)
        #expect(store.folder(for: shoes.id)?.standardizedFileURL == folder.standardizedFileURL)
    }

    // MARK: items files

    @Test func anItemsFileGivesItsItemsAndWhatCountsAsRightForEach() throws {
        let place = Place()
        defer { place.remove() }
        let folder = place.watches.appendingPathComponent("sale")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try place.write(#"{"name": "Sale", "items": ["999", {"key": "123", "expect": {"seller": "Acme"}}], "expect": {"in_stock": true}}"#,
                        to: folder.appendingPathComponent("watch.json"))
        try place.write("item|price|badge\n123|$19.99|Deal\n456||none\n|1|x\n", to: folder.appendingPathComponent("items.psv"))
        try place.write("item,price\n1,2\n", to: folder.appendingPathComponent("items.csv"))

        let store = place.store()

        let watch = try #require(store.watches.first)
        #expect(watch.items.map(\.key) == ["123", "456", "999"])   // the file's first, then watch.json's others
        #expect(watch.file?.name == "items.psv" && watch.file?.skipped == ["row 4 has no item"])
        #expect(watch.fileNote == "It has several items files: items.psv is used, and items.csv isn't.")
        let first = try #require(watch.item("123"))
        #expect(first.listed && first.ownExpect == ["seller": .text("Acme"), "price": .number(19.99), "badge": .text("Deal")])
        #expect(watch.item("456")?.listed == false && watch.item("456")?.row == ["badge": WatchListValue.none])
        #expect(watch.terms.explicit)

        // Its first check: each item's row over the watch's expect; nothing else counts.
        try store.change(watch.id, persist: false) { w in
            let state: [String: WatchListValue] = ["price": .number(24.99), "badges": .list(["Deal", "New"]), "in_stock": .flag(true), "seller": .text("Acme")]
            _ = WatchListRules.apply(.checked(WatchListReading(title: nil, url: nil, state: state, facts: nil)), to: &w.items[0], terms: w.terms, at: Date())
        }
        let checked = try #require(store.watch(id: watch.id)?.item("123"))
        #expect(checked.expected == ["price": .number(19.99), "badges": .text("Deal"), "in_stock": .flag(true), "seller": .text("Acme")])
        #expect(checked.status == .notAsExpected([WatchListDifference(field: "price", now: .number(24.99), expected: .number(19.99))]))

        // Writing watch.json keeps the file's items out of it.
        try store.change(watch.id) { $0.paused = true }
        let text = try String(contentsOf: folder.appendingPathComponent("watch.json"), encoding: .utf8)
        #expect(text.contains("\"999\"") && !text.contains("\"456\""))
    }

    @Test func aChangedItemsFileIsReadAgain() throws {
        let place = Place()
        defer { place.remove() }
        try place.job("holiday/oct/fashion", #"{"name": "Fashion"}"#, items: ("items.tsv", "item\tbadge\n1\tDeal\n"))
        let store = place.store()
        let id = WatchListStore.teamID("holiday/oct/fashion")
        #expect(store.watch(id: id)?.item("1")?.row == ["badge": .text("Deal")])

        try place.write("item\tbadge\n1\tNew\n2\tDeal\n", to: place.team.appendingPathComponent("holiday/oct/fashion/items.tsv"))
        let changes = store.refresh()

        #expect(changes.newItems == [id: ["2"]])
        #expect(store.watch(id: id)?.item("1")?.row == ["badge": .text("New")])

        try place.write("item\tbadge\n1\tNew\n2\tDeal\n", to: place.team.appendingPathComponent("holiday/oct/fashion/items.tsv"))
        #expect(store.refresh() == WatchListChanges())   // touched, not changed: nothing to take in
    }

    @Test func aTeamJobWhoseFilesCantBeReadIsListedWithWhy() throws {
        let place = Place()
        defer { place.remove() }
        try place.job("holiday/broken", #"{"name": "Broken", "items": ["#)
        try place.job("holiday/table", #"{"name": "Table"}"#, items: ("items.psv", ""))
        let store = place.store()
        #expect(store.watches.isEmpty)
        #expect(store.teamUnreadable["holiday/broken"]?.hasPrefix("Can't read watch.json: it isn't valid JSON") == true)
        #expect(store.teamUnreadable["holiday/table"] == "Can't read items.psv: items.psv is empty: it needs a header row, then one item per row.")
    }
}
