import Foundation

/// Comma- or tab-separated text, read and written the plain way: a field in double quotes is kept whole, with its
/// separators, line breaks and doubled quotes, and a field is quoted on the way out only when it has to be.
enum CSVText {
    /// The rows of a table: fields split at `separator`; the first row and up to `limit` after it, and how many rows
    /// came after the first. A text cut short (`whole` false) loses its last row, which may be cut too. A blank line
    /// isn't a row.
    static func rows(_ text: String, separator: Character = ",", limit: Int = .max, whole: Bool = true) -> (rows: [[String]], total: Int) {
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

    /// A field as a line of the table has it: in quotes when it holds the separator, a quote or a line break.
    static func field(_ field: String, separator: Character = ",") -> String {
        field.contains(where: { $0 == separator || $0 == "\"" || $0.isNewline })
            ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
    }

    static func line(_ fields: [String], separator: Character = ",") -> String {
        fields.map { field($0, separator: separator) }.joined(separator: String(separator))
    }
}
