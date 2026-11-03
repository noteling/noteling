import Foundation

/// The log: one file a day in `memory/`, append-only, readable only by this account. Code writes what happened: a job
/// ran, a finding is new, changed or gone, as the row the job reported it, with anything that looks like a secret hidden.
/// The minister writes its verdicts and reasons here too, later. `grep` over these files is how a question about
/// something old is answered.
final class MemoryLog {
    let directory: URL
    var timeZone = TimeZone.autoupdatingCurrent
    var clock: () -> Date = Date.init

    static let folder = "memory"

    init(directory: URL) { self.directory = directory }

    /// Where a job's lines say which job: `team/holiday/oct/gm`, `own/stuck-orders`.
    static func name(of job: FolderJob) -> String { (job.isTeam ? "team/" : "own/") + job.path }

    /// A job ran: what it checked, how many it read and found, and what it said.
    func ran(_ job: FolderJob, outcome: FindingsOutcome) {
        var line: [String: Any] = ["job": Self.name(of: job), "name": job.name]
        var ran: [String: Any] = [:]
        if let source = outcome.source { ran["source"] = source }
        if let read = outcome.read { ran["read"] = read }
        if let rows = outcome.rows { ran["found"] = rows.count }
        if let said = outcome.said { ran["said"] = said }
        line["ran"] = ran
        append(line)
    }

    /// What changed between a job's runs: each new or changed row, as reported, and each id that is gone.
    func record(_ job: FolderJob, change: FindingsChange) {
        let name = Self.name(of: job)
        for row in change.new { append(["job": name, "new": row.id, "row": Self.redact(row.values)]) }
        for changed in change.changed {
            append(["job": name, "changed": changed.row.id, "columns": changed.columns, "row": Self.redact(changed.row.values)])
        }
        for id in change.gone { append(["job": name, "gone": id]) }
    }

    /// Adds one line, with the time, to today's file. A line that can't be written is logged and lost; the log never
    /// stops a job.
    func append(_ fields: [String: Any]) {
        let now = clock()
        var line = fields
        line["t"] = Self.stamp(now, in: timeZone)
        do {
            let data = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys, .withoutEscapingSlashes])
            let file = file(for: now)
            let manager = FileManager.default
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if !manager.fileExists(atPath: file.path) {
                guard manager.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                    throw FolderJobError("Couldn't make \(file.lastPathComponent).")
                }
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data + Data("\n".utf8))
        } catch {
            Log.info("memory: couldn't write a line: \(error.localizedDescription)")
        }
    }

    /// The lines of one day, oldest first; a line that can't be read is skipped.
    func lines(on day: Date) -> [[String: Any]] {
        guard let text = try? String(contentsOf: file(for: day), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
    }

    /// `memory/2026-11-02.jsonl`, the day in this Mac's time.
    func file(for date: Date) -> URL { directory.appendingPathComponent(Self.day(date, in: timeZone) + ".jsonl") }

    static func day(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// "2026-11-02T09:02:11-05:00": the moment, with this Mac's offset, so a line reads right wherever it is read.
    static func stamp(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.string(from: date)
    }

    /// A row with anything that looks like a secret hidden: a column named like one, or a value that looks like a key, a
    /// token or a card number. Lists and objects inside a row are looked through the same way.
    static func redact(_ row: [String: Any]) -> [String: Any] {
        row.reduce(into: [:]) { out, pair in
            out[pair.key] = SecretWords.looksSecret(pair.key) ? hidden : redact(value: pair.value)
        }
    }

    static let hidden = "(hidden)"

    private static func redact(value: Any) -> Any {
        switch value {
        case let text as String: return PageWalk.looksLikeSecretValue(text) ? hidden : text
        case let object as [String: Any]: return redact(object)
        case let list as [Any]: return list.map { redact(value: $0) }
        default: return value
        }
    }
}
