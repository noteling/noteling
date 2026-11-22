#if DEBUG
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Familiar

/// A layout spin blocks the main actor, including ordinary async test timeouts.
/// Run the real view in a child so the parent can report that failure and stop it.
struct BubbleLayoutRegressionTests {
    @Test func keepingALongWatchDraftLeavesTheChatResponsive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("familiar-layout-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer { if completed { try? FileManager.default.removeItem(at: directory) } }
        let output = directory.appendingPathComponent("child.log")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }

        let child = Process()
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        child.executableURL = repository.appendingPathComponent(".build/debug/Familiar")
        child.arguments = ["--probe-watch-keep"]
        var environment = ProcessInfo.processInfo.environment
        environment["NOTELING_HOME"] = directory.appendingPathComponent("home").path
        environment["FAMILIAR_BUBBLE_LAYOUT_FIXTURE"] = directory.path
        child.environment = environment
        child.standardOutput = handle
        child.standardError = handle
        try child.run()
        let end = try await ChildEnd.of(child, limit: 15) {
            await ChildEnd.sample(child, to: directory.appendingPathComponent("hang-sample.txt"), output: handle)
            Self.progress("failure artifacts: \(directory.path)")
        }
        let log = try String(contentsOf: output, encoding: .utf8)
        let told = end.told(child, log: log)
        #expect(!end.timedOut, "The chat main thread stopped responding during Keep. \(told)")
        #expect(end.status == 0, "Hosted chat failed. \(told)")
        #expect(log.contains("LAYOUT: keep completed and chat responsive"), "The child did not finish the actual draft-to-Keep flow. \(told)")
        completed = !end.timedOut && end.status == 0 && log.contains("LAYOUT: keep completed and chat responsive")
    }

    private static func progress(_ text: String) {
        FileHandle.standardOutput.write(Data("LAYOUT: \(text)\n".utf8))
    }
}
#endif
