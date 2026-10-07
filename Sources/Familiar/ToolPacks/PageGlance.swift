import Foundation

/// A brief's own short answer for the pen: what the page shows, why, and what to do, written by the pack's script.
/// It shows on the pick's note the moment something is picked, before any model is asked. The brief's result carries
/// it under `glance`:
///
///     {"glance": {"headline": "ADS Inc's offer, $12.33, for 07960",
///                 "why": ["No Rollback badge: the comparison price ended yesterday (comparison price)",
///                         {"text": "The page and the price of record agree", "source": "priceRT"}],
///                 "do": ["Nothing to fix"]}, …}
///
/// Each line is a string or `{"text", "source"}`; up to three of each are shown, as written.
struct PageGlance: Equatable {
    struct Line: Equatable {
        var text: String
        var source: String?
    }

    var headline: String
    var why: [Line]
    var todo: [Line]

    static let maxLines = 3
    static let maxChars = 240

    /// The glance in a brief's result (compact JSON), or nil when there is none or it says nothing.
    static func parse(_ result: String) -> PageGlance? {
        guard let data = result.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let g = object["glance"] as? [String: Any] else { return nil }
        let glance = PageGlance(headline: clip(g["headline"] as? String ?? ""), why: lines(g["why"]), todo: lines(g["do"]))
        return glance.headline.isEmpty && glance.why.isEmpty && glance.todo.isEmpty ? nil : glance
    }

    private static func lines(_ value: Any?) -> [Line] {
        let items: [Any] = value as? [Any] ?? (value.map { [$0] } ?? [])
        return items.compactMap { item -> Line? in
            if let text = item as? String { return clip(text).isEmpty ? nil : Line(text: clip(text)) }
            guard let d = item as? [String: Any], let text = d["text"] as? String, !clip(text).isEmpty else { return nil }
            let source = (d["source"] as? String).map(clip)
            return Line(text: clip(text), source: source?.isEmpty == false ? source : nil)
        }.prefix(maxLines).map { $0 }
    }

    private static func clip(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > maxChars ? String(t.prefix(maxChars)) + "…" : t
    }

    /// The glance as plain lines, for copying and for the transcript's text.
    var plainText: String {
        func line(_ l: Line) -> String { l.source.map { "\(l.text) (\($0))" } ?? l.text }
        var out = headline.isEmpty ? [] : [headline]
        if !why.isEmpty { out += ["Why:"] + why.map { "- " + line($0) } }
        if !todo.isEmpty { out += ["What you can do:"] + todo.map { "- " + line($0) } }
        return out.joined(separator: "\n")
    }
}
