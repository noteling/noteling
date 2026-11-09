import AppKit
import Foundation
import Testing
@testable import Familiar

/// A note's panel and the windows that keep one for every note: what its menu offers, what writing on it comes to, and
/// where a note sits. Panels are made but never put on the screen.
@Suite @MainActor struct MemoPanelTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func memo(_ id: String = "n-1", text: String = "Call Marco", when: Date? = nil, page: String? = nil) -> Memo {
        Memo(id: id, text: text, when: when, page: page, createdAt: at, updatedAt: at)
    }

    @Test func theMenuOffersThePageTheColoursFoldingTheSizeAndRemoval() {
        let plain = MemoPanel.menu(for: memo(), scale: 1)
        #expect(plain.map { $0?.title ?? "" } == ["Yellow", "Pink", "Blue", "Green", "", "Fold", "Bigger", "Smaller", "", "Remove"])
        #expect(plain.compactMap { $0 }.first { $0.checked }?.title == "Yellow")
        var folded = memo(page: "https://docs.example.com/q4")
        folded.collapsed = true
        folded.colour = .pink
        let items = MemoPanel.menu(for: folded, scale: PaperLook.steps.last!)
        #expect(items.map { $0?.title ?? "" } == ["Open page", "", "Yellow", "Pink", "Blue", "Green", "", "Unfold", "Bigger", "Smaller", "", "Remove"])
        #expect(items.compactMap { $0 }.filter(\.checked).map(\.title) == ["Pink"])
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

    @Test func choosingFromTheMenuChangesTheNote() {
        let panel = MemoPanel(memo: memo(page: "https://docs.example.com/q4"), scale: 1, hideFromScreenShare: false)
        var changes: [Memo] = [], opened: [String] = [], sizes: [CGFloat?] = [], removed = 0
        panel.onChange = { changes.append($0) }
        panel.onOpenPage = { opened.append($0) }
        panel.onResize = { sizes.append($0) }
        panel.onRemove = { removed += 1 }
        panel.choose(.colour(.blue))
        panel.choose(.collapse)
        panel.choose(.openPage)
        panel.choose(.bigger)
        panel.choose(.remove)
        #expect(changes.map(\.colour) == [.blue, .blue] && changes.map(\.collapsed) == [false, true])
        #expect(opened == ["https://docs.example.com/q4"] && sizes == [PaperLook.steps[2]] && removed == 1)   // bigger than 1 is 1.2
        #expect(panel.contextMenu().items.map(\.title).first == "Open page")
    }

    @Test func aNoteIsAnOrdinaryWindowThatComesUpWhenWokenOrWrittenOn() {
        // Up: on top of everything, wherever the person is, full-screen apps too.
        let up = MemoPanel.level(up: true)
        #expect(up.level == .floating && up.behaviour.contains(.canJoinAllSpaces) && up.behaviour.contains(.fullScreenAuxiliary))
        // Down: an ordinary window of its own Space, in Mission Control with the rest.
        let down = MemoPanel.level(up: false)
        #expect(down.level == .normal && down.behaviour.isEmpty)

        let panel = MemoPanel(memo: memo(), scale: 1, hideFromScreenShare: false)
        var changes: [Memo] = []
        panel.onChange = { changes.append($0) }
        // New: an ordinary window where it was made; nothing moves it but the person.
        #expect(!panel.up && panel.level == .normal && !panel.collectionBehavior.contains(.canJoinAllSpaces))
        // Woken: opened if it slept folded, up everywhere and glowing until clicked; then had, and an ordinary window again,
        // where the person is.
        var sleepy = memo(when: at.addingTimeInterval(7_200))
        sleepy.collapsed = true
        panel.show(sleepy)
        panel.wake()
        #expect(!panel.memo.collapsed && changes.last?.collapsed == false)
        #expect(panel.up && panel.state.warm && panel.collectionBehavior.contains(.canJoinAllSpaces))
        panel.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        #expect(!panel.up && !panel.state.warm && panel.level == .normal && changes.count == 1)   // being had changes nothing more in its file
        // Written on: up while the keyboard is on it, back in its place when the keyboard leaves.
        panel.raise()
        panel.state.beginEditing()
        panel.resignKey()
        #expect(!panel.up && !panel.state.editing && panel.level == .normal)
    }

    @Test func aNoteGoesBackUnderTheWindowThatWasInFrontOfIt() {
        // The window server lists windows front to back: a floating one, another app's window, one of our own notes, this
        // note, another app's window behind it. The one directly in front, of another app at the ordinary level, is 8.
        func window(_ id: Int, layer: Int, pid: Int32) -> [String: Any] {
            [kCGWindowNumber as String: NSNumber(value: id), kCGWindowLayer as String: NSNumber(value: layer), kCGWindowOwnerPID as String: NSNumber(value: pid)]
        }
        let list = [window(9, layer: 3, pid: 7), window(8, layer: 0, pid: 7), window(6, layer: 0, pid: 42), window(5, layer: 0, pid: 42), window(4, layer: 0, pid: 7)]
        #expect(MemoPanel.above(5, in: list, ownPID: 42) == 8)
        #expect(MemoPanel.above(8, in: list, ownPID: 42) == nil)   // nothing of another app in front of it
        #expect(MemoPanel.above(4, in: list, ownPID: 42) == 8)
        #expect(MemoPanel.above(99, in: list, ownPID: 42) == nil)   // not on the screen
        // A note never on the screen has nothing to go back under, and settling it is harmless.
        let panel = MemoPanel(memo: memo(), scale: 1, hideFromScreenShare: false)
        panel.raise()
        panel.settle()
        #expect(!panel.up && panel.level == .normal)
    }

    @Test func theWindowsTickOnTheMinuteAndANoteComesUpForAMomentWhenItsTimeComesNear() {
        let store = MemoStore(directory: nil)
        store.clock = { self.at }
        store.save(memo("n-old", text: "From yesterday"))
        store.save(memo("n-soon", text: "Stand-up", when: at.addingTimeInterval(50 * 60)))
        var asleep = memo("n-later", text: "Dentist", when: at.addingTimeInterval(3 * 3_600))
        asleep.collapsed = true   // a note for later sleeps folded
        store.save(asleep)
        let windows = MemoWindows(store: store, scale: 1, hideFromScreenShare: false)
        windows.shows = false
        windows.clock = { self.at }
        windows.start()
        // At launch, the note within the hour of its time comes up for a moment; the others are ordinary windows.
        #expect(windows.panels["n-soon"]!.up && !windows.panels["n-old"]!.up && !windows.panels["n-later"]!.up)
        #expect(windows.panels.values.allSatisfy { !$0.state.warm } && !windows.glancing)
        // Made within the hour of its time: in front as it is made, so no moment for it.
        let fresh = windows.newNote(memo("n-new", text: "Just made", when: at.addingTimeInterval(30 * 60)))
        windows.tick(now: at.addingTimeInterval(60))
        #expect(!windows.panels[fresh.id]!.up && windows.panels[fresh.id]!.headsUpGiven)

        let later = at.addingTimeInterval(2 * 3_600 + 10 * 60)
        windows.tick(now: later)
        #expect(windows.panels.values.allSatisfy { $0.state.now == later })
        #expect(windows.panels["n-later"]!.up && !windows.panels["n-old"]!.up)   // fifty minutes to go: its moment
        #expect(!windows.panels["n-later"]!.memo.collapsed && store.memo(id: "n-later")?.collapsed == false)   // and it opens
        // 10:13:20 ticks next at 10:14:00.3, in step with the menu bar's clock.
        let twenty = Date(timeIntervalSinceReferenceDate: 1_000 * 60 + 20)
        #expect(MemoWindows.nextMinute(after: twenty) == Date(timeIntervalSinceReferenceDate: 1_001 * 60 + 0.3))
    }

    @Test func aGlanceBringsEveryNoteUpAndEndsWithAnotherClickOrASwitchOfSpace() {
        let store = MemoStore(directory: nil)
        store.clock = { self.at }
        let windows = MemoWindows(store: store, scale: 1, hideFromScreenShare: false)
        windows.shows = false
        windows.clock = { self.at }
        windows.start()
        #expect(!windows.hasNotes)
        store.save(memo("n-1", text: "Call Marco"))
        store.save(memo("n-2", text: "Dentist"))
        windows.sync()
        #expect(windows.hasNotes && !windows.glancing)

        windows.showAll()
        #expect(windows.glancing)
        #expect(windows.panels.values.allSatisfy { $0.up && $0.level == .floating && $0.collectionBehavior.contains(.canJoinAllSpaces) })
        windows.endGlance()
        #expect(!windows.glancing && windows.panels.values.allSatisfy { !$0.up && $0.level == .normal })
        // Some of them, by id, as the chat shows them: the rest stay where they are.
        windows.show(ids: ["n-1"])
        #expect(windows.glancing && windows.panels["n-1"]!.up && !windows.panels["n-2"]!.up)
        windows.endGlance()
        // The orb's click: up, and back with the next click; a switch of Space ends it too.
        windows.toggleGlance()
        #expect(windows.glancing && windows.panels.values.allSatisfy(\.up))
        windows.toggleGlance()
        #expect(!windows.glancing && windows.panels.values.allSatisfy { !$0.up })
        windows.showAll()
        windows.spaceChanged()
        #expect(!windows.glancing && windows.panels.values.allSatisfy { !$0.up })
        // Hide my notes: off the screen until shown, by the menu, the orb, the chat or a new note; told to the config.
        var hiddenChanges: [Bool] = []
        windows.onHiddenChange = { hiddenChanges.append($0) }
        windows.showAll()
        windows.hide()
        #expect(windows.hidden && !windows.glancing && windows.panels.values.allSatisfy { !$0.up })
        windows.hide()   // twice says nothing more
        windows.show(ids: ["n-1"])
        #expect(!windows.hidden && windows.glancing && windows.panels["n-1"]!.up)
        windows.endGlance()
        windows.hide()
        windows.newNote(memo("n-3", text: "Fresh"))
        #expect(!windows.hidden && hiddenChanges == [true, false, true, false])
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
