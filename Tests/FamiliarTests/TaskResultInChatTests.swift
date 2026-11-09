import Foundation
import Testing
import FamiliarContracts
import FamiliarRuntime
@testable import Familiar

/// A background task's result belongs in the chat as well as the task window: the request stays, a line says the work
/// is in the background, the result lands with the last view of the window, and Chat about it opens the chat on it.
@Suite @MainActor struct TaskResultInChatTests {
    private func assistant() -> (Assistant, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("task-result-\(UUID().uuidString)")
        var config = Config()
        config.apiKey = "fixture-no-network"
        config.screenshotMode = "never"
        let registry = ToolRegistry(root: root, runner: ScriptRunner(config: config))
        let learning = WatchLearnSession(operations: .init(
            start: { _ in }, stop: { Recording(dir: root, events: [], meta: WatchMeta(startedAt: "test", clicks: 0)) }, abandon: {},
            summarize: { _, _, _ in throw ClaudeError(message: "Not recording") }, write: { _ in [] }, reload: {}
        ))
        return (Assistant(config: config, watcher: ContextWatcher(), registry: registry, shell: ShellState(), learning: learning), root)
    }

    private func record(_ outcome: BackgroundTaskOutcome, text: String = "Sent the reminder to the warehouse.", elapsed: TimeInterval = 38) -> BackgroundTaskRecord {
        BackgroundTaskRecord(id: UUID(), title: "Nudge the warehouse about order 4417", outcome: outcome, text: text,
                             startedAt: Date(), finishedAt: Date(), elapsed: elapsed, frame: nil, appName: "Safari", windowTitle: "Orders", step: 4, caption: "Done")
    }

    @Test func theLineUnderAResultSaysHowItWentWhereAndHowLong() {
        #expect(record(.completed).chatLine == "Done in the background · Safari · Orders · 4 steps · 38 s")
        #expect(record(.stopped, elapsed: 75).chatLine == "Stopped in the background · Safari · Orders · 4 steps · 1 min 15 s")
        var bare = record(.failed, elapsed: 2)
        bare = BackgroundTaskRecord(id: bare.id, title: bare.title, outcome: .failed, text: "", startedAt: bare.startedAt, finishedAt: bare.finishedAt,
                                    elapsed: 2, frame: nil, appName: "", windowTitle: "", step: 0, caption: "")
        #expect(bare.chatLine == "Couldn't finish in the background · 2 s" && bare.report.text == "Couldn’t finish")
        #expect(Assistant.taskNotice.hasPrefix("Working on it in the background."))
    }

    @Test func chatAboutItOpensTheChatOnTheResultPuttingItThereIfItIsGone() {
        let (assistant, root) = assistant()
        defer { try? FileManager.default.removeItem(at: root) }
        let done = record(.completed).report
        assistant.chatAbout(done)
        #expect(assistant.shell.expanded && assistant.status == "Ask about it below.")
        #expect(assistant.transcript.map(\.role) == [.user, .assistant, .receipt])
        #expect(assistant.transcript[0].text == done.title && assistant.transcript[1].text == done.text && assistant.transcript[2].task == done.id)
        // Already in the chat: nothing is added twice.
        assistant.chatAbout(done)
        #expect(assistant.transcript.count == 3)
        // A task that ended with nothing to say shows how it ended.
        assistant.chatAbout(record(.stopped, text: "").report)
        #expect(assistant.transcript.count == 6 && assistant.transcript[4].text == "Stopped")
    }
}
