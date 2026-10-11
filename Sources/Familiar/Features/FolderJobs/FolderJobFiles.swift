import CryptoKit
import Foundation

/// A job's folder and what Noteling reads in it: `job.json` (only what the job is and when it runs), `job.py` (its
/// one entry point) and `input/`; and on this Mac, what its runs left: `output/` and `run.json`.
enum FolderJobFiles {
    static let definition = "job.json"
    static let entry = "job.py"
    static let input = "input"
    static let output = "output"
    static let preview = "preview"
    static let state = "run.json"
    /// The keys job.json may have. Any other is left alone: a job's data belongs in its folders, not here.
    static let known: Set<String> = ["name", "about", "every_minutes", "starts", "ends", "requires"]
    /// Folders looked at under `jobs/`, and how deep.
    static let folderLimit = 2_000
    static let depthLimit = 8
    /// Files listed from a job's input or output.
    static let fileLimit = 200
    /// What a preview draws: rows of a table, after its first; characters of a text.
    static let rowLimit = 200
    static let textLimit = 20_000
    /// The most of a preview file that is read; a bigger one shows its beginning.
    static let readLimit = 5_000_000
    /// The kinds a preview shows as they are.
    static let previewKinds = ["csv", "tsv", "txt"]

    // MARK: finding jobs

    /// What a look at a `jobs/` folder found: each job's folder, as a path under it; and folders that look like a job
    /// but can't be one, with why.
    struct Found: Equatable {
        var jobs: [String] = []
        var unreadable: [String: String] = [:]
    }

    /// Every folder under `root`, at any depth, that holds a job.json and a job.py. A job's folder is the job's, with
    /// its input and anything else: nothing inside it is looked at for another job. A job.json without a job.py is
    /// said, since that's a job someone is still writing.
    static func jobFolders(in root: URL) -> Found {
        let manager = FileManager.default
        var found = Found()
        guard let walk = manager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return found }
        let base = root.standardizedFileURL.path
        var looked = 0
        for case let url as URL in walk {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            looked += 1
            if looked > folderLimit { break }
            if walk.level > depthLimit { walk.skipDescendants(); continue }
            let hasDefinition = manager.fileExists(atPath: url.appendingPathComponent(definition).path)
            let hasEntry = manager.fileExists(atPath: url.appendingPathComponent(entry).path)
            guard hasDefinition || hasEntry else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            let relative = String(path.dropFirst(base.count + 1))
            if hasDefinition && hasEntry { found.jobs.append(relative); walk.skipDescendants() }
            else if hasDefinition { found.unreadable[relative] = "It has a job.json but no job.py beside it." }
        }
        found.jobs.sort()
        return found
    }

    // MARK: job.json

    /// Reads job.json as someone may have left it, saying what is wrong in plain words. Every key is optional: the
    /// name is the folder's, and with no `every_minutes` the job runs only when someone runs it.
    static func parse(_ data: Data, path: String, source: WatchListSource) throws -> FolderJob {
        let value: Any
        do { value = try JSONSerialization.jsonObject(with: data) }
        catch {
            let detail = ((error as NSError).userInfo["NSDebugDescription"] as? String).map {
                ($0.prefix(1).lowercased() + $0.dropFirst()).replacingOccurrences(of: ". around line", with: " around line")
                    .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            }
            throw FolderJobError("Its job.json isn't valid JSON" + (detail.map { " (\($0))" } ?? "") + ".")
        }
        guard let object = value as? [String: Any] else { throw FolderJobError("Its job.json must be one JSON object: { … }.") }

        func text(_ key: String) throws -> String? {
            guard let raw = object[key], !(raw is NSNull) else { return nil }
            guard let text = raw as? String else { throw FolderJobError("In its job.json, \(key) must be text in quotes.") }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        func moment(_ key: String) throws -> WatchListMoment? {
            guard let raw = try text(key) else { return nil }
            guard let moment = WatchListMoment.parse(raw) else {
                throw FolderJobError("In its job.json, \(key) must be a date and time like 2026-10-05T00:00:00-04:00 (without the offset, it's this Mac's time).")
            }
            return moment
        }
        var every: Int?
        if let raw = object["every_minutes"], !(raw is NSNull) {
            let wrong = FolderJobError("In its job.json, every_minutes must be a number of minutes, \(FolderJob.minimumMinutes) to \(FolderJob.maximumMinutes).")
            let minutes: Double
            if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite { minutes = number.doubleValue }
            else if let text = raw as? String, let number = Double(text.trimmingCharacters(in: .whitespaces)) { minutes = number }
            else { throw wrong }
            every = min(FolderJob.maximumMinutes, max(FolderJob.minimumMinutes, Int(min(max(minutes.rounded(), -1e6), 1e6))))
        }
        var requires: [String] = []
        if let raw = object["requires"], !(raw is NSNull) {
            guard let list = raw as? [Any], list.allSatisfy({ $0 is String }) else {
                throw FolderJobError("In its job.json, requires must be a list of secret names in quotes.")
            }
            var seen = Set<String>()
            requires = list.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != LinkedTools.tokenKey && seen.insert($0).inserted }   // that token is Noteling's own
        }
        return FolderJob(id: id(source, path), source: source, path: path, name: try text("name") ?? path, about: try text("about") ?? "",
                         everyMinutes: every, starts: try moment("starts"), ends: try moment("ends"), requires: requires)
    }

    /// A job's id, the same on every Mac and through every update: made from whose it is and its path.
    static func id(_ source: WatchListSource, _ path: String) -> UUID {
        WatchListFiles.derivedID(folder: (source == .team ? "job-team:" : "job-own:") + path)
    }

    // MARK: files

    /// The files in a job's input or output folder, at any depth: plain files only, never links or hidden ones, those
    /// in `preview/` first, each group by path; and how many more there were past `limit`.
    static func files(in folder: URL, limit: Int = fileLimit) -> (files: [FolderJobFile], more: Int) {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let walk = manager.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return ([], 0) }
        let base = folder.standardizedFileURL.path
        var files: [FolderJobFile] = []
        var looked = 0
        for case let url as URL in walk {
            looked += 1
            if looked > folderLimit * 5 { break }
            if walk.level > depthLimit { walk.skipDescendants(); continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            files.append(FolderJobFile(path: String(path.dropFirst(base.count + 1)), url: url, size: Int64(values.fileSize ?? 0),
                                       modifiedAt: values.contentModificationDate ?? Date()))
        }
        files.sort { a, b in
            if a.inPreview != b.inPreview { return a.inPreview }
            return a.path.localizedStandardCompare(b.path) == .orderedAscending
        }
        return (Array(files.prefix(limit)), max(0, files.count - limit))
    }

    /// A digest of a job's preview files, their paths and contents: a change in any of them is a change of what the
    /// preview shows. Nil when it has none.
    static func previewDigest(output: URL) -> String? {
        let preview = files(in: output.appendingPathComponent(preview), limit: .max).files
        guard !preview.isEmpty else { return nil }
        var hash = SHA256()
        for file in preview.sorted(by: { $0.path < $1.path }) {
            hash.update(data: Data((file.path + "\u{0}").utf8))
            guard let handle = try? FileHandle(forReadingFrom: file.url) else { continue }
            while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
            try? handle.close()
            hash.update(data: Data([0]))
        }
        return hash.finalize().prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// What's in a job's output now: its files, preview first, and how many more there were.
    static func result(output: URL) -> FolderJobResult? {
        guard FileManager.default.fileExists(atPath: output.path) else { return nil }
        let (files, more) = files(in: output)
        return FolderJobResult(files: files, more: more)
    }
}

/// One file in a job's input or output folder.
struct FolderJobFile: Identifiable, Equatable {
    /// Its path in the folder, such as `preview/problems.csv`.
    var path: String
    var url: URL
    /// In bytes.
    var size: Int64
    var modifiedAt: Date
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var kind: String { (path as NSString).pathExtension.lowercased() }
    var inPreview: Bool { path.hasPrefix(FolderJobFiles.preview + "/") }
    /// In `preview/` and of a kind shown as it is: a table or a text.
    var shown: Bool { inPreview && FolderJobFiles.previewKinds.contains(kind) }
    /// Of a kind that opens in its app without running anything: what a card may carry. Anything else is only saved or
    /// shown in Finder.
    var opens: Bool { CardFiles.kinds.contains(kind) }
}

/// A job's latest output: every file, the preview ones first.
struct FolderJobResult: Equatable {
    var files: [FolderJobFile] = []
    /// Files past the first `FolderJobFiles.fileLimit`, not listed.
    var more = 0
    var preview: [FolderJobFile] { files.filter(\.inPreview) }
    var shown: [FolderJobFile] { files.filter(\.shown) }
    var hasPreview: Bool { files.contains(where: \.inPreview) }
}

/// What a preview file shows: a table, as its rows are; a text, as written; or why it can't be shown.
enum FolderJobPreview: Equatable {
    /// The first row and up to `rowLimit` after it; how many rows came after the first, when the whole file was read.
    case table(rows: [[String]], total: Int?)
    /// Up to `textLimit` characters; how many there are, when the whole file was read.
    case text(String, total: Int?)
    case unreadable(String)

    /// Reads a preview file: csv and tsv as a table, txt as text. Only its first `readLimit` bytes when it's bigger.
    static func read(_ file: FolderJobFile) -> FolderJobPreview {
        guard let handle = try? FileHandle(forReadingFrom: file.url) else { return .unreadable("It can't be read.") }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: FolderJobFiles.readLimit)) ?? Data()
        let whole = Int64(data.count) >= file.size
        guard var text = String(data: data, encoding: .utf8) ?? (whole ? nil : utf8Prefix(data)) ?? String(data: data, encoding: .windowsCP1252)
        else { return .unreadable("It isn't text.") }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        switch file.kind {
        case "csv", "tsv":
            let (rows, total) = table(text, separator: file.kind == "tsv" ? "\t" : ",", limit: FolderJobFiles.rowLimit, whole: whole)
            return .table(rows: rows, total: whole ? total : nil)
        default:
            let shown = text.count > FolderJobFiles.textLimit ? String(text.prefix(FolderJobFiles.textLimit)) : text
            return .text(shown, total: whole ? text.count : nil)
        }
    }

    /// Data cut off in the middle of a character: the text up to it.
    private static func utf8Prefix(_ data: Data) -> String? {
        for cut in 1...3 where data.count > cut {
            if let text = String(data: data.dropLast(cut), encoding: .utf8) { return text }
        }
        return nil
    }

    /// The rows of a table: fields split at `separator`, a field in double quotes kept whole (with its separators, line
    /// breaks and doubled quotes); the first row and up to `limit` after it, and how many rows came after the first.
    /// A text cut short (`whole` false) loses its last row, which may be cut too.
    static func table(_ text: String, separator: Character, limit: Int, whole: Bool = true) -> (rows: [[String]], total: Int) {
        var rows: [[String]] = []
        var count = 0
        var row: [String] = []
        var field = ""
        var quoted = false, wasQuoted = false
        var iterator = text.makeIterator()
        var pending: Character?
        func endRow() {
            row.append(field)
            field = ""
            if !(row.count == 1 && row[0].isEmpty && !wasQuoted) {   // a blank line isn't a row
                if rows.count <= limit { rows.append(row) }
                count += 1
            }
            row = []
            wasQuoted = false
        }
        while let char = pending ?? iterator.next() {
            pending = nil
            if quoted {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else { quoted = false }
                } else { field.append(char) }
            } else if char == "\"" && field.isEmpty {
                quoted = true
                wasQuoted = true
            } else if char == separator {
                row.append(field)
                field = ""
            } else if char == "\n" || char == "\r\n" || char == "\r" {
                endRow()
            } else {
                field.append(char)
            }
        }
        if whole, !field.isEmpty || !row.isEmpty || wasQuoted { endRow() }
        return (rows, max(0, count - 1))
    }

    /// Under a preview cut short: "Open the file for all 1,240 rows.", "Open the file for all of it." when it was too
    /// big to count; nil when it's all shown.
    static func more(_ preview: FolderJobPreview) -> String? {
        switch preview {
        case .table(let rows, let total):
            let shown = max(0, rows.count - 1)
            guard let total else { return "Open the file for all its rows." }
            return total > shown ? "Open the file for all \(total.formatted()) rows." : nil
        case .text(let text, let total):
            guard let total else { return "Open the file for all of it." }
            return total > text.count ? "Open the file for all \(total.formatted()) characters." : nil
        case .unreadable: return nil
        }
    }
}
