import AppKit
import Foundation
import Testing
import FamiliarContracts
import FamiliarRuntime
@testable import Familiar

/// On a page whose pack briefs it, the brief's own answer shows on the pick at once, and a question about the pick is
/// one lean turn: no pack tools (the brief ran them), on the pen's model and effort.
@Suite
@MainActor
struct PenBriefFirstTests {
    private static let glanceJSON = """
        {"price":12.33,"glance":{"headline":"ADS Inc's offer, $12.33, for 07960",\
        "why":["No Rollback badge: the comparison price ended (comparison price)",{"text":"The page agrees with the price of record","source":"priceRT"},"a third","a fourth"],\
        "do":["Nothing to fix"]}}
        """

    // MARK: the glance

    @Test
    func aBriefCarriesItsGlanceAsWritten() throws {
        let glance = try #require(PageGlance.parse(Self.glanceJSON))
        #expect(glance.headline == "ADS Inc's offer, $12.33, for 07960")
        #expect(glance.why.count == 3)   // at most three
        #expect(glance.why[0] == PageGlance.Line(text: "No Rollback badge: the comparison price ended (comparison price)"))
        #expect(glance.why[1] == PageGlance.Line(text: "The page agrees with the price of record", source: "priceRT"))
        #expect(glance.todo == [PageGlance.Line(text: "Nothing to fix")])
        #expect(glance.plainText.contains("What you can do:\n- Nothing to fix"))
    }

    @Test
    func noGlanceWhenTheBriefHasNoneOrFailed() {
        #expect(PageGlance.parse("{\"price\":12.33}") == nil)
        #expect(PageGlance.parse("{\"glance\":{\"headline\":\"  \",\"why\":[],\"do\":[\"\"]}}") == nil)
        #expect(PageGlance.parse("not json") == nil)
        let failed = PageBriefs.Brief(pack: "Shop", script: "shop__summary", page: "p", text: Self.glanceJSON, at: Date(), failed: true)
        #expect(failed.glance == nil)
    }

    @Test
    func longLinesAreClipped() throws {
        let long = String(repeating: "x", count: 400)
        let glance = try #require(PageGlance.parse("{\"glance\":{\"headline\":\"\(long)\"}}"))
        #expect(glance.headline.count == PageGlance.maxChars + 1)
        #expect(glance.headline.hasSuffix("…"))
    }

    // MARK: the router

    @Test
    func aLeanTurnLeavesThePacksScriptsOut() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let full = try ExecutionTools.make(registry: fixture.registry, context: Fixture.item, control: nil, background: false,
                                           lookAtScreen: { .text("unused") })
        let lean = try ExecutionTools.make(registry: fixture.registry, context: Fixture.item, control: nil, background: false,
                                           packScripts: false, lookAtScreen: { .text("unused") })
        #expect(full.accepts(name: "shop__summary"))
        #expect(!lean.accepts(name: "shop__summary"))
        #expect(Set(lean.definitions.compactMap { $0["name"] as? String }) == BuiltinTools.names)
    }

    // MARK: the pad

    @Test
    func aKeptBriefAnswersOnThePickAtOnce() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        fixture.briefs.prefetch(Fixture.item)
        _ = await fixture.briefs.brief(for: Fixture.item, wait: 5)

        fixture.assistant.wandPick(Fixture.circle)

        // Before anything else runs: the pick, then the brief's answer, and the pick still waiting for a question.
        #expect(fixture.assistant.transcript.map(\.role) == [.wand, .glance])
        #expect(fixture.assistant.transcript.last?.glance?.headline == "ADS Inc's offer, $12.33, for 07960")
        #expect(fixture.assistant.pendingPickID != nil)
        await fixture.settle()
        #expect(fixture.assistant.transcript.filter { $0.role == .glance }.count == 1)   // not shown twice
    }

    @Test
    func aBriefStillRunningJoinsThePickWhenItsIn() async throws {
        let fixture = try await Fixture(briefDelay: .milliseconds(150))
        defer { fixture.remove() }

        fixture.assistant.wandPick(Fixture.circle)
        #expect(!fixture.assistant.transcript.contains { $0.role == .glance })
        await fixture.settle(seconds: 2)
        #expect(fixture.assistant.transcript.contains { $0.role == .glance })
    }

    @Test
    func aNewPickKeepsOneTheBriefAlreadyAnswered() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        fixture.briefs.prefetch(Fixture.item)
        _ = await fixture.briefs.brief(for: Fixture.item, wait: 5)

        fixture.assistant.wandPick(Fixture.circle)
        let first = try #require(fixture.assistant.transcript.first?.id)
        fixture.assistant.wandPick(Fixture.circle)

        #expect(fixture.assistant.transcript.filter { $0.role == .wand }.count == 2)
        #expect(fixture.assistant.transcript.first { $0.id == first }?.seen == nil)   // nothing of it was sent
        await fixture.settle()
    }

    @Test
    func doneKeepsTheBriefsAnswerAndStopsWaiting() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        fixture.briefs.prefetch(Fixture.item)
        _ = await fixture.briefs.brief(for: Fixture.item, wait: 5)

        fixture.assistant.wandPick(Fixture.circle)
        fixture.assistant.dismissPick()

        #expect(fixture.assistant.transcript.map(\.role) == [.wand, .glance])
        #expect(fixture.assistant.pendingPickID == nil)
        #expect(fixture.assistant.suggestions.isEmpty)
        await fixture.settle()
        #expect(fixture.client.calls.isEmpty)
    }

    @Test
    func aQuestionOnABriefedPageIsOneLeanTurnOnThePensModelAndEffort() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        fixture.assistant.config.penModel = "claude-sonnet-5-5"
        fixture.assistant.config.penEffort = "low"

        fixture.assistant.wandPick(Fixture.circle)
        fixture.assistant.askSuggestion("Why is it like this?")
        await fixture.settle(seconds: 3)

        let call = try #require(fixture.client.calls.first)
        #expect(fixture.client.calls.count == 1)
        #expect(!call.tools.contains("shop__summary"))
        #expect(!call.tools.contains { $0.contains("computer") })
        #expect(call.model == "claude-sonnet-5-5")
        #expect(call.effort == "low")
        #expect(call.text.contains("## Their question about it\nWhy is it like this?"))
        #expect(call.text.contains("What the page's tools say"))
        // and the connection is itself again afterwards
        #expect(fixture.client.model == "fixture-model")
        #expect(fixture.client.effort == "high")
        #expect(!fixture.assistant.chatBusy)
    }

    @Test
    func aHaikuPenTurnSendsNoEffort() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        fixture.assistant.config.penModel = "claude-haiku-4-5"

        fixture.assistant.wandPick(Fixture.circle)
        fixture.assistant.ask()
        await fixture.settle(seconds: 3)

        let call = try #require(fixture.client.calls.first)
        #expect(call.model == "claude-haiku-4-5")
        #expect(call.effort.isEmpty)
        #expect(fixture.client.effort == "high")
    }

    @Test
    func withoutAPenModelThePenUsesTheUsualModelAtThePensEffort() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }

        fixture.assistant.wandPick(Fixture.circle)
        fixture.assistant.ask()
        await fixture.settle(seconds: 3)

        let call = try #require(fixture.client.calls.first)
        #expect(call.model == "fixture-model")
        #expect(call.effort == "low")   // Config's default pen effort
    }

    /// An assistant on a shop's item page whose pack briefs it, with a recording connection and no screen.
    @MainActor
    private final class Fixture {
        static let item = ScreenContext(appName: "Safari", bundleID: "com.apple.Safari", windowTitle: "Item",
                                        url: "https://shop.example.com/item/123", focused: nil, timestamp: Date())
        static let circle = WandTarget(screenPoint: .zero, element: nil, windowOwner: "Safari", windowTitle: "Item",
                                       region: NSRect(x: 0, y: 0, width: 40, height: 20))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pen-brief-\(UUID().uuidString)")
        let registry: ToolRegistry
        let briefs: PageBriefs
        let assistant: Assistant
        let client = RecordingClient()

        init(briefDelay: Duration = .zero) async throws {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("shop"), withIntermediateDirectories: true)
            try "---\nname: Shop\nmatch:\n  urls: [shop.example.com/item/]\nbrief: summary\n---\nItems."
                .write(to: root.appendingPathComponent("shop/SKILL.md"), atomically: true, encoding: .utf8)
            var config = Config()
            config.apiKey = "fixture-no-network"
            registry = ToolRegistry(root: root, runner: ScriptRunner(config: config))
            await registry.reload()
            let pack = try #require(registry.packs.first)
            pack.scripts = [ScriptTool(id: "shop__summary", packDir: "shop", fileName: "summary.py",
                                       path: pack.dir.appendingPathComponent("scripts/summary.py"), description: "Fixture",
                                       inputSchema: ["type": "object", "properties": [:]], dependencies: [])]
            briefs = PageBriefs(registry: registry)
            briefs.run = { script, pack, ctx in
                if briefDelay > .zero { try? await Task.sleep(for: briefDelay) }
                return PageBriefs.Brief(pack: pack.name, script: script.id, page: PageBriefs.key(ctx) ?? "", text: PenBriefFirstTests.glanceJSON, at: Date())
            }
            let root = root
            let learning = WatchLearnSession(operations: .init(
                start: { _ in }, stop: { Recording(dir: root, events: [], meta: WatchMeta(startedAt: "test", clicks: 0)) }, abandon: {},
                summarize: { _, _, _ in throw ClaudeError(message: "Not recording") }, write: { _ in [] }, reload: {}
            ))
            assistant = Assistant(config: config, watcher: ContextWatcher(), registry: registry, shell: ShellState(), learning: learning)
            assistant.briefs = briefs
            assistant.sceneNow = { Fixture.item }
            assistant.captureDisplay = { _ in throw ScreenCaptureError.notPermitted }
            assistant.useConnection(client)
        }

        func settle(seconds: Double = 0.3) async {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                if !assistant.chatBusy, !client.calls.isEmpty { return }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    /// Records each turn: the tools it was given, its model and effort, and the request's text. Answers at once.
    final class RecordingClient: ConversationClient, ModelSwitchable {
        struct Call { var tools: [String]; var model: String; var effort: String; var text: String }
        var calls: [Call] = []
        var model = "fixture-model"
        var effort = "high"
        var maxTokens = 1024
        var maxToolRounds = 8
        var shouldStop: () -> Bool = { false }

        func converse(system: String, tools: [[String: Any]], messages: inout [[String: Any]],
                      executor: @escaping ToolExecutor, onStatus: @escaping (String) -> Void) async throws -> ClaudeReply {
            let last = messages.last?["content"] as? [[String: Any]] ?? []
            let text = last.compactMap { $0["text"] as? String }.joined(separator: "\n")
            calls.append(Call(tools: tools.compactMap { $0["name"] as? String }, model: model, effort: effort, text: text))
            messages.append(["role": "assistant", "content": [["type": "text", "text": "Answer."]]])
            return ClaudeReply(text: "Answer.\nSuggestions: More?", inputTokens: 1, outputTokens: 1, cacheRead: 0, toolCalls: 0)
        }
    }
}
