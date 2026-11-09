import CoreGraphics
import Foundation

/// One of your own notes: the words you wrote or dictated, on paper of your colour, pinned where you put it. It may
/// carry a when, a page and a checklist, and remembers the words you said when the scribe wrote it and the matter it
/// came from when it was a card. It is a file (`MemoFile`), so Finder is its folder.
struct Memo: Identifiable, Equatable {
    var id: String
    var headline: String?
    var text: String = ""
    var items: [PaperItem] = []
    var colour: PaperColour = .yellow
    var when: Date?
    var page: String?
    /// The words you said, when the scribe wrote this; an edit can go back to them.
    var asked: String?
    /// The matter whose card became this note.
    var matter: String?
    /// Where it is pinned: the paper's top-left corner on the screen, so it grows downward as it is written; nil until placed.
    var at: CGPoint?
    var collapsed = false
    /// Kept on top of your windows, in the Space it is on; otherwise it lives on the desktop, under them.
    var onTop = false
    var createdAt: Date
    var updatedAt: Date

    static func newID() -> String { "n-" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(8)) }

    /// Nothing written on it yet.
    var isBlank: Bool { (headline ?? "").isEmpty && text.isEmpty && items.isEmpty }

    /// Its headline, else its first line of words, else its first item: what a collapsed note and a log line show.
    var firstLine: String {
        if let headline, !headline.isEmpty { return headline }
        if let line = text.split(whereSeparator: \.isNewline).first { return String(line) }
        return items.first?.text ?? ""
    }

    /// Every item ticked, and there was at least one.
    var isDone: Bool { !items.isEmpty && items.allSatisfy(\.done) }
}

/// A note as a file: a few lines of front matter between `---` lines (its colour, when, page, place, and so on), then
/// the note itself as markdown: `# ` for the headline, lines of words, `- [ ]` and `- [x]` for a checklist. A file with
/// no front matter is a note too, with everything at its defaults, so a person can write one in any editor.
enum MemoFile {
    static let ext = "md"

    static func parse(_ text: String, id: String, modified: Date? = nil) -> Memo {
        var head: [String: String] = [:]
        var lines = text.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            var i = 1
            var closed = false
            while i < lines.count {
                let line = lines[i]
                if line.trimmingCharacters(in: .whitespaces) == "---" { closed = true; break }
                if let colon = line.firstIndex(of: ":") {
                    let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                    let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if !key.isEmpty { head[key] = value }
                }
                i += 1
            }
            if closed { lines = Array(lines[(i + 1)...]) } else { head = [:] }
        }
        var headline: String?
        var words: [String] = []
        var items: [PaperItem] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if headline == nil, words.allSatisfy(\.isEmpty), items.isEmpty, line.hasPrefix("# ") {
                headline = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if let item = item(line) { items.append(item); continue }
            words.append(line)
        }
        let body = words.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let created = head["created"].flatMap(date) ?? modified ?? Date()
        return Memo(id: id, headline: headline?.isEmpty == false ? headline : nil, text: body, items: items,
                    colour: PaperColour(rawValue: head["colour"] ?? "") ?? .yellow,
                    when: head["when"].flatMap(date), page: value(head["page"]), asked: value(head["asked"]), matter: value(head["matter"]),
                    at: head["at"].flatMap(point), collapsed: head["collapsed"] == "true", onTop: head["top"] == "true",
                    createdAt: created, updatedAt: head["updated"].flatMap(date) ?? modified ?? created)
    }

    /// `- [ ] milk` or `- [x] milk`; nil for any other line.
    static func item(_ line: String) -> PaperItem? {
        guard line.hasPrefix("- ["), line.count >= 5 else { return nil }
        let mark = line[line.index(line.startIndex, offsetBy: 3)]
        guard line[line.index(line.startIndex, offsetBy: 4)] == "]" else { return nil }
        let done: Bool
        switch mark {
        case " ": done = false
        case "x", "X": done = true
        default: return nil
        }
        return PaperItem(text: String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces), done: done)
    }

    static func text(_ memo: Memo) -> String {
        var head: [(String, String)] = [("colour", memo.colour.rawValue)]
        if let when = memo.when { head.append(("when", stamp(when))) }
        if let page = memo.page, !page.isEmpty { head.append(("page", oneLine(page))) }
        if let asked = memo.asked, !asked.isEmpty { head.append(("asked", oneLine(asked))) }
        if let matter = memo.matter, !matter.isEmpty { head.append(("matter", matter)) }
        if let at = memo.at { head.append(("at", "\(Self.number(at.x)),\(Self.number(at.y))")) }
        if memo.collapsed { head.append(("collapsed", "true")) }
        if memo.onTop { head.append(("top", "true")) }
        head.append(("created", stamp(memo.createdAt)))
        head.append(("updated", stamp(memo.updatedAt)))
        var out = "---\n" + head.map { "\($0.0): \($0.1)" }.joined(separator: "\n") + "\n---\n"
        if let headline = memo.headline, !headline.isEmpty { out += "# \(oneLine(headline))\n" }
        if !memo.text.isEmpty { out += memo.text + "\n" }
        for item in memo.items { out += "- [\(item.done ? "x" : " ")] \(oneLine(item.text))\n" }
        return out
    }

    /// A moment as a person reads it, in this Mac's time: `2026-11-05T15:00:00-05:00`.
    static func stamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    static func date(_ text: String) -> Date? { JobMoment.parse(text)?.date }

    static func point(_ text: String) -> CGPoint? {
        let parts = text.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, let x = parts[0], let y = parts[1], x.isFinite, y.isFinite else { return nil }
        return CGPoint(x: x, y: y)
    }

    private static func value(_ text: String?) -> String? { text.flatMap { $0.isEmpty ? nil : $0 } }
    private static func oneLine(_ text: String) -> String { text.split(whereSeparator: \.isNewline).joined(separator: " ") }
    private static func number(_ value: CGFloat) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", Double(value))
    }
}
