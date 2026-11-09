import Foundation
import Testing
@testable import Familiar

/// The chat's map of the shared state: what Noteling holds right now, built from the files, with where the rest is read.
@Suite @MainActor struct HoldingsTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func theDigestListsNotesCardsScansAndWhatTheMinisterWasToldFromTheFiles() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("holdings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        // Nothing yet: the digest says so, and the day is empty.
        let empty = Holdings.digest(home: home, now: at)
        #expect(empty.contains("## What Noteling holds right now") && empty.contains("Their notes: none.\n") && empty.hasSuffix("Today: Nothing came through the deck today.\n"))
        #expect(!empty.contains("The deck") && !empty.contains("Scans the chat did"))

        // A note with a time and a checklist; a card with a next step; a scan with its rows; a rule told.
        let store = MemoStore(directory: home.appendingPathComponent(MemoStore.folder))
        store.clock = { self.at }
        var standup = Memo(id: "n-1", headline: "Stand-up", when: at.addingTimeInterval(50 * 60), createdAt: at, updatedAt: at)
        standup.items = [PaperItem(text: "bug 12"), PaperItem(text: "bug 15", done: true)]
        store.save(standup)
        let matters = Matters(directory: home.appendingPathComponent(Matters.folder))
        matters.clock = { self.at }
        var lena = Matter(id: "m-1", findings: [FindingRef(job: "chat/inbox", id: "M-1")], state: .open,
                          view: MatterView(headline: "Lena wants the deck by 3", text: "Nothing has gone back to her.", next: "Reply to Lena", tone: .calm),
                          jobName: "Inbox", byline: nil, createdAt: at, updatedAt: at)
        lena.writtenAt = at
        matters.save(lena)
        let scan = home.appendingPathComponent("job-results").appendingPathComponent("chat").appendingPathComponent("calendar")
        let map = try FindingsMap.parse(["id": "link", "what": "title", "due": "start"])
        try ChatSource(slug: "calendar", name: "Calendar", about: "Each row is a meeting on the person's calendar today.", map: map, raw: ["id": "link"]).write(to: scan)
        var state = FolderJobState()
        state.lastRunAt = at.addingTimeInterval(-600)
        state.found = 4
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: scan, withIntermediateDirectories: true)
        try encoder.encode(state).write(to: scan.appendingPathComponent(FolderJobFiles.state))
        let lessons = Lessons(file: home.appendingPathComponent(Matters.folder).appendingPathComponent(Lessons.fileName))
        lessons.clock = { self.at }
        try lessons.tell("For all meetings, make the link the thing to open")

        let digest = Holdings.digest(home: home, now: at)
        #expect(digest.contains("Their notes (the notes root, one markdown file each; read one for its words):\n- n-1: Stand-up · in 50 min · 1 of 2 to tick\n"))
        #expect(digest.contains("The deck (the minister's cards; matters/<id>/matter.json and notes.md):\n- m-1: Lena wants the deck by 3 · next: Reply to Lena\n"))
        #expect(digest.contains("Scans the chat did for them (read the rows with rows on the file named):\n- Calendar: 4 rows, scanned "))   // the clock's words depend on the time zone
        #expect(digest.contains(" · results/chat/calendar/output/findings.csv · Each row is a meeting on the person's calendar today.\n"))
        #expect(digest.contains("Told to the minister, in their words:\n- For all meetings, make the link the thing to open\n"))
        // The chat's standing prompt names the roots and the rule.
        #expect(Prompt.system.contains("notes (the person's own notes") && Prompt.system.contains("results/chat/<source>/output/findings.csv"))
        #expect(Prompt.system.contains("never answer that you have no data before looking"))
    }
}
