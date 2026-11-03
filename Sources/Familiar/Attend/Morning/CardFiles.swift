import Darwin
import Foundation

/// The files an inbox card carries (`files` in its card file): names of files its script wrote beside the card file,
/// in the same folder of the inbox, such as a run's full results for Excel. When Noteling reads a new version of the
/// card file, it copies them into its own folder, `cards/files/<card id>/`, in place of the card's earlier set, so a
/// card holds only its latest files, and the script may change or delete its own afterwards without breaking the card.
/// Only plain names of files in that folder are taken, up to 10, each up to 500 MB and of a kind that can't run
/// anything: tables, text, PDFs and pictures. A file that can't be attached is said on the card, one plain note each.
enum CardFiles {
    static let limit = 10
    /// 500 MB, counted as Finder does.
    static let sizeLimit: Int64 = 500_000_000
    /// What a card may carry: tables, text, PDFs and pictures. Never anything that can run or open something else,
    /// such as an app, a command, a script, an installer, a disk image, a web page, an SVG or an archive.
    static let kinds = ["csv", "tsv", "txt", "json", "md", "log", "xlsx", "pdf", "png", "jpg", "jpeg", "gif", "heic"]
    /// Names read from one card file.
    static let nameLimit = 100
    /// Notes a card shows; the rest are counted in one more.
    static let noteLimit = 20

    /// Where cards keep their files: `cards/files/` in Noteling's folder, beside the inbox.
    static var root: URL { Config.dir.appendingPathComponent("cards/files") }

    /// A card's own folder of files.
    static func folder(for cardID: UUID, in root: URL) -> URL { root.appendingPathComponent(cardID.uuidString) }

    /// The names a card file lists under `files`, trimmed, as written: a list of names, or one name; anything else is
    /// left out.
    static func names(_ value: Any?) -> [String] {
        let raw: [Any]
        switch value {
        case let name as String: raw = [name]
        case let list as [Any]: raw = list
        default: return []
        }
        let names = raw.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Array(names.prefix(nameLimit))
    }

    /// Why a name can't be one of a card's files, whatever is on disk: it isn't the plain name of a file in the card's
    /// folder, or it isn't a kind a card carries. Nil when it can be.
    static func refusal(_ name: String) -> String? {
        let plain = !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains(":")
            && name.rangeOfCharacter(from: .controlCharacters) == nil && name.utf8.count <= 255
        guard plain else { return "it must be the name of a file in the card's folder, without a path." }
        guard !name.hasPrefix(".") else { return "hidden files aren't attached." }
        guard kinds.contains((name as NSString).pathExtension.lowercased()) else {
            return "a card only carries " + kinds.dropLast().joined(separator: ", ") + " and " + kinds[kinds.count - 1] + " files."
        }
        return nil
    }

    /// Takes the listed files from `folder`, the card's folder in the inbox, into `destination`, the card's own
    /// folder, in place of what it held, all at once: the new set is put together beside it, then the two swap. Each
    /// copy keeps its file's modification time and can only be read, so a change made in Excel is saved elsewhere
    /// rather than lost at the next run. With nothing to attach, the card's folder goes. `from` is the card file's
    /// modification date.
    static func take(_ names: [String], in folder: URL, to destination: URL, from: Date) -> CardFilesTaken {
        let manager = FileManager.default
        var taken = CardFilesTaken(from: names.isEmpty ? nil : from)
        var notes: [String] = []
        var seen = Set<String>()
        let parent = destination.deletingLastPathComponent(), prefix = ".\(destination.lastPathComponent)-"
        // A set a quit or a crash left half put together goes first.
        for name in (try? manager.contentsOfDirectory(atPath: parent.path)) ?? [] where name.hasPrefix(prefix) && name.hasSuffix(".tmp") {
            try? manager.removeItem(at: parent.appendingPathComponent(name))
        }
        let staging = parent.appendingPathComponent(prefix + UUID().uuidString + ".tmp")
        defer { try? manager.removeItem(at: staging) }
        for name in names {
            // The Mac's disks don't tell "Problems.csv" from "problems.csv".
            guard seen.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted else { continue }
            if let refusal = refusal(name) { notes.append(note(name, refusal)); continue }
            let source = folder.appendingPathComponent(name)
            // Its own attributes, not those of what a link points to.
            guard let found = try? manager.attributesOfItem(atPath: source.path) else {
                notes.append(note(name, "it isn't in the card's folder."))
                continue
            }
            let type = found[.type] as? FileAttributeType
            if type == .typeSymbolicLink { notes.append(note(name, "it's a link, and a card only carries files that are in its folder.")); continue }
            guard type == .typeRegular else { notes.append(note(name, "it isn't a plain file.")); continue }
            let size = (found[.size] as? NSNumber)?.int64Value ?? 0
            guard size <= sizeLimit else {
                notes.append(note(name, "it's \(Self.size(size)), and the most is \(Self.size(sizeLimit))."))
                continue
            }
            guard taken.files.count < limit else { notes.append(note(name, "a card carries up to \(limit) files.")); continue }
            let modified = found[.modificationDate] as? Date ?? from
            do {
                try manager.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let copy = staging.appendingPathComponent(name)
                try manager.copyItem(at: source, to: copy)
                // What was copied must still be a plain file within the limit: the script may have changed it meanwhile.
                let copied = try manager.attributesOfItem(atPath: copy.path)
                let copiedSize = (copied[.size] as? NSNumber)?.int64Value ?? 0
                guard copied[.type] as? FileAttributeType == .typeRegular, copiedSize <= sizeLimit else {
                    try? manager.removeItem(at: copy)
                    notes.append(note(name, "it changed while it was being copied."))
                    continue
                }
                try manager.setAttributes([.modificationDate: modified, .posixPermissions: 0o400], ofItemAtPath: copy.path)
                taken.files.append(CardFile(name: name, size: copiedSize, modifiedAt: modified))
            } catch {
                notes.append(note(name, "it couldn't be copied (\(error.localizedDescription))."))
            }
        }
        do {
            if taken.files.isEmpty {
                if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
            } else {
                try swap(staging, into: destination)
            }
        } catch {
            notes.append("The files couldn't be put in Noteling's folder: \(error.localizedDescription)")
            taken.files = []
        }
        if notes.count > noteLimit {
            let more = notes.count - (noteLimit - 1)
            notes = Array(notes.prefix(noteLimit - 1)) + ["…and \(more) more files weren't attached."]
        }
        taken.notes = notes
        return taken
    }

    /// Puts the new set in place of the old in one step: the two folders swap names, and the old set, now at the
    /// staging name, is deleted with it.
    private static func swap(_ staging: URL, into destination: URL) throws {
        let flags = FileManager.default.fileExists(atPath: destination.path) ? UInt32(RENAME_SWAP) : 0
        guard renamex_np(staging.path, destination.path, flags) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: destination.path])
        }
    }

    /// "problems.csv wasn't attached: it's 620 MB, and the most is 500 MB."
    static func note(_ name: String, _ reason: String) -> String { "\(shown(name)) wasn't attached: \(reason)" }

    /// A name as a note shows it: on one line, and not too long.
    static func shown(_ name: String) -> String {
        let line = name.components(separatedBy: .controlCharacters).joined(separator: " ")
        return line.count > 80 ? String(line.prefix(79)) + "…" : line
    }

    /// "620 MB", "1.2 MB", "820 KB", "12 bytes": counted as Finder does, 1,000 bytes to a KB.
    static func size(_ bytes: Int64) -> String {
        func number(_ value: Double, digits: Int) -> String {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.maximumFractionDigits = digits
            return formatter.string(from: NSNumber(value: value)) ?? String(value)
        }
        if bytes < 1_000 { return bytes == 1 ? "1 byte" : "\(max(0, bytes)) bytes" }
        if bytes < 999_500 { return number(Double(bytes) / 1e3, digits: 0) + " KB" }
        if bytes < 999_950_000 { return number(Double(bytes) / 1e6, digits: 1) + " MB" }
        return number(Double(bytes) / 1e9, digits: 2) + " GB"
    }

    /// The symbol a file's kind shows with.
    static func icon(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "csv", "tsv", "xlsx": return "tablecells"
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "heic": return "photo"
        default: return "doc.text"
        }
    }
}

/// What taking a card file's `files` found: the files attached, and a note for each one that wasn't.
struct CardFilesTaken: Equatable {
    var files: [CardFile] = []
    var notes: [String] = []
    /// The card file's modification date, when it listed files.
    var from: Date?
}
