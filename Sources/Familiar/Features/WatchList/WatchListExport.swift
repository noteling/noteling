import Foundation

/// A watch's results as CSV files its card carries, so a list too long to read on a card opens where people already
/// work, such as Excel, with ⌘F, filters and tabs: `problems.csv`, every item not as expected or that couldn't be
/// checked (those not as expected first), and `all.csv`, every item, in the watch's order. One row per item:
/// - item, title, url, status ("as expected", "not as expected", "couldn't check" or "not checked yet"), and symptoms,
///   the fields that differ, joined with "; ";
/// - one column per field the check reports, with what it shows now (empty while it couldn't check), then one
///   `expected <field>` column per field with what counts as right;
/// - why, the check's own `why` lines joined with " / " (or why it couldn't check); checked_at, in this Mac's time; and
///   check, which check ran.
/// The files follow RFC 4180, in UTF-8 with a byte order mark so Excel reads every language. Numbers are written as the
/// check wrote them (19.99), and a text Excel would take for a formula gets a `'` in front, so it shows as written and
/// never runs. Excel opens at most 1,048,576 rows, so a longer file is split: `all-1.csv`, `all-2.csv`…
enum WatchListExport {
    /// Rows Excel opens in one sheet, the header's included.
    static let excelRows = 1_048_576
    /// Items one file holds; the rest go in the next.
    static let rowLimit = excelRows - 1

    /// One file of a watch's card: its name, and the items it holds.
    struct Part: Equatable {
        var name: String
        var kind: WatchListCardFile
        var items: ArraySlice<WatchListItem>
        /// How many files its kind is split into.
        var of = 1
    }

    /// The columns between symptoms and why: the fields the check reports, then what counts as right.
    struct Columns: Equatable {
        var state: [String] = []
        var expected: [String] = []
    }

    /// The items a kind of file holds: the problems, not as expected first, then couldn't check; or every item.
    static func items(_ kind: WatchListCardFile, of watch: WatchListWatch) -> [WatchListItem] {
        switch kind {
        case .problems:
            return watch.items.filter(\.isRed) + watch.items.filter { if case .couldNotCheck? = $0.status { return true }; return false }
        case .all:
            return watch.items
        }
    }

    /// The files a watch's card carries, in order: one for each kind its `files` name that has items, split into
    /// numbered parts past `rowLimit` items.
    static func parts(for watch: WatchListWatch, rowLimit: Int = rowLimit) -> [Part] {
        let limit = max(1, rowLimit)
        return watch.files.flatMap { kind -> [Part] in
            let items = items(kind, of: watch)
            guard items.count > limit else { return items.isEmpty ? [] : [Part(name: kind.rawValue + ".csv", kind: kind, items: items[...])] }
            let count = (items.count + limit - 1) / limit
            return (0..<count).map { index -> Part in
                let start = index * limit
                return Part(name: "\(kind.rawValue)-\(index + 1).csv", kind: kind, items: items[start..<min(start + limit, items.count)], of: count)
            }
        }
    }

    /// What a card says about a kind of file that is split: "All results are in 2 files: Excel opens at most
    /// 1,048,576 rows per file."
    static func splitLines(_ parts: [Part]) -> [String] {
        WatchListCardFile.allCases.compactMap { kind -> String? in
            guard let part = parts.first(where: { $0.kind == kind }), part.of > 1 else { return nil }
            return (kind == .all ? "All results are" : "The problems are") + " in \(part.of) files: Excel opens at most 1,048,576 rows per file."
        }
    }

    /// Whether a name is one of Noteling's tables in a watch's folder of the inbox: problems.csv, all.csv, or one of
    /// their numbered parts.
    static func isOwn(_ name: String) -> Bool {
        guard name.hasSuffix(".csv") else { return false }
        let stem = name.dropLast(4)
        return WatchListCardFile.allCases.contains { kind in
            if stem == kind.rawValue { return true }
            guard stem.hasPrefix(kind.rawValue + "-") else { return false }
            let number = stem.dropFirst(kind.rawValue.count + 1)
            return !number.isEmpty && number.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    /// The fields any item checked now reports, and the fields anything says count, each once: those the watch names
    /// first, in its order, then the rest alphabetically.
    static func columns(for watch: WatchListWatch) -> Columns {
        var state = Set<String>(), expected = Set<String>()
        for item in watch.items {
            if item.status?.isVerdict == true, let fields = item.state?.keys { state.formUnion(fields) }
            if let fields = item.expected?.keys { expected.formUnion(fields) }
        }
        func ordered(_ fields: Set<String>) -> [String] {
            var named: [String] = []
            for name in watch.fields ?? [] {
                if let field = WatchListRules.field(for: name, in: fields), !named.contains(field) { named.append(field) }
            }
            return named + fields.subtracting(named).sorted { ($0.lowercased(), $0) < ($1.lowercased(), $1) }
        }
        return Columns(state: ordered(state), expected: ordered(expected))
    }

    static func header(_ columns: Columns) -> [String] {
        ["item", "title", "url", "status", "symptoms"] + columns.state + columns.expected.map { "expected " + $0 } + ["why", "checked_at", "check"]
    }

    /// One item's cells, in the header's order.
    static func row(_ item: WatchListItem, columns: Columns, check: String, time: (Date) -> String) -> [String] {
        var status = "not checked yet", symptoms = "", why = item.whyNow.joined(separator: " / ")
        switch item.status {
        case .asExpected?: status = "as expected"
        case .notAsExpected(let differences)?:
            status = "not as expected"
            symptoms = differences.map(\.field).joined(separator: "; ")
        case .couldNotCheck(let reason)?:
            status = "couldn't check"
            why = reason
        case nil: break
        }
        // What it shows now: nothing from an earlier check while it couldn't check.
        let now = item.status?.isVerdict == true ? item.state ?? [:] : [:]
        let fields = columns.state.map { value(now[$0]) } + columns.expected.map { value(item.expected?[$0]) }
        return [text(item.key), text(item.title ?? ""), text(item.pageURL ?? ""), status, text(symptoms)] + fields
            + [text(why), item.checkedAt.map(time) ?? "", text(check)]
    }

    /// A value as a cell: a number as the check wrote it, yes or no, a list joined with "; ", none, or the text; empty
    /// when the check didn't report it.
    static func value(_ value: WatchListValue?) -> String {
        switch value {
        case nil: return ""
        case .number(let number)?: return JSONText.scalar(NSNumber(value: number))
        case .flag(let flag)?: return flag ? "yes" : "no"
        case .list(let list)?: return list.isEmpty ? "none" : text(list.joined(separator: "; "))
        case .some(.none): return "none"
        case .text(let words)?: return text(words)
        }
    }

    /// Text as a cell: one that starts the way an Excel formula does gets a `'` in front, unless it is a plain number.
    static func text(_ text: String) -> String {
        guard let first = text.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first),
              text.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$"#, options: .regularExpression) == nil else { return text }
        return "'" + text
    }

    /// A cell as RFC 4180 writes it: in double quotes, with its own doubled, when it holds a comma, a quote or a line
    /// break.
    static func field(_ cell: String) -> String {
        guard cell.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return cell }
        return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// A file's bytes: a byte order mark, the header, then one row per item, each line ending in CRLF.
    static func csv(_ part: Part, columns: Columns, check: String, timeZone: TimeZone = .autoupdatingCurrent) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var data = Data("\u{FEFF}".utf8)
        func line(_ cells: [String]) { data.append(contentsOf: (cells.map(field).joined(separator: ",") + "\r\n").utf8) }
        line(header(columns).map(text))
        for item in part.items { line(row(item, columns: columns, check: check, time: formatter.string(from:))) }
        return data
    }
}
