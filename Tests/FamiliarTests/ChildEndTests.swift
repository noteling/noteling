#if DEBUG
import Darwin
import Foundation
import Testing

/// The layout tests' wait for their child: every way it can end is told, and none of them waits forever.
struct ChildEndTests {
    /// A child by the numbers: over after `looks` looks at it, or only once stopped, or never.
    private final class StandIn: WatchedChild, @unchecked Sendable {
        let processIdentifier: Int32 = 0x7fff_fff0   // nobody's
        var terminationStatus: Int32 = 0
        private(set) var stopped = 0
        private var looks: Int
        private let overOnceStopped: Bool
        init(overAfter looks: Int, overOnceStopped: Bool = true) { self.looks = looks; self.overOnceStopped = overOnceStopped }
        var isRunning: Bool {
            if stopped > 0 && overOnceStopped { return false }
            looks -= 1
            return looks >= 0
        }
        func stop() { stopped += 1 }
    }

    private static let never = Int.max

    @Test func aChildThatEndsByItselfIsToldWithItsStatus() async throws {
        let child = StandIn(overAfter: 2)
        child.terminationStatus = 3
        var late = 0
        let end = try await ChildEnd.of(child, limit: 30) { late += 1 }
        #expect(end.seenRunning && !end.timedOut && end.status == 3)
        #expect(child.stopped == 0 && late == 0)
        #expect(end.told(child, log: "one line") == "The child (pid \(child.processIdentifier)) was seen running and ended by itself with status 3. Its log:\none line")
    }

    @Test func aChildOverBeforeTheFirstLookWasNeverSeenRunning() async throws {
        let child = StandIn(overAfter: 0)
        let end = try await ChildEnd.of(child, limit: 30)
        #expect(!end.seenRunning && !end.timedOut && end.status == 0)
        #expect(end.told(child, log: "").hasSuffix("was never seen running and ended by itself with status 0. Its log:\n(empty)"))
    }

    @Test func aChildStillRunningAtTheLimitIsStopped() async throws {
        let child = StandIn(overAfter: Self.never)
        child.terminationStatus = 9
        var stoppedWhenLate: [Int] = []
        let end = try await ChildEnd.of(child, limit: 0.2) { stoppedWhenLate.append(child.stopped) }
        #expect(end.seenRunning && end.timedOut && end.status == 9)
        #expect(child.stopped == 1)
        #expect(stoppedWhenLate == [0])   // sampled while it still ran
        #expect(end.told(child, log: "x").contains("was stopped at the limit, and ended with status 9"))
    }

    /// The symptom that stopped whole runs, in its worst form: the child's end is never reported, stopped or not.
    @Test func aChildWhoseEndIsNeverReportedIsToldAndNotWaitedForForever() async throws {
        let child = StandIn(overAfter: Self.never, overOnceStopped: false)
        let end = try await ChildEnd.of(child, limit: 0.2, afterStop: 0.3)
        #expect(end.seenRunning && end.timedOut && end.status == nil)
        #expect(child.stopped == 1)
        #expect(end.told(child, log: "its last line") == "The child (pid \(child.processIdentifier)) was seen running and was not over at the limit, and its end was never reported (process gone). Its log:\nits last line")
    }

    @Test func aRealChildPastTheLimitIsNotLeftBehind() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", "trap '' TERM INT; while :; do /bin/sleep 1; done"]
        try child.run()
        let end = try await ChildEnd.of(child, limit: 0.3)
        #expect(end.seenRunning && end.timedOut && end.status == SIGKILL)
        #expect(kill(child.processIdentifier, 0) == -1 && errno == ESRCH)
    }

    @Test func onlyAChildOfThisProcessIsKilled() async throws {
        let child = Process()
        let pipe = Pipe()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", "/bin/sleep 60 & echo $!; wait"]
        child.standardOutput = pipe
        try child.run()
        let line = String(decoding: pipe.fileHandleForReading.availableData, as: UTF8.self)
        let grandchild = try #require(pid_t(line.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(ChildEnd.isOurs(child.processIdentifier))
        #expect(!ChildEnd.isOurs(grandchild))
        ChildEnd.kill(grandchild)   // not ours to kill: it stays
        try await Task.sleep(for: .milliseconds(200))
        #expect(child.isRunning)   // it waits for the grandchild
        #expect(kill(grandchild, 0) == 0)
        _ = kill(grandchild, SIGTERM)
        #expect(try await ChildEnd.of(child, limit: 30).timedOut == false)
    }

    @Test func aCancelledTestDoesNotLeaveItsChildBehind() async throws {
        let child = StandIn(overAfter: Self.never)
        let task = Task { try await ChildEnd.of(child, limit: 30) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(child.stopped == 1)
    }
}
#endif
