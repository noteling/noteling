import Foundation
import Testing
@testable import Familiar

/// The notes a job's rows make: one per row the job marks as a note, with no minister; it follows the row while its
/// parts are the keeper's, keeps the person's words, and peels when the row goes or is no longer marked.
@Suite @MainActor struct JobNotesTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func job(note: String? = "sticky") -> FolderJob {
        var map: [String: Any] = ["id": "order_id", "about": ["customer", "owner"], "where": "https://orders.example.com/order/{order_id}", "due": "due_by"]
        if let note { map["note"] = note }
        var job = FolderJob(id: UUID(), source: .own, path: "orders-stuck", name: "Orders stuck")
        job.map = try! FindingsMap.parse(map)
        return job
    }

    private func row(_ id: String, _ customer: String, sticky: Any = "yes", due: String = "2026-11-08T09:12:00-05:00") -> FindingRow {
        FindingRow(id: id, values: ["order_id": id, "customer": customer, "owner": "Yang", "due_by": due, "sticky": sticky],
                   columns: ["order_id", "customer", "owner", "due_by", "sticky"])
    }

    @Test func aColumnMarksARowAsANote() throws {
        let map = try FindingsMap.parse(["id": "order_id", "note": "sticky"])
        #expect(map.note == "sticky" && FindingsMap.known.contains("note"))
        for value in ["yes", "true", "1", "x", "Due"] { #expect(map.isNote(row("1", "Acme", sticky: value))) }
        for value in ["", "false", "no", "0", "FALSE", " "] { #expect(!map.isNote(row("1", "Acme", sticky: value))) }
        #expect(!(try FindingsMap.parse(["id": "order_id"])).isNote(row("1", "Acme")))
        // What the keeper writes: what, else the first about value, else the job and the id; the rest are the words.
        let plain = JobNotes.written(job(), job().map!, row("4417", "Acme Industrial"))
        #expect(plain.headline == "Acme Industrial" && plain.text == "Yang" && plain.page == "https://orders.example.com/order/4417")
        #expect(plain.when == JobMoment.parse("2026-11-08T09:12:00-05:00")?.date && plain.from == "Orders stuck · 4417")
        var bare = job()
        bare.map = try FindingsMap.parse(["id": "order_id", "note": "sticky"])
        #expect(JobNotes.written(bare, bare.map!, row("4417", "Acme Industrial")).headline == "Orders stuck 4417")
        // The job's page says so, and the summary counts them.
        #expect(FindingVerdicts.words(.noted) == "On your note" && FindingVerdicts.symbol(.noted) == "hand.raised")
        let lines = [FindingVerdicts.Line(id: "1", label: "Acme", verdict: .noted), FindingVerdicts.Line(id: "2", label: "Blue", verdict: .quiet("Small."))]
        #expect(FindingVerdicts.summary(lines) == "2 findings: 1 on your note, 1 kept quiet")
    }

    @Test func aMarkedRowBecomesANoteThatFollowsTheRowAndKeepsThePersonsWords() throws {
        let store = MemoStore(directory: nil)
        store.clock = { self.at }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("job-notes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = MemoryLog(directory: dir)
        log.clock = { self.at }
        let notes = JobNotes(store: store, memory: log)
        notes.spot = { CGPoint(x: 100, y: 500) }
        let job = job()

        // Two rows, one marked: one note, near the orb, with the finding in its file.
        notes.notice(job, change: FindingsChange(new: [row("4417", "Acme Industrial"), row("4421", "Blue Harbor Café", sticky: "no")]))
        let made = try #require(store.all.first)
        #expect(store.all.count == 1 && made.finding == "own/orders-stuck/4417" && made.from == "Orders stuck · 4417")
        #expect(made.headline == "Acme Industrial" && made.text == "Yang" && made.page == "https://orders.example.com/order/4417")
        #expect(made.when == JobMoment.parse("2026-11-08T09:12:00-05:00")?.date && made.at == CGPoint(x: 100, y: 500))
        #expect(log.lines(on: at).compactMap { $0["made"] as? String } == ["Acme Industrial"])
        // The same row again is not a second note.
        notes.notice(job, change: FindingsChange(new: [row("4417", "Acme Industrial")]))
        #expect(store.all.count == 1)

        // The row changes: the keeper's parts follow it.
        var change = FindingsChange()
        change.changed = [FindingsChange.Changed(row: row("4417", "Acme Industrial Ltd", due: "2026-11-09T09:12:00-05:00"),
                                                 before: row("4417", "Acme Industrial"), columns: ["customer", "due_by"])]
        notes.notice(job, change: change)
        let followed = try #require(store.memo(id: made.id))
        #expect(followed.headline == "Acme Industrial Ltd" && followed.when == JobMoment.parse("2026-11-09T09:12:00-05:00")?.date)
        #expect(log.lines(on: at).compactMap { $0["changed"] as? String } == ["Acme Industrial Ltd"])

        // The person wrote on it: their headline stays; the time still follows.
        var theirs = followed
        theirs.headline = "Chase Acme"
        store.save(theirs)
        change.changed = [FindingsChange.Changed(row: row("4417", "Acme Holdings", due: "2026-11-10T09:12:00-05:00"),
                                                 before: row("4417", "Acme Industrial Ltd", due: "2026-11-09T09:12:00-05:00"), columns: ["customer", "due_by"])]
        notes.notice(job, change: change)
        let kept = try #require(store.memo(id: made.id))
        #expect(kept.headline == "Chase Acme" && kept.when == JobMoment.parse("2026-11-10T09:12:00-05:00")?.date)

        // A row marked later becomes a note; one no longer marked, or gone, peels its note.
        change = FindingsChange()
        change.changed = [FindingsChange.Changed(row: row("4421", "Blue Harbor Café"), before: row("4421", "Blue Harbor Café", sticky: "no"), columns: ["sticky"]),
                          FindingsChange.Changed(row: row("4417", "Acme Holdings", sticky: "no"), before: row("4417", "Acme Holdings"), columns: ["sticky"])]
        notes.notice(job, change: change)
        #expect(store.all.map(\.finding) == ["own/orders-stuck/4421"])
        change = FindingsChange()
        change.gone = ["4421"]
        notes.notice(job, change: change)
        #expect(store.all.isEmpty)
        #expect(log.lines(on: at).compactMap { $0["peeled"] as? String } == ["the job no longer marks it as a note", "its finding is gone"])

        // Nothing without the role.
        notes.notice(self.job(note: nil), change: FindingsChange(new: [row("4428", "Northwind")]))
        #expect(store.all.isEmpty)
    }
}
