import Foundation

/// One thing a watch's check reported about an item: text, a number, yes or no, a list of texts, or none (JSON null).
/// What counts as right is kept the same way, and both are what an alert shows.
enum WatchListValue: Equatable {
    case text(String)
    case number(Double)
    case flag(Bool)
    case list([String])
    case none

    static let textLimit = 500
    static let listLimit = 50

    /// From what a script returned or the model sent (JSONSerialization types). A list holds texts: numbers and yes or
    /// no in it become text, and a null in it is dropped. An object, or a list holding objects, is kept as its JSON
    /// text, so it is still compared.
    init(json value: Any?) {
        switch value {
        case nil, is NSNull:
            self = .none
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { self = .flag(number.boolValue) }
            else if number.doubleValue.isFinite { self = .number(number.doubleValue) }
            else { self = .text(number.stringValue) }
        case let text as String:
            self = .text(WatchListValue.clip(text, WatchListValue.textLimit))
        case let array as [Any]:
            var texts: [String] = []
            for element in array {
                switch element {
                case is NSNull: continue
                case let text as String: texts.append(WatchListValue.clip(text, 200))
                case let number as NSNumber: texts.append(CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "yes" : "no") : number.stringValue)
                default: self = .text(WatchListValue.jsonText(array, limit: WatchListValue.textLimit)); return
                }
            }
            self = .list(Array(texts.prefix(WatchListValue.listLimit)))
        case let other?:
            self = .text(WatchListValue.jsonText(other, limit: WatchListValue.textLimit))
        }
    }

    /// Back to JSON, for a script's arguments and the chat's summaries: whole numbers as integers.
    var json: Any {
        switch self {
        case .text(let text): return text
        case .number(let number): return number.rounded() == number && abs(number) < 1e15 ? Int(number) as Any : number
        case .flag(let flag): return flag
        case .list(let list): return list
        case .none: return NSNull()
        }
    }

    /// In plain words, as a row or an alert shows it: 12.33, yes, Deal, New, none.
    var words: String {
        switch self {
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "empty" : trimmed
        case .number(let number): return Self.format(number)
        case .flag(let flag): return flag ? "yes" : "no"
        case .list(let list): return list.isEmpty ? "none" : list.joined(separator: ", ")
        case .none: return "none"
        }
    }

    /// The form two values are compared and remembered in: text trimmed; a list trimmed, without repeats and in order;
    /// an empty list as none.
    var normalized: WatchListValue {
        switch self {
        case .text(let text): return .text(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case .list(let list):
            let texts = Set(list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            return texts.isEmpty ? .none : .list(texts.sorted())
        default: return self
        }
    }

    /// Whole numbers without decimals; anything else with at least two, the way prices are written.
    static func format(_ number: Double) -> String {
        if number.rounded() == number, abs(number) < 1e15 { return String(Int(number)) }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    /// Compact JSON, with numbers as written (13.95, not 13.949999999999999).
    static func jsonText(_ value: Any, limit: Int) -> String {
        clip(WatchListJSON.compact(value), limit)
    }
}

extension WatchListValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .none }
        else if let flag = try? container.decode(Bool.self) { self = .flag(flag) }
        else if let number = try? container.decode(Double.self) { self = .number(number) }
        else if let text = try? container.decode(String.self) { self = .text(text) }
        else { self = .list(try container.decode([String].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .number(let number): try container.encode(number)
        case .flag(let flag): try container.encode(flag)
        case .list(let list): try container.encode(list)
        case .none: try container.encodeNil()
        }
    }
}

/// One field that isn't what counts as right: what the check shows now, and what was expected.
struct WatchListDifference: Codable, Equatable {
    var field: String
    var now: WatchListValue
    var expected: WatchListValue
    /// One value was expected among a list the check shows (a badge that should be there), rather than the list itself.
    var includes = false

    init(field: String, now: WatchListValue, expected: WatchListValue, includes: Bool = false) {
        self.field = field
        self.now = now
        self.expected = expected
        self.includes = includes
    }

    /// The earlier single file's keys; latest.json writes `includes` itself.
    private enum CodingKeys: String, CodingKey { case field, now, expected }

    /// "Price: 13.95 — expected 12.33", "Badges: New — expected to include Deal"
    var words: String { "\(WatchListRules.label(field)): \(now.words) — expected \(includes ? "to include " : "")\(expected.words)" }
}

/// What an item's last check said: as expected, not as expected (and how), or that it couldn't check (and why).
enum WatchListStatus: Equatable {
    case asExpected
    case notAsExpected([WatchListDifference])
    case couldNotCheck(String)

    /// Whether this says how the item is, rather than that it couldn't be checked.
    var isVerdict: Bool {
        if case .couldNotCheck = self { return false }
        return true
    }
}

extension WatchListStatus: Codable {
    private enum CodingKeys: String, CodingKey { case kind, differences, reason }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "asExpected": self = .asExpected
        case "notAsExpected": self = .notAsExpected(try container.decodeIfPresent([WatchListDifference].self, forKey: .differences) ?? [])
        default: self = .couldNotCheck(try container.decodeIfPresent(String.self, forKey: .reason) ?? "")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .asExpected:
            try container.encode("asExpected", forKey: .kind)
        case .notAsExpected(let differences):
            try container.encode("notAsExpected", forKey: .kind)
            try container.encode(differences, forKey: .differences)
        case .couldNotCheck(let reason):
            try container.encode("couldNotCheck", forKey: .kind)
            try container.encode(reason, forKey: .reason)
        }
    }
}

/// One watched item: the key exactly as the person gave it (an id or a page address) and what counts as right for it
/// alone, which watch.json and the items file hold; then what its checks found and what the person was last told,
/// which latest.json holds.
struct WatchListItem: Equatable, Identifiable {
    var key: String
    /// What counts as right for this item only, as watch.json says it: over the watch's own `expect`.
    var expect: [String: WatchListValue] = [:]
    /// Its row in the items file, when it has one: what counts as right for it, column by column. Over `expect`.
    var row: [String: WatchListValue]?
    /// Listed in watch.json's `items`. An item only in the items file isn't, and only that file can take it out.
    var listed = true
    var title: String?
    var url: String?
    /// Everything its first check that worked reported: a snapshot of it may count as right. Nil until then.
    var captured: [String: WatchListValue]?
    /// What the latest check that worked said counts as right by default (its `expect`), the weakest of the explicit.
    var checkExpect: [String: WatchListValue]?
    /// What counts as right now, worked out by `WatchListRules.expectations` whenever a check or the watch changes.
    var expected: [String: WatchListValue]?
    /// What its last check that worked reported.
    var state: [String: WatchListValue]?
    /// The rest of what that check returned, as JSON text, for an explanation. Never shown as a cause by itself.
    var facts: String?
    /// What that check said about the item in its own words (`why`): shown as the check wrote it, never by the model.
    var why: [String]?
    var checkedAt: Date?
    var status: WatchListStatus?
    /// Checks in a row that couldn't check.
    var failures = 0
    /// What the person was last told about it, by a notification or by the chat: as expected, or not and how. Only so
    /// the same news isn't repeated; never evidence of a cause.
    var notified: WatchListStatus?
    /// They were told it couldn't be checked; cleared when a check works again.
    var notifiedCouldNotCheck = false

    init(key: String, expect: [String: WatchListValue] = [:]) {
        self.key = key
        self.expect = expect
    }

    var id: String { key }

    /// What counts as right for this item alone: watch.json's, with its row in the items file over it.
    var ownExpect: [String: WatchListValue] { expect.merging(row ?? [:]) { _, row in row } }

    /// What the check said in its own words, while its latest check says how the item is. A check that failed has
    /// nothing to say: an earlier check's words are never shown in its place.
    var whyNow: [String] {
        guard status?.isVerdict == true else { return [] }
        return why ?? []
    }

    /// Its title from the check, or the key as given.
    var label: String {
        let title = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? key : title
    }

    /// The page to open: the check's address for it, or the key when the person gave a page address.
    var pageURL: String? {
        if let url, !url.isEmpty { return url }
        return key.lowercased().hasPrefix("http://") || key.lowercased().hasPrefix("https://") ? key : nil
    }

    /// Fields that count, or that the person named, but that the latest check didn't report: shown, never alerted on.
    /// Nothing when it failed. Names match the check's own loosely (see `WatchListRules.field`).
    func unreported(named fields: [String]? = nil) -> [String] {
        guard let state, status?.isVerdict == true else { return [] }
        let reported = Set(state.keys)
        let counted = Set(expected?.keys.map { $0 } ?? []).union(fields ?? [])
        return counted.filter { WatchListRules.field(for: $0, in: reported) == nil }.sorted()
    }

    /// Red and grey rows have something to explain.
    var needsExplaining: Bool {
        switch status {
        case .notAsExpected?, .couldNotCheck?: return true
        default: return false
        }
    }

    var isRed: Bool {
        if case .notAsExpected? = status { return true }
        return false
    }
}

/// The earlier single `watch-list.json`, read once to move its watches into folders (`WatchListStore`), and written by
/// tests to stand in for it. Folders use `WatchListFiles` instead.
extension WatchListItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case key, title, url, expected, state, facts, checkedAt, status, failures, notified, notifiedCouldNotCheck
    }

    /// Fields a later version adds are optional here, so an older file always opens.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        expected = try container.decodeIfPresent([String: WatchListValue].self, forKey: .expected)
        state = try container.decodeIfPresent([String: WatchListValue].self, forKey: .state)
        facts = try container.decodeIfPresent(String.self, forKey: .facts)
        checkedAt = try container.decodeIfPresent(Date.self, forKey: .checkedAt)
        status = try container.decodeIfPresent(WatchListStatus.self, forKey: .status)
        failures = try container.decodeIfPresent(Int.self, forKey: .failures) ?? 0
        notified = try container.decodeIfPresent(WatchListStatus.self, forKey: .notified)
        notifiedCouldNotCheck = try container.decodeIfPresent(Bool.self, forKey: .notifiedCouldNotCheck) ?? false
    }
}

/// Whose a watch is: yours, in `watches/` in Noteling's folder, or your team's, in the linked tools' `watches/`, which
/// Noteling only reads and checks once you turn it on.
enum WatchListSource: Hashable {
    case own, team
}

/// A list of items checked together on a schedule: by the pack's `watch:` script, or by the watch's own check.py.
struct WatchListWatch: Equatable, Identifiable {
    var id = UUID()
    var source = WatchListSource.own
    /// Its folder under `watches/`, e.g. `holiday/oct/fashion`: a team job's id.
    var path = ""
    /// A team job is checked only once the person turns it on; a watch of their own always is.
    var on = true
    var name: String
    /// The check: a pack script's tool name, e.g. shop__watch_item. A check.py in the watch's folder is used instead.
    var check: String
    var items: [WatchListItem]
    /// Extra arguments the person gave for the check, e.g. a zip code. Passed only if the script declares them.
    var args: [String: WatchListValue] = [:]
    /// Only these state fields count; nil counts every field the check reports.
    var fields: [String]?
    /// What counts as right for every item, as the person said it. Overrides what a first check finds.
    var expect: [String: WatchListValue] = [:]
    var everyMinutes = WatchListWatch.defaultMinutes
    var paused = false
    var createdAt = Date()
    /// The secrets its own check.py gets, by the names packs use. A pack's check gets the pack's own instead.
    var requires: [String] = []
    /// No checks or notifications before it starts or after it ends.
    var starts: WatchListMoment?
    var ends: WatchListMoment?
    /// Its items file (items.psv, .csv or .tsv), when it has one, as last read.
    var file: WatchListItemsFile?
    /// Something to know about its files, e.g. that there are two items files and which one is used.
    var fileNote: String?
    var lastRunAt: Date?

    static let defaultMinutes = 15
    static let minimumMinutes = 5
    static let maximumMinutes = 240

    init(id: UUID = UUID(), name: String, check: String, items: [WatchListItem], args: [String: WatchListValue] = [:],
         fields: [String]? = nil, expect: [String: WatchListValue] = [:], everyMinutes: Int = WatchListWatch.defaultMinutes,
         paused: Bool = false, createdAt: Date = Date(), requires: [String] = [], lastRunAt: Date? = nil) {
        self.id = id
        self.name = name
        self.check = check
        self.items = items
        self.args = args
        self.fields = fields
        self.expect = expect
        self.everyMinutes = WatchListWatch.clamp(everyMinutes)
        self.paused = paused
        self.createdAt = createdAt
        self.requires = requires
        self.lastRunAt = lastRunAt
    }

    static func clamp(_ minutes: Int) -> Int { min(maximumMinutes, max(minimumMinutes, minutes)) }

    /// "every 15 minutes", "every hour", "every 2 hours"
    var everyWords: String {
        if everyMinutes % 60 == 0 { return everyMinutes == 60 ? "every hour" : "every \(everyMinutes / 60) hours" }
        return "every \(everyMinutes) minutes"
    }

    func item(_ key: String) -> WatchListItem? { items.first { $0.key == key } }

    var isTeam: Bool { source == .team }

    /// Whether it is checked at `now`: on, not paused, and between its start and end, if it has them.
    func checking(at now: Date) -> Bool {
        on && !paused && !notStarted(at: now) && !ended(at: now)
    }

    func notStarted(at now: Date) -> Bool { starts.map { now < $0.date } ?? false }
    func ended(at now: Date) -> Bool { ends.map { now > $0.date } ?? false }

    /// What it needs to work out what counts as right for each item. A watch is explicit as soon as anything says what
    /// counts as right: an items file, its own `expect`, an item's, or a check's.
    var terms: WatchListTerms {
        WatchListTerms(fields: fields, expect: expect,
                       explicit: file != nil || !expect.isEmpty || items.contains { !$0.ownExpect.isEmpty || !($0.checkExpect ?? [:]).isEmpty })
    }

    /// What its watch.json holds: the items listed there, not those only in its items file.
    var definition: WatchListDefinition {
        WatchListDefinition(id: id, name: name, check: check, items: items.filter(\.listed).map { .init(key: $0.key, expect: $0.expect) },
                            args: args, fields: fields, expect: expect, everyMinutes: everyMinutes, paused: paused, createdAt: createdAt,
                            requires: requires, starts: starts, ends: ends)
    }

    /// Takes in a definition (a watch.json changed by hand, or a change from the chat) and its items file: the file's
    /// items come first, then those listed in watch.json that it doesn't hold. Items keep what their checks found, by
    /// key; new items start unchecked; and what counts as right is worked out again for every item. `quiet` when the
    /// person sees the result where they made the change. The watch keeps its id.
    mutating func adopt(_ definition: WatchListDefinition, file: WatchListItemsFile?, quiet: Bool) {
        name = definition.name
        check = definition.check
        args = definition.args
        fields = definition.fields
        expect = definition.expect
        everyMinutes = WatchListWatch.clamp(definition.everyMinutes)
        paused = definition.paused
        createdAt = definition.createdAt
        requires = definition.requires
        starts = definition.starts
        ends = definition.ends
        self.file = file
        let earlier = Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let listed = Dictionary(definition.items.map { ($0.key, $0.expect) }, uniquingKeysWith: { first, _ in first })
        var keys = file?.rows.map(\.key) ?? []
        keys += definition.items.map(\.key).filter { !keys.contains($0) }
        let rows = Dictionary((file?.rows ?? []).map { ($0.key, $0.expect) }, uniquingKeysWith: { first, _ in first })
        items = keys.map { key in
            var item = earlier[key] ?? WatchListItem(key: key)
            item.expect = listed[key] ?? [:]
            item.row = rows[key]
            item.listed = listed[key] != nil
            return item
        }
        let terms = self.terms
        for index in items.indices { WatchListRules.refresh(&items[index], terms: terms, quiet: quiet) }
    }

    /// Works out again what counts as right for every item, after the watch's terms changed.
    mutating func reexpect(quiet: Bool) {
        let terms = self.terms
        for index in items.indices { WatchListRules.refresh(&items[index], terms: terms, quiet: quiet) }
    }
}

/// What a watch's items need to work out what counts as right: the fields it names, its own `expect`, and whether
/// anything says what counts as right explicitly.
struct WatchListTerms: Equatable {
    var fields: [String]?
    var expect: [String: WatchListValue] = [:]
    var explicit = false
}

/// A moment as watch.json gives it (`starts`, `ends`): ISO 8601, with an offset or in the Mac's own time, kept as written.
struct WatchListMoment: Equatable {
    var text: String
    var date: Date

    /// "2026-10-05T00:00:00-04:00", "2026-10-05T00:00:00Z", "2026-10-05T00:00" or "2026-10-05" (this Mac's time).
    static func parse(_ text: String) -> WatchListMoment? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let offset = trimmed.replacingOccurrences(of: #"([+-]\d{2})(\d{2})$"#, with: "$1:$2", options: .regularExpression)
            .replacingOccurrences(of: #"(T\d{2}:\d{2})(Z|[+-]\d{2}:\d{2})$"#, with: "$1:00$2", options: .regularExpression)
        if let date = try? CalendarSubmission.timestamp(offset) { return WatchListMoment(text: trimmed, date: date) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        let plain = trimmed.replacingOccurrences(of: #"\.\d+$"#, with: "", options: .regularExpression)
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: plain) { return WatchListMoment(text: trimmed, date: date) }
        }
        return nil
    }

    /// "Mon Oct 5, 12:00 AM", in this Mac's time.
    var words: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

/// A watch's items file: a header row, then one item per row, its first column the item and each other column a field
/// of the check's `state`, with what counts as right for that item in it.
struct WatchListItemsFile: Equatable {
    struct Row: Equatable {
        var key: String
        var expect: [String: WatchListValue]
    }

    /// items.psv, items.csv or items.tsv.
    var name: String
    /// The headers after the first, as written.
    var columns: [String]
    var rows: [Row]
    /// Rows left out, in plain words: "row 7 has no item", "row 9 repeats 123".
    var skipped: [String] = []
}

/// A watch as its watch.json says it: what to check, what counts as right and how often; not what the checks found.
struct WatchListDefinition: Equatable {
    struct Item: Equatable {
        var key: String
        var expect: [String: WatchListValue] = [:]
    }

    var id: UUID
    var name: String
    var check: String
    var items: [Item]
    var args: [String: WatchListValue] = [:]
    var fields: [String]?
    var expect: [String: WatchListValue] = [:]
    var everyMinutes = WatchListWatch.defaultMinutes
    var paused = false
    var createdAt: Date
    var requires: [String] = []
    var starts: WatchListMoment?
    var ends: WatchListMoment?
    /// Keys a person added that Noteling doesn't use, kept as they wrote them (compact JSON) when it writes the file.
    var other: String?

    /// The same definition, apart from the id and the keys Noteling doesn't use.
    func sameSettings(as other: WatchListDefinition) -> Bool {
        var a = self, b = other
        a.id = b.id
        a.other = nil
        b.other = nil
        return a == b
    }
}

extension WatchListWatch: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, check, items, args, fields, expect, everyMinutes, paused, createdAt, lastRunAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        check = try container.decode(String.self, forKey: .check)
        items = try container.decodeIfPresent([WatchListItem].self, forKey: .items) ?? []
        args = try container.decodeIfPresent([String: WatchListValue].self, forKey: .args) ?? [:]
        fields = try container.decodeIfPresent([String].self, forKey: .fields)
        expect = try container.decodeIfPresent([String: WatchListValue].self, forKey: .expect) ?? [:]
        everyMinutes = WatchListWatch.clamp(try container.decodeIfPresent(Int.self, forKey: .everyMinutes) ?? WatchListWatch.defaultMinutes)
        paused = try container.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastRunAt = try container.decodeIfPresent(Date.self, forKey: .lastRunAt)
    }
}

/// What one check of one item found, or why it couldn't check.
enum WatchListOutcome: Equatable {
    case checked(WatchListReading)
    case failed(String)
}

/// What a check script returned for one item.
struct WatchListReading: Equatable {
    var title: String?
    var url: String?
    var state: [String: WatchListValue]
    var facts: String?
    /// The check's own words about the item, when it said something.
    var why: [String]?
    /// What the check says counts as right for the item by default, e.g. no problems and in stock.
    var expect: [String: WatchListValue]?

    init(title: String?, url: String?, state: [String: WatchListValue], facts: String?, why: [String]? = nil,
         expect: [String: WatchListValue]? = nil) {
        self.title = title
        self.url = url
        self.state = state
        self.facts = facts
        self.why = why
        self.expect = expect
    }

    static let fieldLimit = 40
    static let factsLimit = 8_000
    static let whyLimit = 5
    static let whyLineLimit = 300

    /// A check's return value: `title`, optional `url`, `state` (an object of flat fields), optional `facts` and an
    /// optional `why` (a short string, or a list of them). An `error`, or no `state` object, means it couldn't check.
    static func parse(_ value: Any?) -> WatchListOutcome {
        guard let object = value as? [String: Any] else { return .failed("The check didn't return what it found.") }
        if let error = object["error"], !(error is NSNull), !"\(error)".trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failed(WatchListRules.reason(error as? String ?? WatchListValue.jsonText(error, limit: 300)))
        }
        guard let raw = object["state"] as? [String: Any] else { return .failed("The check didn't say what it found (no state).") }
        var state: [String: WatchListValue] = [:]
        for key in raw.keys.sorted() {
            let field = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !field.isEmpty, state.count < fieldLimit else { continue }
            state[field] = WatchListValue(json: raw[key])
        }
        func text(_ key: String, _ limit: Int) -> String? {
            let value: String?
            if let string = object[key] as? String { value = string }
            else if let number = object[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { value = number.stringValue }
            else { value = nil }
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : WatchListValue.clip(trimmed, limit)
        }
        let facts = object["facts"].flatMap { $0 is NSNull ? nil : WatchListValue.jsonText($0, limit: factsLimit) }
        var expect: [String: WatchListValue]?
        if let raw = object["expect"] as? [String: Any] {
            var values: [String: WatchListValue] = [:]
            for key in raw.keys.sorted() {
                let field = key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !field.isEmpty, values.count < fieldLimit else { continue }
                values[field] = WatchListValue(json: raw[key])
            }
            expect = values.isEmpty ? nil : values
        }
        return .checked(WatchListReading(title: text("title", 300), url: text("url", 2_000), state: state, facts: facts,
                                         why: whyLines(object["why"]), expect: expect))
    }

    /// `why` as the check wrote it: a string or a list of strings, each trimmed and kept short; nil when it said nothing.
    static func whyLines(_ value: Any?) -> [String]? {
        let raw: [Any]
        switch value {
        case let text as String: raw = [text]
        case let list as [Any]: raw = list
        default: return nil
        }
        let lines = raw.compactMap { entry -> String? in
            guard let text = entry as? String else { return nil }
            let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? nil : WatchListValue.clip(line, whyLineLimit)
        }
        return lines.isEmpty ? nil : Array(lines.prefix(whyLimit))
    }

    /// What a list check returned for all its items: a list of per-item results in the items' order, or an object of
    /// per-item results keyed by item. A list of another length can't be matched to the items, so every item is "couldn't
    /// check"; with an object, an item it has no result for is "couldn't check", and a key that is no item is left out.
    /// An `error` for the whole run, or anything else, is "couldn't check" for every item, with the run's reason.
    static func parseList(_ value: Any?, keys: [String]) -> [String: WatchListOutcome] {
        func all(_ reason: String) -> [String: WatchListOutcome] {
            Dictionary(keys.map { ($0, .failed(reason)) }, uniquingKeysWith: { first, _ in first })
        }
        func one(_ entry: Any?) -> WatchListOutcome {
            if entry == nil || entry is NSNull { return .failed("The check returned nothing for this item.") }
            guard entry is [String: Any] else { return .failed("The check's result for this item isn't an object with a state.") }
            return parse(entry)
        }
        if let list = value as? [Any] {
            guard list.count == keys.count else {
                return all("The check returned \(list.count) result\(list.count == 1 ? "" : "s") for \(keys.count) item\(keys.count == 1 ? "" : "s"), "
                    + "so they can't be matched to the items in order.")
            }
            return Dictionary(zip(keys, list).map { ($0, one($1)) }, uniquingKeysWith: { first, _ in first })
        }
        guard let object = value as? [String: Any] else {
            return all("The check didn't return a list of results, or results keyed by item.")
        }
        let wanted = Set(keys)
        if !wanted.contains("error"), let error = object["error"], !(error is NSNull) {
            return all(WatchListRules.reason(error as? String ?? WatchListValue.jsonText(error, limit: 300)))
        }
        if !wanted.contains("state"), object["state"] != nil, object.keys.allSatisfy({ !wanted.contains($0) }) {
            return all("The check returned one result, not one for each item.")
        }
        let others = object.keys.filter { !wanted.contains($0) }.sorted()
        let hint = others.isEmpty ? "" : " It returned results for " + WatchListValue.clip(others.prefix(5).joined(separator: ", "), 200)
            + (others.count > 5 ? " and \(others.count - 5) more" : "") + "."
        var outcomes: [String: WatchListOutcome] = [:]
        for key in keys where outcomes[key] == nil {
            outcomes[key] = object.keys.contains(key) ? one(object[key]) : .failed("The check returned nothing for this item." + hint)
        }
        return outcomes
    }
}

/// What to tell the person about one item, or about several items of a watch that couldn't be checked for one reason.
struct WatchListAlert: Equatable {
    enum Kind: Equatable {
        case notAsExpected([WatchListDifference])
        case backToExpected
        case couldNotCheck(String)
        /// How many items, and why.
        case couldNotCheckItems(Int, String)
    }

    var watchID: UUID
    var watchName: String
    /// The item, or empty when the alert is about several items.
    var itemKey: String
    /// The item's title (or its key), or the watch's name when the alert is about several items.
    var title: String
    var kind: Kind
    /// What the check said about the item in its own words, if anything.
    var why: [String] = []

    /// In plain words: one line per difference, "Back to what you expected", or why it couldn't check. Then, when the
    /// check said why in its own words, its first reason: the difference comes first, since a notification shows little.
    var body: String {
        switch kind {
        case .notAsExpected(let differences): return (differences.map(\.words) + WatchListRules.notificationLines(why)).joined(separator: "\n")
        case .backToExpected: return (["Back to what you expected"] + WatchListRules.notificationLines(why)).joined(separator: "\n")
        case .couldNotCheck(let reason): return "Couldn't check: \(reason)"
        case .couldNotCheckItems(let count, let reason): return "Couldn't check \(count) items: \(reason)"
        }
    }
}

struct WatchListError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
