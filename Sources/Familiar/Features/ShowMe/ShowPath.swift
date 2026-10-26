import Foundation

/// A way through an app that someone showed Noteling with Watch Me, kept beside the how-to written from it, so the next
/// person can be shown it on their own screen: each click's control as the app names it, where it was, and one line to
/// say. Kept as `paths/<workflow>.json` in the pack.
struct ShowPath: Codable, Equatable {
    var title: String
    /// yyyy-MM-dd, the day it was shown.
    var recorded: String?
    var steps: [ShowStep]

    /// "Account and access → Agent tokens → Create token"
    var route: String { steps.map { $0.label ?? $0.say }.joined(separator: " → ") }

    /// Where the first step was shown: the window's title and the page's address, for "start on …".
    var start: String? {
        guard let first = steps.first else { return nil }
        let place = [first.title.map { "“\($0)”" }, first.url.map { PageWalk.safeAddress($0) }].compactMap { $0 }
        return place.isEmpty ? nil : place.joined(separator: " at ")
    }

    /// The way without the trip there. A recording often starts where the person was, on a search engine or a blank
    /// tab, and the clicks that got them to the tool teach nothing: the tour opens the page the way starts on. So the
    /// leading steps on the trip go, up to the first on the tool, which is wherever the last step is; never all of them.
    var withoutTheWayThere: ShowPath {
        let tool = steps.last?.host
        guard let first = steps.firstIndex(where: { !$0.isOnTheWayThere || $0.host == tool }), first > 0 else { return self }
        var path = self
        path.steps = Array(steps[first...])
        return path
    }
}

extension ShowStep {
    /// Browsers, by the name a recording gives an app.
    static let browsers: Set<String> = ["Google Chrome", "Google Chrome Canary", "Safari", "Microsoft Edge", "Arc",
                                        "Brave Browser", "Firefox", "Vivaldi", "Opera"]
    /// Where people search from. Google is any google.<country>.
    static let searchHosts = ["bing.com", "duckduckgo.com", "search.yahoo.com", "ecosia.org", "startpage.com", "search.brave.com",
                              "yandex.com", "yandex.ru", "baidu.com", "kagi.com", "perplexity.ai"]

    /// The page's host, lowercased and without "www.".
    var host: String? {
        guard let url, var host = URLComponents(string: url)?.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// A click on the trip to the tool rather than in it: on a search engine, on a sign-in or another page everyone
    /// passes through, or in a browser showing no web page (a new tab, the browser's own pages).
    var isOnTheWayThere: Bool {
        guard let url, let components = URLComponents(string: url), let scheme = components.scheme?.lowercased() else {
            return app.map { Self.browsers.contains($0) } ?? false
        }
        guard ["http", "https", "file"].contains(scheme) else { return true }
        guard let host else { return true }
        if host.range(of: #"^google\.[a-z.]+$"#, options: .regularExpression) != nil { return true }
        if Self.searchHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        return WatchSummarizer.isGenericHost(host)
    }
}

struct ShowStep: Codable, Equatable {
    /// What to tell the person, in the app's words: "Open Account and access".
    var say: String
    /// The control: its Accessibility role ("AXButton"), its name as shown, and the page's own id for it.
    var role: String?
    var label: String?
    var domID: String?
    /// Where it was: the app, the window's title and the page's address when it was shown.
    var app: String?
    var title: String?
    var url: String?
    /// Its frame as fractions of its window (x, y, w, h, top-left origin): a last resort for a control without a name.
    var rect: [Double]?

    /// The name to look for and to say: the label, else the instruction.
    var name: String { label ?? say }
}

extension ShowPath {
    /// The path through a recording: the clicks the write-up picked, in its order, each with its line, as recorded.
    /// Without picks it is every click on a named control, so a write-up that leaves the path out still keeps one.
    static func from(recording: Recording, picks: [(event: Int, say: String)], title: String, recorded: String?) -> ShowPath? {
        let clicks = Dictionary(recording.events.filter { $0.kind == "click" }.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
        var steps: [ShowStep] = []
        if picks.isEmpty {
            for e in recording.events where e.kind == "click" {
                guard let label = e.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else { continue }
                if let last = steps.last, last.label == label, last.url == e.url.map(PageWalk.safeAddress) { continue }   // a double click, or a click again
                steps.append(step(e, say: "Click “\(label)”"))
            }
        } else {
            for pick in picks {
                guard let e = clicks[pick.event] else { continue }
                let say = pick.say.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = e.label.map { "Click “\($0)”" } ?? "Click here"
                steps.append(step(e, say: say.isEmpty ? fallback : String(say.prefix(80))))
            }
        }
        // A step must be findable again: by its name, by the page's id for it, or by where it was.
        steps = steps.filter { $0.label != nil || $0.domID != nil || $0.rect != nil }
        guard !steps.isEmpty else { return nil }
        var path = ShowPath(title: title, recorded: recorded, steps: steps).withoutTheWayThere
        path.steps = Array(path.steps.prefix(Self.maxSteps))
        return path
    }

    static let maxSteps = 12

    /// The write-up's picks with the clicks it names in its steps but left out of its path put back, in event order.
    /// A click that opens a menu or reveals the next control is part of the way although the page didn't change, and
    /// a write-up that says "click **Search**" has named it. Only clicks between the first and the last pick count
    /// (the trip there and anything after the task stay out), never a click into a field to type in it, and a click
    /// again on the same control on the same page is one step. Returns the picks and which were put back.
    static func complete(_ picks: [(event: Int, say: String)], from markdown: String, recording: Recording)
        -> (picks: [(event: Int, say: String)], added: [Int]) {
        guard let first = picks.map(\.event).min(), let last = picks.map(\.event).max() else { return (picks, []) }
        let named = Set(bold(in: markdown).compactMap { NoteAnchor.norm($0) })
        guard !named.isEmpty else { return (picks, []) }
        let picked = Set(picks.map(\.event))
        let clicks = Dictionary(recording.events.filter { $0.kind == "click" }.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
        var added: [Int] = []
        for e in recording.events where e.kind == "click" && e.index > first && e.index < last && !picked.contains(e.index) {
            guard let label = NoteAnchor.norm(e.label), named.contains(label), !PageWalk.editable.contains(e.axRole ?? "") else { continue }
            added.append(e.index)
        }
        guard !added.isEmpty else { return (picks, []) }
        let all = (picks + added.map { (event: $0, say: "") }).sorted { $0.event < $1.event }
        var kept: [(event: Int, say: String)] = []
        for pick in all {
            if added.contains(pick.event), let e = clicks[pick.event], let previous = kept.last.flatMap({ clicks[$0.event] }),
               previous.label == e.label, previous.url == e.url { continue }
            kept.append(pick)
        }
        return (kept, added.filter { index in kept.contains { $0.event == index } })
    }

    /// The bold phrases in a write-up: the labels it tells the reader to click.
    static func bold(in markdown: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"\*\*([^*\n]{1,60}?)\*\*"#) else { return [] }
        return re.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)).compactMap {
            Range($0.range(at: 1), in: markdown).map { String(markdown[$0]).trimmingCharacters(in: .whitespaces) }
        }
    }

    /// The local day of a recording's start, which is written in UTC: an evening recording in California is still
    /// the day it was made there.
    static func day(of startedAt: String, in zone: TimeZone = .current) -> String? {
        guard let date = ISO8601DateFormatter().date(from: startedAt) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = zone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    private static func step(_ e: WatchEvent, say: String) -> ShowStep {
        ShowStep(say: say, role: e.axRole, label: e.label.flatMap { $0.isEmpty ? nil : $0 }, domID: e.domID,
                 app: e.app, title: e.title, url: e.url.map(PageWalk.safeAddress), rect: e.rect)
    }

    /// Which part of the path to show: `from` and `until` are 1-based and inclusive, as the model names steps.
    func slice(from: Int?, until: Int?) -> ShowPath {
        let lower = min(max(1, from ?? 1), steps.count)
        let upper = max(lower, min(steps.count, until ?? steps.count))   // "until 0" still shows where it starts
        guard lower >= 1 else { return self }
        var part = self
        part.steps = Array(steps[(lower - 1)...(upper - 1)])
        return part
    }
}

/// The paths a pack keeps, `paths/<slug>.json`, by slug.
enum ShowPathStore {
    static let folder = "paths"

    static func load(packDir: URL) -> [String: ShowPath] {
        let dir = packDir.appendingPathComponent(folder)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [:] }
        var out: [String: ShowPath] = [:]
        for name in names where name.hasSuffix(".json") {
            let url = dir.appendingPathComponent(name)
            // A way kept before the trip there was left out still loses it when read back.
            do { out[String(name.dropLast(5))] = try JSONDecoder().decode(ShowPath.self, from: Data(contentsOf: url)).withoutTheWayThere }
            catch { Log.info("show: cannot read \(url.path): \(error.localizedDescription)") }
        }
        return out
    }

    static func write(_ path: ShowPath, slug: String, packDir: URL) throws -> URL {
        let dir = packDir.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(slug).json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(path).write(to: url, options: .atomic)
        return url
    }
}
