import Foundation
import Testing

/// scripts/check-modes.sh, which release.sh runs before anything is sent to Apple.
struct CheckModesTests {
    private static let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("scripts/check-modes.sh")

    /// A folder with one of each kind, all open to every account.
    private func app() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("modes-\(UUID().uuidString)/Noteling.app")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        for name in ["tool", "text"] {
            try Data("x".utf8).write(to: root.appendingPathComponent("Contents/\(name)"))
        }
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("Contents/link").path, withDestinationPath: "text")
        try mode(0o755, root)
        try mode(0o755, root.appendingPathComponent("Contents"))
        try mode(0o755, root.appendingPathComponent("Contents/tool"))
        try mode(0o644, root.appendingPathComponent("Contents/text"))
        return root
    }

    private func mode(_ mode: Int, _ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    private func run(_ target: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.script.path, target.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }

    @Test func anAppEveryAccountCanOpenPasses() throws {
        let root = try app()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let result = try run(root)
        #expect(result.status == 0, "\(result.output)")
    }

    @Test(arguments: [
        ("", 0o700), ("Contents", 0o700), ("Contents", 0o744), ("Contents", 0o775), ("Contents", 0o757),
        ("Contents/tool", 0o700), ("Contents/tool", 0o744), ("Contents/tool", 0o745), ("Contents/tool", 0o754),
        ("Contents/text", 0o600), ("Contents/text", 0o640), ("Contents/text", 0o604),
        ("Contents/text", 0o664), ("Contents/text", 0o646),
    ])
    func oneEntryAnotherAccountCannotOpenOrCouldChangeIsRefused(path: String, bad: Int) throws {
        let root = try app()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try mode(bad, path.isEmpty ? root : root.appendingPathComponent(path))
        let result = try run(root)
        #expect(result.status == 1)
        #expect(result.output.contains(path.isEmpty ? "Noteling.app" : path))
        #expect(!result.output.contains("modes ok"))
    }

    @Test func nothingToCheckIsRefused() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("modes-\(UUID().uuidString)/Noteling.app")
        let result = try run(missing)
        #expect(result.status == 1)
        #expect(result.output.contains("no app to check"))
    }
}
