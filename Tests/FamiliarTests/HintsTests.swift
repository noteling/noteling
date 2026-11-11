import AppKit
import Foundation
import Testing
@testable import Familiar

/// Hints shown by themselves: placed from reads of the page as it comes up, shown once it holds still, kept with the
/// page, gone with it; the
/// tag's place on a control; which hint the pointer is on; the team's hints read from their folder and shared through
/// GitHub; and the setting.
@Suite @MainActor
struct HintsTests {
    private func note(_ id: String, label: String = "Submit", url: String = "https://portal.example.test/submission?id=7",
                      text: String = "Fetched from Workday; tell abc if it's wrong", kind: String = "tip") -> StickyNote {
        var anchor = NoteStore.sceneAnchor(bundleID: "com.google.Chrome", windowTitle: "Portal", url: url)
        anchor.role = "AXButton"
        anchor.label = label
        return StickyNote(id: id, anchor: anchor, kind: kind, text: text, by: "Yang", at: "2026-11-09", confirmed: "2026-11-09")
    }

    private func scene(_ url: String = "https://portal.example.test/submission?id=7") -> ScreenContext {
        ScreenContext(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: "Portal", url: url, focused: nil, timestamp: Date())
    }

    private func controller(_ reading: @escaping (ScreenContext, [StickyNote]) async -> HintsController.Reading?) -> HintsController {
        let controller = HintsController()
        controller.shows = false
        controller.reader = reading
        controller.retryDelays = []   // no looks to see the page settle: the marks go on at the first read; the tests of the looks set their own
        return controller
    }

    private let small = NSRect(x: 0, y: 0, width: 10, height: 10)

    // MARK: - Coming and going with the page

    @Test func arrivingPlacesTheHintsAndLeavingClearsThem() async {
        let frame = NSRect(x: 100, y: 500, width: 120, height: 30)
        let hints = controller { _, notes in .init(marks: notes.map { .init(note: $0, frame: frame) }) }
        var told: [(Int, Int)] = []
        hints.onPlaced = { told.append(($0, $1)) }
        hints.arrive(scene(), notes: [note("a")])
        await hints.settle()
        #expect(hints.marks.map(\.note.id) == ["a"])
        #expect(hints.marks.first?.frame == frame)
        #expect(hints.isShowing)
        #expect(told.count == 1 && told[0] == (1, 1))
        hints.leave()
        #expect(hints.marks.isEmpty)
        #expect(!hints.isShowing)
    }

    @Test func aMissIsToldWithWhatItLookedFor() async {
        let hints = controller { _, notes in .init(marks: [], missing: notes.count, notFound: notes) }
        var told: [(Int, Int)] = []
        hints.onPlaced = { told.append(($0, $1)) }
        hints.arrive(scene(), notes: [note("a", label: "Import from spreadsheet")])
        await hints.settle()
        #expect(told.first.map { $0 == (0, 1) } == true)
        #expect(WandController.shortfall(hints.notes, of: 1, on: "portal.example.test/submission?id=7")
                == "hints: 1 of 1 not found on portal.example.test/submission?id=7: button “Import from spreadsheet”")
    }

    @Test func noHintsOrHintsOffMeansNothingComesUp() async {
        let hints = controller { _, _ in .init(marks: []) }
        hints.arrive(scene(), notes: [])
        #expect(!hints.isShowing)
        hints.enabled = false
        hints.arrive(scene(), notes: [note("a")])
        #expect(!hints.isShowing)
        hints.setEnabled(true, scene: scene(), notes: [note("a")])
        await hints.settle()
        #expect(hints.isShowing)
        hints.setEnabled(false, scene: scene(), notes: [note("a")])
        #expect(!hints.isShowing)
    }

    @Test func thePageMovingOnUnderTheMarksLeavesThem() async {
        let hints = controller { _, notes in
            .init(marks: notes.map { .init(note: $0, frame: self.small) }, pageURL: "https://portal.example.test/done")
        }
        hints.arrive(scene(), notes: [note("a")])
        await hints.settle()
        #expect(hints.marks.isEmpty)
        #expect(!hints.isShowing)
    }

    @Test func theSamePageSeenAgainKeepsItsMarksAndReadsAgain() async {
        // The watcher fires again for a new title; the page's own address differs only by a tracking parameter.
        var reads = 0
        let hints = controller { _, notes in
            reads += 1
            return .init(marks: notes.map { .init(note: $0, frame: self.small) }, pageURL: "https://portal.example.test/submission?id=7&utm_source=mail")
        }
        hints.arrive(scene(), notes: [note("a")])
        await hints.settle()
        var retitled = scene()
        retitled.windowTitle = "Portal · saved"
        hints.arrive(retitled, notes: [note("a")])
        await hints.settle()
        #expect(hints.marks.count == 1)
        #expect(reads == 2)
    }

    @Test func hintsChangedReadsAgainAndNoneLeftLeaves() async {
        let hints = controller { _, notes in .init(marks: notes.map { .init(note: $0, frame: self.small) }) }
        hints.arrive(scene(), notes: [note("a")])
        await hints.settle()
        hints.sync(scene(), notes: [note("a"), note("b", label: "Validate")])
        await hints.settle()
        #expect(hints.marks.count == 2)
        hints.sync(scene(), notes: [])
        #expect(!hints.isShowing)
        hints.sync(scene(), notes: [note("b", label: "Validate")])   // not showing: this arrives
        await hints.settle()
        #expect(hints.marks.map(\.note.id) == ["b"])
        hints.sync(nil, notes: [])
        #expect(!hints.isShowing)
    }

    @Test func aPageStillLoadingIsLookedAtAgain() async {
        var reads = 0
        let hints = controller { _, notes in
            reads += 1
            return reads == 1 ? .init(marks: [], missing: notes.count) : .init(marks: notes.map { .init(note: $0, frame: self.small) })
        }
        hints.retryDelays = [0.05, 0.05, 0.05]
        hints.arrive(scene(), notes: [note("a")])
        await hints.settle()
        #expect(hints.marks.isEmpty)
        // Placed at the second look, shown once the third finds it in the same place.
        await looks(hints, until: { !hints.marks.isEmpty })
        #expect(hints.marks.count == 1)
        #expect(reads == 3)
    }

    @Test func aFreshPageShowsItsMarksOnceTwoLooksAgree() async {
        // A page just come: its first look is kept, not shown; the marks go on when the next look puts them in the
        // same place (a second later in the app), so a page still laying itself out shows no tag on the wrong spot.
        let frames = [NSRect(x: 100, y: 500, width: 120, height: 30), NSRect(x: 100, y: 420, width: 120, height: 30)]
        var reads = 0
        let hints = controller { _, notes in
            reads += 1
            return .init(marks: notes.map { .init(note: $0, frame: frames[min(reads, 2) - 1]) })
        }
        hints.retryDelays = [0.05, 0.05, 0.05]
        hints.arrive(scene(), notes: [note("a")])
        await hints.settle()
        #expect(hints.marks.isEmpty)
        #expect(hints.isShowing)
        await looks(hints, until: { !hints.marks.isEmpty })
        #expect(hints.marks.first?.frame == frames[1])
        #expect(reads == 3)   // moved at the second look, stayed at the third
        try? await Task.sleep(for: .milliseconds(150))
        await hints.settle()
        #expect(reads == 3)   // and nothing more to see
    }

    @Test func aMarkThatHeldStillGoesOnWhileAnotherStillMoves() async {
        // Two hints on a page laying itself out: the control that stayed gets its tag; the one still moving waits.
        let still = NSRect(x: 100, y: 500, width: 120, height: 30)
        let moving = [NSRect(x: 100, y: 300, width: 120, height: 30), NSRect(x: 100, y: 240, width: 120, height: 30)]
        var reads = 0
        let hints = controller { _, notes in
            reads += 1
            return .init(marks: notes.map { .init(note: $0, frame: $0.id == "a" ? still : moving[min(reads, 2) - 1]) })
        }
        hints.retryDelays = [0.05, 0.05, 0.05]
        hints.arrive(scene(), notes: [note("a"), note("b", label: "Validate")])
        await hints.settle()
        #expect(hints.marks.isEmpty)
        await looks(hints, until: { !hints.marks.isEmpty })
        #expect(hints.marks.map(\.note.id) == ["a"])   // the second look: a stayed, b moved
        await looks(hints, until: { hints.marks.count == 2 })
        #expect(hints.marks.map(\.note.id) == ["a", "b"])
        #expect(hints.marks.last?.frame == moving[1])
        #expect(reads == 3)
    }

    @Test func theLooksRunningOutShowTheLastLook() async {
        // A page that never holds still (a carousel turning under the hint): after the last look the marks go on
        // where it found them, rather than never.
        var reads = 0
        let hints = controller { _, notes in
            reads += 1
            return .init(marks: notes.map { .init(note: $0, frame: NSRect(x: 100, y: 500 - 10 * reads, width: 120, height: 30)) })
        }
        hints.retryDelays = [0.05, 0.05, 0.05]
        hints.arrive(scene(), notes: [note("a")])
        await looks(hints, until: { !hints.marks.isEmpty })
        #expect(reads == 4)   // the first look and the three after it
        #expect(hints.marks.first?.frame.minY == 460)
        try? await Task.sleep(for: .milliseconds(150))
        await hints.settle()
        #expect(reads == 4)
    }

    @Test func aPageLoadingAgainHoldsItsMarksUntilItHoldsStill() async {
        // A reload: the page says it is loading where it had finished, so the marks go until two looks agree again.
        let frames = [NSRect(x: 100, y: 500, width: 120, height: 30), NSRect(x: 100, y: 380, width: 120, height: 30)]
        var reads = 0
        var reloading = false
        let hints = controller { _, notes in
            reads += 1
            return .init(marks: notes.map { .init(note: $0, frame: frames[reloading ? 1 : 0]) }, loading: reloading && reads < 5)
        }
        hints.retryDelays = [0.05, 0.05, 0.05]
        hints.arrive(scene(), notes: [note("a")])
        await looks(hints, until: { !hints.marks.isEmpty })
        #expect(hints.marks.first?.frame == frames[0])
        #expect(reads == 2)
        reloading = true
        hints.touch()   // the ⌘R was seen
        hints.read()
        await hints.settle()
        #expect(hints.marks.isEmpty)   // the new document's first look is held
        await looks(hints, until: { !hints.marks.isEmpty })
        #expect(hints.marks.first?.frame == frames[1])
        #expect(reads == 4)
        // Still loading, it is looked at once more; loaded and unmoved, left alone.
        await looks(hints, until: { reads >= 5 })
        try? await Task.sleep(for: .milliseconds(150))
        await hints.settle()
        #expect(reads == 5)
        #expect(hints.marks.first?.frame == frames[1])
    }

    /// Waits for the looks a page gets to settle, which come on the main queue's time: until `done`, or a few seconds.
    private func looks(_ hints: HintsController, until done: () -> Bool) async {
        for _ in 0..<100 where !done() {
            try? await Task.sleep(for: .milliseconds(50))
            await hints.settle()
        }
    }

    @Test func thePageIsLookedAtAgainUntilTheMarksSettle() async {
        // A page laying itself out after a reload or in a new tab: the control moves between the first looks, then
        // stays; later it moves once more, after a touch of the page.
        let frames = [NSRect(x: 100, y: 500, width: 120, height: 30), NSRect(x: 100, y: 420, width: 120, height: 30), NSRect(x: 100, y: 400, width: 120, height: 30)]
        var reads = 0
        let hints = controller { _, notes in
            reads += 1
            let frame = reads <= 4 ? frames[min(reads, 3) - 1] : frames[0]
            return .init(marks: notes.map { .init(note: $0, frame: frame) })
        }
        hints.retryDelays = [0.05, 0.05, 0.05]
        hints.arrive(scene(), notes: [note("a")])
        await hints.settle()
        #expect(hints.marks.isEmpty)   // the first look alone shows nothing
        // Looked at again after each move, once more to see it stayed, then left alone: the looks are three.
        await looks(hints, until: { reads >= 4 })
        try? await Task.sleep(for: .milliseconds(150))
        await hints.settle()
        #expect(hints.marks.first?.frame == frames[2])
        #expect(reads == 4)
        // A touch of the page (a click, a key, the wheel, another element with the focus) starts the looks over.
        hints.touch()
        hints.read()
        await looks(hints, until: { reads >= 6 })
        try? await Task.sleep(for: .milliseconds(150))
        await hints.settle()
        #expect(hints.marks.first?.frame == frames[0])
        #expect(reads == 6)
    }

    @Test func aPageStillLoadingIsLookedAtAgainThoughEveryHintWasPlaced() async {
        var reads = 0
        let hints = controller { _, notes in
            reads += 1
            return .init(marks: notes.map { .init(note: $0, frame: self.small) }, loading: reads < 3)
        }
        hints.retryDelays = [0.05, 0.05, 0.05]
        hints.arrive(scene(), notes: [note("a")])
        await hints.settle()
        // Read again while the page says it is loading, though the marks stayed; then, loaded and unmoved, left alone.
        await looks(hints, until: { reads >= 3 })
        try? await Task.sleep(for: .milliseconds(150))
        await hints.settle()
        #expect(reads == 3)
    }

    @Test func thePenUpKeepsTheMarksAway() async {
        var penUp = true
        let hints = controller { _, notes in .init(marks: notes.map { .init(note: $0, frame: self.small) }) }
        hints.suppressed = { penUp }
        hints.arrive(scene(), notes: [note("a")])
        await hints.settle()
        #expect(hints.marks.count == 1)
        hints.withdraw()
        #expect(hints.marks.isEmpty)
        #expect(hints.isShowing)
        penUp = false
        hints.resume()
        await hints.settle()
        #expect(hints.marks.count == 1)
    }

    // MARK: - On the screen

    @Test func theTagSitsOnTheControlsTopRightCornerAndStaysOnScreen() {
        let bounds = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let tag = StickerLayer.tagFrame(control: NSRect(x: 100, y: 500, width: 120, height: 30), in: bounds)
        #expect(tag.size == NSSize(width: StickerLayer.tagSide, height: StickerLayer.tagSide))
        #expect(abs(tag.minX - (220 - StickerLayer.tagSide * 0.6)) < 0.01)
        #expect(abs(tag.minY - (530 - StickerLayer.tagSide * 0.55)) < 0.01)
        let edge = StickerLayer.tagFrame(control: NSRect(x: 900, y: 790, width: 120, height: 30), in: bounds)
        #expect(edge.maxX <= bounds.width - 2)
        #expect(edge.maxY <= bounds.height - 2)
    }

    @Test func thePointerPicksTheHintOnItsControlOrTagAndKeepsAnOpenOne() {
        let a = HintsController.Mark(note: note("a"), frame: NSRect(x: 100, y: 500, width: 120, height: 30))
        let b = HintsController.Mark(note: note("b", label: "Validate"), frame: NSRect(x: 300, y: 500, width: 120, height: 30))
        #expect(HintsController.pick([a, b], open: nil, at: NSPoint(x: 110, y: 510)) == "a")
        #expect(HintsController.pick([a, b], open: nil, at: NSPoint(x: 410, y: 525)) == "b")
        #expect(HintsController.pick([a, b], open: nil, at: NSPoint(x: 600, y: 100)) == nil)
        let tag = HintsController.tag(on: a.frame)   // just past the control's corner
        #expect(HintsController.pick([a, b], open: nil, at: NSPoint(x: tag.maxX - 1, y: tag.maxY - 1)) == "a")
        let paper = NSRect(x: 180, y: 520, width: 280, height: 120)   // the open hint, read with the pointer on it
        #expect(HintsController.pick([a, b], open: ("a", paper), at: NSPoint(x: 440, y: 630)) == "a")
        #expect(HintsController.pick([a, b], open: ("a", paper), at: NSPoint(x: 440, y: 700)) == nil)
    }

    @Test func thePenSaysHint() {
        #expect(WandView.caption.contains("right-click to leave a hint"))
        #expect(WandController.noNotes.hasPrefix("No hints on this page yet"))
        #expect(WandController.notice(unplaced: 2)?.contains("2 more hints") == true)
        #expect(NotesBadge.summary([note("a")]).hasPrefix("1 hint here:"))
    }

    // MARK: - The team's hints

    @Test func theTeamsHintsAreReadOneFilePerHintAndShownOnTheirPage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hints-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let linked = root.appendingPathComponent("linked")
        let folder = linked.appendingPathComponent(TeamHints.folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let shared = note("t1", text: "From the team")
        let (name, json) = try TeamHints.file(for: shared)
        #expect(name == "t1.json")
        try json.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        try "{broken".write(to: folder.appendingPathComponent("bad.json"), atomically: true, encoding: .utf8)
        #expect(TeamHints.load(root: linked) == [shared])
        #expect(TeamHints.load(root: root).isEmpty)

        let registry = ToolRegistry(root: root.appendingPathComponent("tools"), runner: ScriptRunner(config: Config()))
        registry.linkedRoot = linked
        let store = NotesStore(directory: root.appendingPathComponent("notes"))
        registry.notesStore = store
        await registry.reload()
        #expect(registry.notes(for: scene()).map(\.id) == ["t1"])
        #expect(registry.notes(for: scene("https://elsewhere.example.test/")).isEmpty)
        #expect(registry.teamHas("t1"))
        #expect(!registry.teamHas("x"))
        // Your own copy of a team hint wins, once; a removed one stays gone.
        var mine = shared
        mine.text = "Edited here"
        try store.save(mine)
        #expect(registry.notes(for: scene()).map(\.text) == ["Edited here"])
        try store.remove("t1")
        #expect(registry.notes(for: scene()).isEmpty)
    }

    @Test func aTeamHintForPagesOfAKindIsMetOnEachOfThem() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hints-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let linked = root.appendingPathComponent("linked")
        let folder = linked.appendingPathComponent(TeamHints.folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var shared = note("t2", url: "https://www.walmart.com/ip/Great-Value-Whole-Milk/10450114", text: "The per-unit price counts the whole pack")
        shared.anchor.pattern = "www.walmart.com/ip/*/*"
        let (name, json) = try TeamHints.file(for: shared)
        // The pattern travels as text; an older Noteling, which knows nothing of it, reads the page alone.
        #expect(try JSONDecoder().decode(StickyNote.self, from: Data(json.utf8)).anchor.pattern == "www.walmart.com/ip/*/*")
        try json.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        let registry = ToolRegistry(root: root.appendingPathComponent("tools"), runner: ScriptRunner(config: Config()))
        registry.linkedRoot = linked
        registry.notesStore = NotesStore(directory: root.appendingPathComponent("notes"))
        await registry.reload()
        let bananas = scene("https://www.walmart.com/ip/Bananas-each/44390948?from=search")
        #expect(registry.notes(for: bananas).map(\.id) == ["t2"])
        #expect(registry.notes(for: scene("https://www.walmart.com/cart")).isEmpty)
        // Met as the person arrives there, from a read of the page alone.
        let hints = controller { _, notes in .init(marks: notes.map { .init(note: $0, frame: self.small) }) }
        hints.arrive(bananas, notes: registry.notes(for: bananas))
        await hints.settle()
        #expect(hints.marks.map(\.note.id) == ["t2"])
    }

    @Test func sharingOpensGitHubWithTheFileReadyToAdd() throws {
        let repo = try RepoAddress.parse("https://github.com/acme/tools")
        let hint = note("t1", text: "C++ builds & tests = slow; ask abc+ops@example.com")
        let url = try TeamHints.newFileURL(repo: repo, branch: "main", note: hint)
        #expect(url.host == "github.com")
        #expect(url.path == "/acme/tools/new/main")
        #expect(!url.absoluteString.contains("+"))   // a plus would reach GitHub as a space
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "filename" }?.value == "hints/t1.json")
        let value = try #require(items.first { $0.name == "value" }?.value)
        #expect(try JSONDecoder().decode(StickyNote.self, from: Data(value.utf8)) == hint)
        let edit = try TeamHints.editURL(repo: repo, branch: "main", note: hint)
        #expect(edit.absoluteString == "https://github.com/acme/tools/edit/main/hints/t1.json")
        let enterprise = try RepoAddress.parse("https://github.example.com/team/tools")
        let branch = try TeamHints.newFileURL(repo: enterprise, branch: "release/2", note: hint)
        #expect(branch.host == "github.example.com")
        #expect(branch.absoluteString.hasPrefix("https://github.example.com/team/tools/new/release/2?filename=hints%2Ft1.json&value="))
    }

    @Test func hintsAreOnUnlessTurnedOff() throws {
        #expect(Config().autoHints)
        #expect(try !JSONDecoder().decode(Config.self, from: Data(#"{"autoHints": false}"#.utf8)).autoHints)
        #expect(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).autoHints)   // an install from before the setting
    }
}
