#if DEBUG
import Foundation
import Testing

/// The parent stays outside the UI process so a SwiftUI main-thread spin cannot block its timeout.
struct ChatLayoutRegressionTests {
    @Test func followingUpAfterLongAnswersKeepsChatResponsive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("familiar-chat-layout-\(UUID().uuidString)")
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
        child.arguments = ["--probe-chat-layout"]
        var environment = ProcessInfo.processInfo.environment
        environment["NOTELING_HOME"] = directory.appendingPathComponent("home").path
        environment["FAMILIAR_BUBBLE_LAYOUT_FIXTURE"] = directory.path
        child.environment = environment
        child.standardOutput = handle
        child.standardError = handle
        try child.run()
        let end = try await ChildEnd.of(child, limit: 20) {
            await ChildEnd.sample(child, to: directory.appendingPathComponent("hang-sample.txt"), output: handle)
            FileHandle.standardOutput.write(Data("CHAT LAYOUT: failure artifacts: \(directory.path)\n".utf8))
        }
        let log = try String(contentsOf: output, encoding: .utf8)
        let told = end.told(child, log: log)
        #expect(!end.timedOut, "The chat main thread stopped responding after a follow-up. \(told)")
        #expect(end.status == 0, "Hosted chat failed. \(told)")
        #expect(log.contains("CHAT LAYOUT: conversation completed and chat responsive"), "The child did not finish the conversation. \(told)")
        completed = !end.timedOut && end.status == 0 && log.contains("CHAT LAYOUT: conversation completed and chat responsive")
    }
}
#endif
