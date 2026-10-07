import Foundation
import Testing
import FamiliarContracts
import FamiliarRuntime
@testable import Familiar

/// The answer shows on the pad as it is written, and the finished one takes its place: one answer, never the
/// Suggestions line, and the follow-ups as tabs at the end.
@Suite
@MainActor
struct PadWritingTests {
    @Test
    func theSuggestionsLineNeverShowsEvenHalfWritten() {
        #expect(Assistant.writingText("It's ADS Inc's offer.") == "It's ADS Inc's offer.")
        #expect(Assistant.writingText("It's ADS Inc's offer.\nSugg") == "It's ADS Inc's offer.")
        #expect(Assistant.writingText("It's ADS Inc's offer.\n**Suggestions") == "It's ADS Inc's offer.")
        #expect(Assistant.writingText("It's ADS Inc's offer.\nSuggestions: Why? | Wh") == "It's ADS Inc's offer.")
        #expect(Assistant.writingText("Sure.\nSo the price is right.") == "Sure.\nSo the price is right.")
        #expect(Assistant.writingText("") == "")
    }

    @Test
    func theAnswerShowsAsItIsWrittenAndTheFinishedOneTakesItsPlace() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let assistant = fixture.assistant

        assistant.question = "whose offer wins here"
        assistant.ask()

        // While it writes: one answer on the pad, growing, without the Suggestions line.
        var during: [String] = []
        let end = Date().addingTimeInterval(3)
        while Date() < end, assistant.chatBusy {
            if let answer = assistant.transcript.last(where: { $0.role == .assistant }) { during.append(answer.text) }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!assistant.chatBusy)
        #expect(during.contains("It's"))
        #expect(during.contains("It's ADS Inc's offer."))
        #expect(!during.contains { $0.contains("Sugg") })

        let answers = assistant.transcript.filter { $0.role == .assistant }
        #expect(answers.count == 1)
        #expect(answers.first?.text == "It's ADS Inc's offer, the only one for 07960.")
        #expect(assistant.suggestions == ["Why is it the only one?", "Check another zip"])
    }

    @MainActor
    private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pad-writing-\(UUID().uuidString)")
        let assistant: Assistant

        init() {
            var config = Config()
            config.apiKey = "fixture-no-network"
            config.screenshotMode = "never"
            let registry = ToolRegistry(root: root, runner: ScriptRunner(config: config))
            let root = root
            let learning = WatchLearnSession(operations: .init(
                start: { _ in }, stop: { Recording(dir: root, events: [], meta: WatchMeta(startedAt: "test", clicks: 0)) }, abandon: {},
                summarize: { _, _, _ in throw ClaudeError(message: "Not recording") }, write: { _ in [] }, reload: {}
            ))
            assistant = Assistant(config: config, watcher: ContextWatcher(), registry: registry, shell: ShellState(), learning: learning)
            assistant.captureDisplay = { _ in throw ScreenCaptureError.notPermitted }
            assistant.useConnection(WritingClient())
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    /// Writes its answer in three pieces, a little apart, the way a streamed reply arrives.
    final class WritingClient: ConversationClient, StreamsText {
        var effort = "medium"
        var maxTokens = 1024
        var maxToolRounds = 8
        var shouldStop: () -> Bool = { false }
        var onText: ((String) -> Void)?

        func converse(system: String, tools: [[String: Any]], messages: inout [[String: Any]],
                      executor: @escaping ToolExecutor, onStatus: @escaping (String) -> Void) async throws -> ClaudeReply {
            let final = "It's ADS Inc's offer, the only one for 07960.\nSuggestions: Why is it the only one? | Check another zip"
            for piece in ["It's", "It's ADS Inc's offer.", "It's ADS Inc's offer.\nSugg"] {
                onText?(piece)
                try await Task.sleep(for: .milliseconds(200))
            }
            messages.append(["role": "assistant", "content": [["type": "text", "text": final]]])
            return ClaudeReply(text: final, inputTokens: 1, outputTokens: 1, cacheRead: 0, toolCalls: 0)
        }
    }
}
