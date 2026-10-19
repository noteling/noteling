import FamiliarContracts
import FamiliarRuntime
import Foundation
import Testing
@testable import Familiar

/// Secrets a pack script makes (`secretScripts`), for a gateway whose token a sign-in tool renews every few hours:
/// reading them from the team's file and your own, which client they give, running the script and keeping its value,
/// falling back to a saved value, what Settings shows, and the script never being a tool.
@Suite @MainActor
struct SecretScriptsTests {
    static let gateway = #"{"claude": {"baseURL": "https://llm-gateway.example.com", "headers": {"Authorization": "$GATEWAY_TOKEN", "X-Consumer-Id": "abc"}, "secretScripts": {"GATEWAY_TOKEN": "gateway-auth/token"}}}"#

    static func team(_ json: String = gateway) throws -> TeamSettings { try TeamSettings.parse(Data(json.utf8)) }

    // MARK: - The files

    @Test func aTeamFileNamesTheScriptsThatMakeItsSecrets() throws {
        let settings = try Self.team()
        #expect(settings.claude.secretScripts == ["GATEWAY_TOKEN": "gateway-auth/token"])
        #expect(settings.ignored.isEmpty && settings.notes.isEmpty)
        #expect(TeamSettingsFile.describe(TeamSettingsState(settings: settings))
                == "Claude through llm-gateway.example.com, headers Authorization, X-Consumer-Id, secret scripts for GATEWAY_TOKEN")

        // Entries that can't be used are notes, naming the secret, and the rest of the file still applies.
        let mixed = try Self.team(#"{"claude": {"baseURL": "https://llm-gateway.example.com", "headers": {"Authorization": "$GATEWAY_TOKEN"}, "secretScripts": {"GATEWAY_TOKEN": "gateway-auth/token.py", "bad-name": "a/b", "NOTELING_TOOLS_REPO_TOKEN": "a/b", "NUMBER": 3, "FLAT": "token", "DEEP": "a/b/c", "HIDDEN": "../token", "UNUSED": "gateway-auth/other"}}}"#)
        #expect(mixed.claude.secretScripts == ["GATEWAY_TOKEN": "gateway-auth/token", "UNUSED": "gateway-auth/other"])
        #expect(mixed.claude.baseURL == "https://llm-gateway.example.com")
        #expect(mixed.notes == [
            "DEEP has no script: \"a/b/c\" must name a pack and a script in its scripts folder, like gateway-auth/token.",
            "FLAT has no script: \"token\" must name a pack and a script in its scripts folder, like gateway-auth/token.",
            "HIDDEN has no script: \"../token\" must name a pack and a script in its scripts folder, like gateway-auth/token.",
            "NOTELING_TOOLS_REPO_TOKEN can't come from a script: it is the token for the team's tools, which Noteling only reads from Settings.",
            "NUMBER has no script: its value must be text in quotes, like \"gateway-auth/token\".",
            "“bad-name” can't come from a script: a secret's name is letters, digits and _, like GATEWAY_TOKEN.",
            "UNUSED has a script, but no header in claude.headers is $UNUSED, so it isn't used.",
        ])

        // Anything but an object is a file that can't be used, as for headers.
        #expect(throws: TeamSettingsError("claude.secretScripts must be an object of secret names and scripts, { \"GATEWAY_KEY\": \"gateway-auth/token\" }.")) {
            try Self.team(#"{"claude": {"secretScripts": ["gateway-auth/token"]}}"#)
        }
        #expect(try Self.team(#"{"claude": {"secretScripts": {}}}"#).claude.isEmpty)
    }

    @Test func referencesNameAPackFolderAndAScriptInIt() {
        #expect(SecretScripts.reference("gateway-auth/token")! == ("gateway-auth", "token"))
        #expect(SecretScripts.reference(" gateway-auth/_token.py ")! == ("gateway-auth", "_token"))
        for bad in ["", "token", "/token", "gateway-auth/", "a/b/c", ".hidden/token", "gateway-auth/.token", "watches/token", "jobs/token", "a\\b/token"] {
            #expect(SecretScripts.reference(bad) == nil, "\(bad)")
        }
    }

    @Test func theTeamsScriptsComeFirstAndYourOwnFillIn() throws {
        var own = Config()
        own.apiSecretScripts = ["GATEWAY_TOKEN": "mine/token", "OWN_TOKEN": "mine/own", "bad-name": "mine/x"]
        #expect(own.secretScripts == ["GATEWAY_TOKEN": "mine/token", "OWN_TOKEN": "mine/own"])
        let effective = own.applying(try Self.team())
        #expect(effective.secretScripts == ["GATEWAY_TOKEN": "gateway-auth/token", "OWN_TOKEN": "mine/own"])

        // Kept in config.json, and a value of the wrong shape there doesn't cost the rest of the file.
        let restored = try JSONDecoder().decode(Config.self, from: try JSONEncoder().encode(own))
        #expect(restored.apiSecretScripts == own.apiSecretScripts)
        let wrong = try JSONDecoder().decode(Config.self, from: Data(#"{"apiSecretScripts": ["x"], "model": "kept"}"#.utf8))
        #expect(wrong.apiSecretScripts.isEmpty && wrong.model == "kept")
    }

    // MARK: - The client

    @Test func aScriptedSecretIsMadePerRequestInsteadOfBeingMissing() throws {
        let effective = Config().applying(try Self.team())
        let client = try #require(ConversationBackend.make(config: effective, secret: { _ in nil }) as? ClaudeClient)
        #expect(client.extraHeaders == ["X-Consumer-Id": "abc"])   // the token is made right before each request
        #expect(client.refreshHeaders != nil)
        #expect(ConversationBackend.scriptedSecrets(effective) == ["GATEWAY_TOKEN"])

        // Another secret the headers name still has to be saved, and the chat names only that one.
        let more = Config().applying(try Self.team(#"{"claude": {"baseURL": "https://llm-gateway.example.com", "headers": {"Authorization": "$GATEWAY_TOKEN", "X-Key": "$GATEWAY_KEY"}, "secretScripts": {"GATEWAY_TOKEN": "gateway-auth/token"}}}"#))
        #expect(ConversationBackend.make(config: more, secret: { _ in nil }) == nil)
        #expect(ConversationBackend.setupMessage(config: more, secret: { _ in nil })
                == "Your team's Claude settings need a secret that isn't set: GATEWAY_KEY. Add it in Noteling Settings, under Tool packs, then choose Save.")

        // Without a script, headers are filled when the client is built, as before.
        let plain = Config().applying(try Self.team(#"{"claude": {"baseURL": "https://llm-gateway.example.com", "headers": {"Authorization": "$GATEWAY_TOKEN"}}}"#))
        let built = try #require(ConversationBackend.make(config: plain, secret: { $0 == "GATEWAY_TOKEN" ? "Bearer typed" : nil }) as? ClaudeClient)
        #expect(built.extraHeaders == ["Authorization": "Bearer typed"] && built.refreshHeaders == nil)
    }

    // MARK: - Running the script

    /// The message a call ends with; nil when it doesn't throw.
    static func message(_ body: () async throws -> Any) async -> String? {
        do { _ = try await body(); return nil } catch { return (error as? ClaudeError)?.message ?? error.localizedDescription }
    }

    /// A tools folder with a `gateway-auth` pack whose token.py counts its runs and returns `body`'s value.
    struct Place {
        let root: URL
        var tools: URL { root.appendingPathComponent("tools") }
        var runs: Int { Int((try? String(contentsOf: tools.appendingPathComponent("gateway-auth/count"), encoding: .utf8)) ?? "0") ?? 0 }

        init(_ name: String, returns body: String) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
            try Self.write("---\nname: Gateway sign-in\n---\nMakes the gateway's token.", to: tools.appendingPathComponent("gateway-auth/SKILL.md"))
            try Self.write("""
            import os, pathlib

            def run():
                \"\"\"Makes a fixture token.\"\"\"
                count = pathlib.Path(os.environ["NOTELING_TOOL_DIR"]) / "count"
                n = int(count.read_text()) + 1 if count.exists() else 1
                count.write_text(str(n))
                \(body)
            """, to: tools.appendingPathComponent("gateway-auth/scripts/token.py"))
        }

        var config: Config {
            var c = Config()
            c.toolsDir = tools.path
            c.apiBaseURL = "https://llm-gateway.example.com"
            c.apiHeaders = ["Authorization": "$GATEWAY_TOKEN", "X-Consumer-Id": "abc"]
            c.apiSecretScripts = ["GATEWAY_TOKEN": "gateway-auth/token"]
            return c
        }

        @MainActor func secrets() -> ScriptedSecrets {
            let made = ScriptedSecrets()
            made.runner = ScriptRunner(config: config)
            return made
        }

        static func write(_ text: String, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @Test func theScriptsValueIsKeptAsLongAsItSaysAndMadeAgainAfter() async throws {
        let place = try Place("secret-script-kept", returns: #"return {"value": f"Bearer tok-{n}", "ttl": 300}"#)
        defer { try? FileManager.default.removeItem(at: place.root) }
        let secrets = place.secrets()
        var clock = Date()
        secrets.now = { clock }

        let first = try await secrets.headers(for: place.config, secret: { _ in nil })
        #expect(first == ["Authorization": "Bearer tok-1", "X-Consumer-Id": "abc"])
        // Requests asking at once share one run.
        async let a = secrets.headers(for: place.config, secret: { _ in nil })
        async let b = secrets.headers(for: place.config, secret: { _ in nil })
        #expect(try await [a, b].map { $0["Authorization"] } == ["Bearer tok-1", "Bearer tok-1"])
        #expect(place.runs == 1)

        clock = clock.addingTimeInterval(301)   // past its ttl
        #expect(try await secrets.headers(for: place.config, secret: { _ in nil })["Authorization"] == "Bearer tok-2")
        // Turned down by the gateway, it is made again at once.
        #expect(try await secrets.headers(for: place.config, secret: { _ in nil }, fresh: true)["Authorization"] == "Bearer tok-3")
        #expect(place.runs == 3 && secrets.failures.isEmpty)
    }

    @Test func textIsKeptAMinuteAndATtlOfNoneIsntKept() async throws {
        let place = try Place("secret-script-text", returns: #"return f"Bearer tok-{n}""#)
        defer { try? FileManager.default.removeItem(at: place.root) }
        let secrets = place.secrets()
        var clock = Date()
        secrets.now = { clock }
        _ = try await secrets.headers(for: place.config, secret: { _ in nil })
        clock = clock.addingTimeInterval(59)
        #expect(try await secrets.headers(for: place.config, secret: { _ in nil })["Authorization"] == "Bearer tok-1")
        clock = clock.addingTimeInterval(2)
        #expect(try await secrets.headers(for: place.config, secret: { _ in nil })["Authorization"] == "Bearer tok-2")

        let never = try Place("secret-script-ttl0", returns: #"return {"value": f"tok-{n}", "ttl": 0}"#)
        defer { try? FileManager.default.removeItem(at: never.root) }
        let each = never.secrets()
        _ = try await each.headers(for: never.config, secret: { _ in nil })
        #expect(try await each.headers(for: never.config, secret: { _ in nil })["Authorization"] == "tok-2")
    }

    @Test func aFailingScriptFallsBackToTheSavedValueOrSaysWhatWentWrong() async throws {
        let place = try Place("secret-script-fails", returns: #"raise RuntimeError("Sign in first")"#)
        defer { try? FileManager.default.removeItem(at: place.root) }
        let secrets = place.secrets()
        #expect(await Self.message { try await secrets.headers(for: place.config, secret: { _ in nil }) }
                == "GATEWAY_TOKEN, which your Claude settings send, comes from the script gateway-auth/token, and it failed: Sign in first. Fix that, then ask again.")
        #expect(secrets.failures == ["GATEWAY_TOKEN": "gateway-auth/token failed: Sign in first"])

        // A saved value of the same name stands in, and the script isn't run again for every request meanwhile.
        let saved = try await secrets.headers(for: place.config, secret: { $0 == "GATEWAY_TOKEN" ? "Bearer saved" : nil })
        #expect(saved["Authorization"] == "Bearer saved")
        _ = try await secrets.headers(for: place.config, secret: { $0 == "GATEWAY_TOKEN" ? "Bearer saved" : nil })
        #expect(place.runs == 1)

        // A missing script and a value that can't be a header say so too.
        var missing = place.config
        missing.apiSecretScripts = ["GATEWAY_TOKEN": "gateway-auth/nothing"]
        #expect(await Self.message { try await secrets.headers(for: missing, secret: { _ in nil }) }
                == "GATEWAY_TOKEN, which your Claude settings send, comes from the script gateway-auth/nothing, and it wasn't found: there is no scripts/nothing.py in a gateway-auth pack, in your tools or your team's. Fix that, then ask again.")
        let broken = try Place("secret-script-newline", returns: #"return "tok\nX-Injected: 1""#)
        defer { try? FileManager.default.removeItem(at: broken.root) }
        let refused = broken.secrets()
        _ = try? await refused.headers(for: broken.config, secret: { _ in nil })
        #expect(refused.failures == ["GATEWAY_TOKEN": "gateway-auth/token returned a value with a line break or another control character"])
    }

    @Test func aScriptGetsTheSecretsItsPackRequires() async throws {
        let place = try Place("secret-script-requires", returns: #"return "Bearer " + os.environ.get("GATEWAY_CLIENT_FOR_TESTS", "none")"#)
        defer { try? FileManager.default.removeItem(at: place.root); Secrets.set("GATEWAY_CLIENT_FOR_TESTS", "") }
        try Place.write("---\nname: Gateway sign-in\nrequires: [GATEWAY_CLIENT_FOR_TESTS]\n---\nMakes the token.", to: place.tools.appendingPathComponent("gateway-auth/SKILL.md"))
        Secrets.set("GATEWAY_CLIENT_FOR_TESTS", "client-7")
        #expect(try await place.secrets().headers(for: place.config, secret: { _ in nil })["Authorization"] == "Bearer client-7")
    }

    @Test func yourOwnPackWinsOverTheTeams() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("secret-script-locate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let own = root.appendingPathComponent("own"), linked = root.appendingPathComponent("linked")
        try Place.write("def run(): return 'team'", to: linked.appendingPathComponent("gateway-auth/scripts/token.py"))
        #expect(SecretScripts.locate(pack: "gateway-auth", script: "token", own: own, linked: linked)?.path.hasPrefix(linked.path) == true)
        // A pack of your own of that name is the one used, as for every pack, even without the script.
        try FileManager.default.createDirectory(at: own.appendingPathComponent("gateway-auth"), withIntermediateDirectories: true)
        #expect(SecretScripts.locate(pack: "gateway-auth", script: "token", own: own, linked: linked) == nil)
        try Place.write("def run(): return 'mine'", to: own.appendingPathComponent("gateway-auth/scripts/token.py"))
        #expect(SecretScripts.locate(pack: "gateway-auth", script: "token", own: own, linked: linked)?.path.hasPrefix(own.path) == true)
    }

    @Test func whatAScriptReturnsAndHowItFails() throws {
        #expect(try SecretScripts.value(of: " Bearer abc \n") == ("Bearer abc", 60))
        #expect(try SecretScripts.value(of: ["value": "abc", "ttl": 7200]) == ("abc", 3600))
        #expect(try SecretScripts.value(of: ["value": "abc", "ttl": -5]) == ("abc", 0))
        #expect(throws: SecretScriptFailure.self) { try SecretScripts.value(of: ["token": "abc"]) }
        #expect(throws: SecretScriptFailure.self) { try SecretScripts.value(of: "  ") }

        let raised = ScriptRunnerError(message: "token.py failed: RuntimeError: Sign in first\nTraceback …", raised: "RuntimeError: Sign in first")
        #expect(SecretScripts.reason(raised, timeout: 15) == "failed: Sign in first")
        #expect(SecretScripts.reason(ScriptRunnerError(message: "x", raised: "auth.SignInError: Expired\nmore"), timeout: 15) == "failed: Expired")
        #expect(SecretScripts.reason(ScriptRunnerError(message: "x", raised: "Token: is missing"), timeout: 15) == "failed: Token: is missing")
        #expect(SecretScripts.reason(ScriptRunnerError(message: "token.py timed out after 15s", timedOut: true), timeout: 15) == "didn't finish within 15 seconds")
        // What the script printed is never repeated: it may hold the token.
        #expect(SecretScripts.reason(ScriptRunnerError(message: "token.py produced no result. stderr: Bearer abc"), timeout: 15) == "returned nothing")
    }

    // MARK: - Settings and tools

    @Test func settingsAsksForNoValueAndSaysWhereTheSecretComesFrom() throws {
        let model = SettingsModel()
        model.load(config: Config(), packs: [], team: try Self.team())
        #expect(model.packSecrets.isEmpty)   // the script makes it: nothing to type
        #expect(model.scriptedSecrets == ["GATEWAY_TOKEN": "gateway-auth/token"])
        #expect(model.secretScriptLines.map(\.text) == ["GATEWAY_TOKEN comes from gateway-auth/token, run when a request needs it."])
        #expect(model.secretScriptLines.map(\.failed) == [false])

        model.applyTeam(try Self.team(#"{"claude": {"baseURL": "https://llm-gateway.example.com", "headers": {"Authorization": "$GATEWAY_TOKEN"}}}"#))
        #expect(model.packSecrets.map(\.id) == ["GATEWAY_TOKEN"] && model.secretScriptLines.isEmpty)
    }

    @Test func aScriptThatMakesASecretIsNeverATool() async throws {
        let place = try Place("secret-script-tools", returns: #"return "tok""#)
        defer { try? FileManager.default.removeItem(at: place.root) }
        try Place.write("def run() -> str:\n    \"\"\"Says hello.\"\"\"\n    return 'hi'\n", to: place.tools.appendingPathComponent("gateway-auth/scripts/status.py"))
        let registry = ToolRegistry(root: place.tools, runner: ScriptRunner(config: Config()))
        registry.secretScripts = { Set(place.config.secretScripts.values) }
        await registry.reload()
        #expect(registry.packs.flatMap(\.scripts).map(\.id) == ["gateway-auth__status"])
    }
}
