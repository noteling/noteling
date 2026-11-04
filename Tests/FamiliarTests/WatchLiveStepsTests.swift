import AppKit
import Foundation
import Testing
@testable import Familiar

/// Watch Me shows each step the moment it is kept, so a miss shows at once, and the pen fixes the last one (#84).
@Suite
struct WatchLiveStepsTests {
    static func click(_ index: Int, axRole: String? = nil, label: String? = nil, domID: String? = nil, rect: [Double]? = nil) -> WatchEvent {
        var e = WatchEvent(index: index, t: 0, kind: "click")
        e.axRole = axRole
        e.label = label
        e.domID = domID
        e.rect = rect
        return e
    }

    static let row: [Double] = [0, 0.1, 0.2, 0.05]

    @Test func eachClickIsKeptByItsNameItsIdItsPlaceOrNotAtAll() {
        let named = CapturedStep.of(Self.click(3, axRole: "AXGroup", label: "Billing", rect: Self.row), number: 1)
        #expect(named.kind == .named("Billing") && !named.isMiss && named.words == "Billing" && named.event == 3)
        let byID = CapturedStep.of(Self.click(4, axRole: "AXButton", domID: "save-draft", rect: Self.row), number: 2)
        #expect(byID.kind == .byID("button") && !byID.isMiss)
        let place = CapturedStep.of(Self.click(5, axRole: "AXGroup", rect: Self.row), number: 3)
        #expect(place.kind == .place("group") && place.isMiss && place.words == "? a group with no name")
        #expect(place.tag == "? a group with no name: kept by where it is")
        // A spot without a size is no control; nor is a click whose name came from the window, not from a control.
        let spot = CapturedStep.of(Self.click(6, rect: [0.5, 0.5, 0, 0]), number: 4)
        #expect(spot.kind == .nothing && spot.isMiss && spot.words == "· missed")
        #expect(CapturedStep.of(Self.click(7, label: "Billing – Example"), number: 5).kind == .nothing)
        // A step fixed with the pen says so; a long name is cut.
        #expect(CapturedStep.of(Self.click(8, axRole: "AXLink", label: "Billing", rect: Self.row), number: 6, fixed: true).words == "Billing ✎")
        let long = CapturedStep.of(Self.click(9, axRole: "AXLink", label: String(repeating: "Quarterly ", count: 5), rect: Self.row), number: 7)
        #expect(long.words.count == 26 && long.words.hasSuffix("…"))
    }

    @Test func theCaptionShowsTheLastStepsAndOffersToFixAMiss() {
        #expect(WatchHUD.stepsLine([]).string == "Click through it the way you always do")
        #expect(WatchHUD.status(hotkey: "⌃⌥Space") == "Noteling is watching  ·  ⌃⌥Space to stop")
        let steps = [
            CapturedStep.of(Self.click(2, axRole: "AXLink", label: "Home", rect: Self.row), number: 1),
            CapturedStep.of(Self.click(4, axRole: "AXLink", label: "Accounts", rect: Self.row), number: 2),
            CapturedStep.of(Self.click(5, axRole: "AXGroup", rect: Self.row), number: 3),
            CapturedStep.of(Self.click(7, rect: [0.5, 0.5, 0, 0]), number: 4),
        ]
        let line = WatchHUD.stepsLine(steps)
        #expect(line.string == "…   2  Accounts     3  ? a group with no name     4  · missed   ·   click here, then point at it")
        // The misses are in amber, the steps a way will find in white.
        let text = line.string as NSString
        let amber = { (word: String) in line.attribute(.foregroundColor, at: text.range(of: word).location, effectiveRange: nil) as? NSColor }
        #expect(amber("? a group") == WatchHUD.amber && amber("· missed") == WatchHUD.amber && amber("Accounts") != WatchHUD.amber)
        // Once the last step is good again, there is nothing to fix.
        let fine = Array(steps.prefix(2))
        #expect(WatchHUD.stepsLine(fine).string == "1  Home     2  Accounts")
    }

    @Test func aSecondLookReplacesOnlyWhatItSaysBetter() {
        let group = ShowFinder.Control(role: "AXGroup", name: nil, domID: nil, frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        let text = ShowFinder.Control(role: "AXStaticText", name: "Billing", domID: nil, frame: NSRect(x: 40, y: 10, width: 80, height: 18))
        let around = ShowFinder.Control(role: "AXLink", name: "Billing", domID: nil, frame: NSRect(x: -4, y: -2, width: 260, height: 44))
        let menu = ShowFinder.Control(role: "AXMenuItem", name: "Export", domID: nil, frame: NSRect(x: 20, y: -120, width: 200, height: 24))
        let save = ShowFinder.Control(role: "AXButton", name: "Save", domID: nil, frame: NSRect(x: 0, y: 0, width: 80, height: 30))
        // Nothing at first: whatever the second look finds.
        #expect(WatchRecorder.secondLook(text, betterThan: nil))
        // A thing without a name: the name inside it, or the named control around it.
        #expect(WatchRecorder.secondLook(text, betterThan: group) && WatchRecorder.secondLook(around, betterThan: group))
        // Never a menu that opened somewhere else, nothing, or anything in place of a control that had a name.
        #expect(!WatchRecorder.secondLook(menu, betterThan: group))
        #expect(!WatchRecorder.secondLook(nil, betterThan: group) && !WatchRecorder.secondLook(nil, betterThan: nil))
        #expect(!WatchRecorder.secondLook(text, betterThan: save))
        // Nor one without a name in place of another without a name.
        #expect(!WatchRecorder.secondLook(group, betterThan: group))
    }

    @Test func aStepFixedWithThePenKeepsWhatThePenPointedAt() {
        let window = NSRect(x: 0, y: 0, width: 1_200, height: 900)
        var e = WatchEvent(index: 9, t: 1, kind: "click", app: "Google Chrome", title: "Billing", url: "https://app.example.com/billing")
        e.role = "web area"
        e.label = "Billing – Example"
        e.value = "a glimpse of something else"
        e.rect = [0.5, 0.5, 0, 0]
        let row = ShowFinder.Control(role: "AXGroup", name: "Billing", domID: "nav-billing", frame: NSRect(x: 0, y: 700, width: 240, height: 40))
        var fixed = e
        WatchRecorder.pointed(row, in: &fixed, bundle: "com.google.Chrome", window: window, page: "https://app.example.com/accounts")
        #expect(fixed.axRole == "AXGroup" && fixed.role == "group" && fixed.label == "Billing" && fixed.domID == "nav-billing")
        #expect(fixed.value == nil && fixed.rect == NoteAnchor.fractions(of: row.frame, in: window))
        // The page stays the one it was clicked on.
        #expect(fixed.url == "https://app.example.com/billing")
        #expect(CapturedStep.of(fixed, number: 1).kind == .named("Billing"))
        // The browser's own toolbar has no page; a click that had none takes the page the pen pointed on.
        var toolbar = e
        let downloads = ShowFinder.Control(role: "AXButton", name: "Downloads", domID: nil, frame: NSRect(x: 1_100, y: 860, width: 30, height: 30), inPage: false)
        WatchRecorder.pointed(downloads, in: &toolbar, bundle: "com.google.Chrome", window: window, page: "https://app.example.com/billing")
        #expect(toolbar.url == nil)
        var pageless = e
        pageless.url = nil
        WatchRecorder.pointed(row, in: &pageless, bundle: "com.google.Chrome", window: window, page: "https://app.example.com/accounts")
        #expect(pageless.url == "https://app.example.com/accounts")
        // A name that looks secret is not written down, and a page's id that changes every load is not kept.
        var secret = e
        WatchRecorder.pointed(ShowFinder.Control(role: "AXTextField", name: "Password", domID: "react-123", frame: row.frame), in: &secret,
                              bundle: "com.google.Chrome", window: window, page: nil)
        #expect(secret.label == nil && secret.domID == nil && secret.axRole == "AXTextField")
    }
}
