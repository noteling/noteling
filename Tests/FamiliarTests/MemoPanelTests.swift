import AppKit
import Foundation
import Testing
@testable import Familiar

/// A note's panel and the windows that keep one for every note: what its menu offers, what writing on it comes to, and
/// where a new note goes. Panels are made but never put on the screen.
@Suite @MainActor struct MemoPanelTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func memo(_ id: String = "n-1", text: String = "Call Marco", page: String? = nil) -> Memo {
        Memo(id: id, text: text, page: page, createdAt: at, updatedAt: at)
    }

    @Test func theMenuOffersThePageTheColoursFoldingTheLevelTheSizeAndRemoval() {
        let plain = MemoPanel.menu(for: memo(), scale: 1)
        #expect(plain.map { $0?.title ?? "" } == ["Yellow", "Pink", "Blue", "Green", "", "Fold", "Pinned", "Bigger", "Smaller", "", "Remove"])
        #expect(plain.compactMap { $0 }.first { $0.checked }?.title == "Yellow")
        var folded = memo(page: "https://docs.example.com/q4")
        folded.collapsed = true
        folded.pinned = true
        folded.colour = .pink
        let items = MemoPanel.menu(for: folded, scale: PaperLook.steps.last!)
        #expect(items.map { $0?.title ?? "" } == ["Open page", "", "Yellow", "Pink", "Blue", "Green", "", "Unfold", "Pinned", "Bigger", "Smaller", "", "Remove"])
        #expect(items.compactMap { $0 }.filter(\.checked).map(\.title) == ["Pink", "Pinned"])
        #expect(items.compactMap { $0 }.first { $0.title == "Bigger" }?.enabled == false)
        #expect(items.compactMap { $0 }.first { $0.title == "Smaller" }?.enabled == true)
    }

    @Test func writingOnTheNoteBecomesItsHeadlineWordsAndChecklist() {
        let panel = MemoPanel(memo: memo(), scale: 1, hideFromScreenShare: false)
        var changes: [Memo] = []
        panel.onChange = { changes.append($0) }
        panel.state.beginEditing()
        #expect(panel.state.editing && panel.state.headline == "" && panel.state.words == "Call Marco")
        panel.state.headline = " Marco "
        panel.state.words = "Call Marco back\n\n- [ ] the lease\n- [x] the term"
        panel.endEditing()
        #expect(!panel.state.editing)
        #expect(changes.count == 1)
        #expect(changes.first?.headline == "Marco" && changes.first?.text == "Call Marco back")
        #expect(changes.first?.items == [PaperItem(text: "the lease"), PaperItem(text: "the term", done: true)])
        #expect(MemoPanelState.wordsToEdit(changes[0]) == "Call Marco back\n- [ ] the lease\n- [x] the term")
        // Nothing changed: nothing said.
        panel.state.beginEditing()
        panel.endEditing()
        #expect(changes.count == 1)
    }

    @Test func choosingFromTheMenuChangesTheNoteAndItsLevel() {
        let panel = MemoPanel(memo: memo(page: "https://docs.example.com/q4"), scale: 1, hideFromScreenShare: false)
        var changes: [Memo] = [], opened: [String] = [], sizes: [CGFloat?] = [], removed = 0
        panel.onChange = { changes.append($0) }
        panel.onOpenPage = { opened.append($0) }
        panel.onResize = { sizes.append($0) }
        panel.onRemove = { removed += 1 }
        // New: pinned, above the windows of its own Space, not every Space.
        #expect(panel.level == .floating && !panel.collectionBehavior.contains(.canJoinAllSpaces))
        panel.choose(.colour(.blue))
        panel.choose(.collapse)
        panel.choose(.pin)
        panel.choose(.openPage)
        panel.choose(.bigger)
        panel.choose(.remove)
        #expect(changes.map(\.colour) == [.blue, .blue, .blue])
        #expect(changes.map(\.collapsed) == [false, true, true] && changes.last?.pinned == false)
        // Unpinned: on the desktop, the same on every Space.
        #expect(panel.level == MemoPanel.desktopLevel && panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(opened == ["https://docs.example.com/q4"] && sizes == [PaperLook.steps[2]] && removed == 1)   // bigger than 1 is 1.2
        #expect(panel.contextMenu().items.map(\.title).first == "Open page")
    }

    @Test func aNoteIsPinnedOverItsSpaceOrLiesOnTheDesktopAndComesUpWhenWokenOrWrittenOn() {
        // Up: on top of everything, wherever the person is, full-screen apps too.
        let up = MemoPanel.level(pinned: false, up: true)
        #expect(up.level == .floating && up.behaviour.contains(.canJoinAllSpaces) && up.behaviour.contains(.fullScreenAuxiliary))
        // Pinned: above the windows of its own Space only.
        let pinned = MemoPanel.level(pinned: true, up: false)
        #expect(pinned.level == .floating && !pinned.behaviour.contains(.canJoinAllSpaces))
        // On the desktop: under every window, the same on every Space; never over a full-screen app.
        let desk = MemoPanel.level(pinned: false, up: false)
        #expect(desk.level == MemoPanel.desktopLevel && desk.behaviour.contains(.canJoinAllSpaces) && !desk.behaviour.contains(.fullScreenAuxiliary))

        let panel = MemoPanel(memo: memo(), scale: 1, hideFromScreenShare: false)
        var changes: [Memo] = []
        panel.onChange = { changes.append($0) }
        // New: pinned where it was made, and it stays; no clock takes it down.
        #expect(!panel.up && panel.memo.pinned && panel.level == .floating && !panel.collectionBehavior.contains(.canJoinAllSpaces))
        panel.pin(false)
        #expect(panel.level == MemoPanel.desktopLevel && changes.last?.pinned == false)
        panel.pin(false)
        #expect(changes.count == 1)   // already lying there: nothing said
        // Woken: up everywhere and glowing until clicked; then had, and pinned where the person is.
        panel.wake()
        #expect(panel.up && panel.state.warm && panel.collectionBehavior.contains(.canJoinAllSpaces))
        panel.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        #expect(!panel.up && !panel.state.warm && panel.memo.pinned && changes.last?.pinned == true)
        #expect(panel.level == .floating && !panel.collectionBehavior.contains(.canJoinAllSpaces))
        // Written on: up while the keyboard is on it, back in its place when the keyboard leaves.
        panel.pin(false)
        panel.raise()
        panel.state.beginEditing()
        panel.resignKey()
        #expect(!panel.up && !panel.state.editing && panel.level == MemoPanel.desktopLevel)
    }

    @Test func theWindowsTickOnTheMinuteAndANewNoteIsPinnedWithNoClockOnIt() {
        let store = MemoStore(directory: nil)
        store.clock = { self.at }
        store.save(memo("n-old", text: "From yesterday"))
        let windows = MemoWindows(store: store, scale: 1, hideFromScreenShare: false)
        windows.shows = false
        windows.start()
        let fresh = windows.newNote(memo("n-new", text: "Just pinned"))
        #expect(windows.panels.values.allSatisfy { !$0.up && $0.memo.pinned && $0.level == .floating })
        #expect(windows.panels[fresh.id]?.collectionBehavior.contains(.canJoinAllSpaces) == false)

        let later = at.addingTimeInterval(600)
        windows.tick(now: later)
        #expect(windows.panels.values.allSatisfy { $0.state.now == later })
        // 10:13:20 ticks next at 10:14:00.3, in step with the menu bar's clock.
        let twenty = Date(timeIntervalSinceReferenceDate: 1_000 * 60 + 20)
        #expect(MemoWindows.nextMinute(after: twenty) == Date(timeIntervalSinceReferenceDate: 1_001 * 60 + 0.3))
    }

    @Test func aGlanceBringsEveryNoteUpUntilAClickElsewhereAndAPinMeanwhileHolds() {
        let store = MemoStore(directory: nil)
        store.clock = { self.at }
        let windows = MemoWindows(store: store, scale: 1, hideFromScreenShare: false)
        windows.shows = false
        windows.start()
        #expect(!windows.hasNotes && !windows.hasPinned)
        store.save(memo("n-1", text: "Call Marco"))
        store.save(memo("n-2", text: "Dentist"))
        windows.sync()
        windows.panels["n-2"]!.pin(false)
        #expect(windows.hasNotes && windows.hasPinned)

        windows.showAll()
        #expect(windows.glancing)
        #expect(windows.panels.values.allSatisfy { $0.up && $0.level == .floating && $0.collectionBehavior.contains(.canJoinAllSpaces) })
        windows.panels["n-2"]!.pin(true)   // pinned while up: it holds
        windows.endGlance()
        #expect(!windows.glancing)
        #expect(windows.panels.values.allSatisfy { !$0.up && $0.memo.pinned && $0.level == .floating && !$0.collectionBehavior.contains(.canJoinAllSpaces) })

        windows.unpinAll()
        #expect(!windows.hasPinned && windows.panels.values.allSatisfy { $0.level == MemoPanel.desktopLevel })
        // A note that woke is passed by: it stays up and glowing until it is had.
        windows.panels["n-1"]!.wake()
        windows.showAll()
        windows.endGlance()
        #expect(windows.panels["n-1"]!.up && windows.panels["n-1"]!.state.warm && windows.panels["n-2"]!.up == false)
    }

    @Test func theWindowsKeepAPanelForEveryNoteAndPlaceANewOneAboveTheOrb() {
        let store = MemoStore(directory: nil)
        store.clock = { self.at }
        let windows = MemoWindows(store: store, scale: 1, hideFromScreenShare: false)
        windows.shows = false
        windows.orbFrame = { NSRect(x: 1_000, y: 100, width: 84, height: 84) }
        windows.start()
        #expect(windows.panels.isEmpty)

        let first = windows.newNote()
        #expect(windows.panels.keys.contains(first.id))
        #expect(store.memo(id: first.id)?.at == NSPoint(x: 1_042 - PaperLook.memoWidth / 2, y: 184 + 12 + PaperLook.minHeight))
        // The next one goes a little further along, not on top of the first.
        let second = windows.newNote()
        let a = try! #require(store.memo(id: first.id)?.at), b = try! #require(store.memo(id: second.id)?.at)
        #expect(b.x == a.x + 22 && b.y == a.y - 22)

        // Gone from the store, gone from the screen; changed in the store, changed on the panel.
        store.remove(second.id)
        windows.sync()
        #expect(windows.panels.count == 1)
        var changed = try! #require(store.memo(id: first.id))
        changed.text = "Written in Finder"
        store.save(changed)
        windows.sync()
        #expect(windows.panels[first.id]?.memo.text == "Written in Finder")

        // Bigger steps every panel and tells the app.
        var remembered: [CGFloat] = []
        windows.onScaleChange = { remembered.append($0) }
        windows.setScale(PaperLook.bigger(than: 1))
        #expect(windows.panels[first.id]?.state.scale == 1.2 && remembered == [1.2])
    }
}
