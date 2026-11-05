import Foundation
import FamiliarContracts
import FamiliarRuntime

/// Four read-only tools in place of a shell, for the chat and the minister: list, read, search and rows over what a
/// person or Noteling wrote on this Mac, under named roots, and nothing else. The model never composes code or
/// commands that run here: it reads with these four and invokes what a person wrote (a pack's script, a job's button).
/// Every path starts with a root's name; nothing outside a root is read, nor anything hidden, nor a link that leads
/// out; and secrets are hidden the way the memory log hides them.
struct Recall {
    struct Root: Equatable {
        let name: String
        let url: URL
        /// One line for the model: what is in it and how it is laid out.
        let about: String
        /// A path with no root in front is looked for here, the way the prompt lists a pack's docs (`shop/docs/guide.md`).
        var bare = false
    }

    /// How much one call gives back; tests lower them.
    struct Limits {
        var entries = 300
        var lines = 200
        var linesMost = 2_000
        var characters = 40_000
        var hits = 80
        var context = 5
        var rows = 50
        var rowsMost = 500
        /// The most of one file that is read.
        var bytes = 16 * 1024 * 1024
        var walk = 20_000
        var depth = 8
    }

    /// A path as the model names it, resolved: its root and the file or folder it is.
    struct Place {
        let root: Root
        let url: URL
        let path: String
        var kind: String { url.pathExtension.lowercased() }
    }

    let roots: () -> [Root]
    var limits = Limits()

    static let names: Set<String> = ["list", "read", "search", "rows"]
    /// What search looks into: the text people and jobs write.
    static let kinds: Set<String> = ["md", "markdown", "txt", "py", "json", "jsonl", "csv", "tsv", "yaml", "yml"]
    static let tables: Set<String> = ["csv", "tsv", "jsonl"]
    static let lineLimit = 240

    init(roots: @escaping () -> [Root]) { self.roots = roots }

    /// Noteling's roots: its folder's memory, matters, jobs and job results, your own tool packs, and your team's tools
    /// while a repository is linked.
    static func standard(home: URL, tools: URL, team: @escaping () -> URL?) -> Recall {
        Recall {
            var out = [
                Root(name: "memory", url: home.appendingPathComponent("memory"),
                     about: "Noteling's log, one file a day (2026-11-02.jsonl), one JSON object per line: each job's run (ran), each finding new, changed or gone with its row, the minister's verdict on each finding and why (verdict, why), each sticker it wrote (sticker), and what the person put away (put_away) or pressed (pressed)."),
                Root(name: "matters", url: home.appendingPathComponent("matters"),
                     about: "The minister's matters, one folder each: matter.json (its findings, state, sticker) and notes.md (its notes on what it is and why)."),
                Root(name: "notes", url: home.appendingPathComponent("memos"),
                     about: "The person's own notes, pinned on their screen, one markdown file each (n-1a2b3c4d.md): a few lines of front matter (colour, when, page, asked, matter), then `# headline`, the words, and `- [ ]` checklist lines. Read them to know what the person already knows or means to do; never write them."),
                Root(name: "jobs", url: home.appendingPathComponent("jobs"),
                     about: "The person's own jobs, one folder each: job.json, job.md, job.py, input/."),
                Root(name: "results", url: home.appendingPathComponent("job-results"),
                     about: "What each job's runs left: own/<path>/ or team/<path>/ with output/ (findings.csv, preview/, …) and run.json."),
                Root(name: "tools", url: tools, about: "The person's own tool packs: <pack>/docs/… and their scripts.", bare: true),
            ]
            if let team = team() {
                out.append(Root(name: "team", url: team, about: "The team's tools as linked from GitHub: tool packs (<pack>/docs/…) and jobs/<path>/ (job.json, job.md, input/).", bare: true))
            }
            return out
        }
    }

    // MARK: the tools

    var definitions: [[String: Any]] { Self.definitions }

    static var definitions: [[String: Any]] {
        [
            tool("list", "What is in a folder Noteling can read: files with their size and date, folders with a slash after their name. With no path, the roots and what each holds. With a pattern, every file under the folder, at any depth, whose name matches it, such as *.csv or 2026-11-*.jsonl.",
                 ["path": ["type": "string", "description": "A root, or a folder under one: memory, matters/m-7617d061, results/team/sales/stuck-orders/output."],
                  "pattern": ["type": "string", "description": "A glob on file names."]], required: []),
            tool("read", "A text file, or part of one: `lines` lines (200 unless said, at most 2,000) from line `from` (1 is the first; search gives line numbers). A csv or tsv read from the middle comes with its first line, the columns, first.",
                 ["path": ["type": "string"], "from": ["type": "integer"], "lines": ["type": "integer"]], required: ["path"]),
            tool("search", "The lines matching a regular expression (case-insensitive) in the text files under a root or a folder, or under every root with no path: file:line: text, with `context` lines around each (none unless said, at most 5). At most 80 hits; narrow the pattern or the folder when it says more were left out.",
                 ["pattern": ["type": "string"], "path": ["type": "string"], "context": ["type": "integer"]], required: ["pattern"]),
            tool("rows", "The rows of a table, a csv, tsv or jsonl file (a jsonl file's columns are its keys): filtered with `where`, down to `columns`, sorted, up to `limit` (50 unless said, at most 500), or only counted. `where` is an object of column → test: plain text means contains (case-insensitive); =x means equals, !=x not, and >3, >=3, <3, <=3 compare as numbers when both sides are. `sort` is a column, or -column for descending; numbers sort as numbers.",
                 ["path": ["type": "string"], "where": ["type": "object", "additionalProperties": ["type": ["string", "number", "boolean"]]],
                  "columns": ["type": "array", "items": ["type": "string"]], "sort": ["type": "string"],
                  "limit": ["type": "integer"], "count": ["type": "boolean"]], required: ["path"]),
        ]
    }

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any], required: [String]) -> [String: Any] {
        ["name": name, "description": description,
         "input_schema": ["type": "object", "additionalProperties": false, "properties": properties, "required": required]]
    }

    func routes() -> [ToolRoute] {
        Self.definitions.map { definition in
            let name = definition["name"] as? String ?? ""
            return ToolRoute(match: .tool(name: name), definition: definition) { _, input, _ in self.execute(name, input) }
        }
    }

    func execute(_ name: String, _ input: [String: Any]) -> ToolResult {
        do {
            switch name {
            case "list": return .text(try list(input))
            case "read": return .text(try read(input))
            case "search": return .text(try search(input))
            case "rows": return .text(try rows(input))
            default: return .text("Unknown tool \(name)", isError: true)
            }
        } catch let error as RecallError {
            return .text(error.message, isError: true)
        } catch {
            return .text(error.localizedDescription, isError: true)
        }
    }

    // MARK: paths

    private var rootNames: String { roots().map(\.name).joined(separator: ", ") }
    private var outside: RecallError { RecallError("That path isn't under a root Noteling can read. Roots: \(rootNames).") }

    /// The file or folder a path names: its root's name first, then folders; no hidden names, no way up, no link out.
    func place(_ raw: Any?) throws -> Place {
        let text = Self.text(raw)
        guard !text.isEmpty else { throw RecallError("Say a path, starting with a root: \(rootNames).") }
        guard !text.hasPrefix("/"), !text.hasPrefix("~") else { throw outside }
        var parts = text.split(separator: "/").map(String.init)
        for part in parts {
            if part == "." || part == ".." { throw outside }
            if part.hasPrefix(".") { throw RecallError("Hidden files aren't read.") }
        }
        let all = roots()
        let root: Root
        if let named = all.first(where: { $0.name == parts.first }) {
            root = named
            parts.removeFirst()
        } else if let bare = all.first(where: { $0.bare && FileManager.default.fileExists(atPath: $0.url.appendingPathComponent(parts.joined(separator: "/")).path) }) {
            root = bare
        } else {
            throw RecallError("No root called \(parts.first ?? ""). Roots: \(rootNames). Call list with no path to see what each holds.")
        }
        let url = parts.reduce(root.url) { $0.appendingPathComponent($1) }
        guard Self.inside(url, root: root) else { throw outside }
        return Place(root: root, url: url, path: ([root.name] + parts).joined(separator: "/"))
    }

    /// Under the root with links followed: a link that leads out is outside.
    static func inside(_ url: URL, root: Root) -> Bool {
        let base = root.url.resolvingSymlinksInPath().standardizedFileURL.path
        let real = url.resolvingSymlinksInPath().standardizedFileURL.path
        return real == base || real.hasPrefix(base + "/")
    }

    private var rootPlaces: [Place] { roots().map { Place(root: $0, url: $0.url, path: $0.name) } }

    // MARK: list

    private func list(_ input: [String: Any]) throws -> String {
        let raw = Self.text(input["path"])
        let pattern = Self.text(input["pattern"])
        if raw.isEmpty, pattern.isEmpty {
            let lines = roots().map { root in
                "\(root.name)/  \(root.about)" + (FileManager.default.fileExists(atPath: root.url.path) ? "" : " (nothing there yet)")
            }
            return lines.joined(separator: "\n") + "\nA path starts with one of these names."
        }
        let places = raw.isEmpty ? rootPlaces : [try place(raw)]
        var out: [String] = []
        var more = 0
        if pattern.isEmpty {
            let one = places[0]
            guard Self.isFolder(one.url) else {
                throw FileManager.default.fileExists(atPath: one.url.path) ? RecallError("\(one.path) is a file; read it.") : RecallError("There is no \(one.path).")
            }
            let entries = ((try? FileManager.default.contentsOfDirectory(at: one.url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                                                                          options: [.skipsHiddenFiles])) ?? [])
                .filter { Self.inside($0, root: one.root) }
                .sorted { a, b in
                    let folderA = Self.isFolder(a), folderB = Self.isFolder(b)
                    if folderA != folderB { return folderA }
                    return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
                }
            for entry in entries {
                if out.count >= limits.entries { more += 1; continue }
                out.append(Self.entryLine(entry, path: one.path + "/" + entry.lastPathComponent))
            }
            if out.isEmpty { return "\(one.path)/ is empty." }
        } else {
            for one in places where Self.isFolder(one.url) {
                for file in files(under: one, kinds: nil) where fnmatch(pattern, file.url.lastPathComponent, FNM_CASEFOLD) == 0 {
                    if out.count >= limits.entries { more += 1; continue }
                    out.append(Self.entryLine(file.url, path: file.path))
                }
            }
            if out.isEmpty { return "No file named like \(pattern)" + (raw.isEmpty ? "." : " under \(places[0].path).") }
        }
        if more > 0 { out.append("…and \(more.formatted()) more") }
        return out.joined(separator: "\n")
    }

    private static func entryLine(_ url: URL, path: String) -> String {
        if isFolder(url) { return path + "/" }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return "\(path)  \(size(values?.fileSize ?? 0))  \(stamp(values?.contentModificationDate))"
    }

    static func size(_ bytes: Int) -> String {
        bytes < 1024 ? "\(bytes) B"
            : bytes < 1024 * 1024 ? String(format: "%.1f KB", Double(bytes) / 1024)
            : String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }

    private static func stamp(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// The plain files under a place at any depth (to `limits.depth`), none hidden, none through a link that leads out,
    /// of the given kinds (all with nil); the place itself when it is a file.
    private func files(under place: Place, kinds: Set<String>?) -> [Place] {
        let manager = FileManager.default
        guard Self.isFolder(place.url) else {
            return manager.fileExists(atPath: place.url.path) && (kinds?.contains(place.kind) ?? true) ? [place] : []
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let walk = manager.enumerator(at: place.url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let base = place.url.standardizedFileURL.path
        var out: [Place] = []
        var looked = 0
        for case let url as URL in walk {
            looked += 1
            if looked > limits.walk { break }
            if walk.level > limits.depth { walk.skipDescendants(); continue }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base + "/"), Self.inside(url, root: place.root) else { continue }
            if let kinds, !kinds.contains(url.pathExtension.lowercased()) { continue }
            out.append(Place(root: place.root, url: url, path: place.path + "/" + path.dropFirst(base.count + 1)))
        }
        return out.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: read

    private func read(_ input: [String: Any]) throws -> String {
        let place = try place(input["path"])
        let (text, cut) = try contents(of: place)
        let lines = Self.lines(text)
        let from = max(1, Self.int(input["from"]) ?? 1)
        let count = min(limits.linesMost, max(1, Self.int(input["lines"]) ?? limits.lines))
        guard from <= lines.count else { throw RecallError("\(place.path) has \(lines.count.formatted()) line(s); there is no line \(from).") }
        let end = min(lines.count, from + count - 1)
        let hide = Hider(place: place, header: lines.first)
        var out: [String] = []
        if hide.hasHeader, from > 1 { out.append(lines[0]) }
        for index in (from - 1)..<end { out.append(hide(lines[index], header: index == 0)) }
        var joined = out.joined(separator: "\n")
        if joined.count > limits.characters {
            joined = String(joined.prefix(limits.characters)) + "\n…(cut at \(limits.characters.formatted()) characters; read fewer lines at a time)"
        }
        if from > 1 || end < lines.count || cut {
            joined += "\n(lines \(from)–\(end) of \(lines.count.formatted())" + (cut ? ", in the first \(Self.size(limits.bytes)) of the file)" : ")")
        }
        return joined
    }

    /// A file's text, up to `limits.bytes` of it, and whether there was more.
    private func contents(of place: Place) throws -> (text: String, cut: Bool) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: place.url.path, isDirectory: &isDirectory) else { throw RecallError("There is no \(place.path).") }
        guard !isDirectory.boolValue else { throw RecallError("\(place.path) is a folder; list it.") }
        guard let handle = try? FileHandle(forReadingFrom: place.url) else { throw RecallError("\(place.path) can't be read.") }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: limits.bytes)) ?? Data()
        let size = (try? place.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? data.count
        let cut = size > data.count
        guard !data.prefix(8_192).contains(0),
              var text = String(data: data, encoding: .utf8) ?? (cut ? Self.utf8Prefix(data) : nil) ?? String(data: data, encoding: .windowsCP1252)
        else { throw RecallError("\(place.path) isn't text.") }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return (text, cut)
    }

    /// Data cut off in the middle of a character: the text up to it.
    private static func utf8Prefix(_ data: Data) -> String? {
        for cut in 1...3 where data.count > cut {
            if let text = String(data: data.dropLast(cut), encoding: .utf8) { return text }
        }
        return nil
    }

    static func lines(_ text: String) -> [String] {
        var lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    // MARK: search

    private func search(_ input: [String: Any]) throws -> String {
        let pattern = Self.text(input["pattern"])
        guard !pattern.isEmpty else { throw RecallError("Say a pattern.") }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            throw RecallError("That isn't a regular expression that can be read.")
        }
        let context = min(limits.context, max(0, Self.int(input["context"]) ?? 0))
        let raw = Self.text(input["path"])
        let places = raw.isEmpty ? rootPlaces : [try place(raw)]
        if !raw.isEmpty, !FileManager.default.fileExists(atPath: places[0].url.path) { throw RecallError("There is no \(places[0].path).") }
        var out: [String] = []
        var hits = 0
        var omitted = false
        files: for place in places {
            for file in files(under: place, kinds: Self.kinds) {
                guard let (text, _) = try? contents(of: file) else { continue }
                let lines = Self.lines(text)
                var matched: [Int] = []
                for (index, line) in lines.enumerated() where regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    if hits + matched.count >= limits.hits { omitted = true; break }
                    matched.append(index)
                }
                if !matched.isEmpty {
                    let hide = Hider(place: file, header: lines.first)
                    let isHit = Set(matched)
                    var printed = -1
                    for index in matched {
                        let low = max(printed + 1, index - context), high = min(lines.count - 1, index + context)
                        if context > 0, printed >= 0, low > printed + 1 { out.append("--") }
                        if low <= high {
                            for line in low...high {
                                let hit = isHit.contains(line)
                                out.append("\(file.path)\(hit ? ":" : "-")\(line + 1)\(hit ? ": " : "- ")\(Self.clip(hide(lines[line], header: line == 0)))")
                            }
                        }
                        printed = max(printed, high)
                    }
                    hits += matched.count
                }
                if omitted { break files }
            }
        }
        if out.isEmpty { return "No matches." }
        if omitted { out.append("…(more matches left out: narrow the pattern or the folder)") }
        return out.joined(separator: "\n")
    }

    private static func clip(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > lineLimit ? String(trimmed.prefix(lineLimit)) + "…" : trimmed
    }

    // MARK: rows

    private func rows(_ input: [String: Any]) throws -> String {
        let place = try place(input["path"])
        guard Self.tables.contains(place.kind) else {
            throw RecallError("rows reads a csv, tsv or jsonl file; \(place.path) is " + (place.kind.isEmpty ? "something else." : "a .\(place.kind) file.") + " Use read.")
        }
        let (text, cut) = try contents(of: place)
        let table = try Table(text: text, kind: place.kind)
        var kept = Array(table.records.indices)
        if let conditions = input["where"] as? [String: Any] {
            for (column, raw) in conditions.sorted(by: { $0.key < $1.key }) {
                let index = try table.index(of: column)
                let test = Test(raw)
                kept = kept.filter { test.matches(table.records[$0].values[index]) }
            }
        }
        let sort = Self.text(input["sort"])
        if !sort.isEmpty {
            let descending = sort.hasPrefix("-")
            let index = try table.index(of: descending ? String(sort.dropFirst()) : sort)
            let numeric = kept.allSatisfy { let value = table.records[$0].values[index]; return value.isEmpty || Double(value) != nil }
            kept.sort { a, b in
                let x = table.records[a].values[index], y = table.records[b].values[index]
                let order = numeric ? Self.order(Double(x) ?? -.infinity, Double(y) ?? -.infinity) : x.localizedStandardCompare(y)
                if order == .orderedSame { return a < b }
                return descending ? order == .orderedDescending : order == .orderedAscending
            }
        }
        let matched = kept.count
        let all = table.records.count.formatted()
        if let count = input["count"] as? NSNumber, count.boolValue {
            return input["where"] == nil ? "\(all) rows." : "\(matched.formatted()) of \(all) rows match."
        }
        let limit = min(limits.rowsMost, max(1, Self.int(input["limit"]) ?? limits.rows))
        let shown = Array(kept.prefix(limit))
        var columns = Array(table.columns.indices)
        if let wanted = input["columns"] as? [Any], !wanted.isEmpty { columns = try wanted.map { try table.index(of: Self.text($0)) } }
        let hidden = Set(columns.filter { SecretWords.looksSecret(table.columns[$0]) })
        var out: [String] = []
        if place.kind == "jsonl" {
            for row in shown {
                var object: [String: Any] = [:]
                for index in columns { if let value = table.records[row].raw?[table.columns[index]] { object[table.columns[index]] = value } }
                if let data = try? JSONSerialization.data(withJSONObject: SecretText.redacted(object), options: [.sortedKeys, .withoutEscapingSlashes]) {
                    out.append(String(decoding: data, as: UTF8.self))
                }
            }
        } else {
            let separator: Character = place.kind == "tsv" ? "\t" : ","
            out.append(CSVText.line(columns.map { table.columns[$0] }, separator: separator))
            for row in shown {
                out.append(CSVText.line(columns.map { hidden.contains($0) ? SecretText.hidden : SecretText.hiding(table.records[row].values[$0]) }, separator: separator))
            }
        }
        var joined = out.joined(separator: "\n")
        if joined.count > limits.characters {
            joined = String(joined.prefix(limits.characters)) + "\n…(cut at \(limits.characters.formatted()) characters; ask for fewer columns or rows)"
        }
        joined += "\n(\(shown.count.formatted()) of \(matched.formatted()) matching rows; \(all) in the file" + (cut ? "'s first \(Self.size(limits.bytes)))" : ")")
        return joined
    }

    /// A table as rows reads it: its columns, and each record's values by column, with the JSON object a jsonl line
    /// was, for giving it back as it was.
    private struct Table {
        struct Record {
            var values: [String]
            var raw: [String: Any]?
        }
        let columns: [String]
        let records: [Record]

        init(text: String, kind: String) throws {
            if kind == "jsonl" {
                var columns: [String] = [], seen = Set<String>(), objects: [[String: Any]] = []
                for line in Recall.lines(text) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    guard let data = line.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
                    for key in object.keys.sorted() where seen.insert(key).inserted { columns.append(key) }
                    objects.append(object)
                }
                self.columns = columns
                records = objects.map { object in Record(values: columns.map { object[$0].map(Recall.string) ?? "" }, raw: object) }
            } else {
                let parsed = CSVText.rows(text, separator: kind == "tsv" ? "\t" : ",")
                guard let header = parsed.rows.first else { throw RecallError("The table is empty.") }
                columns = header
                records = parsed.rows.dropFirst().map { row in Record(values: header.indices.map { $0 < row.count ? row[$0] : "" }, raw: nil) }
            }
        }

        func index(of column: String) throws -> Int {
            let name = column.trimmingCharacters(in: .whitespaces)
            if let index = columns.firstIndex(of: name) { return index }
            if let index = columns.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return index }
            throw RecallError("No column \(name). Columns: \(columns.joined(separator: ", ")).")
        }
    }

    /// One test of `where`: contains unless it starts with =, !=, >, >=, < or <=.
    private struct Test {
        enum Kind { case contains, equals, differs, greater, atLeast, less, atMost }
        let kind: Kind
        let value: String

        init(_ raw: Any) {
            if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                kind = .equals
                value = number.stringValue
                return
            }
            let text = Recall.string(raw).trimmingCharacters(in: .whitespaces)
            for (prefix, kind) in [(">=", Kind.atLeast), ("<=", .atMost), ("!=", .differs), (">", .greater), ("<", .less), ("=", .equals)] where text.hasPrefix(prefix) {
                self.kind = kind
                value = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return
            }
            kind = .contains
            value = text
        }

        func matches(_ cell: String) -> Bool {
            switch kind {
            case .contains: return value.isEmpty ? cell.isEmpty : cell.range(of: value, options: .caseInsensitive) != nil
            case .equals: return Recall.order(cell, value) == .orderedSame
            case .differs: return Recall.order(cell, value) != .orderedSame
            case .greater: return Recall.order(cell, value) == .orderedDescending
            case .atLeast: return Recall.order(cell, value) != .orderedAscending
            case .less: return Recall.order(cell, value) == .orderedAscending
            case .atMost: return Recall.order(cell, value) != .orderedDescending
            }
        }
    }

    /// As numbers when both are, else as text, case aside.
    static func order(_ a: String, _ b: String) -> ComparisonResult {
        if let x = Double(a), let y = Double(b) { return order(x, y) }
        return a.caseInsensitiveCompare(b)
    }

    static func order(_ x: Double, _ y: Double) -> ComparisonResult { x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame }

    // MARK: secrets

    /// Hides secrets in a line the way the memory log does: in a csv or tsv, every value of a column named like a
    /// secret and any value that looks like one; in a JSON line, keys named like one and such values; elsewhere, such
    /// values in the text.
    struct Hider {
        private let separator: Character?
        private let secretColumns: Set<Int>
        private let jsonl: Bool
        /// A csv or tsv: its first line names the columns and is given as it is.
        var hasHeader: Bool { separator != nil }

        init(place: Place, header: String?) {
            switch place.kind {
            case "csv", "tsv":
                let separator: Character = place.kind == "tsv" ? "\t" : ","
                self.separator = separator
                let columns = header.map { CSVText.rows($0, separator: separator).rows.first ?? [] } ?? []
                secretColumns = Set(columns.indices.filter { SecretWords.looksSecret(columns[$0]) })
                jsonl = false
            case "jsonl":
                separator = nil
                secretColumns = []
                jsonl = true
            default:
                separator = nil
                secretColumns = []
                jsonl = false
            }
        }

        func callAsFunction(_ line: String, header: Bool = false) -> String {
            if let separator {
                if header { return line }
                guard !secretColumns.isEmpty, var fields = CSVText.rows(line, separator: separator).rows.first else { return SecretText.hiding(line) }
                for index in fields.indices { fields[index] = secretColumns.contains(index) ? SecretText.hidden : SecretText.hiding(fields[index]) }
                return CSVText.line(fields, separator: separator)
            }
            if jsonl, let data = line.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let out = try? JSONSerialization.data(withJSONObject: SecretText.redacted(object), options: [.sortedKeys, .withoutEscapingSlashes]) {
                return String(decoding: out, as: UTF8.self)
            }
            return SecretText.hiding(line)
        }
    }

    // MARK: values

    static func text(_ value: Any?) -> String { ((value as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// A JSON value as a cell: text as it is, a number or a boolean as written, null as nothing, the rest as JSON.
    static func string(_ value: Any) -> String {
        switch value {
        case let text as String: return text
        case let number as NSNumber: return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        case is NSNull: return ""
        default:
            return (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])).map { String(decoding: $0, as: UTF8.self) } ?? "\(value)"
        }
    }
}

struct RecallError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
