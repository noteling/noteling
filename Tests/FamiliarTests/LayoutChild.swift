#if DEBUG
import Darwin
import Foundation

/// A child process a layout test watches. `Process`, or a test's stand-in.
protocol WatchedChild: AnyObject {
    var processIdentifier: Int32 { get }
    var isRunning: Bool { get }
    /// Only once `isRunning` is false.
    var terminationStatus: Int32 { get }
    func stop()
}

extension Process: WatchedChild {
    func stop() { kill(processIdentifier, SIGKILL) }
}

/// How a watched child ended. Every wait here has a limit: `waitUntilExit` has none, and has been seen not to come back
/// after the child was over and `isRunning` false, which stopped a whole run with nothing said.
struct ChildEnd {
    /// The child was still running at least once when it was looked at.
    var seenRunning = false
    /// It was still running at the limit, so it was stopped.
    var timedOut = false
    /// Its exit status, or the signal that ended it; nil when its end was never reported, even after it was stopped.
    var status: Int32?

    /// Watches the child until it ends or the limit runs out; then calls `late`, stops the child, and gives its end
    /// `afterStop` more seconds to be reported. The child is stopped too when the test itself is cancelled meanwhile.
    static func of(_ child: some WatchedChild, limit: TimeInterval, afterStop: TimeInterval = 10, late: () async -> Void = {}) async throws -> ChildEnd {
        var end = ChildEnd()
        func over(within seconds: TimeInterval) async throws -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while child.isRunning {
                end.seenRunning = true
                if Date() >= deadline { return false }
                try await Task.sleep(for: .milliseconds(100))
            }
            return true
        }
        do {
            if try await !over(within: limit) {
                end.timedOut = true
                await late()
                if child.isRunning { child.stop() }
                guard try await over(within: afterStop) else { return end }
            }
        } catch {
            if child.isRunning { child.stop() }
            throw error
        }
        end.status = child.terminationStatus
        return end
    }

    /// What is known of the child, for a failure: its end, whether it was seen running, and its log.
    func told(_ child: some WatchedChild, log: String) -> String {
        let how = switch (timedOut, status) {
        case (false, let status?): "ended by itself with status \(status)"
        case (true, let status?): "was stopped at the limit, and ended with status \(status)"
        case (_, nil): "was stopped at the limit, and its end was never reported (process \(kill(child.processIdentifier, 0) == 0 ? "still there" : "gone"))"
        }
        return "The child (pid \(child.processIdentifier)) was \(seenRunning ? "seen running" : "never seen running") and \(how). Its log:\n\(log.isEmpty ? "(empty)" : log)"
    }

    /// A sample of a child that stopped responding, for its failure artifacts. Bounded too.
    static func sample(_ child: some WatchedChild, to file: URL, output: FileHandle) async {
        let sample = Process()
        sample.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        sample.arguments = [String(child.processIdentifier), "1", "1", "-file", file.path]
        sample.standardOutput = output
        sample.standardError = output
        guard (try? sample.run()) != nil else { return }
        _ = try? await ChildEnd.of(sample, limit: 20)
    }
}
#endif
