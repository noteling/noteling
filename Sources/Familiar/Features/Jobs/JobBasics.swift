import CryptoKit
import Foundation

/// Where a job stands against its `starts` and `ends`: before its start, between them, or after its end. Before and
/// after, it is out of the way: it doesn't run, tell anyone or keep a card, and in Jobs it waits under Upcoming or Ended.
enum JobPhase: Equatable {
    case upcoming, live, ended
}

/// Whose a job is: yours, in `jobs/` in Noteling's folder, or your team's, in the linked tools' `jobs/`, which Noteling
/// only reads and runs once you turn it on.
enum JobSource: Hashable {
    case own, team
}

/// A moment as job.json gives it (`starts`, `ends`): ISO 8601, with an offset or in the Mac's own time, kept as written.
struct JobMoment: Equatable {
    var text: String
    var date: Date

    /// "2026-10-05T00:00:00-04:00", "2026-10-05T00:00:00Z", "2026-10-05T00:00" or "2026-10-05" (this Mac's time).
    static func parse(_ text: String) -> JobMoment? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let offset = trimmed.replacingOccurrences(of: #"([+-]\d{2})(\d{2})$"#, with: "$1:$2", options: .regularExpression)
            .replacingOccurrences(of: #"(T\d{2}:\d{2})(Z|[+-]\d{2}:\d{2})$"#, with: "$1:00$2", options: .regularExpression)
        if let date = try? CalendarSubmission.timestamp(offset) { return JobMoment(text: trimmed, date: date) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        let plain = trimmed.replacingOccurrences(of: #"\.\d+$"#, with: "", options: .regularExpression)
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: plain) { return JobMoment(text: trimmed, date: date) }
        }
        return nil
    }

    /// "Mon Oct 5, 12:00 AM", in this Mac's time.
    var words: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

/// Small words every job's page and card use: when something happened, a line cut to length, and a script's error in
/// plain words.
enum JobWords {
    /// "6:31 PM" today, "Oct 7, 2026 at 6:31 PM" on another day.
    static func time(_ date: Date, now: Date = Date()) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    /// "6:31 PM", in this Mac's time (or `timeZone`), whatever the day: a card's title says it this way.
    static func clock(_ date: Date, in timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    /// Plain words from a script's error: its first line, without the script's file name or the Python error type; nil
    /// when that leaves nothing.
    static func reason(_ error: String) -> String? {
        var line = error.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        line = line.replacingOccurrences(of: #"^[\w.-]+\.py failed: "#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^[A-Za-z_][\w.]*(Error|Exception): "#, with: "", options: .regularExpression)
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : clip(line, 200)
    }
}

/// How the jobs keep their own files: whole or not at all, and readable only by this account; and ids made from a name.
enum JobFiles {
    /// Writes the whole file under a hidden name beside it, readable only by this account, then moves it into place.
    static func write(_ text: String, to file: URL) throws {
        try write(Data(text.utf8), to: file)
    }

    static func write(_ data: Data, to file: URL) throws {
        let manager = FileManager.default
        let temporary = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent)-\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw FolderJobError("Couldn't write \(file.lastPathComponent) in \(file.deletingLastPathComponent().path).")
        }
        guard rename(temporary.path, file.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: file.path])
        }
    }

    static func modified(_ file: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    /// An id made from a name, the same on every Mac and every time. (Made as watches made theirs, so a job's id
    /// didn't change when watches went.)
    static func derivedID(_ name: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("noteling-watch-folder:\(name)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // a name-based UUID
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
