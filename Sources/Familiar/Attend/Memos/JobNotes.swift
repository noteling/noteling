import CoreGraphics
import Foundation

/// The notes a job's rows make: one of the person's own notes for every row the job marks as a note (`map.note`), with
/// no minister and no Mine. The note is made when the row first appears, its parts follow the row while they are still
/// as the keeper wrote them, and it peels to the Trash when the row is gone or no longer marked. What the person wrote
/// on it is theirs: a part they changed keeps their words.
@MainActor
final class JobNotes {
    let store: MemoStore
    var memory: MemoryLog?
    /// Where a new note goes; nil leaves it to the windows, which place it near the orb.
    var spot: () -> CGPoint? = { nil }

    static let headlineLimit = 60

    init(store: MemoStore, memory: MemoryLog? = nil) {
        self.store = store
        self.memory = memory
    }

    /// What the keeper writes from a row: the headline from `what`, else the first `about` value, else the job's name
    /// and the id; the words from the other `about` values; the page from `where`; the time from `due`; and where it
    /// came from, for the paper's last line.
    struct Written: Equatable {
        var headline: String
        var text: String
        var page: String?
        var when: Date?
        var from: String
    }

    static func written(_ job: FolderJob, _ map: FindingsMap, _ row: FindingRow) -> Written {
        let about = map.about(of: row).map { $0.split(whereSeparator: \.isNewline).joined(separator: " ") }
        let what = map.what.flatMap { row.text($0) }?.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces) ?? ""
        var headline = what, rest = about
        if headline.isEmpty, let first = about.first { headline = first; rest = Array(about.dropFirst()) }
        if headline.isEmpty { headline = "\(job.name) \(row.id)" }
        let when = map.due.flatMap { row.text($0) }.flatMap { JobMoment.parse($0)?.date }
        return Written(headline: JobWords.clip(headline, headlineLimit), text: rest.joined(separator: " · "), page: map.place(of: row), when: when,
                       from: "\(job.name) · \(row.id)")
    }

    /// A run reported findings: the rows marked as notes make, change or take down notes.
    func notice(_ job: FolderJob, change: FindingsChange) {
        guard let map = job.map, map.note != nil else { return }
        let name = MemoryLog.name(of: job)
        func existing(_ id: String) -> Memo? { store.all.first { $0.finding == FindingRef(job: name, id: id).key } }
        for row in change.new where map.isNote(row) && existing(row.id) == nil { make(job, map, row) }
        for changed in change.changed {
            switch (map.isNote(changed.row), existing(changed.row.id)) {
            case (true, nil): make(job, map, changed.row)   // marked a note now
            case (true, let memo?): follow(memo, job, map, from: changed.before, to: changed.row)
            case (false, let memo?): peel(memo, job, why: "the job no longer marks it as a note")
            case (false, nil): break
            }
        }
        for id in change.gone {
            if let memo = existing(id) { peel(memo, job, why: "its finding is gone") }
        }
    }

    private func make(_ job: FolderJob, _ map: FindingsMap, _ row: FindingRow) {
        let written = Self.written(job, map, row)
        var memo = store.blank()
        memo.headline = written.headline
        memo.text = written.text
        memo.page = written.page
        memo.when = written.when
        memo.from = written.from
        memo.finding = FindingRef(job: job, id: row.id).key
        memo.at = spot()
        store.save(memo)
        memory?.append(["job": MemoryLog.name(of: job), "finding": row.id, "note": memo.id, "made": written.headline])
    }

    /// The row changed: each part of the note still as the keeper wrote it follows the row; a part the person changed
    /// is theirs and stays.
    private func follow(_ memo: Memo, _ job: FolderJob, _ map: FindingsMap, from before: FindingRow, to row: FindingRow) {
        let was = Self.written(job, map, before), now = Self.written(job, map, row)
        guard was != now else { return }
        var kept = memo
        if (kept.headline ?? "") == was.headline { kept.headline = now.headline }
        if kept.text == was.text { kept.text = now.text }
        if kept.page == was.page { kept.page = now.page }
        if kept.when == was.when { kept.when = now.when }
        kept.from = now.from
        guard kept != memo else { return }
        store.save(kept)
        memory?.append(["job": MemoryLog.name(of: job), "finding": row.id, "note": memo.id, "changed": kept.firstLine])
    }

    private func peel(_ memo: Memo, _ job: FolderJob, why: String) {
        store.remove(memo.id)
        memory?.append(["job": MemoryLog.name(of: job), "note": memo.id, "peeled": why])
    }
}
