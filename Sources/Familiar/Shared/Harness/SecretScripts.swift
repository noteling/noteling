import Combine
import FamiliarContracts
import FamiliarRuntime
import Foundation

/// `secretScripts`, in `noteling.json` (`claude.secretScripts`) or your own config.json (`apiSecretScripts`): secrets
/// whose value a pack script makes when a request needs it, such as a gateway's token that a sign-in tool renews every
/// few hours, which a value typed once in Settings can't keep up with.
///
///     {"claude": {"headers": {"Authorization": "$GATEWAY_TOKEN"}, "secretScripts": {"GATEWAY_TOKEN": "gateway-auth/token"}}}
///
/// `gateway-auth/token` is `scripts/token.py` in the `gateway-auth` pack, run with no arguments like any pack script.
/// Its `run()` returns the value as text, or `{"value": "…", "ttl": seconds}` to say how long it may be kept.
enum SecretScripts {
    /// The entries that can be used, each as `pack/script` (without `.py`), and one sentence for each that can't,
    /// naming the secret but never a value.
    static func check(_ entries: [String: Any]) -> (kept: [String: String], notes: [String]) {
        var kept: [String: String] = [:], notes: [String] = []
        for name in entries.keys.sorted() {
            guard GatewayHeaders.isSecretName(name) else {
                notes.append("“\(name)” can't come from a script: a secret's name is letters, digits and _, like GATEWAY_TOKEN.")
                continue
            }
            guard name != LinkedTools.tokenKey else {
                notes.append("\(name) can't come from a script: it is the token for the team's tools, which Noteling only reads from Settings.")
                continue
            }
            guard let raw = entries[name] as? String else {
                notes.append("\(name) has no script: its value must be text in quotes, like \"gateway-auth/token\".")
                continue
            }
            guard let (pack, script) = reference(raw) else {
                notes.append("\(name) has no script: \"\(raw)\" must name a pack and a script in its scripts folder, like gateway-auth/token.")
                continue
            }
            kept[name] = pack + "/" + script
        }
        return (kept, notes)
    }

    /// Your own config.json's entries that can be used; those that can't are left out.
    static func valid(_ entries: [String: String]) -> [String: String] { check(entries).kept }

    /// The pack folder and script a reference names: exactly `pack/script`, `.py` optional, neither part hidden.
    static func reference(_ raw: String) -> (pack: String, script: String)? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasSuffix(".py") { text = String(text.dropLast(3)) }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let pack = parts.first, let script = parts.last else { return nil }
        for part in parts {
            guard !part.isEmpty, !part.hasPrefix("."), !part.contains("\\"),
                  !part.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        }
        guard pack != ToolRegistry.watchesFolder, pack != ToolRegistry.jobsFolder else { return nil }
        return (pack, script)
    }

    /// The script file a reference names: in your own tools folder when it has a pack of that name (your own pack
    /// wins, as everywhere), else in the team's linked tools.
    static func locate(pack: String, script: String, own: URL, linked: URL?) -> URL? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let mine = own.appendingPathComponent(pack)
        let folder = fm.fileExists(atPath: mine.path, isDirectory: &isDir) && isDir.boolValue ? mine : linked?.appendingPathComponent(pack)
        guard let file = folder?.appendingPathComponent("scripts").appendingPathComponent(script + ".py"),
              fm.fileExists(atPath: file.path) else { return nil }
        return file
    }

    /// What a script's `run()` returned: the value, and how long it may be kept (60 seconds unless it says, an hour at
    /// most, 0 for not at all). Throws, in plain words, when it isn't a value that can be sent in a header.
    static func value(of result: Any) throws -> (value: String, keep: TimeInterval) {
        var keep = ScriptedSecrets.defaultKeep
        let raw: Any?
        if let object = result as? [String: Any] {
            raw = object["value"]
            if let ttl = (object["ttl"] as? NSNumber)?.doubleValue, ttl.isFinite { keep = min(max(ttl, 0), ScriptedSecrets.longestKeep) }
        } else {
            raw = result
        }
        guard let text = raw as? String else { throw SecretScriptFailure("returned neither text nor {\"value\": \"…\"}") }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw SecretScriptFailure("returned an empty value") }
        guard !value.unicodeScalars.contains(where: { $0 != "\t" && CharacterSet.controlCharacters.contains($0) }) else {
            throw SecretScriptFailure("returned a value with a line break or another control character")
        }
        return (value, keep)
    }

    /// A script's error in plain words: what it raised, without the exception's type ("Sign in first").
    static func reason(_ error: Error, timeout: TimeInterval) -> String {
        guard let failure = error as? ScriptRunnerError else {
            return (error as? SecretScriptFailure)?.message ?? error.localizedDescription
        }
        if failure.timedOut { return "didn't finish within \(Int(timeout)) seconds" }
        guard var raised = failure.raised?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return failure.message.hasSuffix("no Python runtime") ? "can't run: there is no Python runtime (install uv)" : "returned nothing"
        }
        if let colon = raised.range(of: ": "), raised[..<colon.lowerBound].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }),
           raised[..<colon.lowerBound].hasSuffix("Error") || raised[..<colon.lowerBound].hasSuffix("Exception") {
            raised = String(raised[colon.upperBound...])
        }
        let line = raised.split(whereSeparator: \.isNewline).first.map(String.init) ?? raised
        let short = line.count > 200 ? String(line.prefix(200)) + "…" : line
        return "failed: " + (short.isEmpty ? "it raised an error with no message" : short)
    }
}

struct SecretScriptFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Makes scripted secrets' values (`SecretScripts`) right before a request needs them, keeping each as long as its
/// script allows, so most requests don't wait for one. One run at a time per secret: requests that ask while it runs
/// share its value. A value lives in memory only, never on disk or in the log, which names the secret and the script.
@MainActor
final class ScriptedSecrets: ObservableObject {
    static let shared = ScriptedSecrets()
    nonisolated static let defaultKeep: TimeInterval = 60
    nonisolated static let longestKeep: TimeInterval = 3600
    /// A sign-in tool reads a file or renews over the network; one that hangs ends here, not with the turn.
    nonisolated static let timeout: TimeInterval = 15

    /// The app's runner, which has the Mac's proxy and certificates. A command run without the app gets one made from
    /// its configuration.
    var runner: ScriptRunner?
    var now: () -> Date = Date.init

    /// Why each secret's script last failed, in plain words ("gateway-auth/token failed: Sign in first"), until it
    /// works again: Settings shows it, so a problem is visible before anyone asks a question.
    @Published private(set) var failures: [String: String] = [:]

    private struct Made { let value: String; let until: Date }
    private var kept: [String: Made] = [:]            // by secret name and script
    private var failedAt: [String: Date] = [:]
    private var running: [String: Task<Made, Error>] = [:]
    private var dependencies: [String: (modified: Date?, list: [String])] = [:]   // by script path

    /// The headers sent with one request: the scripted secrets the headers name, made now or kept, and the rest as
    /// `GatewayHeaders.resolve` fills them from `secret`. `fresh` makes them again, after the gateway turned the last
    /// ones down.
    func headers(for config: Config, secret: @escaping (String) -> String?, fresh: Bool = false) async throws -> [String: String] {
        let scripts = config.secretScripts
        var made: [String: String] = [:]
        for name in GatewayHeaders.secretNames(config.apiHeaders) {
            guard let reference = scripts[name] else { continue }
            made[name] = try await value(name, reference: reference, config: config, secret: secret, fresh: fresh)
        }
        let resolved = GatewayHeaders.resolve(config.apiHeaders, secret: { made[$0] ?? secret($0) })
        if !resolved.missing.isEmpty { throw ClaudeError(message: ConversationBackend.setupMessage(config: config, secret: secret)) }
        return resolved.values
    }

    /// Makes the scripted secrets ahead of the first question, at launch and when Settings opens, so a failing script
    /// shows in Settings before anyone asks anything.
    func warm(_ config: Config, secret: @escaping (String) -> String? = { Secrets.get($0) }) {
        guard config.connectionMode != "claudeCode", !ConversationBackend.scriptedSecrets(config).isEmpty else { return }
        Task { _ = try? await headers(for: config, secret: secret) }
    }

    /// One secret's value: kept, else made by its script, else the secret of that name you saved, if any.
    private func value(_ name: String, reference: String, config: Config, secret: (String) -> String?, fresh: Bool) async throws -> String {
        let key = name + " " + reference
        if fresh { kept[key] = nil }
        if let made = kept[key], made.until > now() { return made.value }
        // A script that just failed isn't run for every request while a saved value stands in for it.
        if !fresh, let saved = secret(name), let failed = failedAt[key], now().timeIntervalSince(failed) < Self.defaultKeep { return saved }
        let task = running[key] ?? start(name, reference: reference, config: config, key: key)
        do {
            return try await task.value.value
        } catch {
            if let saved = secret(name) { return saved }
            let reason = SecretScripts.reason(error, timeout: Self.timeout)
            throw ClaudeError(message: "\(name), which your Claude settings send, comes from the script \(reference), and it \(reason). "
                              + "Fix that, then ask again.")
        }
    }

    private func start(_ name: String, reference: String, config: Config, key: String) -> Task<Made, Error> {
        let task = Task { () async throws -> Made in
            defer { running[key] = nil }
            let started = now()
            do {
                let (value, keep) = try await run(reference, config: config)
                let made = Made(value: value, until: started.addingTimeInterval(keep))
                kept[key] = keep > 0 ? made : nil
                failedAt[key] = nil
                if failures[name] != nil { failures[name] = nil }
                Log.info("secret \(name): made by \(reference) in \(String(format: "%.1f", now().timeIntervalSince(started)))s, kept \(Int(keep))s")
                return made
            } catch {
                let reason = SecretScripts.reason(error, timeout: Self.timeout)
                kept[key] = nil
                failedAt[key] = now()
                failures[name] = "\(reference) \(reason)"
                Log.info("secret \(name): \(reference) \(reason)" + (Secrets.has(name) ? "; the saved \(name) is used instead" : ""))
                throw error
            }
        }
        running[key] = task
        return task
    }

    /// Runs the script a reference names, as its pack's scripts run, with the secrets its pack requires.
    private func run(_ reference: String, config: Config) async throws -> (value: String, keep: TimeInterval) {
        guard let (pack, script) = SecretScripts.reference(reference) else { throw SecretScriptFailure("isn't a pack and a script") }
        guard let file = SecretScripts.locate(pack: pack, script: script, own: config.resolvedToolsDir, linked: LinkedTools.root(for: config)) else {
            throw SecretScriptFailure("wasn't found: there is no scripts/\(script).py in a \(pack) pack, in your tools or your team's")
        }
        let runner = await runner(for: config)
        let packDir = file.deletingLastPathComponent().deletingLastPathComponent()
        let tool = ScriptTool(id: ToolRegistry.toolName("\(pack)__\(script)"), packDir: pack, fileName: file.lastPathComponent, path: file,
                              description: "", inputSchema: ["type": "object", "properties": [:]],
                              dependencies: await dependencies(of: file, runner: runner))
        let requires = (try? String(contentsOf: packDir.appendingPathComponent("SKILL.md"), encoding: .utf8))
            .map { ToolRegistry.list(ToolRegistry.parseFrontmatter($0).0["requires"]) } ?? []
        let result = try await runner.result(tool, secrets: requires.filter { $0 != LinkedTools.tokenKey }, timeout: Self.timeout)
        return try SecretScripts.value(of: result)
    }

    private func runner(for config: Config) async -> ScriptRunner {
        if let runner { return runner }
        let made = ScriptRunner(config: config)
        made.extraEnv = config.env
        made.networkEnv = await ScriptNetwork.current()
        runner = made
        return made
    }

    /// The packages a script names (PEP 723), read once per change to the file.
    private func dependencies(of file: URL, runner: ScriptRunner) async -> [String] {
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        if let known = dependencies[file.path], known.modified == modified { return known.list }
        let list = (try? await runner.introspect(file).dependencies) ?? []
        dependencies[file.path] = (modified, list)
        return list
    }

    /// Forgets every kept value and failure: for tests.
    func reset() {
        kept = [:]; failedAt = [:]; failures = [:]; dependencies = [:]
    }
}
