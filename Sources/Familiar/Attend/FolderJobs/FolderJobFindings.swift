import Foundation

/// What a job reports: its findings, as rows of its own columns, and a map in `job.json` saying which column is which to
/// Noteling. The developer writes no prose per finding; the map links their table to the roles the system needs. A run
/// reports everything that is true now, and Noteling tells new, changed and gone apart by the `id` column.
struct FindingsMap: Equatable {
    /// The column that makes a row the same row next run.
    var id: String
    /// Columns naming who and what a row concerns: a customer, an order, an owner. Data, never routing.
    var about: [String] = []
    /// A column, or an address with `{column}` in it: the page a row lives on (`where` in job.json).
    var page: String?
    /// Columns: true since when, matters until, happened at. With `at`, rows are events: not re-asserted, never gone.
    var since: String?
    var due: String?
    var at: String?
    /// A column holding a ready sentence, for jobs whose rows don't share a shape.
    var what: String?
    /// A column naming files in the job's output.
    var files: String?

    var isEvents: Bool { at != nil }

    static let known: Set<String> = ["id", "about", "where", "since", "due", "at", "what", "files"]
    static let columnLimit = 100

    /// Reads `map` as job.json has it, saying what is wrong in plain words.
    static func parse(_ raw: Any) throws -> FindingsMap {
        guard let object = raw as? [String: Any] else {
            throw FolderJobError("In its job.json, map must be an object saying which column is which: {\"id\": \"order_id\", …}.")
        }
        func column(_ key: String) throws -> String? {
            guard let raw = object[key], !(raw is NSNull) else { return nil }
            guard let text = raw as? String else { throw FolderJobError("In its job.json, map's \(key) must be a column name in quotes.") }
            let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= columnLimit else { throw FolderJobError("In its job.json, map's \(key) must be a column name in quotes.") }
            return name
        }
        guard let id = try column("id") else {
            throw FolderJobError("In its job.json, map needs id: the column that makes a row the same row next run, such as {\"id\": \"order_id\"}.")
        }
        var about: [String] = []
        if let raw = object["about"], !(raw is NSNull) {
            guard let list = raw as? [Any], list.allSatisfy({ $0 is String }) else {
                throw FolderJobError("In its job.json, map's about must be a list of column names in quotes.")
            }
            var seen = Set<String>()
            about = list.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count <= columnLimit && seen.insert($0).inserted }
        }
        var place: String?
        if let raw = object["where"], !(raw is NSNull) {
            guard let text = raw as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty, text.count <= 2_000 else {
                throw FolderJobError("In its job.json, map's where must be a column name, or an address with {column} in it, in quotes.")
            }
            place = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return FindingsMap(id: id, about: about, page: place, since: try column("since"), due: try column("due"), at: try column("at"),
                           what: try column("what"), files: try column("files"))
    }

    // MARK: a row's roles

    /// The page a row lives on: the column's text, or the template filled in; nil when a column it names is missing.
    func place(of row: FindingRow) -> String? {
        guard let place = page else { return nil }
        if place.contains("{") { return FolderJobFindings.fill(place, row: row) }
        guard let text = row.text(place), !text.isEmpty else { return nil }
        return text
    }

    /// Who and what a row concerns, as its `about` columns have it, empty values left out.
    func about(of row: FindingRow) -> [String] {
        about.compactMap { row.text($0) }.filter { !$0.isEmpty }
    }
}

/// A button on a job's findings: a function of its own job.py, with arguments templated from a row's columns.
struct FolderJobAction: Equatable, Identifiable {
    var label: String
    var run: String
    /// One JSON object, as job.json has it; `{column}` in its strings is filled from the row when pressed.
    var args: [String: Any] = [:]
    var confirm = false

    var id: String { run + "|" + label }

    static func == (a: FolderJobAction, b: FolderJobAction) -> Bool {
        a.label == b.label && a.run == b.run && a.confirm == b.confirm && JSONText.pretty(a.args, indent: "") == JSONText.pretty(b.args, indent: "")
    }

    static let limit = 6
    static let labelLimit = 40
    static let argsLimit = 4_000

    /// Reads `actions` as job.json has it: up to six buttons, each a label and a function of job.py.
    static func parse(_ raw: Any) throws -> [FolderJobAction] {
        guard let list = raw as? [Any] else {
            throw FolderJobError("In its job.json, actions must be a list of buttons: [{\"label\": \"Nudge the warehouse\", \"run\": \"nudge\"}].")
        }
        guard list.count <= limit else { throw FolderJobError("In its job.json, up to \(limit) actions are shown. Keep the ones that matter.") }
        return try list.map { item in
            guard let object = item as? [String: Any] else {
                throw FolderJobError("In its job.json, each action must be an object: {\"label\": \"Nudge the warehouse\", \"run\": \"nudge\"}.")
            }
            guard let label = (object["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty, label.count <= labelLimit else {
                throw FolderJobError("In its job.json, an action needs a label in quotes, up to \(labelLimit) characters.")
            }
            guard let name = object["run"] as? String, let function = Self.function(name) else {
                throw FolderJobError("In its job.json, an action's run must name a function of job.py: letters, digits and _, not run itself and not starting with _.")
            }
            var args: [String: Any] = [:]
            if let raw = object["args"], !(raw is NSNull) {
                guard let object = raw as? [String: Any], JSONText.pretty(object, indent: "").count <= argsLimit else {
                    throw FolderJobError("In its job.json, an action's args must be one JSON object, such as {\"order\": \"{order_id}\"}, up to \(argsLimit) characters.")
                }
                args = object
            }
            var confirm = false
            if let raw = object["confirm"], !(raw is NSNull) {
                guard let flag = raw as? Bool else { throw FolderJobError("In its job.json, an action's confirm must be true or false.") }
                confirm = flag
            }
            return FolderJobAction(label: label, run: function, args: args, confirm: confirm)
        }
    }

    /// A function a job.py can define as a button: a plain name, not a `_helper`, and not `run`, which is the job's own.
    static func function(_ text: String) -> String? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != "run", name.range(of: #"^[A-Za-z][A-Za-z0-9_]{0,63}$"#, options: .regularExpression) != nil else { return nil }
        return name
    }

    /// The arguments for one row: every `{column}` in a string filled from the row. A string naming a column the row
    /// doesn't have is passed as it is.
    func arguments(for row: FindingRow) -> [String: Any] {
        args.mapValues { value in
            guard let text = value as? String, text.contains("{") else { return value }
            return FolderJobFindings.fill(text, row: row) ?? text
        }
    }
}

/// One finding as the job reported it: its id, its values by column, and its columns in the job's order.
struct FindingRow: Equatable {
    var id: String
    /// JSON values as the row had them: text, numbers, true or false, null, and lists or objects as they are.
    var values: [String: Any]
    var columns: [String]

    /// A value as text: numbers as written, true/false, nothing for null, JSON for a list or an object.
    func text(_ column: String) -> String? { values[column].map(FolderJobFindings.text) }

    /// Every value as text, for the diff and the table.
    var texts: [String: String] { values.mapValues(FolderJobFindings.text) }

    static func == (a: FindingRow, b: FindingRow) -> Bool { a.id == b.id && a.columns == b.columns && a.texts == b.texts }
}

/// What a run's `run()` came to: words, or a report of findings.
struct FindingsOutcome: Equatable {
    /// What `run()` said in words, when it did.
    var said: String?
    /// The system it read, in business words, and how many it read: the receipt.
    var source: String?
    var read: Int?
    /// The rows it reported; nil when it reported none (a job that returns words), which leaves the last ones as they are.
    var rows: [FindingRow]?
    /// The job's columns in order, for the table.
    var columns: [String] = []
    /// What had to be left out or cut, for the job's page: rows without an id, rows past the limit, long values.
    var notes: [String] = []

    static let rowLimit = 500
    static let valueLimit = 4_000
    static let sourceLimit = 80
    /// The key run_tool.py adds with the rows' columns in the job's order (a Swift dictionary keeps none).
    static let columnsKey = "_columns"

    /// Reads what `run()` returned. Words (or a number) are what it said. An object is a report: `source`, `read`, and
    /// `findings`, a list of rows, which needs the job's map to say which column is the id.
    static func parse(_ value: Any, map: FindingsMap?) throws -> FindingsOutcome {
        if value is [Any], map != nil {
            throw FolderJobError("job.py returned a list. Its findings go inside an object: return {\"findings\": [...]}.")
        }
        guard let object = value as? [String: Any] else { return FindingsOutcome(said: FolderJobFindings.said(value)) }
        var outcome = FindingsOutcome()
        if let raw = object["said"], !(raw is NSNull) { outcome.said = FolderJobFindings.said(raw) }
        if let raw = object["source"], !(raw is NSNull) {
            guard let text = raw as? String else { throw FolderJobError("job.py's source must be the name of what it read, in quotes.") }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            outcome.source = trimmed.isEmpty ? nil : JobWords.clip(trimmed, sourceLimit)
        }
        if let raw = object["read"], !(raw is NSNull) {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue >= 0, number.doubleValue < 1e12 else {
                throw FolderJobError("job.py's read must be how many it read: a whole number, 0 or more.")
            }
            outcome.read = Int(number.doubleValue.rounded())
        }
        guard let raw = object["findings"], !(raw is NSNull) else { return outcome }
        guard let list = raw as? [Any] else { throw FolderJobError("job.py's findings must be a list of rows, each a JSON object.") }
        guard let map else {
            throw FolderJobError("job.py returned findings, but its job.json has no map saying which column is the id. Add \"map\": {\"id\": \"…\"}.")
        }
        // The job's column order comes from run_tool.py; without it, the id first and the rest by name, the same every run.
        let ordered = object[columnsKey] as? [String]
        var columns: [String] = ordered ?? []
        var rows: [FindingRow] = []
        var byID: [String: Int] = [:]
        var noID = 0, duplicates = 0, cut = false
        for item in list {
            guard let fields = item as? [String: Any] else { throw FolderJobError("job.py's findings must be a list of rows, each a JSON object.") }
            var values: [String: Any] = [:]
            for (key, value) in fields where key != columnsKey {
                if !columns.contains(key) { columns.append(key) }
                let (kept, wasCut) = clip(value)
                if wasCut { cut = true }
                values[key] = kept
            }
            let id = fields[map.id].map(text)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !id.isEmpty else { noID += 1; continue }
            if values[map.id] is String { values[map.id] = id }   // the id as the row is known by, without stray spaces
            let row = FindingRow(id: id, values: values, columns: columns)
            if let index = byID[id] { rows[index] = row; duplicates += 1 } else { byID[id] = rows.count; rows.append(row) }
        }
        if ordered == nil { columns = [map.id] + columns.filter { $0 != map.id }.sorted() }
        if columns.isEmpty { columns = [map.id] }
        for index in rows.indices { rows[index].columns = columns }
        let total = rows.count
        if total > rowLimit { rows = Array(rows.prefix(rowLimit)) }
        outcome.columns = columns
        outcome.rows = rows
        if noID > 0 { outcome.notes.append("\(noID) finding\(noID == 1 ? " had" : "s had") no \(map.id), so \(noID == 1 ? "it was" : "they were") left out.") }
        if duplicates > 0 { outcome.notes.append("\(duplicates) finding\(duplicates == 1 ? "" : "s") repeated an earlier \(map.id); the last one counts.") }
        if total > rowLimit { outcome.notes.append("Kept the first \(rowLimit.formatted()) of \(total.formatted()) findings.") }
        if cut { outcome.notes.append("A value longer than \(valueLimit.formatted()) characters was cut.") }
        return outcome
    }

    /// A value kept within bounds: a long string cut, a list or object kept as it is up to the same length as text.
    private static func clip(_ value: Any) -> (Any, Bool) {
        if let text = value as? String { return text.count > valueLimit ? (String(text.prefix(valueLimit)) + "…", true) : (text, false) }
        if value is NSNumber || value is NSNull { return (value, false) }
        let json = FolderJobFindings.text(value)
        return json.count > valueLimit ? (String(json.prefix(valueLimit)) + "…", true) : (value, false)
    }

    private static func text(_ value: Any) -> String { FolderJobFindings.text(value) }
}

/// What a job's last run left for the next: its rows by id with when each was first seen, so the next run can say what
/// is new, changed or gone; or, for events, which ids it has seen. Kept in `findings.json` beside the job's output.
struct FindingsSnapshot: Equatable {
    struct Kept: Equatable {
        var row: FindingRow
        var firstSeen: Date
        var changedAt: Date?
    }
    var rows: [String: Kept] = [:]
    /// Events seen, oldest first.
    var events: [String] = []
    /// The job's columns as its last run that reported any had them, so a run with no findings keeps the same table.
    var columns: [String] = []

    static let eventLimit = 5_000

    static func read(_ file: URL) -> FindingsSnapshot {
        guard let data = try? Data(contentsOf: file), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return FindingsSnapshot() }
        var snapshot = FindingsSnapshot()
        snapshot.columns = object["columns"] as? [String] ?? []
        for (id, raw) in object["rows"] as? [String: Any] ?? [:] {
            guard let kept = raw as? [String: Any], let values = kept["row"] as? [String: Any],
                  let first = (kept["first_seen"] as? String).flatMap(date) else { continue }
            let columns = kept["columns"] as? [String] ?? values.keys.sorted()
            snapshot.rows[id] = Kept(row: FindingRow(id: id, values: values, columns: columns), firstSeen: first,
                                     changedAt: (kept["changed_at"] as? String).flatMap(date))
        }
        snapshot.events = object["events"] as? [String] ?? []
        return snapshot
    }

    /// Times with their fraction of a second, so a snapshot read back is the one written; one written without a
    /// fraction still reads.
    private static let stamps: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let wholeStamps = ISO8601DateFormatter()
    private static func date(_ text: String) -> Date? { stamps.date(from: text) ?? wholeStamps.date(from: text) }

    func write(to file: URL) throws {
        var rows: [String: Any] = [:]
        for (id, kept) in self.rows {
            var entry: [String: Any] = ["row": kept.row.values, "columns": kept.row.columns, "first_seen": Self.stamps.string(from: kept.firstSeen)]
            if let changed = kept.changedAt { entry["changed_at"] = Self.stamps.string(from: changed) }
            rows[id] = entry
        }
        let object: [String: Any] = ["version": 1, "rows": rows, "events": events, "columns": columns]
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JobFiles.write(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), to: file)
    }
}

/// What changed between a job's last run and this one.
struct FindingsChange: Equatable {
    struct Changed: Equatable {
        var row: FindingRow
        /// The columns whose values differ, in the row's order.
        var columns: [String]
    }
    var new: [FindingRow] = []
    var changed: [Changed] = []
    /// The ids of rows the last run had and this one doesn't.
    var gone: [String] = []
    var unchanged = 0

    var isEmpty: Bool { new.isEmpty && changed.isEmpty && gone.isEmpty }
}

enum FolderJobFindings {
    /// What a run's `run()` said, when it returned words (or a number): trimmed, and not too long.
    static func said(_ value: Any) -> String? {
        let text: String
        switch value {
        case let string as String: text = string
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): text = number.stringValue
        default: return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : JobWords.clip(trimmed, 1_000)
    }

    /// Compares this run's rows with the last run's, and makes the snapshot the next run will compare with. Rows are
    /// what is true now: one missing is gone. Events (a map with `at`) are only ever new; nothing is gone.
    static func diff(previous: FindingsSnapshot, rows: [FindingRow], map: FindingsMap, at now: Date) -> (change: FindingsChange, snapshot: FindingsSnapshot) {
        var change = FindingsChange()
        var snapshot = FindingsSnapshot()
        snapshot.columns = rows.first?.columns ?? previous.columns
        if map.isEvents {
            let seen = Set(previous.events)
            change.new = rows.filter { !seen.contains($0.id) }
            var events = previous.events
            for row in change.new where !events.contains(row.id) { events.append(row.id) }
            snapshot.events = Array(events.suffix(FindingsSnapshot.eventLimit))
            change.unchanged = rows.count - change.new.count
            return (change, snapshot)
        }
        for row in rows {
            if let before = previous.rows[row.id] {
                // A column that is missing, null or empty reads the same three ways: nothing there.
                let names = row.columns + before.row.columns.filter { !row.columns.contains($0) }
                let columns = names.filter { (row.text($0) ?? "") != (before.row.text($0) ?? "") }
                if columns.isEmpty {
                    change.unchanged += 1
                    snapshot.rows[row.id] = FindingsSnapshot.Kept(row: row, firstSeen: before.firstSeen, changedAt: before.changedAt)
                } else {
                    change.changed.append(FindingsChange.Changed(row: row, columns: columns))
                    snapshot.rows[row.id] = FindingsSnapshot.Kept(row: row, firstSeen: before.firstSeen, changedAt: now)
                }
            } else {
                change.new.append(row)
                snapshot.rows[row.id] = FindingsSnapshot.Kept(row: row, firstSeen: now, changedAt: nil)
            }
        }
        let current = Set(rows.map(\.id))
        change.gone = previous.rows.keys.filter { !current.contains($0) }.sorted()
        return (change, snapshot)
    }

    /// The rows as a table, the job's columns across and a row per finding; with no rows, the header alone.
    static func csv(_ rows: [FindingRow], columns: [String]) -> String {
        var lines = [columns.map(csvField).joined(separator: ",")]
        for row in rows { lines.append(columns.map { csvField(row.text($0) ?? "") }.joined(separator: ",")) }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A value as a CSV field: quoted when it needs to be, and with a space in front when it starts like a formula
    /// (`=`, `+`, `-` or `@`) and isn't a number, so a spreadsheet never runs what a row said.
    static func csvField(_ text: String) -> String {
        var text = text
        if let first = text.first, "=+-@".contains(first), Double(text) == nil { text = " " + text }
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// A table of findings with anything that looks like a secret hidden, as the memory log hides it: every cell of a
    /// column named like a secret, and any cell that looks like a key, a token or a card number. For what the chat is
    /// shown; the file itself is the person's.
    static func redacted(_ table: [[String]]) -> [[String]] {
        guard let header = table.first else { return table }
        let secretColumns = Set(header.indices.filter { SecretWords.looksSecret(header[$0]) })
        return [header] + table.dropFirst().map { row in
            row.enumerated().map { index, cell in
                secretColumns.contains(index) || PageWalk.looksLikeSecretValue(cell) ? MemoryLog.hidden : cell
            }
        }
    }

    /// `{column}` in a template, each filled from the row; nil when the row has no such column.
    static func fill(_ template: String, row: FindingRow) -> String? {
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else { out += rest[open...]; return out }
            let name = String(rest[rest.index(after: open)..<close])
            guard let value = row.text(name) else { return nil }
            out += value
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }

    /// A JSON value as text: as written for text, numbers as written, true/false, nothing for null, JSON for the rest.
    static func text(_ value: Any) -> String {
        switch value {
        case let text as String: return text
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        case is NSNull: return ""
        default:
            return (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: value)
        }
    }
}
