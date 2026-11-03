import Foundation

/// JSON as people and models read it: two spaces in, `"key": value`, keys in order, a short list of plain values on one
/// line, and numbers as written (19.99, not the 19.989999999999998 Apple's JSON writer prints for a double). Used for
/// whatever Noteling hands on: script results, the page's brief, a check's raw answer, and the watch list's files.
enum JSONText {
    static func pretty(_ value: Any, indent: String) -> String {
        let inner = indent + "  "
        switch value {
        case let object as [String: Any]:
            guard !object.isEmpty else { return "{}" }
            return "{\n" + object.keys.sorted().map { inner + text($0) + ": " + pretty(object[$0]!, indent: inner) }.joined(separator: ",\n")
                + "\n" + indent + "}"
        case let list as [Any]:
            guard !list.isEmpty else { return "[]" }
            let plain = list.allSatisfy { !($0 is [Any]) && !($0 is [String: Any]) }
            let line = "[" + list.map { pretty($0, indent: inner) }.joined(separator: ", ") + "]"
            if plain, line.count <= 80 { return line }
            return "[\n" + list.map { inner + pretty($0, indent: inner) }.joined(separator: ",\n") + "\n" + indent + "]"
        default:
            return scalar(value)
        }
    }

    /// One line, no spaces, keys in order: how facts and values that aren't flat are kept and compared.
    static func compact(_ value: Any) -> String {
        switch value {
        case let object as [String: Any]: return "{" + object.keys.sorted().map { text($0) + ":" + compact(object[$0]!) }.joined(separator: ",") + "}"
        case let list as [Any]: return "[" + list.map(compact).joined(separator: ",") + "]"
        default: return scalar(value)
        }
    }

    static func scalar(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let text = value as? String { return self.text(text) }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            if !CFNumberIsFloatType(number as CFNumber) { return String(number.int64Value) }
            let double = number.doubleValue
            guard double.isFinite else { return "null" }
            return double.rounded() == double && abs(double) < 1e15 ? String(Int64(double)) : String(double)
        }
        return text("\(value)")
    }

    static func text(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed, .withoutEscapingSlashes]) else { return "\"\"" }
        return String(decoding: data, as: UTF8.self)
    }
}
