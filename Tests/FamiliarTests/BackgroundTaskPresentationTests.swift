import Foundation
import Testing
@testable import Familiar
@testable import FamiliarRuntime
import FamiliarContracts

@Suite @MainActor
struct BackgroundTaskPresentationTests {
    @Test func taskResultLandsInTheChatWithoutReopeningIt() throws {
        let (assistant, desktop) = fixture()
        let id = UUID()
        let task = try desktop.executor.begin(TaskRequest(id: id, title: "Fill the report"))
        assistant.chatBusy = true
        assistant.shell.expanded = false
        #expect(assistant.backgroundTaskRunning)
        #expect(!assistant.chatResponding)

        assistant.completeExecution(reply("Filled the report.\nSuggestions: Inspect it | Next task"), task: task)

        // In the chat as the answer with its line, and in the task window; the pad stays as it was.
        #expect(assistant.transcript.map(\.role) == [.assistant, .receipt])
        #expect(assistant.transcript.first?.text == "Filled the report." && assistant.transcript.last?.task == id)
        #expect(assistant.transcript.last?.text.hasPrefix("Done in the background") == true)
        #expect(assistant.suggestions == ["Inspect it", "Next task"])
        #expect(desktop.tasks.history.first?.text == "Filled the report.")
        #expect(!assistant.shell.expanded)
        #expect(!desktop.tasks.isExpanded)
    }

    @Test func chatAboutItOpensTheChatOnTheTaskPuttingItThereIfItIsGone() throws {
        let (assistant, desktop) = fixture()
        let id = UUID()
        let task = try desktop.executor.begin(TaskRequest(id: id, title: "Fill the report"))
        assistant.completeExecution(reply("Filled the report."), task: task)
        assistant.clearConversation()
        #expect(assistant.transcript.isEmpty)
        let report = try #require(desktop.tasks.history.first?.report)
        assistant.chatAbout(report)
        #expect(assistant.transcript.map(\.role) == [.user, .assistant, .receipt] && assistant.transcript[0].text == "Fill the report")
        #expect(assistant.transcript[1].text == "Filled the report." && assistant.transcript[2].task == id && assistant.shell.expanded)
        assistant.chatAbout(report)   // already there: nothing twice
        #expect(assistant.transcript.count == 3 && assistant.status == "Ask about it below.")
    }

    @Test func clearingChatDoesNotEraseTaskAndALateResultStaysOutOfTheClearedChat() throws {
        let (assistant, desktop) = fixture()
        let id = UUID()
        let task = try desktop.executor.begin(TaskRequest(id: id, title: "Background report"))
        assistant.transcript = [ChatMessage(role: .user, text: "Old question")]
        assistant.clearConversation()
        desktop.tasks.dismiss()

        assistant.completeExecution(reply("The result is ready.", accepted: false), task: task)

        #expect(desktop.tasks.history.first?.text == "The result is ready.")
        #expect(assistant.transcript.isEmpty)
        #expect(!desktop.tasks.isVisible)
        #expect(!assistant.shell.expanded)
    }

    @Test func stoppedAndFailedTaskResultsReachBothTheTaskAndTheChat() throws {
        let (assistant, desktop) = fixture()
        let stopped = UUID()
        let stoppedTask = try desktop.executor.begin(TaskRequest(id: stopped, title: "Stopped task"))
        assistant.completeExecution(.init(outcome: .cancelled, accepted: true, elapsed: 1), task: stoppedTask)
        #expect(desktop.tasks.history.first?.outcome == .stopped)
        let failed = UUID()
        let failedTask = try desktop.executor.begin(TaskRequest(id: failed, title: "Failed task"))
        assistant.completeExecution(.init(outcome: .failed(ClaudeError(message: "Connection failed")),
                                          accepted: true, elapsed: 2), task: failedTask)
        #expect(desktop.tasks.history.first?.outcome == .failed)
        #expect(desktop.tasks.history.first?.text == "Connection failed")
        #expect(assistant.transcript.map(\.role) == [.assistant, .receipt, .error, .receipt])
        #expect(assistant.transcript[0].text == "Stopped." && assistant.transcript[1].text.hasPrefix("Stopped in the background"))
        #expect(assistant.transcript[2].text == "Connection failed" && assistant.transcript[3].text.hasPrefix("Couldn't finish in the background"))
    }

    @Test func ordinaryConversationStillReceivesItsAnswer() throws {
        let (assistant, desktop) = fixture()
        let task = try desktop.executor.begin(TaskRequest(id: UUID(), title: "Explain this",
                                                         presentation: .conversation), coordinator: assistant.execution)
        assistant.completeExecution(reply("Here is the answer.\nSuggestions: Explain more | Example"), task: task)
        #expect(assistant.transcript.last?.role == .assistant)
        #expect(assistant.transcript.last?.text == "Here is the answer.")
        #expect(assistant.suggestions == ["Explain more", "Example"])
        #expect(!desktop.tasks.hasTasks)
    }

    @Test func invalidatedConversationDoesNotBecomeATaskOrRestoreClearedChat() throws {
        let (assistant, desktop) = fixture()
        let task = try desktop.executor.begin(TaskRequest(id: UUID(), title: "Explain this",
                                                         presentation: .conversation), coordinator: assistant.execution)
        assistant.clearConversation()
        assistant.completeExecution(reply("An old answer", accepted: false), task: task)
        #expect(assistant.transcript.isEmpty)
        #expect(!desktop.tasks.hasTasks)
        #expect(desktop.tasks.history.isEmpty)
    }

    private func reply(_ text: String, accepted: Bool = true) -> ExecutionResult {
        .init(outcome: .reply(.init(text: text, inputTokens: 1, outputTokens: 1, cacheRead: 0, toolCalls: 1)),
              accepted: accepted, elapsed: 3)
    }

    private func fixture() -> (Assistant, DesktopExecutionService) {
        var config = Config()
        config.apiKey = "fixture-no-network"
        config.screenshotMode = "never"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry = ToolRegistry(root: root, runner: ScriptRunner(config: config))
        let learning = WatchLearnSession(operations: .init(
            start: { _ in }, stop: { Recording(dir: root, events: [], meta: WatchMeta(startedAt: "test", clicks: 0)) }, abandon: {},
            summarize: { _, _, _ in throw ClaudeError(message: "Not recording") }, write: { _ in [] }, reload: {}
        ))
        let desktop = DesktopExecutionService(control: ComputerController(), activities: NativeActivityGate())
        let assistant = Assistant(config: config, watcher: ContextWatcher(), registry: registry,
                                  shell: ShellState(), learning: learning, desktop: desktop)
        return (assistant, desktop)
    }
}
