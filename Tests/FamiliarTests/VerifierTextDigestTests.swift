import Foundation
import Testing
@testable import Familiar

/// A click whose only visible effect is text changing away from the point (a counter, a status line) is a change:
/// the window's text digest catches what the grey grids are too coarse to see.
@Suite struct VerifierTextDigestTests {
    @Test func aChangedTextDigestConfirmsAnyChange() {
        let before = AXSnapshot(textDigest: ActionVerifier.digest(["Count me", "Clicked 1 time(s)"]))
        let after = AXSnapshot(textDigest: ActionVerifier.digest(["Count me", "Clicked 2 time(s)"]))
        #expect(ActionVerifier.verdict(before: before, after: after, expecting: .anyChange) == .confirmed("the window's text changed"))
        #expect(ActionVerifier.verdict(before: before, after: before, expecting: .anyChange)
                == .noEffect("no accessibility change; no screen crop to compare"))
    }

    @Test func anUnreliableToolkitNeedsTheScreenToCorroborateTheText() {
        let before = AXSnapshot(textDigest: ActionVerifier.digest(["a"]))
        let after = AXSnapshot(textDigest: ActionVerifier.digest(["b"]))
        guard case .unverifiable(let why) = ActionVerifier.verdict(before: before, after: after, expecting: .anyChange, trustAX: false) else {
            Issue.record("expected unverifiable without screen corroboration")
            return
        }
        #expect(why.hasPrefix("the window's text changed"))
    }

    @Test func theDigestIsOrderSensitiveAndEmptyForNoText() {
        #expect(ActionVerifier.digest([]) == nil)
        #expect(ActionVerifier.digest(["a", "b"]) == ActionVerifier.digest(["a", "b"]))
        #expect(ActionVerifier.digest(["a", "b"]) != ActionVerifier.digest(["b", "a"]))
        #expect(ActionVerifier.digestRoles.contains("AXStaticText"))
        #expect(!ActionVerifier.digestRoles.contains("AXButton"))
    }
}
