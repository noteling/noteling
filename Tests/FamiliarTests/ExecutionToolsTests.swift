import Foundation
import Testing
import FamiliarContracts
import FamiliarRuntime
@testable import Familiar

@Suite
@MainActor
struct ExecutionToolsTests {
    @Test
    func returnBasedMessageSendingHasAnApprovalToolWithoutAVisibleSendButton() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let control = ComputerController()
        control.lane = .background
        let router = try ExecutionTools.make(registry: fixture.registry(), context: nil, control: control,
                                             background: true, lookAtScreen: { .text("unused") })

        #expect(router.accepts(name: "send_message"))
        let result = await router.execute("send_message", ["recipient": "Local test", "message": "Hello 👋"])
        #expect((result.content as? String)?.contains("No target window") == true)
        #expect(!control.active)
    }

    @Test
    func backgroundScreenshotWithoutTargetDoesNotReadTheHumansDisplay() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let control = ComputerController()
        control.lane = .background
        var displayCaptures = 0
        let router = try ExecutionTools.make(registry: fixture.registry(), context: nil, control: control,
                                             background: true, lookAtScreen: {
            displayCaptures += 1
            return .text("human display fixture")
        })

        let result = await router.execute("look_at_screen", [:])

        #expect(result.isError)
        #expect(displayCaptures == 0)
        #expect((result.content as? String)?.contains("No target window") == true)
        #expect(!control.active)
    }

    @Test
    func backgroundTextWithoutTargetFailsWithoutStartingControl() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let control = ComputerController()
        control.lane = .background
        let router = try ExecutionTools.make(registry: fixture.registry(), context: nil, control: control,
                                             background: true, lookAtScreen: { .text("unused") })

        let result = await router.execute("read_screen", [:])

        #expect(result.isError)
        #expect((result.content as? String)?.contains("No target window") == true)
        #expect(!control.active)
    }

    @Test
    func foregroundAndNonControlScreenshotsKeepTheirSuppliedCapture() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let control = ComputerController()
        for (nativeControl, background) in [(control as ComputerController?, false), (nil, true)] {
            var captures = 0
            let router = try ExecutionTools.make(registry: fixture.registry(), context: nil, control: nativeControl,
                                                 background: background, lookAtScreen: {
                captures += 1
                return .text("supplied screenshot")
            })

            let result = await router.execute("look_at_screen", [:])

            #expect(!result.isError)
            #expect(result.content as? String == "supplied screenshot")
            #expect(captures == 1)
        }
        #expect(!control.active)
    }

    @Test
    func backgroundToolDescriptionsIdentifyTheTargetAndCoordinateSpace() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let router = try ExecutionTools.make(registry: fixture.registry(), context: nil, control: ComputerController(),
                                             background: true, lookAtScreen: { .text("unused") })
        let screenshot = try #require(router.definitions.first { $0["name"] as? String == "look_at_screen" })
        let text = try #require(router.definitions.first { $0["name"] as? String == "read_screen" })

        #expect((screenshot["description"] as? String)?.contains("current target window") == true)
        #expect((screenshot["description"] as? String)?.contains("computer screenshot action for display coordinates") == true)
        #expect((text["description"] as? String)?.contains("current target window") == true)
    }

    @Test
    func absentControlOmitsNativeCapabilitiesInBothLanes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let registry = fixture.registry()

        for background in [false, true] {
            let router = try ExecutionTools.make(registry: registry, context: nil, control: nil,
                                                 background: background, lookAtScreen: { .text("fixture") })
            let names = Set(router.definitions.compactMap { $0["name"] as? String })
            #expect(names == BuiltinTools.names)
            #expect(router.definitions.count == BuiltinTools.names.count)
            #expect(router.definitions.allSatisfy { $0["type"] == nil })
            for name in BuiltinTools.names { #expect(router.accepts(name: name)) }
            #expect(!router.accepts(name: "find_on_screen"))
            for name in ComputerController.backgroundToolNames { #expect(!router.accepts(name: name)) }
            #expect(!router.accepts(name: "left_click", toolset: "computer"))
            #expect(!router.accepts(name: "screenshot", toolset: "computer"))
        }
    }

    @Test
    func unexpectedToolsetsCannotReachFileOrScreenshotHandlers() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var captureCalls = 0
        let router = try ExecutionTools.make(registry: fixture.registry(), context: nil, control: nil,
                                             background: true, lookAtScreen: {
            captureCalls += 1
            return .text("capture fixture")
        })

        for toolset in ["computer", "unexpected"] {
            let file = await router.execute("read_file", ["path": "proof.txt"], toolset: toolset)
            #expect(file.isError)
            #expect(file.content as? String == "Unknown tool read_file")
            let capture = await router.execute("look_at_screen", [:], toolset: toolset)
            #expect(capture.isError)
            #expect(capture.content as? String == "Unknown tool look_at_screen")
        }
        #expect(captureCalls == 0)

        let allowed = await router.execute("read_file", ["path": "proof.txt"])
        #expect(!allowed.isError)
        #expect(allowed.content as? String == "fixture file reached")
    }

    @Test
    func screenshotRouteForwardsTheSuppliedImageWithoutCapturing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let blocks: [[String: Any]] = [["type": "image", "source": [
            "type": "base64", "media_type": "image/png", "data": "fixture-image-payload",
        ]]]
        var captureCalls = 0
        let router = try ExecutionTools.make(registry: fixture.registry(), context: nil, control: nil,
                                             background: false, lookAtScreen: {
            captureCalls += 1
            return .blocks(blocks)
        })

        let result = await router.executor("look_at_screen", [:], nil)
        let returned = try #require(result.content as? [[String: Any]])
        #expect(!result.isError)
        #expect(captureCalls == 1)
        #expect(NSArray(array: returned).isEqual(to: blocks))
    }

    @Test
    func screenTextRouteUsesTheSuppliedReaderSoAHeldAnswerReadsWhatWasAskedAbout() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var reads = 0
        let router = try ExecutionTools.make(registry: fixture.registry(), context: nil, control: nil,
                                             background: false, lookAtScreen: { .text("unused") },
                                             readScreen: { reads += 1; return .text("the page as asked about") })

        let result = await router.executor("read_screen", [:], nil)
        #expect(!result.isError)
        #expect(reads == 1)
        #expect(result.content as? String == "the page as asked about")
    }

    /// The packs for the page, the ones they use here, and the ones for anywhere: a pack for another page and a
    /// library nobody uses here have no tools on this turn.
    @Test
    func onlyActiveUsedAndGlobalPackScriptsBecomeExecutableRoutes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePack("active", match: "expense.example.test", uses: "lib")
        try fixture.writePack("inactive", match: "other.example.test")
        try fixture.writePack("shared", match: "anywhere")
        try fixture.writePack("lib", match: nil)
        try fixture.writePack("unused-lib", match: nil)
        let registry = fixture.registry()
        await registry.reload()
        // Populate definitions after loading packs: registration needs no Python introspection or script execution.
        for pack in registry.packs {
            pack.scripts = [ScriptTool(id: "\(pack.dirName)__inspect", packDir: pack.dirName, fileName: "inspect.py",
                                      path: pack.dir.appendingPathComponent("scripts/inspect.py"),
                                      description: "Fixture inspection", inputSchema: ["type": "object", "properties": [:]],
                                      dependencies: [])]
        }
        let context = ScreenContext(appName: "Fixture Browser", bundleID: "test.browser", windowTitle: "Expense",
                                    url: "https://expense.example.test/new", focused: nil,
                                    timestamp: Date(timeIntervalSince1970: 0))
        let router = try ExecutionTools.make(registry: registry, context: context, control: nil,
                                             background: false, lookAtScreen: { .text("fixture") })
        let names = Set(router.definitions.compactMap { $0["name"] as? String })
        #expect(names == BuiltinTools.names.union(["active__inspect", "lib__inspect", "shared__inspect"]))
        #expect(router.accepts(name: "active__inspect"))
        #expect(router.accepts(name: "lib__inspect"))
        #expect(router.accepts(name: "shared__inspect"))
        #expect(!router.accepts(name: "inactive__inspect"))
        #expect(!router.accepts(name: "unused-lib__inspect"))
        #expect(!router.accepts(name: "active__inspect", toolset: "computer"))
        let descriptions = Dictionary(uniqueKeysWithValues: router.definitions.compactMap { d in
            (d["name"] as? String).map { ($0, d["description"] as? String ?? "") }
        })
        #expect(descriptions["active__inspect"] == "[active/scripts/inspect.py, for this page] Fixture inspection")
        #expect(descriptions["lib__inspect"] == "[lib/scripts/inspect.py, used here by active] Fixture inspection")
        #expect(descriptions["shared__inspect"] == "[shared/scripts/inspect.py, anywhere] Fixture inspection")

        // Off the page, only the pack for anywhere has tools; a nil scene is the same.
        let elsewhere = try ExecutionTools.make(registry: registry, context: nil, control: nil, background: false, lookAtScreen: { .text("fixture") })
        #expect(Set(elsewhere.definitions.compactMap { $0["name"] as? String }) == BuiltinTools.names.union(["shared__inspect"]))
    }

    /// What the page's brief found reaches a pack script as NOTELING_FACTS, through the real runner.
    @Test
    func theBriefsFactsReachAScriptAsAnEnvironmentVariable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePack("active", match: "expense.example.test")
        let scripts = fixture.root.appendingPathComponent("active/scripts")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try """
        import os

        def run() -> dict:
            \"\"\"Says what facts it was given.\"\"\"
            return {"facts": os.environ.get("NOTELING_FACTS", "none")}
        """.write(to: scripts.appendingPathComponent("echo.py"), atomically: true, encoding: .utf8)
        let registry = fixture.registry()
        await registry.reload()
        try #require(registry.packs.first?.scripts.map(\.id) == ["active__echo"])
        let context = ScreenContext(appName: "Fixture Browser", bundleID: "test.browser", windowTitle: "Expense",
                                    url: "https://expense.example.test/new", focused: nil, timestamp: Date())

        let told = try ExecutionTools.make(registry: registry, context: context, control: nil, background: false,
                                           facts: "{\"order\":\"4417\"}", lookAtScreen: { .text("fixture") })
        let answer = await told.executor("active__echo", [:], nil)
        #expect(!answer.isError && (answer.content as? String ?? "").contains("{\\\"order\\\":\\\"4417\\\"}"))

        let untold = try ExecutionTools.make(registry: registry, context: context, control: nil, background: false, lookAtScreen: { .text("fixture") })
        let silence = await untold.executor("active__echo", [:], nil)
        #expect(!silence.isError && (silence.content as? String ?? "").contains("\"facts\": \"none\""))
    }

    @MainActor
    private struct Fixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("familiar-execution-tools-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            do {
                try "fixture file reached".write(to: root.appendingPathComponent("proof.txt"), atomically: true, encoding: .utf8)
            } catch {
                remove()
                throw error
            }
        }

        func registry() -> ToolRegistry { ToolRegistry(root: root, runner: ScriptRunner(config: Config())) }

        /// `match: nil` writes a pack with no rules: a library. `"anywhere"` writes one for every page.
        func writePack(_ name: String, match: String?, uses: String? = nil) throws {
            let dir = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let rules = match.map { $0 == "anywhere" ? "match: anywhere\n" : "match:\n  urls: [\($0)]\n" } ?? ""
            let using = uses.map { "uses: [\($0)]\n" } ?? ""
            try "---\nname: \(name)\n\(rules)\(using)---\nFixture pack\n"
                .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
