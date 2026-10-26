import ApplicationServices
import Foundation
import Testing
@testable import Familiar

/// Showing the way: finding a recorded control again on a page, keeping the way from a Watch Me recording, offering it
/// to the chat, and where the step's card goes. The pages here are made up, so no browser is needed.
@Suite
struct ShowMeTests {
    static let window = CGRect(x: 0, y: 0, width: 1_200, height: 900)

    /// A page with a header button named by its description, a sidebar link named by the text inside it, two
    /// "Settings" buttons, a button the page has but doesn't place, and an icon with no name.
    static func page() -> FakeNode {
        let header = FakeNode("AXButton", ["AXDescription": "Account and access"], frame: CGRect(x: 1_100, y: 20, width: 70, height: 40),
                              [FakeNode("AXStaticText", ["AXValue": "David"], frame: CGRect(x: 1_110, y: 30, width: 40, height: 18))])
        let sidebar = FakeNode("AXLink", [:], frame: CGRect(x: 20, y: 300, width: 250, height: 32),
                               [FakeNode("AXStaticText", ["AXValue": "Waxwing App"], frame: CGRect(x: 40, y: 306, width: 90, height: 18)),
                                FakeNode("AXStaticText", ["AXValue": "25"], frame: CGRect(x: 240, y: 306, width: 16, height: 18))])
        let settingsTop = FakeNode("AXButton", ["AXTitle": "Settings"], frame: CGRect(x: 600, y: 80, width: 80, height: 30))
        let settingsBottom = FakeNode("AXButton", ["AXTitle": "Settings", "AXDOMIdentifier": "footer-settings"], frame: CGRect(x: 600, y: 800, width: 80, height: 30))
        let unplaced = FakeNode("AXButton", ["AXTitle": "Create agent token"], frame: nil)
        let icon = FakeNode("AXButton", [:], frame: CGRect(x: 1_000, y: 20, width: 30, height: 30))
        let area = FakeNode("AXWebArea", ["AXURL": "http://127.0.0.1:4310/"], frame: window,
                            [header, sidebar, settingsTop, settingsBottom, unplaced, icon])
        return FakeNode("AXWindow", [:], frame: window, [FakeNode("AXGroup", [:], frame: window, [area])])
    }

    static func find(_ step: ShowStep) -> ShowFinder.Found<FakeNode>? {
        ShowFinder.find(step, in: page(), visibleArea: window, windowFrame: window)
    }

    // MARK: - Finding a step

    @Test func aControlIsFoundByItsKindAndName() throws {
        let found = try #require(Self.find(ShowStep(say: "Open it", role: "AXButton", label: "Account and access")))
        #expect(found.how == .kindAndName && found.visible && found.frame == CGRect(x: 1_100, y: 20, width: 70, height: 40))
    }

    @Test func theTextInsideALinkStandsForTheLink() throws {
        let found = try #require(Self.find(ShowStep(say: "Open Waxwing App", role: "AXLink", label: "Waxwing App")))
        #expect(found.frame == CGRect(x: 20, y: 300, width: 250, height: 32))   // the whole link, not its words
    }

    @Test func aCountThatChangedDoesNotLoseTheControl() throws {
        // Recorded as "Waxwing App 24"; the page now says 25.
        let found = try #require(Self.find(ShowStep(say: "Open Waxwing App", role: "AXLink", label: "Waxwing App 24")))
        #expect(found.how == .nameButNumbers && found.frame?.minX == 20)
        #expect(ShowFinder.withoutCount("Inbox 3") == "Inbox" && ShowFinder.withoutCount("Notifications (12)") == "Notifications")
        // Numbers inside a name are the name: another quarter's report, or another page, is another control.
        #expect(ShowFinder.withoutCount("Q3 2026 report") == nil && ShowFinder.withoutCount("Page 12") == nil && ShowFinder.withoutCount("42") == nil)
        let reports = FakeNode("AXWindow", [:], frame: Self.window, [
            FakeNode("AXLink", ["AXTitle": "Q4 2025 report"], frame: CGRect(x: 10, y: 10, width: 100, height: 20)),
            FakeNode("AXLink", ["AXTitle": "Page 12"], frame: CGRect(x: 10, y: 40, width: 100, height: 20)),
        ])
        #expect(ShowFinder.find(ShowStep(say: "", role: "AXLink", label: "Q3 2026 report"), in: reports, visibleArea: Self.window) == nil)
        #expect(ShowFinder.find(ShowStep(say: "", role: "AXLink", label: "Page 1"), in: reports, visibleArea: Self.window) == nil)
    }

    @Test func thePagesOwnIdComesFirstAndPlaceBreaksATie() throws {
        let byID = try #require(Self.find(ShowStep(say: "", role: "AXButton", label: "Settings", domID: "footer-settings")))
        #expect(byID.how == .id && byID.frame?.minY == 800)
        // Two with the same name: the one nearer to where it was recorded.
        let low = try #require(Self.find(ShowStep(say: "", role: "AXButton", label: "Settings", rect: [0.5, 0.88, 0.07, 0.03])))
        #expect(low.frame?.minY == 800)
        let high = try #require(Self.find(ShowStep(say: "", role: "AXButton", label: "Settings", rect: [0.5, 0.09, 0.07, 0.03])))
        #expect(high.frame?.minY == 80)
    }

    @Test func aControlThePageDoesNotPlaceIsFoundOutOfView() throws {
        let found = try #require(Self.find(ShowStep(say: "Create a token", role: "AXButton", label: "Create agent token")))
        #expect(found.frame == nil && !found.visible)
    }

    @Test func aControlWithoutANameIsFoundByWhereItWas() throws {
        let found = try #require(Self.find(ShowStep(say: "Click the gear", role: "AXButton", rect: [0.84, 0.025, 0.025, 0.033])))
        #expect(found.how == .place && found.frame?.minX == 1_000)
        // A named step is never matched by place alone.
        #expect(Self.find(ShowStep(say: "", role: "AXButton", label: "Nowhere to be seen", rect: [0.84, 0.025, 0.025, 0.033])) == nil)
    }

    @Test func plainTextIsNotTakenForAControlByPartOfItsName() {
        #expect(Self.find(ShowStep(say: "", label: "Waxwing App collection settings")) == nil)
    }

    @Test func anEmptyPageIsNotReadableYet() {
        let empty = FakeNode("AXWebArea", [:], frame: Self.window, [FakeNode("AXGroup", ["AXSubrole": "AXEmptyGroup"])])
        #expect(!ShowFinder.hasContent(empty))
        let built = Self.page().children[0].children[0]
        #expect(ShowFinder.hasContent(built, atLeast: 6))
    }

    // MARK: - Keeping the way from a recording

    static func recording() -> Recording {
        var events: [WatchEvent] = []
        func add(_ kind: String, label: String? = nil, role: String? = nil, url: String? = nil) {
            var e = WatchEvent(index: events.count, t: Double(events.count), kind: kind, app: "Google Chrome", title: "Waxwing", url: url)
            e.label = label
            e.axRole = role
            if kind == "click" { e.rect = [0.1, 0.1, 0.1, 0.05] }
            events.append(e)
        }
        add("scene", url: "http://127.0.0.1:4310/")
        add("click", label: "Waxwing App 24", role: "AXLink", url: "http://127.0.0.1:4310/?token=secret#top")
        add("click", label: "Waxwing App 24", role: "AXLink", url: "http://127.0.0.1:4310/?token=secret#top")   // clicked twice
        add("click", label: "Header", role: "AXGroup", url: "http://127.0.0.1:4310/?collection=a")             // a stray click
        add("click", label: "History", role: "AXButton", url: "http://127.0.0.1:4310/?collection=a")
        return Recording(dir: URL(fileURLWithPath: "/tmp/none"), events: events, meta: WatchMeta(startedAt: "2026-10-26T12:00:00Z"))
    }

    @Test func theWriteUpPicksTheClicksAndWhatToSay() throws {
        let path = try #require(ShowPath.from(recording: Self.recording(), picks: [(1, "Open Waxwing App in the sidebar"), (4, " Click History "), (0, "a scene, not a click")],
                                              title: "See the history", recorded: "2026-10-26"))
        #expect(path.steps.map(\.say) == ["Open Waxwing App in the sidebar", "Click History"])
        #expect(path.steps.map(\.role) == ["AXLink", "AXButton"] && path.route == "Waxwing App 24 → History")
        // The address loses what could carry a credential, and the part after #.
        #expect(path.steps[0].url == "http://127.0.0.1:4310/" && path.start == "“Waxwing” at http://127.0.0.1:4310/")
        #expect(path.slice(from: 2, until: nil).steps.map(\.label) == ["History"])
        #expect(path.slice(from: nil, until: 1).steps.count == 1)
        #expect(path.slice(from: nil, until: 0).steps.map(\.say) == ["Open Waxwing App in the sidebar"])   // never the whole way
        #expect(path.slice(from: 9, until: nil).steps.map(\.label) == ["History"])
    }

    @Test func theDayShownIsTheLocalDay() {
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        #expect(ShowPath.day(of: "2026-10-27T01:30:00Z", in: pacific) == "2026-10-26")   // 18:30 the evening before
        #expect(ShowPath.day(of: "2026-10-27T01:30:00Z", in: TimeZone(identifier: "UTC")!) == "2026-10-27")
        #expect(ShowPath.day(of: "not a date") == nil)
    }

    @Test func withoutPicksEveryNamedClickIsKeptOnce() throws {
        let path = try #require(ShowPath.from(recording: Self.recording(), picks: [], title: "t", recorded: nil))
        #expect(path.steps.map(\.label) == ["Waxwing App 24", "Header", "History"])
        #expect(path.steps[0].say == "Click “Waxwing App 24”")
    }

    @Test func keepingAWriteUpKeepsItsWayBesideTheHowTo() async throws {
        let text = """
        ```json
        {"pack_dir": "waxwing", "pack_name": "Waxwing", "match_urls": ["127.0.0.1:4310"], "workflow_slug": "see-history",
         "workflow_title": "See the history", "workflow_markdown": "1. Open Waxwing App.\\n2. Click History.",
         "path": [{"event": 1, "say": "Open Waxwing App"}, {"event": 4, "say": "Click History"}]}
        ```
        """
        let draft = WatchSummarizer.parse(text, recording: Self.recording())
        #expect(draft.path?.steps.count == 2 && draft.path?.title == "See the history" && draft.path?.recorded == "2026-10-26")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("show-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try PackWriter.write(draft, root: root)
        try PackWriter.write(draft, root: root)   // the same task kept twice: see-history-2, both with their way
        let paths = ShowPathStore.load(packDir: root.appendingPathComponent("waxwing"))
        #expect(Set(paths.keys) == ["see-history", "see-history-2"] && paths["see-history"]?.steps.map(\.say) == ["Open Waxwing App", "Click History"])

        let registry = await ToolRegistry(root: root, runner: ScriptRunner(config: Config()))
        await registry.reload()
        let pack = try #require(await registry.packs.first { $0.dirName == "waxwing" })
        let section = Prompt.toolPacks(active: [pack], global: [], others: [], stuffLimit: 10_000)
        #expect(section.contains("### Paths you can show (show_me)"))
        #expect(section.contains("- waxwing/see-history: See the history. 2 steps: Waxwing App 24 → History (starts on “Waxwing” at http://127.0.0.1:4310/), shown 2026-10-26"))
        let conversation = await ShowMeConversation(registry: registry)
        #expect(await conversation.path(named: "waxwing/see-history")?.steps.count == 2)
        #expect(await conversation.path(named: "waxwing/nothing") == nil)
    }

    @Test func theChatIsToldToShowRatherThanWriteSteps() {
        #expect(Prompt.system.contains("show_me"))
        #expect(Prompt.watchSystem.contains("- path:"))
        #expect(ShowMeConversation.axRole("Button") == "AXButton" && ShowMeConversation.axRole("whatever") == nil)
    }

    // MARK: - The card

    @Test func theCardHangsUnderAHeaderAndBesideAControlWithRoom() {
        let visible = CGRect(x: 0, y: 0, width: 1_400, height: 900)
        let size = CGSize(width: 304, height: 140)
        // A control in the top bar: under it.
        let header = ShowOverlay.cardOrigin(size: size, ring: CGRect(x: 1_300, y: 840, width: 70, height: 40), in: visible, last: nil)
        #expect(header.y + size.height < 840 - ShowMarksView.pad)
        // In the middle with room to the right: to the right.
        let middle = ShowOverlay.cardOrigin(size: size, ring: CGRect(x: 300, y: 400, width: 100, height: 30), in: visible, last: nil)
        #expect(middle.x > 400)
        // Near the right edge: under it rather than over the field to its left.
        let right = ShowOverlay.cardOrigin(size: size, ring: CGRect(x: 1_250, y: 400, width: 120, height: 36), in: visible, last: nil)
        #expect(right.y + size.height < 400 && right.x + size.width <= visible.maxX)
        // Nothing ringed while the next page loads: where it was.
        #expect(ShowOverlay.cardOrigin(size: size, ring: nil, in: visible, last: CGPoint(x: 10, y: 20)) == CGPoint(x: 10, y: 20))
    }

    @Test func progressCountsFromOne() {
        var p = TourProgress(title: "t", steps: ["a", "b"], current: 0, state: .showing)
        #expect(p.count == "1 of 2" && !p.isLast && p.step == "a")
        p.current = 2; p.state = .done
        #expect(p.count == "2 of 2" && p.isOver && p.step == nil)
    }
}
