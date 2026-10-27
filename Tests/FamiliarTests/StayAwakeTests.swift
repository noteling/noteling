import AppKit
import Testing
@testable import Familiar

/// The display stays awake while the background lane works: one system assertion for any number of overlapping
/// holds, dropped by the last release, never twice, and never when the system refused to create it.
@Suite @MainActor struct StayAwakeTests {
    @Test func theLedgerAsksForOneAssertionAcrossOverlappingHolds() {
        var ledger = StayAwake.Ledger()
        #expect(ledger.hold() == true)      // first hold creates
        #expect(ledger.hold() == false)     // second rides along
        #expect(ledger.release() == false)  // one still out
        #expect(ledger.release() == true)   // last one drops
        #expect(ledger.release() == false)  // nothing to drop
        #expect(ledger.holds == 0)
    }

    @Test func overlappingHoldsShareOneSystemAssertionAndTheLastLeaseDropsIt() {
        let awake = StayAwake()
        var created: [String] = []
        var dropped: [IOPMAssertionID] = []
        awake.create = { created.append($0); return 42 }
        awake.drop = { dropped.append($0) }

        let job = awake.hold("Noteling is working in Mail in the background")
        let tour = awake.hold("a second job")
        #expect(created == ["Noteling is working in Mail in the background"])
        #expect(awake.assertion == 42)

        job.end()
        #expect(dropped.isEmpty)
        job.end()                           // idempotent
        #expect(dropped.isEmpty)
        tour.end()
        #expect(dropped == [42])
        #expect(awake.assertion == nil)

        // A new round after everything was released creates again.
        let again = awake.hold("again")
        #expect(created.count == 2)
        again.end()
        #expect(dropped == [42, 42])
    }

    @Test func aRefusedAssertionIsNeverDropped() {
        let awake = StayAwake()
        var drops = 0
        awake.create = { _ in nil }
        awake.drop = { _ in drops += 1 }
        let lease = awake.hold("refused")
        #expect(awake.assertion == nil)
        lease.end()
        #expect(drops == 0)
        #expect(awake.ledger.holds == 0)
    }

    @Test func theBackgroundClickProbeNamesEveryBrokenPromise() {
        let good = BackgroundClickProbe.checks(completed: true, verdict: .confirmed("value 7 → 8"),
                                               frontBefore: 100, frontAfter: 100,
                                               mouseBefore: NSPoint(x: 10, y: 10), mouseAfter: NSPoint(x: 10.4, y: 9.8),
                                               notelingActive: false, targetFrontmostAfter: false)
        let allGood = good.allSatisfy { $0.ok }
        #expect(allGood)
        #expect(good.count == 6)

        let bad = BackgroundClickProbe.checks(completed: false, verdict: .noEffect("nothing changed"),
                                              frontBefore: 100, frontAfter: 200,
                                              mouseBefore: NSPoint(x: 10, y: 10), mouseAfter: NSPoint(x: 50, y: 10),
                                              notelingActive: true, targetFrontmostAfter: true)
        let allBad = bad.allSatisfy { !$0.ok }
        #expect(allBad)
        let details = Dictionary(uniqueKeysWithValues: bad.map { ($0.name, $0.detail) })
        #expect(details["frontmost app unchanged"] == "100 → 200")
        #expect(details["real cursor unmoved"] == "moved 40 pt")
        #expect(details["the control reacted"] == "no effect: nothing changed")
    }
}
