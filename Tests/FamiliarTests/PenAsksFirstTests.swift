import AppKit
import Foundation
import Testing
import FamiliarContracts
@testable import Familiar

/// A circle says what, not what about it: the pen asks first, and nothing goes to Claude before a tap or Return.
@Suite
@MainActor
struct PenAsksFirstTests {
    private static let point = WandTarget(screenPoint: .zero, element: nil, windowOwner: nil, windowTitle: nil)

    // MARK: the prompt

    @Test
    func returnOnItsOwnAsksForTheShortExplainWithoutAskingBack() {
        for target in [Self.point, WandTarget(screenPoint: .zero, windowOwner: nil, windowTitle: nil, region: NSRect(x: 0, y: 0, width: 10, height: 10))] {
            let s = Prompt.wandInstruction(target: target, ctx: nil)
            #expect(s.contains(Prompt.packShapeFirst))
            #expect(!s.contains("Then ask what they want to know"))
            #expect(s.contains("Don't ask what they want to know"))
            #expect(!s.contains("Their question about it"))
        }
    }

    @Test
    func aQuestionIsAnsweredAsAsked() {
        let s = Prompt.wandInstruction(target: Self.point, ctx: nil, question: "  why is it greyed out ")
        #expect(s.contains("## Their question about it\nwhy is it greyed out\n"))
        #expect(s.contains("Answer that question about what they pointed at"))
        #expect(s.contains(Prompt.packShapeFirst))
        #expect(!s.contains("Respond in this shape"))
        #expect(Prompt.wandInstruction(target: Self.point, ctx: nil, question: "   ") == Prompt.wandInstruction(target: Self.point, ctx: nil))
    }

    @Test
    func thePacksOwnQuestionsComeFirstAndAtMostThree() {
        let root = FileManager.default.temporaryDirectory
        let plain = ToolPack(dirName: "plain", dir: root)
        let shop = ToolPack(dirName: "shop", dir: root)
        shop.pen = ["Why this price?", "What should I do?", "Report it", "A fourth"]
        #expect(Prompt.penQuestions(packs: []) == Prompt.defaultPenQuestions)
        #expect(Prompt.penQuestions(packs: [plain]) == Prompt.defaultPenQuestions)
        #expect(Prompt.penQuestions(packs: [plain, shop]) == ["Why this price?", "What should I do?", "Report it"])
    }

    @Test
    func aPackDeclaresItsPenQuestionsInSkillMd() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pen-questions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, pen) in [("inline", "pen: [Why this price?, What should I do?]"), ("lines", "pen:\n  - Why this badge?\n  - Report it")] {
            let dir = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "---\nname: \(name)\n\(pen)\nmatch:\n  urls: [shop.example.test]\n---\nBody\n"
                .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        let registry = ToolRegistry(root: root, runner: ScriptRunner(config: Config()))
        await registry.reload()
        #expect(registry.packs.first { $0.dirName == "inline" }?.pen == ["Why this price?", "What should I do?"])
        #expect(registry.packs.first { $0.dirName == "lines" }?.pen == ["Why this badge?", "Report it"])
    }

    // MARK: the pad

    @Test
    func aPickWaitsForItsQuestionWithTheQuestionsAsTaps() async {
        let fixture = Fixture()
        defer { fixture.remove() }
        let assistant = fixture.assistant
        let focus = assistant.focusRequest

        assistant.wandPick(Self.point)

        #expect(assistant.transcript.count == 1)
        #expect(assistant.pendingPickID == assistant.transcript.first?.id)
        #expect(assistant.suggestions == Prompt.defaultPenQuestions)
        #expect(!assistant.chatBusy)
        #expect(assistant.focusRequest == focus + 1)
        await fixture.settle()
        #expect(!assistant.chatBusy)   // still nothing sent
    }

    @Test
    func neverMindTakesThePickAwayAndANewPickReplacesAWaitingOne() async {
        let fixture = Fixture()
        defer { fixture.remove() }
        let assistant = fixture.assistant

        assistant.wandPick(Self.point)
        assistant.dismissPick()
        #expect(assistant.transcript.isEmpty)
        #expect(assistant.pendingPickID == nil)
        #expect(assistant.suggestions.isEmpty)

        assistant.wandPick(WandTarget(screenPoint: .zero, element: nil, windowOwner: nil, windowTitle: "First"))
        assistant.wandPick(WandTarget(screenPoint: .zero, element: nil, windowOwner: nil, windowTitle: "Second"))
        #expect(assistant.transcript.count == 1)
        #expect(assistant.transcript.first?.text.contains("Second") == true)
        #expect(assistant.pendingPickID == assistant.transcript.first?.id)
        await fixture.settle()
    }

    @Test
    func aTapAsksItsQuestionAboutThePick() async {
        let fixture = Fixture()
        defer { fixture.remove() }
        let assistant = fixture.assistant

        assistant.wandPick(Self.point)
        assistant.askSuggestion("Why is it like this?")

        #expect(assistant.transcript.first?.asked == "Why is it like this?")
        #expect(assistant.transcript.count == 1)   // the question goes on the pick, not on a note of its own
        #expect(assistant.pendingPickID == nil)
        #expect(assistant.suggestions.isEmpty)
        #expect(assistant.chatBusy)
        assistant.clearConversation()   // before the capture comes back: nothing is sent
        await fixture.settle()
        #expect(!assistant.chatBusy)
    }

    @Test
    func typedWordsOrReturnOnItsOwnAnswerThePick() async {
        let fixture = Fixture()
        defer { fixture.remove() }
        let assistant = fixture.assistant

        assistant.wandPick(Self.point)
        assistant.question = "  can I edit this "
        assistant.ask()
        #expect(assistant.transcript.first?.asked == "can I edit this")
        #expect(assistant.question.isEmpty)
        #expect(assistant.chatBusy)
        assistant.clearConversation()
        await fixture.settle()

        assistant.wandPick(Self.point)
        assistant.ask()   // Return with nothing typed: explain it
        #expect(assistant.transcript.first?.asked == nil)
        #expect(assistant.pendingPickID == nil)
        #expect(assistant.chatBusy)
        assistant.clearConversation()
        await fixture.settle()
        #expect(!assistant.chatBusy)
    }

    /// An assistant whose screen capture always fails, with no network and no desktop.
    @MainActor
    private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pen-asks-\(UUID().uuidString)")
        let assistant: Assistant

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
        }

        /// Lets the pick's preparation and any answer finish.
        func settle() async { for _ in 0..<50 { await Task.yield() } }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
