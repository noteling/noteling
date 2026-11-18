import AppKit
import FamiliarContracts
import FamiliarRuntime
import SwiftUI

@MainActor
func runApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}

#if DEBUG
if CommandLine.arguments.contains("--probe-watch-keep") {
    MainActor.assumeIsolated { WatchKeepLayoutProbe.run() }
}
if CommandLine.arguments.contains("--probe-chat-layout") {
    MainActor.assumeIsolated { ChatLayoutProbe.run() }
}
if CommandLine.arguments.contains("--probe-main-thread-diagnostics") {
    MainActor.assumeIsolated { MainThreadDiagnosticsProbe.run() }
}
#endif

if CommandLine.arguments.contains("--record-synthetic") {
    Task { @MainActor in
        await runRecordSynthetic()
        exit(0)
    }
    RunLoop.main.run()
} else if CommandLine.arguments.contains("--summarize-recording") {
    Task { @MainActor in
        await runSummarizeRecording()
        exit(0)
    }
    RunLoop.main.run()
} else if CommandLine.arguments.contains("--render-mascot") {
    MainActor.assumeIsolated { runRenderMascot() }
} else if CommandLine.arguments.contains("--render-origami") {
    MainActor.assumeIsolated { runRenderOrigami() }
} else if CommandLine.arguments.contains("--render-card") {
    MainActor.assumeIsolated { runRenderCard() }
} else if CommandLine.arguments.contains("--render-paper") {
    MainActor.assumeIsolated { runRenderPaper() }
} else if let index = CommandLine.arguments.firstIndex(of: "--render-background-task"), index + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated {
        do { try BackgroundTaskRender.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
        catch { print("Background task render failed: \(error)"); exit(1) }
    }
} else if let index = CommandLine.arguments.firstIndex(of: "--render-jobs"), index + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated {
        do { try JobsRender.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
        catch { print("Jobs render failed: \(error)"); exit(1) }
    }
} else if CommandLine.arguments.contains("--record-clicks") {
    MainActor.assumeIsolated { runRecordClicks() }
} else if CommandLine.arguments.contains("--find-step") {
    MainActor.assumeIsolated { runFindStep() }
} else if CommandLine.arguments.contains("--show-me") {
    MainActor.assumeIsolated { runShowMe() }
} else if CommandLine.arguments.contains("--background-click") {
    // The direct-click rung proves itself with an activation record posted to our own process, which only the app's
    // event loop answers; an accessory app doesn't come to the front by running it.
    Task { @MainActor in
        let code = await runBackgroundClick()
        exit(code)
    }
    MainActor.assumeIsolated { NSApplication.shared.setActivationPolicy(.accessory) }
    NSApp.run()
} else if CommandLine.arguments.contains("--render-hints") {
    MainActor.assumeIsolated { runRenderHints() }
} else if CommandLine.arguments.contains("--render-pen") {
    MainActor.assumeIsolated { runRenderPen() }
} else if CommandLine.arguments.contains("--ask") {
    Task { @MainActor in
        await runHeadlessAsk()
        exit(0)
    }
    if CommandLine.arguments.contains("--show") || CommandLine.arguments.contains("--control") {
        // A tour hears clicks and Esc through event monitors, and the direct-click rung's record round trip is
        // answered by our own event loop; only the app's run loop feeds either. Without it the rung reads
        // "activation record ignored" and switches itself off, which the app never does.
        MainActor.assumeIsolated { NSApplication.shared.setActivationPolicy(.accessory) }
        NSApp.run()
    }
    RunLoop.main.run()
} else if CommandLine.arguments.contains("--read-page") {
    // What the page reader sees in the browser window nearest the front (ReadPageCommand). Off the main actor, which
    // the browser hold needs free, so the main run loop below must be running.
    Task.detached {
        exit(ReadPageCommand.run(CommandLine.arguments))
    }
    RunLoop.main.run()
} else if CommandLine.arguments.contains("--selftest") {
    Task { @MainActor in
        await runSelfTest()
        exit(0)
    }
    RunLoop.main.run()
} else if let flag = CommandLine.arguments.first(where: { $0.hasPrefix("--render-") }) {
    // A render this build doesn't know must not fall through to the app: an older app once launched whole, with its
    // jobs and its config save, when asked for a render it had never heard of.
    print("\(flag) isn't a render this Noteling knows.")
    exit(2)
} else {
    MainActor.assumeIsolated { runApp() }
}
