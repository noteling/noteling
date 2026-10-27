import Foundation
import IOKit.pwr_mgt

/// Keeps the display from idling to sleep while Noteling works in the background. Events posted to one process are
/// not activity to macOS, so a long background job runs into the display's idle timer: the screen goes dark, the
/// lock engages and a locked session stops the job (and locks the data-protection keychain with it). One system
/// assertion covers any number of overlapping holds; the last release drops it. Public API only
/// (`kIOPMAssertionTypePreventUserIdleDisplaySleep`), the same assertion Codex's computer use holds.
@MainActor
final class StayAwake {
    static let shared = StayAwake()

    /// Pure bookkeeping, testable without IOKit: counts holds and says when the system assertion must come and go.
    struct Ledger: Equatable {
        private(set) var holds = 0
        /// True when this hold is the first one, so the caller must create the assertion.
        mutating func hold() -> Bool {
            holds += 1
            return holds == 1
        }
        /// True when this release is the last one, so the caller must drop the assertion. Releasing with no hold
        /// outstanding is ignored.
        mutating func release() -> Bool {
            guard holds > 0 else { return false }
            holds -= 1
            return holds == 0
        }
    }

    /// One hold. `end()` is idempotent; a lease that is never ended keeps the display awake, so owners end it when
    /// their work ends, not in a deinit.
    final class Lease {
        private weak var owner: StayAwake?
        private(set) var ended = false
        fileprivate init(owner: StayAwake) { self.owner = owner }
        @MainActor func end() {
            guard !ended else { return }
            ended = true
            owner?.release()
        }
    }

    /// Injectable for tests: create returns the assertion id, nil when the system refused.
    var create: (String) -> IOPMAssertionID? = { reason in
        var id: IOPMAssertionID = 0
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)
        return r == kIOReturnSuccess ? id : nil
    }
    var drop: (IOPMAssertionID) -> Void = { IOPMAssertionRelease($0) }

    private(set) var ledger = Ledger()
    private(set) var assertion: IOPMAssertionID?

    /// Holds the display awake until the lease is ended. The reason shows in `pmset -g assertions`.
    func hold(_ reason: String) -> Lease {
        if ledger.hold() {
            assertion = create(reason)
            Log.info("awake: holding the display (\(reason))\(assertion == nil ? " refused by the system" : "")")
        }
        return Lease(owner: self)
    }

    fileprivate func release() {
        guard ledger.release() else { return }
        if let id = assertion { drop(id) }
        assertion = nil
        Log.info("awake: released")
    }
}
