import Foundation
import Testing
@testable import Familiar

/// Which packs a page gets: the ones whose rules hit it, best fit first (that one leads), the packs they use here,
/// and the packs for anywhere. A pack with no rules is a library: nothing until a pack uses it. Packs for other pages
/// are named, never their tools.
@Suite @MainActor
struct PackSelectionTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent("pack-selection-\(UUID().uuidString)")
    private var root: URL { home.appendingPathComponent("tools") }
    private var linkedRoot: URL { home.appendingPathComponent("linked-tools") }

    private func write(_ name: String, _ skill: String, linked: Bool = false) throws {
        let dir = (linked ? linkedRoot : root).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try skill.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    private func registry(linked: Bool = false) async -> ToolRegistry {
        let registry = ToolRegistry(root: root, runner: ScriptRunner(config: Config()))
        if linked { registry.linkedRoot = linkedRoot }
        await registry.reload()
        for pack in registry.packs {
            pack.scripts = [ScriptTool(id: "\(pack.dirName)__tool", packDir: pack.dirName, fileName: "tool.py",
                                       path: pack.dir.appendingPathComponent("scripts/tool.py"), description: "A tool.",
                                       inputSchema: ["type": "object", "properties": [:]], dependencies: [])]
        }
        return registry
    }

    private func scene(_ url: String?, title: String = "Orders") -> ScreenContext {
        ScreenContext(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: title, url: url, focused: nil, timestamp: Date())
    }

    @Test func theBestFitLeadsAndALibraryComesOnlyWithAPackThatUsesIt() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("site", "---\nname: Site\nmatch:\n  urls: [example.com]\nuses: [orders-api, shared]\n---\nThe site.")
        try write("order-page", "---\nname: Order page\nmatch:\n  urls: [orders.example.com/order/]\nbrief: brief\npen: [Why stuck?]\n---\nAn order.")
        try write("orders-api", "---\nname: Orders API\n---\nA library.")
        try write("shared", "---\nname: Shared\nmatch: anywhere\n---\nEverywhere.")
        try write("unused-lib", "---\nname: Unused\n---\nNobody uses it.")
        try write("elsewhere", "---\nname: Elsewhere\nmatch:\n  urls: [other.test]\n---\nFor other pages.")
        let registry = await registry()

        let order = registry.select(for: scene("https://orders.example.com/order/4417"))
        #expect(order.active.map(\.dirName) == ["order-page", "site"])
        #expect(order.lead?.dirName == "order-page")
        #expect(order.hits["order-page"]?.rule == "orders.example.com/order/" && order.hits["site"]?.rule == "example.com")
        #expect(order.hooked.map(\.dirName) == ["orders-api"] && order.usedBy["orders-api"] == ["Site"])
        #expect(order.global.map(\.dirName) == ["shared"] && order.usedBy["shared"] == nil)   // used or not, it is for anywhere
        #expect(order.others.map(\.dirName) == ["elsewhere", "unused-lib"])
        #expect(order.offered.map(\.dirName) == ["order-page", "site", "orders-api", "shared"])
        #expect(order.scope(of: order.active[0]) == "for this page" && order.scope(of: order.hooked[0]) == "used here by Site")
        #expect(order.scope(of: order.global[0]) == "anywhere" && order.scope(of: order.others[1]) == "a library")
        #expect(order.scope(of: order.others[0]) == "for other pages")
        #expect(Prompt.penQuestions(packs: order.active) == ["Why stuck?"])

        let home = registry.select(for: scene("https://www.example.com/"))
        #expect(home.active.map(\.dirName) == ["site"] && home.hooked.map(\.dirName) == ["orders-api"])

        let nowhere = registry.select(for: scene("https://nothing.test/"))
        #expect(nowhere.active.isEmpty && nowhere.hooked.isEmpty && nowhere.global.map(\.dirName) == ["shared"])
        #expect(nowhere.others.map(\.dirName) == ["elsewhere", "order-page", "orders-api", "site", "unused-lib"])

        let blind = registry.select(for: nil)
        #expect(blind.active.isEmpty && blind.global.map(\.dirName) == ["shared"] && blind.others.count == 5)
    }

    @Test func usesFollowsWhatTheUsedPacksUseOnceEachAndIgnoresNamesThatAreNotPacks() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("page", "---\nname: Page\nmatch:\n  urls: [a.test]\nuses: [one, missing, page, two]\n---\n")
        try write("one", "---\nname: One\nuses: [two, three]\n---\n")
        try write("two", "---\nname: Two\nuses: [one]\n---\n")
        try write("three", "---\nname: Three\nmatch:\n  urls: [b.test]\n---\nA pack for another page, used here too.")
        try write("root", "---\nname: Root\nmatch: anywhere\nuses: [four]\n---\n")
        try write("four", "---\nname: Four\n---\n")
        let registry = await registry()
        let selection = registry.select(for: scene("https://a.test/"))
        #expect(selection.active.map(\.dirName) == ["page"])
        #expect(selection.hooked.map(\.dirName) == ["one", "two", "four", "three"])
        #expect(selection.usedBy["one"] == ["Page", "Two"] && selection.usedBy["two"] == ["Page", "One"] && selection.usedBy["three"] == ["One"])
        #expect(selection.usedBy["four"] == ["Root"] && selection.others.isEmpty)
        #expect(selection.scope(of: selection.hooked[0]) == "used here by Page and Two")
        #expect(registry.packs.first { $0.dirName == "page" }?.uses == ["one", "missing", "two"])   // a pack never uses itself
    }

    @Test func aTieGoesToYourOwnPackThenToTheFolderName() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("zeta", "---\nname: Zeta\nmatch:\n  urls: [a.test/x/]\n---\n")
        try write("alpha", "---\nname: Alpha\nmatch:\n  urls: [a.test/x/]\n---\n")
        try write("team", "---\nname: Team\nmatch:\n  urls: [a.test/x/]\n---\n", linked: true)
        try write("mine", "---\nname: Mine\nmatch:\n  urls: [a.test/x/]\n---\n", linked: true)
        try write("deeper", "---\nname: Deeper\nmatch:\n  urls: [a.test/x/y/]\n---\n", linked: true)
        let registry = await registry(linked: true)
        let selection = registry.select(for: scene("https://a.test/x/y/1"))
        #expect(selection.active.map(\.dirName) == ["deeper", "alpha", "zeta", "mine", "team"])
        #expect(selection.lead?.linked == true)   // the narrowest rule leads even from the team's tools
    }

    @Test func theRequestSaysWhoLeadsWhoIsUsedAndWhereTheRestApply() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("order-page", "---\nname: Order page\ndescription: Orders.\nmatch:\n  urls: [orders.example.com/order/]\nuses: [orders-api, shared]\n---\nAn order.")
        try write("orders-api", "---\nname: Orders API\ndescription: The API.\n---\nA library.")
        try write("shared", "---\nname: Shared\ndescription: Helpers.\nmatch: anywhere\n---\nEverywhere.")
        try write("hr", "---\nname: HR\ndescription: HR pages.\nmatch:\n  urls: [hr.example.com]\n  titles: [HR Portal]\n---\n")
        try write("spare", "---\nname: Spare\ndescription: Unused.\n---\n")
        let registry = await registry()
        let page = scene("https://orders.example.com/order/4417")
        let section = Prompt.toolPacks(registry.select(for: page), scene: page, stuffLimit: 10_000)
        #expect(section.contains("## Active tool pack: Order page (leads here: orders.example.com/order/)"))
        #expect(section.contains("## Tool pack used here: Orders API (by Order page)"))
        #expect(section.contains("## Shared tool pack: Shared (anywhere)") && !section.contains("used here: Shared"))   // used, still anywhere
        #expect(section.contains("- hr: HR. HR pages. (for hr.example.com, windows titled “HR Portal”)"))
        #expect(section.contains("- spare: Spare. Unused. (a library: its tools come along with a pack that uses it)"))
        #expect(section.contains("- orders-api__tool: A tool.") && !section.contains("spare__tool"))
        #expect(!section.contains("No tool pack matched"))

        let elsewhere = scene("https://nothing.test/")
        let none = Prompt.toolPacks(registry.select(for: elsewhere), scene: elsewhere, stuffLimit: 10_000)
        #expect(none.contains("No tool pack matched the current app/URL. Answer from the screen"))
        let blind = Prompt.toolPacks(registry.select(for: nil), scene: nil, stuffLimit: 10_000)
        #expect(blind.contains("No tool pack matched the current app/URL: nothing could be read about what is in front"))
        #expect(blind.contains("## Shared tool pack: Shared (anywhere)"))

        // Tools say where their pack stands, so a tool for this page reads differently from one for anywhere.
        let selection = registry.select(for: page)
        let lead = try #require(selection.lead?.scripts.first)
        #expect(lead.definition(scope: selection.scope(of: selection.lead!))["description"] as? String == "[order-page/scripts/tool.py, for this page] A tool.")
        #expect(lead.definition["description"] as? String == "[order-page/scripts/tool.py] A tool.")
        #expect(selection.scope(of: selection.global[0]) == "anywhere")
    }

    /// A tools folder from before packs said `match: anywhere`: its own packs with no rules applied everywhere, so
    /// once, they say so; after that a pack left without rules is a library, as meant.
    @Test func aFolderFromBeforeHasItsRulelessPacksSayAnywhereOnce() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("shared", "---\nname: Shared\ndescription: Helpers.\n---\nMy own words.\n")
        try write("mine", "---\r\nname: Mine\r\n---\r\nMy helpers, saved on Windows.\r\n")
        try write("expenses", "---\nname: Expenses\nmatch:\n  urls: [expenses.internal.example.com]\n---\n")
        try write("deliberate", "---\nname: Deliberate\nmatch:\n---\nA match line with nothing: left alone.\n")
        try write("bare", "No front matter at all.\n")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)

        #expect(ToolRegistry.markOwnPacksAnywhereOnce(in: root) == ["mine", "shared"])
        let shared = try String(contentsOf: root.appendingPathComponent("shared/SKILL.md"), encoding: .utf8)
        #expect(shared == "---\nname: Shared\ndescription: Helpers.\nmatch: anywhere\n---\nMy own words.\n")   // the words stay theirs
        #expect(try String(contentsOf: root.appendingPathComponent("mine/SKILL.md"), encoding: .utf8) == "---\r\nname: Mine\r\nmatch: anywhere\r\n---\r\nMy helpers, saved on Windows.\r\n")
        for untouched in ["expenses", "deliberate", "bare"] {
            #expect(!(try String(contentsOf: root.appendingPathComponent("\(untouched)/SKILL.md"), encoding: .utf8)).contains("anywhere"))
        }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(ToolRegistry.placesAskedMarker).path))

        // Once: a pack left without rules from now on is a library.
        try write("later", "---\nname: Later\n---\nA library, as meant.\n")
        #expect(ToolRegistry.markOwnPacksAnywhereOnce(in: root).isEmpty)
        #expect(!(try String(contentsOf: root.appendingPathComponent("later/SKILL.md"), encoding: .utf8)).contains("anywhere"))
        #expect(ToolRegistry.libraryPacks(in: root) == ["bare", "deliberate", "empty", "later"])
        #expect(ToolRegistry.markOwnPacksAnywhereOnce(in: home.appendingPathComponent("nowhere")).isEmpty)   // no folder, no marker
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("nowhere").path))
    }

    @Test func aBriefsFactsReachTheToolsAsCompactJSON() {
        let brief = PageBriefs.Brief(pack: "Orders", script: "orders__brief", page: "p",
                                     text: "{\"glance\":{\"headline\":\"Order 4417\"},\"facts\":{\"order\":\"4417\",\"status\":\"waiting\"}}", at: Date())
        #expect(brief.facts == "{\"order\":\"4417\",\"status\":\"waiting\"}")
        #expect(PageBriefs.Brief(pack: "Orders", script: "s", page: "p", text: "{\"glance\":{}}", at: Date()).facts == nil)
        #expect(PageBriefs.Brief(pack: "Orders", script: "s", page: "p", text: "not json", at: Date()).facts == nil)
        #expect(PageBriefs.Brief(pack: "Orders", script: "s", page: "p", text: "{\"facts\":{\"a\":1}}", at: Date(), failed: true).facts == nil)
    }
}
