import AppKit
import Testing
@testable import Familiar

/// Background work without stopping for a yes ("Ask before sending, deleting or paying" off): a send goes out after its
/// draft is checked, the person's own use of the window makes Noteling step aside instead of ending the job, and the
/// model is told to finish rather than ask.
@Suite @MainActor struct SmoothBackgroundTests {
    @Test func aSmoothSendGoesOutOnceWithoutAskingButStillChecksTheDraft() async {
        let f = Fixture()
        defer { f.control.end() }
        f.control.asksFirst = false
        let result = await f.control.sendMessage(f.input)
        #expect(f.sent == 1)
        #expect(f.feed.onGoAhead == nil && f.feed.approvalRequestID == nil)   // nothing was asked
        #expect((result.content as? String)?.contains("Delivery is not yet verified") == true)
        // The checks that make it the right message still hold: other words are never sent.
        _ = await f.control.sendMessage(["recipient": "Avery", "message": "Different text"])
        #expect(f.sent == 1)
    }

    @Test func askingFirstIsStillThereWhenTurnedOn() async throws {
        let f = Fixture()
        defer { f.control.end() }
        f.control.asksFirst = true
        let send = Task { await f.control.sendMessage(f.input) }
        for _ in 0..<200 where f.feed.onGoAhead == nil { await Task.yield() }
        #expect(f.sent == 0 && f.feed.onGoAhead != nil)
        f.feed.onNotNow?()
        _ = await send.value
        #expect(f.sent == 0)
    }

    @Test func usingTheWindowMakesNotelingStepAsideNotStop() async {
        let f = Fixture()
        var stops: [String] = [], yields: [String] = [], dirty = 0
        let monitor = ConflictMonitor(target: f.target, recordOutstanding: { false }, expectingActivation: { false },
                                      onStop: { stops.append($0) }, onDirty: { dirty += 1 }, onYield: { yields.append($0) },
                                      onAbortRecord: {})
        monitor.handle(.init(kind: .appActivated(f.target.pid), locationCG: .zero, isOurs: false))
        #expect(stops.isEmpty && yields == ["you switched to Fixture"] && dirty == 1)
        #expect(await !monitor.waitUntilClear(timeout: 0.2))   // waiting for them to pause
        monitor.handle(.init(kind: .appActivated(f.target.pid), locationCG: .zero, isOurs: false))
        #expect(yields.count == 1)   // told once per spell, not on every touch
        #expect(await monitor.waitUntilClear(timeout: ConflictMonitor.yieldSeconds + 1))   // then it carries on

        // Without a way to step aside (the careful mode's callers), it still ends the job as before.
        var ended: [String] = []
        let careful = ConflictMonitor(target: f.target, recordOutstanding: { false }, expectingActivation: { false },
                                      onStop: { ended.append($0) }, onDirty: {}, onAbortRecord: {})
        careful.handle(.init(kind: .appActivated(f.target.pid), locationCG: .zero, isOurs: false))
        #expect(ended == ["you switched to Fixture"])
    }

    @Test func theModelIsToldToFinishRatherThanAsk() {
        let careful = Prompt.control(smooth: false), smooth = Prompt.control(smooth: true)
        #expect(careful.contains("without asking first: stop") && careful.hasPrefix("\nControlling the computer."))
        #expect(!smooth.contains("without asking first: stop") && smooth.contains("including its final Send, Submit or Save"))
        #expect(smooth.contains("never pay, buy or delete anything they didn't ask for"))
        let lane = Prompt.background(smooth: true)
        #expect(Prompt.background(smooth: false).contains("pauses for the user's explicit approval") && !Prompt.background(smooth: false).contains("Working smoothly."))
        #expect(!lane.contains("pauses for the user's explicit approval") && !lane.contains("request fresh send"))
        #expect(lane.contains("pressed without stopping for approval") && lane.contains("Working smoothly."))
        #expect(lane.contains("Never press ⌘Q"))   // what it never does stays
    }

    @MainActor private final class Fixture {
        let target: TargetWindow
        let control: ComputerController
        let ladder: ActionLadder
        let feed = PeekFeed()
        var draft: KeyboardMessageDraft
        var sent = 0
        var input: [String: Any] { ["recipient": "Avery", "message": "Hello 👋"] }
        init() {
            let ax = AXUIElementCreateApplication(-23457)
            let frame = CGRect(x: 20, y: 20, width: 800, height: 600)
            target = TargetWindow(pid: -23457, bundleID: "test.smooth", appName: "Fixture", cgWindowID: 13,
                                  axApp: ax, axWindow: ax, toolkit: .electron, backingScale: 1,
                                  scWindow: nil, frameCG: frame, title: "Conversation")
            draft = KeyboardMessageDraft(pid: target.pid, windowID: target.cgWindowID, window: ax, field: ax,
                                         windowTitle: target.title, windowFrame: frame, role: "AXTextArea",
                                         context: ["Message to Avery"], text: "Hello 👋")
            ladder = ActionLadder(target: target, maxLongEdge: 800)
            ladder.refreshWindow = { _ in true }
            ladder.makeMainForTyping = { _ in true }
            control = ComputerController(backgroundSession: ladder, mouseGranted: false)
            control.peek = feed
            control.readMessageDraft = { _ in self.draft }
            ladder.postMessageReturn = { _ in self.sent += 1 }
        }
    }
}
