import ApplicationServices
import Foundation
import Testing
import FamiliarContracts
import FamiliarRuntime
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

    @Test func aStepFromAPageIsNeverTheBrowsersOwnToolbar() throws {
        // Chrome's toolbar sits in the window beside the page; the page is still loading, so its area is empty.
        let searchTabs = FakeNode("AXButton", ["AXDescription": "Search tabs"], frame: CGRect(x: 92, y: 39, width: 28, height: 28))
        let toolbar = FakeNode("AXToolbar", [:], frame: CGRect(x: 0, y: 0, width: 1_200, height: 80), [searchTabs])
        let page = FakeNode("AXWebArea", ["AXURL": "https://app.example.com/search/by-id"], frame: CGRect(x: 0, y: 80, width: 1_200, height: 820))
        let window = FakeNode("AXWindow", [:], frame: Self.window, [toolbar, page])
        let step = ShowStep(say: "Click SEARCH", role: "AXButton", label: "SEARCH", url: "https://app.example.com/search/by-id")
        // Looked for in the whole window it would be taken, by part of its name.
        #expect(ShowFinder.find(step, in: window, visibleArea: Self.window, windowFrame: Self.window)?.how == .partOfName)
        // A step from a page is looked for on the page only, and an empty page has nothing to find yet.
        let scopes = ShowFinder.scopes(for: step, window: window, page: page, inBrowser: true)
        #expect(scopes.map(\.node.role) == ["AXWebArea"])
        #expect(ShowFinder.find(step, in: scopes[0].node, visibleArea: Self.window, windowFrame: Self.window) == nil)
        #expect(ShowFinder.scopes(for: step, window: window, page: nil, inBrowser: true).isEmpty)
        // One named for the screen now: the page first, then the rest of the window. In another app, the window.
        #expect(ShowFinder.scopes(for: ShowStep(say: "", label: "SEARCH"), window: window, page: page, inBrowser: true).map(\.node.role) == ["AXWebArea", "AXWindow"])
        #expect(ShowFinder.scopes(for: step, window: window, page: nil, inBrowser: false).map(\.node.role) == ["AXWindow"])
        // A control that stays out of view after being asked in is looked for again.
        let t = Date()
        #expect(!ShowTour.staysOutOfView(since: nil, now: t) && !ShowTour.staysOutOfView(since: t, now: t.addingTimeInterval(3)))
        #expect(ShowTour.staysOutOfView(since: t, now: t.addingTimeInterval(ShowTour.offscreenPatience + 0.1)))
    }

    @Test func aClickOnACardIsTheCardNotThePageAroundIt() throws {
        // A card built from plain divs: the text clicked, the card, the list and the page's root, under the web area.
        let text = FakeNode("AXStaticText", ["AXValue": "Ingestion Portal"], frame: CGRect(x: 40, y: 200, width: 120, height: 18))
        let card = FakeNode("AXGroup", [:], frame: CGRect(x: 20, y: 180, width: 280, height: 160), [text])
        let list = FakeNode("AXGroup", [:], frame: CGRect(x: 0, y: 120, width: 900, height: 600), [card])
        let root = FakeNode("AXGroup", ["AXDOMIdentifier": "app"], frame: CGRect(x: 0, y: 100, width: 1_190, height: 790), [list])
        let page = CGRect(x: 0, y: 100, width: 1_200, height: 800)
        let picked = try #require(ShowFinder.pick([text, card, list, root], around: page, rootChild: true))
        #expect(picked.node.role == "AXStaticText" && picked.label == "Ingestion Portal")
        // Clicked on the card's padding: the card itself, to be found by where it is. On the page's background: nothing.
        let padding = try #require(ShowFinder.pick([card, list, root], around: page, rootChild: true))
        #expect(padding.node.role == "AXGroup" && padding.node.frame == card.frame && padding.label == nil)
        #expect(ShowFinder.pick([root], around: page, rootChild: true) == nil)
        // The text inside a button is still the button.
        let inner = FakeNode("AXStaticText", ["AXValue": "Save"], frame: CGRect(x: 50, y: 206, width: 40, height: 18))
        let button = FakeNode("AXButton", ["AXTitle": "Save"], frame: CGRect(x: 40, y: 200, width: 80, height: 30), [inner])
        let inButton = try #require(ShowFinder.pick([inner, button, list, root], around: page, rootChild: true))
        #expect(inButton.node.role == "AXButton" && inButton.label == "Save")
        // The page's root never names a step, and a step once recorded as the root rings nothing, not the whole page.
        #expect(!ShowFinder.isControlID("app") && !ShowFinder.isControlID("__next") && ShowFinder.isControlID("footer-settings"))
        let tree = FakeNode("AXWindow", [:], frame: Self.window, [FakeNode("AXWebArea", [:], frame: Self.window, [root])])
        let old = ShowStep(say: "Open Ingestion Portal", role: "AXGroup", domID: "app", rect: [0, 0.1194, 0.9913, 0.8806])
        #expect(ShowFinder.find(old, in: tree, visibleArea: Self.window, windowFrame: Self.window) == nil)
        // The card recorded as itself is found again by where it is: the group of about that size at that spot.
        let kept = ShowStep(say: "Open Ingestion Portal", role: "AXGroup", rect: [20.0 / 1_200, 180.0 / 900, 280.0 / 1_200, 160.0 / 900])
        #expect(ShowFinder.find(kept, in: tree, visibleArea: Self.window, windowFrame: Self.window)?.frame == card.frame)
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

    @Test func theWayStartsOnTheToolNotOnTheTripThere() throws {
        var events: [WatchEvent] = []
        func add(_ label: String, url: String?) {
            var e = WatchEvent(index: events.count, t: Double(events.count), kind: "click", app: "Google Chrome", title: "t", url: url)
            e.label = label
            e.axRole = "AXButton"
            e.rect = [0.1, 0.1, 0.1, 0.05]
            events.append(e)
        }
        add("Search", url: nil)                                                   // a new tab
        add("Google Search", url: "https://www.google.com/search?q=waxwing")
        add("Next", url: "https://accounts.google.com/signin")
        add("Waxwing App 24", url: "http://127.0.0.1:4310/")
        add("History", url: "http://127.0.0.1:4310/?collection=a")
        let recording = Recording(dir: URL(fileURLWithPath: "/tmp/none"), events: events, meta: WatchMeta(startedAt: "2026-10-26T12:00:00Z"))
        // The write-up picked the trip too; the way still starts on the tool.
        let picks = [(0, "Click the search box"), (1, "Search for Waxwing"), (2, "Click Next"), (3, "Open Waxwing App"), (4, "Click History")]
        let path = try #require(ShowPath.from(recording: recording, picks: picks, title: "t", recorded: nil))
        #expect(path.steps.map(\.label) == ["Waxwing App 24", "History"] && path.start == "“t” at http://127.0.0.1:4310/")
        #expect(ShowPath.from(recording: recording, picks: [], title: "t", recorded: nil)?.steps.map(\.label) == ["Waxwing App 24", "History"])
        // A way through the search engine, or through Slack, is still a way: the trip ends where the last step is.
        let google = ShowStep(say: "a", label: "Tools", url: "https://www.google.com/search?q=x")
        let onGoogle = ShowPath(title: "t", recorded: nil, steps: [google, ShowStep(say: "b", label: "Any time", url: "https://google.com/search?q=x&tbs=1")])
        #expect(onGoogle.withoutTheWayThere == onGoogle)
        let slack = ShowStep(say: "c", label: "Preferences", url: "https://app.slack.com/client/T1")
        #expect(ShowPath(title: "t", recorded: nil, steps: [google, slack]).withoutTheWayThere.steps == [slack])
        // Through an app, nothing is a trip; from a new tab into one, the tab is.
        let finder = ShowStep(say: "d", label: "Applications", app: "Finder")
        #expect(!finder.isOnTheWayThere && ShowStep(say: "e", label: "Search", app: "Safari").isOnTheWayThere)
        #expect(ShowStep(say: "f", label: "x", url: "chrome://newtab/").isOnTheWayThere && !ShowStep(say: "g", label: "x", url: "file:///tmp/tool.html").isOnTheWayThere)
        // A way kept before the trip was left out loses it when read back.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("show-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = ShowPath(title: "old", recorded: nil, steps: [ShowStep(say: "s", label: "Google Search", url: "https://www.google.com/"),
                                                                 ShowStep(say: "o", label: "Open", url: "https://app.example.com/")])
        _ = try ShowPathStore.write(old, slug: "old", packDir: dir)
        #expect(ShowPathStore.load(packDir: dir)["old"]?.steps.map(\.label) == ["Open"])
    }

    @Test func theWayKeepsTheClicksTheWriteUpNames() throws {
        // Clicks A (home), B (opens a menu, same page), C (opens the page), D (a button there); the write-up lists all
        // four as steps but its path picked only A and D, the menu clicks read as "did nothing".
        var events: [WatchEvent] = []
        func add(_ label: String, role: String = "AXButton", url: String) {
            var e = WatchEvent(index: events.count, t: Double(events.count), kind: "click", app: "Google Chrome", title: "t", url: url)
            e.label = label
            e.axRole = role
            e.rect = [0.1, 0.1, 0.1, 0.05]
            events.append(e)
        }
        add("Home", url: "https://app.example.com/")                                     // 0: A
        add("Search", role: "AXMenuItem", url: "https://app.example.com/")                // 1: B
        add("Search", role: "AXMenuItem", url: "https://app.example.com/")                // 2: B again, a double click
        add("Search by Id", role: "AXMenuItem", url: "https://app.example.com/")          // 3: C
        add("Query", role: "AXTextField", url: "https://app.example.com/search/by-id")   // 4: into a field, to type
        add("SEARCH", url: "https://app.example.com/search/by-id")                        // 5: D
        add("Logout", url: "https://app.example.com/search/by-id")                        // 6: after the task
        let recording = Recording(dir: URL(fileURLWithPath: "/tmp/none"), events: events, meta: WatchMeta(startedAt: "2026-10-26T12:00:00Z"))
        let markdown = "1. Click **Home**.\n2. Click **Search**. It expands to show **Search by Id**.\n3. Click **Search by Id**.\n"
            + "4. Type the id in **Query** and click **SEARCH**.\n5. **Logout** when done."
        let (picks, added) = ShowPath.complete([(0, "Open home"), (5, "Click SEARCH")], from: markdown, recording: recording)
        #expect(added == [1, 3] && picks.map(\.event) == [0, 1, 3, 5])
        let path = try #require(ShowPath.from(recording: recording, picks: picks, title: "t", recorded: nil))
        #expect(path.steps.map(\.say) == ["Open home", "Click “Search”", "Click “Search by Id”", "Click SEARCH"])
        // A write-up that names nothing in bold, or picks nothing, is left alone.
        #expect(ShowPath.complete([(0, "a"), (5, "b")], from: "1. Click Search.", recording: recording).added.isEmpty)
        #expect(ShowPath.complete([], from: markdown, recording: recording).picks.isEmpty)
        #expect(ShowPath.bold(in: "click **Search**, then **Search by Id** (not *this*)") == ["Search", "Search by Id"])
        #expect(Prompt.watchSystem.contains("opens a menu"))
    }

    @Test func aStepOnAnotherPageIsNeverTakenByNameAlone() throws {
        let step = ShowStep(say: "Click SEARCH", role: "AXButton", label: "SEARCH", url: "https://app.example.com/search/by-id")
        // The home page has a menu item "Search" and a heading "SEARCH"; the step's page has the button.
        let menu = FakeNode("AXGroup", ["AXDescription": "Search"], frame: CGRect(x: 10, y: 100, width: 150, height: 30))
        let heading = FakeNode("AXStaticText", ["AXValue": "SEARCH"], frame: CGRect(x: 300, y: 100, width: 100, height: 24))
        let home = FakeNode("AXWindow", [:], frame: Self.window, [FakeNode("AXWebArea", ["AXURL": "https://app.example.com/"], frame: Self.window, [menu, heading])])
        // Plain text or a group with the name is never a control's kind: nothing on the home page is the button.
        #expect(ShowFinder.find(step, in: home, visibleArea: Self.window, windowFrame: Self.window) == nil)
        // A control of another kind with the name is a match by name, which the tour takes only on the step's page.
        let link = FakeNode("AXLink", [:], frame: CGRect(x: 10, y: 100, width: 150, height: 30),
                            [FakeNode("AXStaticText", ["AXValue": "SEARCH"], frame: CGRect(x: 20, y: 105, width: 60, height: 20))])
        let withLink = FakeNode("AXWindow", [:], frame: Self.window, [FakeNode("AXWebArea", ["AXURL": "https://app.example.com/"], frame: Self.window, [link])])
        #expect(ShowFinder.find(step, in: withLink, visibleArea: Self.window, windowFrame: Self.window)?.how == .name)
        #expect(!ShowTour.accepts(.name, offset: 0, onPage: false, atItsPlace: false) && ShowTour.accepts(.name, offset: 0, onPage: true, atItsPlace: false))
        #expect(ShowTour.accepts(.kindAndName, offset: 0, onPage: false, atItsPlace: false) && ShowTour.accepts(.place, offset: 0, onPage: true, atItsPlace: false))
        #expect(!ShowTour.accepts(.kindAndName, offset: 1, onPage: true, atItsPlace: false) && ShowTour.accepts(.id, offset: 1, onPage: false, atItsPlace: true))
        let button = FakeNode("AXButton", ["AXTitle": "SEARCH"], frame: CGRect(x: 300, y: 100, width: 100, height: 30))
        let there = FakeNode("AXWindow", [:], frame: Self.window, [FakeNode("AXWebArea", ["AXURL": "https://app.example.com/search/by-id"], frame: Self.window, [button])])
        #expect(ShowFinder.find(step, in: there, visibleArea: Self.window, windowFrame: Self.window)?.how == .kindAndName)
        // Given up on another page, the card can take the person to the step's page.
        #expect(ShowTour.elsewhere(for: step, place: TourPlace(app: "Google Chrome", isBrowser: true, address: "https://app.example.com/")) == "app.example.com/search/by-id")
        #expect(ShowTour.elsewhere(for: step, place: TourPlace(app: "Google Chrome", isBrowser: true, address: "https://app.example.com/search/by-id?x=1")) == nil)
        #expect(ShowTour.elsewhere(for: step, place: nil) == nil)
    }

    @Test func theTourTakesThePersonToWhereTheWayStarts() throws {
        let step = ShowStep(say: "Open Waxwing App", label: "Waxwing App 24", app: "Google Chrome", url: "http://127.0.0.1:4310/")
        let start = try #require(URL(string: "http://127.0.0.1:4310/"))
        // On a search engine, or in Finder: the page is opened at once.
        #expect(ShowTour.entry(to: step, from: TourPlace(app: "Google Chrome", isBrowser: true, address: "https://www.google.com/search?q=waxwing"), waited: 0) == .open(start))
        #expect(ShowTour.entry(to: step, from: TourPlace(app: "Finder", isBrowser: false, address: nil), waited: 0) == .open(start))
        // On the page, even with another item selected: nothing to open, the control is waited for as usual.
        #expect(ShowTour.entry(to: step, from: TourPlace(app: "Safari", isBrowser: true, address: "http://127.0.0.1:4310/?collection=a#x"), waited: 9) == nil)
        // A browser that hasn't said where it is gets a moment, then the page is opened all the same.
        #expect(ShowTour.entry(to: step, from: TourPlace(app: "Google Chrome", isBrowser: true, address: nil), waited: 1) == nil)
        #expect(ShowTour.entry(to: step, from: TourPlace(app: "Google Chrome", isBrowser: true, address: nil), waited: ShowTour.entryPatience) == .open(start))
        // A way through an app brings the app forward.
        let native = ShowStep(say: "Open General", label: "General", app: "System Settings", title: "General")
        #expect(ShowTour.entry(to: native, from: TourPlace(app: "Finder", isBrowser: false, address: nil), waited: 0) == .bring("System Settings"))
        #expect(ShowTour.entry(to: native, from: TourPlace(app: "System Settings", isBrowser: false, address: nil), waited: 0) == nil)
        #expect(ShowFinder.samePage("HTTPS://WWW.Example.com/a/b/?x=1#y", "http://example.com/a/b") && !ShowFinder.samePage("https://example.com/a", "https://example.com/a/b"))
        #expect(ShowTour.shortAddress(start) == "127.0.0.1:4310" && ShowTour.shortAddress(URL(string: "https://app.example.com/settings/tokens/")!) == "app.example.com/settings/tokens")
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
        let scene = ScreenContext(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: "Waxwing", url: "http://127.0.0.1:4310/",
                                  focused: nil, timestamp: Date())
        let section = Prompt.toolPacks(await registry.select(for: scene), scene: scene, stuffLimit: 10_000)
        #expect(section.contains("## Active tool pack: Waxwing (leads on this page: 127.0.0.1:4310)"))
        #expect(section.contains("### Ways you can teach (teach_the_way)"))
        #expect(section.contains("- waxwing/see-history: See the history. 2 steps: Waxwing App 24 → History (starts on “Waxwing” at http://127.0.0.1:4310/), shown 2026-10-26"))
        let conversation = await ShowMeConversation(registry: registry)
        #expect(await conversation.path(named: "waxwing/see-history")?.steps.count == 2)
        #expect(await conversation.path(named: "waxwing/nothing") == nil)
    }

    @Test @MainActor func theChatFoldsToItsNoteWhenAWayIsTaught() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fold-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var config = Config()
        config.apiKey = "fixture-no-network"
        let registry = ToolRegistry(root: root, runner: ScriptRunner(config: config))
        let learning = WatchLearnSession(operations: .init(
            start: { _ in }, stop: { Recording(dir: root, events: [], meta: WatchMeta(startedAt: "test", clicks: 0)) }, abandon: {},
            summarize: { _, _, _ in throw ClaudeError(message: "Not recording") }, write: { _ in [] }, reload: {}
        ))
        let shell = ShellState()
        let assistant = Assistant(config: config, watcher: ContextWatcher(), registry: registry, shell: shell, learning: learning)
        let showMe = ShowMeConversation(registry: registry)
        assistant.showMe = showMe
        var hops = 0
        assistant.onTourDone = { hops += 1 }
        // The chat is open; a way starts: its list goes on the pad and the pad folds to its note.
        shell.expanded = true
        let path = ShowPath(title: "See the history", recorded: nil, steps: [ShowStep(say: "Click History", role: "AXLink", label: "History")])
        var progress = TourProgress(title: path.title, steps: ["Click History"], current: 0, state: .looking)
        let message = try #require(showMe.onStart?(path, progress))
        #expect(!shell.expanded && assistant.transcript.last?.id == message && assistant.transcript.last?.role == .tour)
        // Stopped: nothing; done: the note hops once.
        progress.state = .stopped
        showMe.onEnd?(progress)
        #expect(hops == 0)
        progress.current = 1; progress.state = .done
        showMe.onEnd?(progress)
        #expect(hops == 1)
    }

    @Test func theChatIsToldToShowRatherThanWriteSteps() {
        #expect(Prompt.intents(.standard, pinned: nil).contains("teach_the_way"))
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

    // MARK: - The second day of use (#60, #61, #62, #63)

    @Test func aClickThatResolvedToNothingKeepsTheSpot() throws {
        // A click at (300, 600) in AppKit coordinates, in a 1200×900 window at the origin: a quarter across, a third
        // down from the top, and no size.
        let spot = WatchRecorder.spot(NSPoint(x: 300, y: 600), in: NSRect(x: 0, y: 0, width: 1_200, height: 900))
        #expect(spot == [0.25, 0.3333, 0, 0])
        // Found again by the smallest control that holds the spot, never by the page around it.
        let item = FakeNode("AXMenuItem", ["AXTitle": "Search by Id"], frame: CGRect(x: 20, y: 290, width: 300, height: 32))
        let list = FakeNode("AXGroup", [:], frame: CGRect(x: 0, y: 80, width: 300, height: 820), [item])
        let root = FakeNode("AXGroup", ["AXDOMIdentifier": "app"], frame: Self.window, [list])
        let page = FakeNode("AXWindow", [:], frame: Self.window, [FakeNode("AXWebArea", [:], frame: Self.window, [root])])
        let step = ShowStep(say: "Click Search by Id", rect: spot)
        let found = try #require(ShowFinder.find(step, in: page, visibleArea: Self.window, windowFrame: Self.window))
        #expect(found.how == .place && found.frame?.minY == 290)
        let bare = FakeNode("AXWindow", [:], frame: Self.window, [FakeNode("AXWebArea", [:], frame: Self.window, [FakeNode("AXGroup", [:], frame: Self.window)])])
        #expect(ShowFinder.find(step, in: bare, visibleArea: Self.window, windowFrame: Self.window) == nil)
        // A step with only a spot is still a step: the way keeps it.
        var e = WatchEvent(index: 1, t: 1, kind: "click", app: "Google Chrome", title: "t", url: "https://app.example.com/")
        e.rect = spot
        var unfindable = WatchEvent(index: 2, t: 2, kind: "click", app: "Google Chrome", title: "t", url: "https://app.example.com/")
        unfindable.label = ""
        let recording = Recording(dir: URL(fileURLWithPath: "/tmp/none"), events: [e, unfindable], meta: WatchMeta(startedAt: "2026-10-26T12:00:00Z"))
        let path = try #require(ShowPath.from(recording: recording, picks: [(1, "Click Search by Id"), (2, "Click nothing")], title: "t", recorded: nil))
        #expect(path.steps.map(\.say) == ["Click Search by Id"] && path.steps[0].rect == spot)
    }

    @Test func aStepInTheBrowsersOwnWindowIsLookedForOutsideThePage() throws {
        // Chrome's toolbar beside a page that has a "Downloads" link of its own.
        let icon = FakeNode("AXButton", ["AXDescription": "Downloads"], frame: CGRect(x: 1_100, y: 40, width: 30, height: 30))
        let toolbar = FakeNode("AXToolbar", [:], frame: CGRect(x: 0, y: 0, width: 1_200, height: 80), [icon])
        let link = FakeNode("AXLink", ["AXTitle": "Downloads"], frame: CGRect(x: 100, y: 300, width: 100, height: 20))
        let page = FakeNode("AXWebArea", ["AXURL": "https://app.example.com/"], frame: CGRect(x: 0, y: 80, width: 1_200, height: 820), [link])
        let window = FakeNode("AXWindow", [:], frame: Self.window, [toolbar, page])
        // Recorded with no address and the browser as its app: looked for in the browser's part of the window first,
        // and what shows of it is the window, not the page.
        let step = ShowStep(say: "Open downloads", role: "AXButton", label: "Downloads", app: "Google Chrome")
        #expect(ShowFinder.inBrowsersOwnUI(step) && !ShowFinder.inBrowsersOwnUI(ShowStep(say: "", label: "Downloads", app: "Google Chrome", url: "https://app.example.com/")))
        #expect(ShowFinder.scopes(for: step, window: window, page: page, inBrowser: true).map(\.node.role) == ["AXWindow", "AXWebArea"])
        let found = try #require(ShowFinder.findInWindow(step, window: window, page: page, inBrowser: true))
        #expect(found.how == .kindAndName && found.frame?.minY == 40 && found.area == Self.window)
        // On the page, what shows is the page's area.
        let onPage = try #require(ShowFinder.findInWindow(ShowStep(say: "", role: "AXLink", label: "Downloads", url: "https://app.example.com/"), window: window, page: page, inBrowser: true))
        #expect(onPage.frame?.minY == 300 && onPage.area == CGRect(x: 0, y: 80, width: 1_200, height: 820))
        // The toolbar's button is named for its state; recorded as "New download available", it is found where it was.
        let renamed = ShowStep(say: "Open downloads", role: "AXButton", label: "New download available", app: "Google Chrome", rect: [0.9167, 0.0444, 0.025, 0.0333])
        let byPlace = try #require(ShowFinder.findInWindow(renamed, window: window, page: page, inBrowser: true))
        #expect(byPlace.how == .place && byPlace.frame?.minY == 40)
        // A step on a page is never its place alone (a heading "Search" is not the "SEARCH" button).
        let pageStep = ShowStep(say: "", role: "AXLink", label: "Nowhere", url: "https://app.example.com/", rect: [0.083, 0.333, 0.083, 0.022])
        #expect(ShowFinder.findInWindow(pageStep, window: window, page: page, inBrowser: true) == nil)
        // A name with a file in it is the same control with today's file in it.
        #expect(ShowFinder.stablePart("Show Price-Changes-8f3a-1793038791953.xlsx in Finder") == "Show in Finder")
        #expect(ShowFinder.stablePart("Open report-2026-10-26.pdf") == nil && ShowFinder.stablePart("Q3 2026 report") == nil && ShowFinder.stablePart("Show in Finder") == nil)
        let bubble = FakeNode("AXWindow", [:], frame: Self.window, [
            FakeNode("AXButton", ["AXTitle": "Show Price-Changes-9b1c-1793125191953.xlsx in Finder"], frame: CGRect(x: 10, y: 10, width: 300, height: 24)),
        ])
        let later = ShowStep(say: "Show it in Finder", role: "AXButton", label: "Show Price-Changes-8f3a-1793038791953.xlsx in Finder", app: "Google Chrome")
        #expect(ShowFinder.find(later, in: bubble, visibleArea: Self.window, windowFrame: Self.window)?.how == .nameButNumbers)
        // The trip to the tool is still dropped when the way ends in the browser's own window or another app.
        let way = ShowPath(title: "t", recorded: nil, steps: [
            ShowStep(say: "Search", role: "AXButton", label: "Google Search", app: "Google Chrome", url: "https://www.google.com/"),
            ShowStep(say: "Download", role: "AXButton", label: "Download", app: "Google Chrome", url: "https://app.example.com/items"),
            ShowStep(say: "Open downloads", role: "AXButton", label: "Downloads", app: "Google Chrome"),
            ShowStep(say: "Open the file", role: "AXTextField", label: "Price changes", app: "Finder", title: "Downloads"),
        ])
        #expect(way.withoutTheWayThere.steps.map(\.say) == ["Download", "Open downloads", "Open the file"])
    }

    @Test func theTourHoldsAFieldStepWhileTheNextButtonIsGrey() {
        // The next step's button is on the page from the start, grey: no evidence of going ahead, however long.
        #expect(!ShowTour.goneAhead(nextEnabled: false, seen: nil, acted: true))
        #expect(!ShowTour.goneAhead(nextEnabled: false, seen: (found: true, enabled: false), acted: true))
        // It came alive after the person typed and pressed Enter: they're past the field.
        #expect(ShowTour.goneAhead(nextEnabled: true, seen: (found: true, enabled: false), acted: true))
        #expect(!ShowTour.goneAhead(nextEnabled: true, seen: (found: true, enabled: false), acted: false))
        // It was there and live from the start: the person is on the field, not past it.
        #expect(!ShowTour.goneAhead(nextEnabled: true, seen: (found: true, enabled: true), acted: true))
        // It appeared since (the page after the click), or is live at first sight: they went ahead.
        #expect(ShowTour.goneAhead(nextEnabled: true, seen: (found: false, enabled: false), acted: true))
        #expect(ShowTour.goneAhead(nextEnabled: true, seen: nil, acted: false))
        // A field is a step to leave, not to click.
        #expect(ShowStep(say: "", role: "AXTextField").isField && !ShowStep(say: "", role: "AXButton").isField && !ShowStep(say: "").isField)
        var p = TourProgress(title: "t", steps: ["Type the item number, then press Enter", "Click Next"], current: 0, state: .showing)
        #expect(p.instruction == "Click it when you're ready.")
        p.inField = true
        #expect(p.instruction == "Type what it needs, then press Enter or Tab.")
    }

    @Test func aGreyedOutControlIsRingedButNotDoneOnAClick() throws {
        let grey = FakeNode("AXButton", ["AXTitle": "Next: Products", "AXEnabled": false], frame: CGRect(x: 600, y: 400, width: 120, height: 32))
        let live = FakeNode("AXButton", ["AXTitle": "Back", "AXEnabled": true], frame: CGRect(x: 400, y: 400, width: 80, height: 32))
        let unsaid = FakeNode("AXButton", ["AXTitle": "Help"], frame: CGRect(x: 800, y: 400, width: 80, height: 32))
        let page = FakeNode("AXWindow", [:], frame: Self.window, [grey, live, unsaid])
        func find(_ label: String) -> ShowFinder.Found<FakeNode>? {
            ShowFinder.find(ShowStep(say: "", role: "AXButton", label: label), in: page, visibleArea: Self.window)
        }
        #expect(find("Next: Products")?.enabled == false && find("Back")?.enabled == true && find("Help")?.enabled == true)
        // The card says it's grey, in the way's words when it has them.
        var p = TourProgress(title: "t", steps: ["Click Next"], current: 0, state: .showing, disabled: true)
        #expect(p.instruction == "It's greyed out: something on the page still needs finishing.")
        p.hint = "Press Enter so the item number becomes a chip"
        #expect(p.instruction == "Press Enter so the item number becomes a chip")
        // The keys that commit input are recorded, with the field's name and nothing typed.
        let enter = try #require(WatchRecorder.keyEvent(code: 36, field: .text(label: "Item number")))
        #expect(enter.kind == "key" && enter.text == "Enter" && enter.label == "Item number" && enter.role == "text field")
        #expect(WatchRecorder.keyEvent(code: 76, field: nil)?.text == "Enter" && WatchRecorder.keyEvent(code: 48, field: nil)?.text == "Tab")
        let escape = try #require(WatchRecorder.keyEvent(code: 53, field: .hidden(why: "password field")))
        #expect(escape.text == "Escape" && escape.label == nil && escape.role == "password field")
        #expect(WatchRecorder.keyEvent(code: 0, field: nil) == nil)
        #expect(WatchSummarizer.line(enter).hasSuffix("pressed Enter in Item number"))
        #expect(Prompt.watchSystem.contains("\"blocked\"") && Prompt.watchSystem.contains("Enter, Tab, Escape"))
        // The write-up's hint for a grey control rides along with its step, and a way kept without one reads the same.
        let text = """
        ```json
        {"pack_dir": "waxwing", "pack_name": "Waxwing", "match_urls": ["127.0.0.1:4310"], "workflow_slug": "see-history",
         "workflow_title": "See the history", "workflow_markdown": "1. Open Waxwing App.\\n2. Click History.",
         "path": [{"event": 1, "say": "Open Waxwing App"}, {"event": 4, "say": "Click History", "blocked": "Press Enter so the item number becomes a chip"}]}
        ```
        """
        let path = try #require(WatchSummarizer.parse(text, recording: Self.recording()).path)
        #expect(path.steps.map(\.blocked) == [nil, "Press Enter so the item number becomes a chip"])
        let data = try JSONEncoder().encode(path)
        #expect(try JSONDecoder().decode(ShowPath.self, from: data) == path)
        let old = try JSONDecoder().decode(ShowStep.self, from: Data(#"{"say": "Click History", "role": "AXLink", "label": "History"}"#.utf8))
        #expect(old.blocked == nil && old.label == "History")
    }
}
