import Foundation
import Testing
@testable import Familiar

/// Your notes as files: what is written is what is read back, a bare file is a note too, the store keeps the folder,
/// and the words for a when say what a person would.
@Suite @MainActor struct MemoTests {
    /// 2026-09-21, 10:13:20 AM in New York.
    private let at = Date(timeIntervalSince1970: 1_790_000_000)
    private var newYork: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    @Test func anEarlierVersionsPinLineIsReadPastAndNotKept() {
        let memo = MemoFile.parse("---\ntop: true\npinned: false\ncolour: pink\n---\nMilk", id: "n-2")   // 0.9.1's Keep on top, 0.9.2's pin
        #expect(memo.text == "Milk" && memo.colour == .pink)
        #expect(!MemoFile.text(memo).contains("pinned") && !MemoFile.text(memo).contains("top:"))
    }

    @Test func aNoteRoundTripsThroughItsFile() {
        var memo = Memo(id: "n-1", headline: "Lena · Q4 numbers", text: "Send Lena the Q4 numbers.\nBefore the call.",
                        items: [PaperItem(text: "revenue sheet"), PaperItem(text: "notes", done: true)], colour: .blue,
                        when: at.addingTimeInterval(3_600), page: "https://docs.example.com/q4", asked: "remind me to send Lena the Q4 numbers this afternoon",
                        matter: "m-abc12345", finding: "own/orders-stuck/4417", from: "Orders stuck · 4417", at: CGPoint(x: 412, y: 88.5), collapsed: true, createdAt: at, updatedAt: at.addingTimeInterval(60))
        let text = MemoFile.text(memo)
        #expect(text.hasPrefix("---\ncolour: blue\nwhen: "))
        #expect(text.contains("\n# Lena · Q4 numbers\nSend Lena the Q4 numbers.\nBefore the call.\n- [ ] revenue sheet\n- [x] notes\n"))
        #expect(text.contains("\nmatter: m-abc12345\nfinding: own/orders-stuck/4417\nfrom: Orders stuck · 4417\nat: 412,88.5\n") && text.contains("\ncollapsed: true\n"))
        let back = MemoFile.parse(text, id: "n-1")
        // Dates come back to the second.
        memo.updatedAt = Date(timeIntervalSince1970: memo.updatedAt.timeIntervalSince1970.rounded(.down))
        #expect(back == memo)
    }

    @Test func aBareFileIsANoteWithEverythingAtItsDefaults() {
        let memo = MemoFile.parse("Buy milk\n\n- [ ] eggs\n- [X] bread\n", id: "shopping", modified: at)
        #expect(memo.id == "shopping" && memo.headline == nil && memo.text == "Buy milk")
        #expect(memo.items == [PaperItem(text: "eggs"), PaperItem(text: "bread", done: true)])
        #expect(memo.colour == .yellow && memo.when == nil && memo.at == nil && !memo.collapsed)
        #expect(memo.createdAt == at && memo.updatedAt == at)
        #expect(memo.firstLine == "Buy milk")
        // A headline only counts first; "# " later on is words. A front matter never closed is words too.
        #expect(MemoFile.parse("Words\n# not a headline", id: "x").headline == nil)
        #expect(MemoFile.parse("---\ncolour: pink\nno end", id: "x").text == "---\ncolour: pink\nno end")
        #expect(MemoFile.parse("- [ ] only\n", id: "x").firstLine == "only")
        #expect(MemoFile.parse("", id: "x").isBlank)
    }

    @Test func theStoreKeepsTheFolderAndFinderIsTheFolderToo() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("memos-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MemoStore(directory: dir)
        store.trashes = false
        store.clock = { self.at }
        #expect(store.all.isEmpty)
        var memo = store.blank()
        memo.text = "Call Marco"
        store.save(memo)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(memo.id + ".md").path))
        #expect(store.all.map(\.text) == ["Call Marco"])

        // Written in Finder: picked up on reload, by its file's name.
        try "Dentist Thu 2pm\n".write(to: dir.appendingPathComponent("dentist.md"), atomically: true, encoding: .utf8)
        store.reload()
        #expect(store.all.map(\.id).contains("dentist"))
        #expect(store.memo(id: "dentist")?.text == "Dentist Thu 2pm")

        // Ticked here, written there.
        memo.items = [PaperItem(text: "lease")]
        store.save(memo)
        store.toggle(memo.id, item: 0)
        #expect(store.memo(id: memo.id)?.items.first?.done == true)
        #expect(try String(contentsOf: dir.appendingPathComponent(memo.id + ".md"), encoding: .utf8).contains("- [x] lease"))

        // Removed here, gone there; removed there, gone here.
        store.remove("dentist")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("dentist.md").path))
        try FileManager.default.removeItem(at: dir.appendingPathComponent(memo.id + ".md"))
        store.reload()
        #expect(store.all.isEmpty)
    }

    @Test func aWhenReadsAsAPersonWouldWriteIt() {
        let calendar = newYork
        let three = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: at)!
        #expect(PaperWhen.words(three, now: at, calendar: calendar) == "3:00 PM")
        #expect(PaperWhen.words(at.addingTimeInterval(25 * 60), now: at, calendar: calendar) == "in 25 min")
        #expect(PaperWhen.words(at.addingTimeInterval(59 * 60 + 30), now: at, calendar: calendar) == "in 60 min")
        #expect(PaperWhen.words(at.addingTimeInterval(30), now: at, calendar: calendar) == "now")
        #expect(PaperWhen.words(at.addingTimeInterval(-30), now: at, calendar: calendar) == "now")
        #expect(PaperWhen.words(at.addingTimeInterval(-3_600), now: at, calendar: calendar) == "was 9:13 AM")
        let thursday = calendar.date(byAdding: .day, value: 3, to: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: at)!)!
        #expect(PaperWhen.words(thursday, now: at, calendar: calendar) == "Thu 2:00 PM")   // the 21st is a Monday
        let later = calendar.date(byAdding: .day, value: 20, to: three)!
        #expect(PaperWhen.words(later, now: at, calendar: calendar) == "Oct 11, 3:00 PM")
        #expect(PaperWhen.state(three, now: at) == .later && PaperWhen.state(at.addingTimeInterval(-61), now: at) == .past)
    }

    @Test func aWakeComesWhenTheWhenDoesAndOpensACollapsedNote() {
        let store = MemoStore(directory: nil)
        var now = at
        store.clock = { now }
        var woken: [String] = []
        store.onWake = { woken.append($0.id) }
        var memo = store.blank()
        memo.text = "Stand-up"
        memo.when = at.addingTimeInterval(60)
        memo.collapsed = true
        store.save(memo)
        store.wakeDue()
        #expect(woken.isEmpty)
        now = at.addingTimeInterval(61)
        store.wakeDue()
        #expect(woken == [memo.id] && store.memo(id: memo.id)?.collapsed == false)
        // Long past: not woken again on a later check.
        now = at.addingTimeInterval(10_000)
        store.wakeDue()
        #expect(woken == [memo.id])
    }

    @Test func aSheetLeansTheSameWayEveryTimeAndAPageShowsAsItsHost() {
        #expect(PaperLook.tilt(for: "n-1") == PaperLook.tilt(for: "n-1"))
        #expect(abs(PaperLook.tilt(for: "n-1")) <= 0.7 && abs(PaperLook.tilt(for: "anything")) <= 0.7)
        #expect(PaperView.host(of: "https://www.docs.example.com/finance/q4") == "docs.example.com")
        #expect(PaperView.host(of: "the blue folder") == "the blue folder")
        #expect(PaperView.host(of: "  ") == nil)
    }
}
