import AppKit
import Foundation
import Testing
import FamiliarContracts
import FamiliarRuntime
@testable import Familiar

/// Whether a typed question takes the screen is said over the input before it's sent, and a click changes it for that
/// one question: the guess is still the default, but it can be seen and fixed.
@Suite
@MainActor
struct InputLooksTests {
    static let report = ScreenContext(appName: "Expenses", bundleID: "com.example.expenses", windowTitle: "New Report",
                                      url: nil, focused: nil, timestamp: Date())
    static let browser = ScreenContext(appName: "Safari", bundleID: "com.apple.Safari", windowTitle: "Item 123",
                                       url: "https://shop.example.com/item/123", focused: nil, timestamp: Date())

    @Test
    func theLineFollowsTheGuessAsTheQuestionIsWritten() {
        let fixture = Fixture()
        defer { fixture.remove() }
        let assistant = fixture.assistant
        #expect(assistant.lookLine(for: "") == nil)   // nothing in front: nothing to say

        assistant.inFront = Self.report
        #expect(assistant.lookLine(for: "")?.looks == true)
        #expect(assistant.lookLine(for: "")?.text == "Looks at “New Report”")
        #expect(assistant.lookLine(for: "why is this greyed out")?.looks == true)
        #expect(assistant.lookLine(for: "how many vacation days do I get a year")?.looks == false)
        #expect(assistant.lookLine(for: "how many vacation days do I get a year")?.text == "Doesn't look at your screen")
    }

    @Test
    func aClickChangesItForThisQuestion() {
        let fixture = Fixture()
        defer { fixture.remove() }
        let assistant = fixture.assistant
        assistant.inFront = Self.report

        assistant.toggleLook(for: "why is this greyed out")
        #expect(assistant.lookOverride == false)
        #expect(assistant.lookLine(for: "why is this greyed out")?.looks == false)
        #expect(assistant.evidence(for: "why is this greyed out", ctx: Self.report) == .none)

        assistant.toggleLook(for: "how many vacation days do I get a year")
        #expect(assistant.lookOverride == true)
        #expect(assistant.evidence(for: "how many vacation days do I get a year", ctx: Self.report) == .screenshot)
        // in a browser, looking means reading the page, unless the question is about how it looks
        #expect(assistant.evidence(for: "how many vacation days do I get a year", ctx: Self.browser) == .page)
        #expect(assistant.evidence(for: "what colour is the banner", ctx: Self.browser) == .screenshot)
    }

    @Test
    func aPickWaitingForItsQuestionHasNoLine() {
        let fixture = Fixture()
        defer { fixture.remove() }
        let assistant = fixture.assistant
        assistant.inFront = Self.report
        assistant.wandPick(WandTarget(screenPoint: .zero, element: nil, windowOwner: nil, windowTitle: nil))
        #expect(assistant.lookLine(for: "") == nil)
    }

    @Test
    func sentWithoutTheScreenTakesNothingAndTheChoiceIsForgotten() async {
        let fixture = Fixture()
        defer { fixture.remove() }
        let assistant = fixture.assistant
        assistant.inFront = Self.report

        assistant.question = "why is this greyed out"
        assistant.toggleLook(for: assistant.question)
        assistant.ask()
        #expect(assistant.lookOverride == nil)
        let end = Date().addingTimeInterval(3)
        while Date() < end, assistant.chatBusy { try? await Task.sleep(for: .milliseconds(20)) }

        #expect(fixture.captures == 0)
        #expect(fixture.client.texts.count == 1)
        #expect(!(fixture.client.texts.first ?? "").contains("The page in front"))
        #expect(assistant.transcript.first { $0.role == .user }?.seen == nil)   // no chip: nothing of the screen went
    }

    @MainActor
    private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("input-looks-\(UUID().uuidString)")
        let assistant: Assistant
        let client = TextClient()
        var captures = 0

        init() {
            var config = Config()
            config.apiKey = "fixture-no-network"
            let registry = ToolRegistry(root: root, runner: ScriptRunner(config: config))
            let root = root
            let learning = WatchLearnSession(operations: .init(
                start: { _ in }, stop: { Recording(dir: root, events: [], meta: WatchMeta(startedAt: "test", clicks: 0)) }, abandon: {},
                summarize: { _, _, _ in throw ClaudeError(message: "Not recording") }, write: { _ in [] }, reload: {}
            ))
            assistant = Assistant(config: config, watcher: ContextWatcher(), registry: registry, shell: ShellState(), learning: learning)
            assistant.captureDisplay = { [weak self] _ in
                self?.captures += 1
                throw ScreenCaptureError.notPermitted
            }
            assistant.useConnection(client)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    /// Answers at once and keeps the text each turn was sent.
    final class TextClient: ConversationClient {
        var texts: [String] = []
        var effort = "medium"
        var maxTokens = 1024
        var maxToolRounds = 8
        var shouldStop: () -> Bool = { false }

        func converse(system: String, tools: [[String: Any]], messages: inout [[String: Any]],
                      executor: @escaping ToolExecutor, onStatus: @escaping (String) -> Void) async throws -> ClaudeReply {
            let content = messages.last?["content"] as? [[String: Any]] ?? []
            texts.append(content.compactMap { $0["text"] as? String }.joined(separator: "\n"))
            messages.append(["role": "assistant", "content": [["type": "text", "text": "Fine."]]])
            return ClaudeReply(text: "Fine.", inputTokens: 1, outputTokens: 1, cacheRead: 0, toolCalls: 0)
        }
    }
}
