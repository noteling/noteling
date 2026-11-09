import AppKit
import Foundation
import Testing
@testable import Familiar

/// Hints shown by themselves: placed from a read of the page as it comes up, kept with the page, gone with it; the
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
        hints.arrive(scene(), notes: [note("a")])
        await hints.settle()
        #expect(hints.marks.isEmpty)
        try? await Task.sleep(for: .milliseconds(1400))   // the first look again comes after a second
        await hints.settle()
        #expect(hints.marks.count == 1)
        #expect(reads == 2)
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
