import Foundation
import Testing
import FamiliarContracts
import FamiliarRuntime
@testable import Familiar

/// Explain, Teach me, Do it for me: the three things a message can want, chosen by a tab or a pin rather than by
/// particular words; a team's own words for them; and the prompt that describes them to the model.
@Suite @MainActor
struct IntentTests {
    @Test func aTabIsAVerbByItsWordHoweverItIsWritten() {
        let words = IntentWords.standard
        #expect(words.intent(ofTab: "Teach me") == .teach && words.intent(ofTab: " teach me! ") == .teach)
        #expect(words.intent(ofTab: "Do it for me") == .act && words.intent(ofTab: "Explain") == .explain)
        #expect(words.intent(ofTab: "Teach me how") == nil && words.intent(ofTab: "") == nil)
        #expect(words.verbTabs == ["Teach me", "Do it for me"])
    }

    @Test func aTeamRenamesTheVerbsAndGivesItsOwnExamples() throws {
        let json = """
        {"verbs": {"teach": "Show me how", "act": " Just do it ", "colour": "red",
                   "examples": {"teach": ["walk me through", " 带我走一遍 "], "act": [""], "other": ["x"]}}}
        """
        let team = try TeamSettings.parse(Data(json.utf8))
        let words = try #require(team.verbs)
        #expect(words.explain == "Explain" && words.teach == "Show me how" && words.act == "Just do it")
        #expect(words.examples(for: .teach) == ["walk me through", "带我走一遍"])
        #expect(words.examples(for: .act) == IntentWords.standard.examples(for: .act))   // an empty list keeps the usual ones
        #expect(team.ignored == ["verbs.colour", "verbs.examples.other"])
        #expect(words.intent(ofTab: "show me how") == .teach && words.intent(ofTab: "Teach me") == nil)
        let effective = Config().applying(team)
        #expect(effective.intentWords == words && Config().applying(nil).intentWords == .standard)
        // A team file without verbs leaves the words alone, even one that sets nothing for Claude.
        #expect(try Config().applying(TeamSettings.parse(Data("{}".utf8))).intentWords == .standard)
    }

    @Test(arguments: [
        "{\"verbs\": \"teach\"}",
        "{\"verbs\": {\"teach\": \"\"}}",
        "{\"verbs\": {\"teach\": \"Do it for me\"}}",
        "{\"verbs\": {\"act\": \"A verb far too long to fit on one tab\"}}",
        "{\"verbs\": {\"examples\": {\"teach\": \"walk me through\"}}}",
    ])
    func aVerbsBlockThatCantBeUsedSaysWhy(json: String) {
        #expect(throws: TeamSettingsError.self) { try TeamSettings.parse(Data(json.utf8)) }
    }

    @Test func thePromptDescribesTheThreeAndHowToChoose() {
        var words = IntentWords.standard
        words.teach = "Show me how"
        let open = Prompt.intents(words, pinned: nil)
        #expect(open.contains("- Show me how: to be able to do it themselves next time") && open.contains("teach_the_way"))
        #expect(open.contains("end the Suggestions line with exactly \"Show me how\" and \"Do it for me\""))
        #expect(open.contains("never go by a phrase") && open.contains("“where do I find…”"))
        #expect(!Prompt.system.contains("show_me") && !Prompt.system.contains("idk where"))   // no trigger phrases in the base prompt
        let teach = Prompt.intents(words, pinned: .teach)
        #expect(teach.contains("They chose \"Show me how\" for this message") && !teach.contains("end the Suggestions line"))
        #expect(Prompt.intents(words, pinned: .act).contains("Don't teach it or merely explain it"))
        #expect(Prompt.intents(words, pinned: .explain).contains("answer in words, even if it reads like a request"))
    }

    @Test func aVerbTabPinsTheIntentForThatMessageOnly() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let assistant = fixture.assistant
        #expect(assistant.offersIntents && assistant.intentOverride == nil)
        assistant.pinIntent(.teach)
        #expect(assistant.intentOverride == .teach)
        assistant.pinIntent(.teach)   // the pinned one again: unpinned
        #expect(assistant.intentOverride == nil)

        // Tapping the verb under an answer sends it as that verb, once.
        assistant.askSuggestion("Do it for me")
        try await fixture.settle()
        #expect(assistant.transcript.first?.text == "Do it for me")
        #expect(fixture.client.systems.last?.contains("They chose \"Do it for me\" for this message") == true)
        #expect(assistant.intentOverride == nil)

        // Pinned Explain keeps the teach tool out; nothing pinned leaves the model to judge, with the tool in.
        assistant.pinIntent(.explain)
        assistant.question = "how do I create a token"
        assistant.ask()
        try await fixture.settle()
        #expect(fixture.client.systems.last?.contains("They chose \"Explain\"") == true)
        #expect(fixture.client.tools.last?.contains(ShowMeConversation.toolName) == false)
        assistant.question = "how do I create a token"
        assistant.ask()
        try await fixture.settle()
        #expect(fixture.client.systems.last?.contains("end the Suggestions line with exactly") == true)
        #expect(fixture.client.tools.last?.contains(ShowMeConversation.toolName) == true)
    }

    @MainActor private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("intents-\(UUID().uuidString)")
        let assistant: Assistant
        let client = RecordingClient()

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
            assistant.captureDisplay = { _ in throw ScreenCaptureError.notPermitted }
            assistant.showMe = ShowMeConversation(registry: registry)
            assistant.useConnection(client)
        }

        /// Waits for the turn under way to finish.
        func settle() async throws {
            for _ in 0..<500 where assistant.chatBusy { try await Task.sleep(nanoseconds: 10_000_000) }
            try #require(!assistant.chatBusy)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    /// Answers at once and keeps each turn's system prompt and tool names.
    final class RecordingClient: ConversationClient {
        var systems: [String] = []
        var tools: [[String]] = []
        var effort = "medium"
        var maxTokens = 1024
        var maxToolRounds = 8
        var shouldStop: () -> Bool = { false }

        func converse(system: String, tools: [[String: Any]], messages: inout [[String: Any]],
                      executor: @escaping ToolExecutor, onStatus: @escaping (String) -> Void) async throws -> ClaudeReply {
            systems.append(system)
            self.tools.append(tools.compactMap { $0["name"] as? String })
            messages.append(["role": "assistant", "content": [["type": "text", "text": "Fine."]]])
            return ClaudeReply(text: "Fine.", inputTokens: 1, outputTokens: 1, cacheRead: 0, toolCalls: 0)
        }
    }
}
