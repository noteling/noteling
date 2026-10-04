import Foundation

/// `noteling.json` at the root of the team's linked tools: settings a team makes for everyone who links its tools. For
/// now only `claude`, the connection to Claude, such as a company gateway:
///
///     {"claude": {"baseURL": "https://llm-gateway.example.com", "headers": {"X-Consumer-Id": "abc", "X-Api-Key": "$GATEWAY_KEY"},
///                 "model": "claude-opus-5", "effort": "medium"}}
///
/// The name is reserved at the repository's root. While the tools are linked, what the file sets wins over each
/// person's own settings (`Config.applying`), and is never written into their config.json.
struct TeamSettings: Equatable {
    static let fileName = "noteling.json"
    static let efforts = ["low", "medium", "high", "xhigh", "max"]

    /// What the team sets for the connection to Claude. A field it leaves out (nil) stays each person's own.
    struct Claude: Codable, Equatable {
        var baseURL: String?
        var headers: [String: String]?   // values as written: `$NAME` is a secret, read when the client is built
        var model: String?
        var effort: String?

        var isEmpty: Bool { baseURL == nil && headers == nil && model == nil && effort == nil }
        /// The gateway's host, as Settings and the log name it.
        var host: String? { baseURL.flatMap { URLComponents(string: $0)?.host } }
    }

    var claude = Claude()
    /// Keys Noteling doesn't use ("theme", "claude.timeout"): ignored, and listed in Settings.
    var ignored: [String] = []
    /// What the file asks for that Noteling doesn't do as written, one sentence each, naming headers but never their values.
    var notes: [String] = []

    /// Reads the file, or says in plain words why it can't be used: anything but JSON of the right shape changes nothing.
    static func parse(_ data: Data) throws -> TeamSettings {
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) } catch {
            throw TeamSettingsError("It isn't valid JSON\(location(of: error)). Check its brackets, commas and quotes.")
        }
        guard let top = object as? [String: Any] else { throw TeamSettingsError("It must be one JSON object, { … }.") }
        var settings = TeamSettings()
        settings.ignored = top.keys.filter { $0 != "claude" }.sorted()
        guard let raw = top["claude"], !(raw is NSNull) else { return settings }
        guard let claude = raw as? [String: Any] else { throw TeamSettingsError("claude must be an object, { … }.") }
        let known = ["baseURL", "headers", "model", "effort"]
        settings.ignored += claude.keys.filter { !known.contains($0) }.sorted().map { "claude.\($0)" }

        func text(_ key: String) throws -> String? {
            guard let raw = claude[key], !(raw is NSNull) else { return nil }
            guard let value = raw as? String else { throw TeamSettingsError("claude.\(key) must be text in quotes.") }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let url = try text("baseURL") {
            guard let parts = URLComponents(string: url), let scheme = parts.scheme?.lowercased(), let host = parts.host, !host.isEmpty,
                  scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())),
                  parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
                throw TeamSettingsError("claude.baseURL must be a web address that starts with https://, like https://llm-gateway.example.com, with nothing after a ? or #.")
            }
            settings.claude.baseURL = url
            let path = parts.path.hasSuffix("/") ? String(parts.path.dropLast()) : parts.path
            if path.lowercased().hasSuffix("/v1") {
                settings.notes.append("claude.baseURL ends in /v1. Noteling adds /v1/messages itself, as Anthropic's SDKs do, so requests go to …/v1/v1/messages. Leave /v1 off unless the gateway expects that.")
            }
        }
        settings.claude.model = try text("model")
        if let effort = try text("effort") {
            guard efforts.contains(effort) else { throw TeamSettingsError("claude.effort must be low, medium, high, xhigh or max.") }
            settings.claude.effort = effort
        }
        if let raw = claude["headers"], !(raw is NSNull) {
            guard let headers = raw as? [String: Any] else {
                throw TeamSettingsError("claude.headers must be an object of header names and values, { \"X-Consumer-Id\": \"…\" }.")
            }
            var kept: [String: String] = [:]
            for name in headers.keys.sorted() {
                guard let value = headers[name] as? String else { throw TeamSettingsError("The \(name) header's value must be text in quotes.") }
                if let refusal = GatewayHeaders.refusal(name: name, value: value) { settings.notes.append(refusal); continue }
                if let same = kept.keys.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    settings.notes.append("\(name) isn't set: it is the same header as \(same) (header names ignore case), which is.")
                    continue
                }
                if case .literal = GatewayHeaders.meaning(value), !value.trimmingCharacters(in: .whitespaces).hasPrefix("$$"),
                   value.range(of: #"\$[A-Za-z_]"#, options: .regularExpression) != nil {
                    settings.notes.append("\(name) is sent as written: only a value that is exactly $NAME is read from your secrets.")
                }
                kept[name] = value
            }
            settings.claude.headers = kept
        }
        return settings
    }

    /// Where JSON stopped making sense, as a line and column (never the text there, which may be a header's value).
    private static func location(of error: Error) -> String {
        let debug = (error as NSError).userInfo["NSDebugDescription"] as? String ?? ""
        guard let range = debug.range(of: #"line \d+, column \d+"#, options: .regularExpression) else { return "" }
        return " (around \(debug[range]))"
    }
}

struct TeamSettingsError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Headers

/// The extra headers sent to Claude's address, the team's or your own (`apiHeaders`). A value written exactly `$NAME` is
/// the secret of that name, read when the client is built; `$$` at the start stands for a literal `$`. A few headers
/// are Noteling's own to set. Log lines name headers, never their values.
enum GatewayHeaders {
    /// Set by Noteling, or by the Mac's network code, for every request.
    static let reserved: Set<String> = ["host", "content-length", "content-type", "connection", "transfer-encoding", "anthropic-version"]

    enum Value: Equatable {
        case literal(String)
        case secret(String)
    }

    /// What a value stands for; nil when it starts with a single `$` but what follows isn't a secret's name.
    static func meaning(_ raw: String) -> Value? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("$$") { return .literal(String(value.dropFirst())) }
        guard value.hasPrefix("$") else { return .literal(raw) }
        let name = String(value.dropFirst())
        return isSecretName(name) ? .secret(name) : nil
    }

    /// The names a secret can have: letters, digits and `_`, not starting with a digit, as pack secrets are named.
    static func isSecretName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, name.count <= 100, !CharacterSet.decimalDigits.contains(first) else { return false }
        return name.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_") }
    }

    /// Why a header can't be set, naming the header but never its value; nil when it can.
    static func refusal(name: String, value: String) -> String? {
        let tokenSymbols = "!#$%&'*+-.^_`|~"
        guard !name.isEmpty, name.count <= 128,
              name.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || tokenSymbols.unicodeScalars.contains($0)) }) else {
            return "“\(name)” isn't set: it isn't a header name (letters, digits and - only)."
        }
        if reserved.contains(name.lowercased()) { return "\(name) isn't set: Noteling sets that header itself." }
        if value.unicodeScalars.contains(where: { $0 != "\t" && CharacterSet.controlCharacters.contains($0) }) {
            return "\(name) isn't set: its value has a line break or another control character."
        }
        switch meaning(value) {
        case nil:
            return "\(name) isn't set: a value that starts with $ must be a secret's name, like $GATEWAY_KEY (letters, digits and _), or start with $$ for a $."
        case .secret(let secret) where secret == LinkedTools.tokenKey:
            return "\(name) isn't set: $\(secret) is the token for the team's tools, and Noteling never sends it anywhere else."
        default:
            return nil
        }
    }

    /// The secrets the headers ask for, by name.
    static func secretNames(_ headers: [String: String]) -> [String] {
        let names = headers.compactMap { name, value -> String? in
            guard refusal(name: name, value: value) == nil, case .secret(let secret) = meaning(value) else { return nil }
            return secret
        }
        return Array(Set(names)).sorted()
    }

    struct Resolved: Equatable {
        var values: [String: String] = [:]   // what is sent
        var missing: [String] = []           // secrets asked for that aren't set
        var refused: [String] = []           // headers left out, by name
    }

    /// The headers as sent: secrets filled in from `secret`, and those that can't be set left out.
    static func resolve(_ headers: [String: String], secret: (String) -> String?) -> Resolved {
        var out = Resolved()
        for name in headers.keys.sorted() {
            let raw = headers[name] ?? ""
            guard refusal(name: name, value: raw) == nil, let value = meaning(raw) else { out.refused.append(name); continue }
            switch value {
            case .literal(let text): out.values[name] = text
            case .secret(let key):
                if let found = secret(key) { out.values[name] = found } else if !out.missing.contains(key) { out.missing.append(key) }
            }
        }
        out.missing.sort()
        return out
    }

    /// Headers for a log line: their names only.
    static func describe(_ headers: [String: String]) -> String {
        headers.isEmpty ? "no extra headers" : "headers " + headers.keys.sorted().joined(separator: ", ")
    }
}

// MARK: - The file in the linked copy

/// The team's settings in effect, and why the copy's file can't be used, when it can't.
struct TeamSettingsState: Equatable {
    var settings: TeamSettings?
    var problem: String?
    /// The file can't be used, so the last one that could stays in effect.
    var fromEarlierFile = false
}

/// Reads `noteling.json` from the linked copy. Each one that can be used is kept (`team-settings.json`, owner-only),
/// so a broken file, even at launch, never undoes settings that worked.
enum TeamSettingsFile {
    /// `root` is the linked copy, nil when nothing is linked; `url` the repository it came from.
    static func load(root: URL?, url: String?, home: URL) -> TeamSettingsState {
        let fm = FileManager.default
        let kept = LinkedToolsFolder(home: home).teamSettingsFile
        guard let root else { try? fm.removeItem(at: kept); return TeamSettingsState() }
        guard fm.fileExists(atPath: root.path) else { return TeamSettingsState() }   // not downloaded yet
        let file = root.appendingPathComponent(TeamSettings.fileName)
        guard let data = try? Data(contentsOf: file) else { try? fm.removeItem(at: kept); return TeamSettingsState() }
        do {
            let settings = try TeamSettings.parse(data)
            if let object = try? JSONSerialization.jsonObject(with: data),
               let saved = try? JSONSerialization.data(withJSONObject: ["url": url ?? "", "file": object], options: [.sortedKeys]) {
                try? saved.write(to: kept, options: .atomic)
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: kept.path)
            }
            return TeamSettingsState(settings: settings)
        } catch {
            let problem = "\(TeamSettings.fileName) in the team's tools can't be used. " + error.localizedDescription
            guard let saved = try? Data(contentsOf: kept), let object = try? JSONSerialization.jsonObject(with: saved) as? [String: Any],
                  object["url"] as? String == (url ?? ""), let earlier = object["file"],
                  let data = try? JSONSerialization.data(withJSONObject: earlier), let settings = try? TeamSettings.parse(data) else {
                return TeamSettingsState(problem: problem)
            }
            return TeamSettingsState(settings: settings, problem: problem, fromEarlierFile: true)
        }
    }

    /// The state for a person's settings, as the app reads it at launch: for commands run without the app.
    static func load(for config: Config, home: URL = Config.dir) -> TeamSettingsState {
        load(root: LinkedTools.root(for: config, home: home), url: LinkedToolsFolder(home: home).record()?.url, home: home)
    }

    /// One log line: what is in effect, named but never valued.
    static func describe(_ state: TeamSettingsState) -> String {
        var parts: [String] = []
        if let claude = state.settings?.claude, !claude.isEmpty {
            var set: [String] = []
            if let host = claude.host { set.append("Claude through \(host)") }
            if let headers = claude.headers { set.append(GatewayHeaders.describe(headers)) }
            if let model = claude.model { set.append("model \(model)") }
            if let effort = claude.effort { set.append("effort \(effort)") }
            parts.append(set.joined(separator: ", ") + (state.fromEarlierFile ? " (from the last file that could be used)" : ""))
        } else {
            parts.append("none")
        }
        if let ignored = state.settings?.ignored, !ignored.isEmpty { parts.append("ignored " + ignored.joined(separator: ", ")) }
        if let notes = state.settings?.notes, !notes.isEmpty { parts.append("\(notes.count) note(s)") }
        if let problem = state.problem { parts.append(problem) }
        return parts.joined(separator: "; ")
    }
}

// MARK: - The configuration in effect

extension Config {
    /// The configuration in effect: the team's Claude settings over your own, for exactly the fields they set. A team
    /// gateway (`baseURL`) also means the API connection, and gets only the headers the team names: your own headers,
    /// and your own Anthropic key (`ConversationBackend`), stay with your own address. Never saved, so unlinking, or a
    /// team file without them, brings your own values back.
    func applying(_ team: TeamSettings?) -> Config {
        guard let claude = team?.claude, !claude.isEmpty else { return self }
        var effective = self
        effective.teamClaude = claude
        if let url = claude.baseURL {
            effective.apiBaseURL = url
            effective.connectionMode = "api"
            effective.apiHeaders = [:]
        }
        if let headers = claude.headers { effective.apiHeaders = headers }
        if let model = claude.model {
            effective.model = model
            effective.claudeModel = model
        }
        if let effort = claude.effort { effective.effort = effort }
        return effective
    }
}
