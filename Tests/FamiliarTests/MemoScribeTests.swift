import Foundation
import FamiliarRuntime
import Testing
@testable import Familiar

/// The scribe: a question that reads as a note puts the paper up at once with the person's words; the model's write
/// lands on that same paper; a turn that writes nothing takes it down; and what the model may put on a note is checked.
@Suite @MainActor struct MemoScribeTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func scribe() -> (MemoScribe, MemoStore) {
        let store = MemoStore(directory: nil)
        store.clock = { self.at }
        return (MemoScribe(store: store, windows: nil), store)
    }

    @Test func aQuestionReadsAsANoteByItsOpeningWords() {
        for yes in ["Remind me to send Lena the Q4 numbers this afternoon", "note to self: lease", "Note: call Marco", "write a note that says hi",
                    "remember to buy milk", "Don't let me forget the dentist", "jot down: eggs, milk", "Set a reminder for 3pm", "pin this"] {
            #expect(MemoScribe.looksLikeNote(yes), "\(yes)")
        }
        for no in ["What does the GM job do?", "", "   ", "a reminder is overdue in the orders job", "Explain this page", "how do I remember my password"] {
            #expect(!MemoScribe.looksLikeNote(no), "\(no)")
        }
    }

    @Test func thePaperGoesUpAtOnceAndTheModelWritesOntoIt() throws {
        let (scribe, store) = scribe()
        scribe.began("remind me to send Lena the Q4 numbers this afternoon", page: "https://docs.example.com/q4")
        let draft = try #require(scribe.draft)
        #expect(store.memo(id: draft)?.text == "remind me to send Lena the Q4 numbers this afternoon")
        #expect(store.memo(id: draft)?.asked == "remind me to send Lena the Q4 numbers this afternoon")

        let said = try scribe.write(["headline": "Lena · Q4 numbers", "words": "Send Lena the Q4 numbers before the call.",
                                     "when": "2026-09-21T15:00:00-04:00", "page": "here", "items": ["revenue sheet", "notes"], "colour": "blue"])
        #expect(said.hasPrefix("Pinned note \(draft): Lena · Q4 numbers"))
        #expect(scribe.draft == nil && store.all.count == 1)
        let memo = try #require(store.memo(id: draft))
        #expect(memo.headline == "Lena · Q4 numbers" && memo.text == "Send Lena the Q4 numbers before the call.")
        #expect(memo.when == Date(timeIntervalSince1970: 1_790_017_200) && memo.page == "https://docs.example.com/q4")
        #expect(memo.items.map(\.text) == ["revenue sheet", "notes"] && memo.colour == .blue)
        #expect(memo.asked == "remind me to send Lena the Q4 numbers this afternoon")
        scribe.turnEnded()
        #expect(store.all.count == 1)

        // A note the person asked for in other words: no draft, a new note.
        scribe.began("could you put something on my screen so I call Marco", page: nil)
        #expect(scribe.draft == nil)
        _ = try scribe.write(["words": "Call Marco"])
        let marco = store.all.first { $0.text == "Call Marco" }
        #expect(store.all.count == 2 && marco != nil && marco?.asked == nil)
    }

    @Test func aNoteForLaterSleepsFoldedUntilItsTimeComesNear() throws {
        let (scribe, store) = scribe()
        scribe.clock = { self.at }
        _ = try scribe.write(["headline": "Dentist", "words": "Thursday, the check-up.", "when": MemoFile.stamp(at.addingTimeInterval(3 * 3_600))])
        let later = try #require(store.all.first)
        #expect(later.collapsed && later.when == at.addingTimeInterval(3 * 3_600))
        _ = try scribe.write(["words": "Call Marco", "when": MemoFile.stamp(at.addingTimeInterval(30 * 60))])
        #expect(store.all.first { $0.text == "Call Marco" }?.collapsed == false)   // within the hour: open, as any note
        // A change leaves the fold as it is.
        _ = try scribe.change(["note": later.id, "words": "Thursday, the check-up at 2."])
        #expect(store.memo(id: later.id)?.collapsed == true)
    }

    @Test func aTurnThatWritesNothingTakesTheDraftDown() {
        let (scribe, store) = scribe()
        scribe.began("remind me what the GM job does", page: nil)
        #expect(store.all.count == 1)
        scribe.turnEnded()
        #expect(store.all.isEmpty && scribe.draft == nil)
        // A second question while a draft is up replaces it.
        scribe.began("remind me to call Marco", page: nil)
        scribe.began("remind me to call Lena", page: nil)
        #expect(store.all.map(\.text) == ["remind me to call Lena"])
    }

    @Test func whatTheModelPutsOnANoteIsChecked() throws {
        let (scribe, store) = scribe()
        #expect(throws: MinisterError.self) { try scribe.write([:]) }
        #expect(throws: MinisterError.self) { try scribe.write(["words": String(repeating: "x", count: 241)]) }
        #expect(throws: MinisterError.self) { try scribe.write(["words": "ok", "when": "this afternoon"]) }
        #expect(throws: MinisterError.self) { try scribe.write(["words": "ok", "page": "the blue folder"]) }
        #expect(throws: MinisterError.self) { try scribe.write(["words": "ok", "colour": "amber"]) }
        #expect(throws: MinisterError.self) { try scribe.write(["words": "ok", "items": Array(repeating: "x", count: 9)]) }
        #expect(store.all.isEmpty)
        _ = try scribe.write(["words": "ok", "headline": String(repeating: "h", count: 50), "when": NSNull(), "page": NSNull()])
        #expect(store.all.first?.headline?.count == 41 && store.all.first?.when == nil)   // clipped, with its ellipsis
        // "here" with no page on the screen is no page.
        scribe.began("hello", page: nil)
        _ = try scribe.write(["words": "nowhere", "page": "here"])
        #expect(store.all.first { $0.text == "nowhere" }?.page == nil)
    }

    @Test func aNoteCanBeChangedOrTakenAwayOnlyByName() throws {
        let (scribe, store) = scribe()
        _ = try scribe.write(["words": "Call Marco", "when": "2026-09-21T15:00:00-04:00"])
        let id = try #require(store.all.first?.id)
        #expect(throws: MinisterError.self) { try scribe.change(["note": "n-nothere"]) }
        #expect(try scribe.change(["note": id, "when": "2026-09-21T16:00:00-04:00", "headline": "Marco"]) == "Changed note \(id): Marco")
        #expect(store.memo(id: id)?.when == Date(timeIntervalSince1970: 1_790_020_800) && store.memo(id: id)?.text == "Call Marco")
        #expect(try scribe.change(["note": id, "remove": true]) == "Took note \(id) away.")
        #expect(store.all.isEmpty)
    }

    @Test func theChatGetsTwoToolsThatReachTheScribe() async throws {
        let (scribe, store) = scribe()
        let routes = scribe.routes()
        #expect(routes.compactMap { $0.definition["name"] as? String } == ["write_note", "change_note"])
        let router = try ToolRouter(routes: routes)
        let written = await router.execute("write_note", ["words": "Call Marco"])
        #expect(!written.isError && (written.content as? String)?.hasPrefix("Pinned note n-") == true)
        let id = try #require(store.all.first?.id)
        let changed = await router.execute("change_note", ["note": id, "colour": "green"])
        #expect(!changed.isError && store.memo(id: id)?.colour == .green)
        let refused = await router.execute("write_note", ["words": ""])
        #expect(refused.isError && refused.content as? String == "Give words: what the note says.")
    }
}
