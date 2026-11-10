import Foundation

/// Pages of a kind: a page's key with the parts of its address that name one item, record or person made `*`, so a
/// hint about what every item page has (what the price block means) is met on every item page, not only the one it
/// was left on. Worked out from the address by code, shown on the hint's paper as `/ip/*/*` to read and change, and
/// kept with the hint as text. Whether a page is of the kind is a comparison of strings: no model, nothing leaves
/// the Mac, and it costs nothing on arrival.
struct PagePattern: Hashable, Codable, CustomStringConvertible {
    /// As the key has it: lowercased, with its port when it has one.
    var host: String
    /// The key's path with `*` for a segment that names one thing; a `#/route` stays part of it.
    var path: String
    /// The parameters that name the kind of page, such as ServiceNow's portal page id; a record's sys_id is not one.
    var query: [String: String] = [:]

    /// `walmart.com/ip/*/*`, or `example.service-now.com/sp?id=sc_cat_item`.
    var description: String { host + pathAndQuery }

    /// The part after the host, as the paper shows it: `/ip/*/*`.
    var pathAndQuery: String {
        path + (query.isEmpty ? "" : "?" + query.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&"))
    }

    /// Whether it takes in more than one page.
    var isWide: Bool { Self.segments(of: path).contains("*") }

    init(host: String, path: String, query: [String: String] = [:]) {
        self.host = host
        self.path = path
        self.query = query
    }

    /// The key itself, as a pattern that takes in that one page.
    static func exact(_ key: PageKey) -> PagePattern { PagePattern(host: key.host, path: key.path, query: key.query) }

    /// The kind of page a key suggests: a segment that looks generated (an id, a hash, a slug made from a title)
    /// becomes `*`, and a parameter whose value names one record goes.
    static func of(_ key: PageKey) -> PagePattern {
        let (plain, route) = split(key.path)
        var out = wildcards(plain)
        if let route { out += "#" + wildcards(route) }
        return PagePattern(host: key.host, path: out, query: key.query.filter { !looksGenerated($0.value) })
    }

    /// From the text kept with a hint, or typed on its paper: `host/path?query`, or with `host` given, the part after
    /// the host alone. Nil when there is no host or the text is empty.
    init?(_ text: String, host given: String? = nil) {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        guard !text.isEmpty else { return nil }
        var host: String, rest: String
        if let given {
            // The paper shows the part after the host; a whole address pasted there is taken as one too.
            host = given
            rest = text.lowercased().hasPrefix(given.lowercased()) ? String(text.dropFirst(given.count)) : text
            if rest.isEmpty { rest = "/" }
        } else if let slash = text.firstIndex(where: { $0 == "/" || $0 == "?" }) {
            host = String(text[..<slash])
            rest = String(text[slash...])
        } else {
            host = text
            rest = "/"
        }
        host = host.lowercased()
        guard !host.isEmpty, !host.contains(" ") else { return nil }
        var query: [String: String] = [:]
        if let mark = rest.firstIndex(of: "?") {
            for pair in rest[rest.index(after: mark)...].split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard let name = parts.first?.lowercased(), !name.isEmpty else { continue }
                query[name] = parts.count > 1 ? parts[1] : ""
            }
            rest = String(rest[..<mark])
        }
        self.host = host
        self.path = Self.normalized(rest)
        self.query = query
    }

    /// Whether the key is a page of this kind: the same host, segment for segment the same or `*`, and every
    /// parameter the kind names.
    func matches(_ key: PageKey) -> Bool {
        guard host == key.host else { return false }
        let mine = Self.segments(of: path), theirs = Self.segments(of: key.path)
        guard mine.count == theirs.count else { return false }
        for (a, b) in zip(mine, theirs) where a != "*" && a != b { return false }
        for (name, value) in query where key.query[name] != value { return false }
        return true
    }

    // MARK: what names one thing

    /// A segment that names one item, record or person rather than a kind of page: digits, a hash, a token.
    static func looksGenerated(_ segment: String) -> Bool {
        let s = segment
        if s.isEmpty { return false }
        if s.allSatisfy(\.isNumber) { return true }
        if s.range(of: #"^[0-9a-f]{8,}$"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        if s.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        if s.range(of: #"\d{3,}"#, options: .regularExpression) != nil { return true }
        if s.count >= 6, s.filter(\.isNumber).count >= 2 { return true }
        if s.contains(where: { "%@~=+".contains($0) }) { return true }
        return s.count >= 32
    }

    /// A segment that looks like a title made into an address (`great-value-whole-milk-gallon`): many words, or long.
    static func looksLikeASlug(_ segment: String) -> Bool {
        let joins = segment.filter { $0 == "-" || $0 == "_" }.count
        return joins >= 3 || (joins >= 1 && segment.count >= 24)
    }

    /// The path with `*` where a segment names one thing: by its own look, or by being a hyphenated name beside an
    /// id, the `<slug>/<id>` and `<id>/<slug>` shapes shops and forums give an item's page.
    private static func wildcards(_ path: String) -> String {
        let parts = segments(of: path)
        guard !parts.isEmpty else { return "/" }
        let strong = parts.map(looksGenerated)
        var out: [String] = []
        for (index, part) in parts.enumerated() {
            let besideAnID = (index > 0 && strong[index - 1]) || (index + 1 < parts.count && strong[index + 1])
            let hyphenated = part.contains("-") || part.contains("_")
            let generated = strong[index] || looksLikeASlug(part) || (besideAnID && hyphenated)
            out.append(generated ? "*" : part)
        }
        return "/" + out.joined(separator: "/")
    }

    /// A key's path and the `#/route` it carries, when it does.
    private static func split(_ path: String) -> (String, String?) {
        guard let hash = path.firstIndex(of: "#") else { return (path, nil) }
        return (String(path[..<hash]), String(path[path.index(after: hash)...]))
    }

    /// The segments of a path, a `#/route`'s as well, with the `#` as a segment of its own so a route is matched as
    /// the route it is.
    static func segments(of path: String) -> [String] {
        path.replacingOccurrences(of: "#", with: "/#/").split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    /// A typed path, tidied: a leading slash, no run of slashes, no trailing slash but the root's.
    private static func normalized(_ typed: String) -> String {
        var path = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.hasPrefix("/") { path = "/" + path }
        while path.contains("//") { path = path.replacingOccurrences(of: "//", with: "/") }
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
