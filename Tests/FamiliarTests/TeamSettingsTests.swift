import FamiliarContracts
@testable import FamiliarRuntime
import Foundation
import Testing
@testable import Familiar

/// The team's Claude settings from `noteling.json` in its linked tools: reading the file, keeping the last good one,
/// the configuration in effect (the team's values over your own, never saved), secrets named in header values, the
/// headers Noteling never lets a file set, what a client is built from, log lines without values, and Settings.
@Suite @MainActor
struct TeamSettingsTests {
    static let gateway = #"{"claude": {"baseURL": "https://llm-gateway.example.com", "headers": {"X-Consumer-Id": "abc", "X-Api-Key": "$GATEWAY_KEY"}, "model": "claude-opus-5", "effort": "medium"}}"#

    static func team(_ json: String = gateway) throws -> TeamSettings { try TeamSettings.parse(Data(json.utf8)) }

    /// Someone who uses the local Claude CLI, with a gateway and a header of their own.
    static var own: Config {
        var c = Config()
        c.connectionMode = "claudeCode"
        c.claudeModel = "sonnet"
        c.model = "own-model"
        c.effort = "low"
        c.apiKey = "own-anthropic-key"
        c.apiBaseURL = "https://own-gateway.example.net"
        c.apiHeaders = ["X-Own": "mine"]
        return c
    }

    // MARK: - The file

    @Test func aTeamFileSetsClaudeAndListsWhatItIgnores() throws {
        let settings = try Self.team(#"{"claude": {"baseURL": "https://llm-gateway.example.com", "headers": {"X-Consumer-Id": "abc", "X-Api-Key": "$GATEWAY_KEY"}, "model": " claude-opus-5 ", "effort": "medium", "timeout": 30}, "theme": "dark", "notes": {}}"#)
        #expect(settings.claude == TeamSettings.Claude(baseURL: "https://llm-gateway.example.com",
                                                       headers: ["X-Consumer-Id": "abc", "X-Api-Key": "$GATEWAY_KEY"],
                                                       model: "claude-opus-5", effort: "medium"))
        #expect(settings.claude.host == "llm-gateway.example.com")
        #expect(settings.ignored == ["notes", "theme", "claude.timeout"])
        #expect(settings.notes.isEmpty)

        // Leaving a field out, null or empty leaves it to each person; a file without claude sets nothing.
        #expect(try Self.team(#"{"claude": {"model": "claude-opus-5", "effort": null, "baseURL": ""}}"#).claude
                == TeamSettings.Claude(model: "claude-opus-5"))
        #expect(try Self.team(#"{"theme": "dark"}"#).claude.isEmpty)
        #expect(try Self.team("{}").claude.isEmpty)
        #expect(try Self.team(#"{"claude": {"baseURL": "http://localhost:8080"}}"#).claude.baseURL == "http://localhost:8080")
        #expect(try Self.team(#"{"claude": {"baseURL": "https://llm-gateway.example.com/v1"}}"#).notes
                == ["claude.baseURL ends in /v1. Noteling adds /v1/messages itself, as Anthropic's SDKs do, so requests go to …/v1/v1/messages. Leave /v1 off unless the gateway expects that."])
    }

    @Test func aFileThatCantBeUsedSaysWhyPlainly() {
        let cases: [(String, String)] = [
            (#"{"claude": {"model": "claude-opus-5",}"#, "It isn't valid JSON"),
            ("", "It isn't valid JSON"),
            (#"["claude"]"#, "It must be one JSON object, { … }."),
            (#"{"claude": "llm-gateway.example.com"}"#, "claude must be an object, { … }."),
            (#"{"claude": {"baseURL": 443}}"#, "claude.baseURL must be text in quotes."),
            (#"{"claude": {"baseURL": "http://llm-gateway.example.com"}}"#, "claude.baseURL must be a web address that starts with https://"),
            (#"{"claude": {"baseURL": "https://llm-gateway.example.com/?key=abc"}}"#, "claude.baseURL must be a web address that starts with https://"),
            (#"{"claude": {"baseURL": "llm-gateway.example.com"}}"#, "claude.baseURL must be a web address that starts with https://"),
            (#"{"claude": {"model": true}}"#, "claude.model must be text in quotes."),
            (#"{"claude": {"effort": "ultra"}}"#, "claude.effort must be low, medium, high, xhigh or max."),
            (#"{"claude": {"headers": ["X-Consumer-Id"]}}"#, "claude.headers must be an object of header names and values"),
            (#"{"claude": {"headers": {"X-Consumer-Id": 42}}}"#, "The X-Consumer-Id header's value must be text in quotes."),
        ]
        for (json, expected) in cases {
            do {
                _ = try TeamSettings.parse(Data(json.utf8))
                Issue.record("took \(json)")
            } catch {
                #expect(error is TeamSettingsError)
                #expect(error.localizedDescription.hasPrefix(expected), "\(json): \(error.localizedDescription)")
            }
        }
        // Where JSON broke is told by line and column, never by the text there.
        do { _ = try TeamSettings.parse(Data("{\"claude\": {\"headers\": {\"X-Api-Key\": SECRET-VALUE}}}".utf8)) } catch {
            #expect(error.localizedDescription.contains("(around line 1, column"))
            #expect(!error.localizedDescription.contains("SECRET"))
        }
    }

    @Test func headersNotelingSetsItselfAreRefusedAndSaidSo() throws {
        let settings = try Self.team(#"""
        {"claude": {"headers": {"Host": "evil.example.net", "content-length": "1", "Content-Type": "text/plain", "Connection": "close",
          "Transfer-Encoding": "chunked", "Anthropic-Version": "2020-01-01", "anthropic-beta": "some-beta", "Authorization": "Bearer abc",
          "x-api-key": "$GATEWAY_KEY", "X-Api-Key": "$OTHER_KEY", "X Bad": "1", "X-Token": "$NOTELING_TOOLS_REPO_TOKEN",
          "X-Broken": "$not a name", "X-Digit": "$1KEY", "X-Line": "a\nb", "X-Bearer": "Bearer $GATEWAY_KEY", "X-Price": "$$5"}}}
        """#)
        let headers = try #require(settings.claude.headers)
        #expect(headers == ["anthropic-beta": "some-beta", "Authorization": "Bearer abc", "X-Api-Key": "$OTHER_KEY",
                            "X-Bearer": "Bearer $GATEWAY_KEY", "X-Price": "$$5"])
        #expect(settings.notes == [
            "Anthropic-Version isn't set: Noteling sets that header itself.",
            "Connection isn't set: Noteling sets that header itself.",
            "Content-Type isn't set: Noteling sets that header itself.",
            "Host isn't set: Noteling sets that header itself.",
            "Transfer-Encoding isn't set: Noteling sets that header itself.",
            "“X Bad” isn't set: it isn't a header name (letters, digits and - only).",
            "X-Bearer is sent as written: only a value that is exactly $NAME is read from your secrets.",
            "X-Broken isn't set: a value that starts with $ must be a secret's name, like $GATEWAY_KEY (letters, digits and _), or start with $$ for a $.",
            "X-Digit isn't set: a value that starts with $ must be a secret's name, like $GATEWAY_KEY (letters, digits and _), or start with $$ for a $.",
            "X-Line isn't set: its value has a line break or another control character.",
            "X-Token isn't set: $NOTELING_TOOLS_REPO_TOKEN is the token for the team's tools, and Noteling never sends it anywhere else.",
            "content-length isn't set: Noteling sets that header itself.",
            "x-api-key isn't set: it is the same header as X-Api-Key (header names ignore case), which is.",
        ])
        for note in settings.notes { #expect(!note.contains("evil") && !note.contains("chunked") && !note.contains("text/plain")) }
    }

    @Test func secretsInHeaderValues() {
        let headers = ["X-Consumer-Id": "abc", "X-Api-Key": "$GATEWAY_KEY", "X-Price": "$$5", "X-Other": " $OTHER_KEY ",
                       "Host": "evil.example.net", "X-Token": "$NOTELING_TOOLS_REPO_TOKEN"]
        #expect(GatewayHeaders.meaning("$GATEWAY_KEY") == .secret("GATEWAY_KEY"))
        #expect(GatewayHeaders.meaning("$$GATEWAY_KEY") == .literal("$GATEWAY_KEY"))
        #expect(GatewayHeaders.meaning("abc$") == .literal("abc$"))
        #expect(GatewayHeaders.meaning("$") == nil && GatewayHeaders.meaning("$a-b") == nil)
        #expect(GatewayHeaders.secretNames(headers) == ["GATEWAY_KEY", "OTHER_KEY"])

        let found = ["GATEWAY_KEY": "gk-123", "OTHER_KEY": "ok-456"]
        let present = GatewayHeaders.resolve(headers, secret: { found[$0] })
        #expect(present.values == ["X-Consumer-Id": "abc", "X-Api-Key": "gk-123", "X-Price": "$5", "X-Other": "ok-456"])
        #expect(present.missing.isEmpty && present.refused == ["Host", "X-Token"])

        let missing = GatewayHeaders.resolve(headers, secret: { $0 == "OTHER_KEY" ? "ok-456" : nil })
        #expect(missing.missing == ["GATEWAY_KEY"] && missing.values["X-Api-Key"] == nil && missing.values["X-Other"] == "ok-456")
    }

    @Test func logLinesNameHeadersButNeverTheirValues() throws {
        let settings = try Self.team(#"{"claude": {"baseURL": "https://llm-gateway.example.com", "headers": {"X-Consumer-Id": "consumer-VALUE-1", "X-Api-Key": "$GATEWAY_KEY", "Host": "host-VALUE-2", "X-Odd": "$bad name VALUE-3"}, "model": "claude-opus-5"}, "theme": "dark"}"#)
        let line = TeamSettingsFile.describe(TeamSettingsState(settings: settings, problem: "noteling.json in the team's tools can't be used. It isn't valid JSON."))
        #expect(line.contains("Claude through llm-gateway.example.com") && line.contains("headers X-Api-Key, X-Consumer-Id")
                && line.contains("model claude-opus-5") && line.contains("ignored theme"))
        #expect(GatewayHeaders.describe(["X-Consumer-Id": "consumer-VALUE-1"]) == "headers X-Consumer-Id")
        #expect(!line.contains("VALUE") && !line.contains("$GATEWAY_KEY"), "\(line)")
        #expect(settings.notes.count == 2)
        for note in settings.notes { #expect(!note.contains("VALUE"), "\(note)") }
        #expect(TeamSettingsFile.describe(TeamSettingsState()) == "none")
    }

    // MARK: - The configuration in effect

    @Test func theTeamsValuesWinForExactlyTheFieldsItSets() throws {
        let own = Self.own
        let effective = own.applying(try Self.team())
        #expect(effective.connectionMode == "api")   // a team gateway means the API connection
        #expect(effective.apiBaseURL == "https://llm-gateway.example.com")
        #expect(effective.apiHeaders == ["X-Consumer-Id": "abc", "X-Api-Key": "$GATEWAY_KEY"])   // yours aren't sent there
        #expect(effective.model == "claude-opus-5" && effective.claudeModel == "claude-opus-5" && effective.effort == "medium")
        #expect(effective.teamClaude?.host == "llm-gateway.example.com")
        #expect(effective.claudePath == own.claudePath && effective.hotkey == own.hotkey && effective.apiKey == own.apiKey)

        // Only a model: your own connection, address, headers and effort stay.
        let modelOnly = own.applying(try Self.team(#"{"claude": {"model": "claude-opus-5"}}"#))
        #expect(modelOnly.connectionMode == "claudeCode" && modelOnly.apiBaseURL == own.apiBaseURL && modelOnly.apiHeaders == own.apiHeaders)
        #expect(modelOnly.claudeModel == "claude-opus-5" && modelOnly.effort == "low")
        // Headers without an address replace yours, for your own address.
        let headersOnly = own.applying(try Self.team(#"{"claude": {"headers": {"X-Consumer-Id": "abc"}}}"#))
        #expect(headersOnly.apiHeaders == ["X-Consumer-Id": "abc"] && headersOnly.apiBaseURL == own.apiBaseURL && headersOnly.connectionMode == "claudeCode")

        // Unlinked, or a file that sets nothing: your own, exactly.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for none in [nil, try Self.team(#"{"theme": "dark"}"#)] {
            let back = own.applying(none)
            #expect(back.teamClaude == nil)
            #expect(try encoder.encode(back) == encoder.encode(own))
        }
    }

    @Test func theConfigurationInEffectIsNeverSaved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("team-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let own = Self.own
        own.applying(try Self.team()).save(to: folder.appendingPathComponent("effective.json"))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("effective.json").path))

        own.save(to: folder.appendingPathComponent("config.json"))
        let saved = try String(contentsOf: folder.appendingPathComponent("config.json"), encoding: .utf8)
        #expect(!saved.contains("teamClaude") && !saved.contains("llm-gateway") && saved.contains("own-model"))
        let restored = try JSONDecoder().decode(Config.self, from: Data(saved.utf8))
        #expect(restored.teamClaude == nil && restored.connectionMode == "claudeCode" && restored.apiHeaders == ["X-Own": "mine"])
    }

    // MARK: - The client

    @Test func theClientIsBuiltFromTheConfigurationInEffect() throws {
        let secrets = ["GATEWAY_KEY": "gk-123", "ANTHROPIC_API_KEY": "own-key-from-settings"]
        let effective = Self.own.applying(try Self.team())   // someone on the CLI: the team's gateway wins
        let client = try #require(ConversationBackend.make(config: effective, secret: { secrets[$0] }) as? ClaudeClient)
        #expect(client.baseURL.absoluteString == "https://llm-gateway.example.com")
        #expect(client.extraHeaders == ["X-Consumer-Id": "abc", "X-Api-Key": "gk-123"])
        #expect(client.apiKey == "")   // your own Anthropic key isn't sent to the team's gateway
        #expect(client.model == "claude-opus-5" && client.effort == "medium")
        #expect(!client.serverFallbacks)

        // Without the gateway's secret there is no client, and the chat says what is missing.
        #expect(ConversationBackend.make(config: effective, secret: { _ in nil }) == nil)
        #expect(ConversationBackend.setupMessage(config: effective, secret: { _ in nil })
                == "Your team's Claude settings need a secret that isn't set: GATEWAY_KEY. Add it in Noteling Settings, under Tool packs, then choose Save.")
        let two = Self.own.applying(try Self.team(#"{"claude": {"baseURL": "https://llm-gateway.example.com", "headers": {"A": "$KEY_A", "B": "$KEY_B"}}}"#))
        #expect(ConversationBackend.setupMessage(config: two, secret: { _ in nil })
                == "Your team's Claude settings need secrets that aren't set: KEY_A, KEY_B. Add them in Noteling Settings, under Tool packs, then choose Save.")

        // The team's headers can ask for your key by name; a team address at Anthropic gets it as usual.
        let asked = Self.own.applying(try Self.team(#"{"claude": {"baseURL": "https://llm-gateway.example.com", "headers": {"x-api-key": "$ANTHROPIC_API_KEY"}}}"#))
        #expect((ConversationBackend.make(config: asked, secret: { secrets[$0] }) as? ClaudeClient)?.extraHeaders == ["x-api-key": "own-key-from-settings"])
        let anthropic = Self.own.applying(try Self.team(#"{"claude": {"baseURL": "https://api.anthropic.com", "headers": {"X-Consumer-Id": "abc"}}}"#))
        #expect((ConversationBackend.make(config: anthropic, secret: { secrets[$0] }) as? ClaudeClient)?.apiKey == "own-anthropic-key")

        // Your own settings, as before: your key, your address, and your own `$NAME` headers filled in.
        var mine = Self.own
        mine.connectionMode = "api"
        mine.apiHeaders = ["X-Own": "$OWN_SECRET", "Host": "x"]
        let own = try #require(ConversationBackend.make(config: mine, secret: { $0 == "OWN_SECRET" ? "own-secret" : nil }) as? ClaudeClient)
        #expect(own.apiKey == "own-anthropic-key" && own.baseURL.absoluteString == "https://own-gateway.example.net")
        #expect(own.extraHeaders == ["X-Own": "own-secret"])
        #expect(ConversationBackend.setupMessage(config: mine, secret: { _ in nil })
                == "Your Claude gateway headers need a secret that isn't set: OWN_SECRET. Add it in Noteling Settings, under Tool packs, then choose Save.")
    }

    // MARK: - The last good file

    @Test func aBrokenFileKeepsTheLastGoodSettings() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("team-file-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = LinkedToolsFolder(home: home)
        let file = folder.root.appendingPathComponent(TeamSettings.fileName)
        try FileManager.default.createDirectory(at: folder.root, withIntermediateDirectories: true)
        let url = "https://github.example.com/acme/tools"

        try Self.gateway.write(to: file, atomically: true, encoding: .utf8)
        let good = TeamSettingsFile.load(root: folder.root, url: url, home: home)
        #expect(good.settings == (try Self.team()) && good.problem == nil && !good.fromEarlierFile)
        #expect(FileManager.default.fileExists(atPath: folder.teamSettingsFile.path))
        #expect((try FileManager.default.attributesOfItem(atPath: folder.teamSettingsFile.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        // A broken push, now and after a restart: the settings that worked stay, and Settings says why.
        try #"{"claude": {"baseURL": 42}}"#.write(to: file, atomically: true, encoding: .utf8)
        for _ in 0..<2 {
            let broken = TeamSettingsFile.load(root: folder.root, url: url, home: home)
            #expect(broken.settings == (try Self.team()) && broken.fromEarlierFile)
            #expect(broken.problem == "noteling.json in the team's tools can't be used. claude.baseURL must be text in quotes.")
        }
        // Not when the copy now comes from another repository.
        let elsewhere = TeamSettingsFile.load(root: folder.root, url: "https://github.example.com/other/tools", home: home)
        #expect(elsewhere.settings == nil && elsewhere.problem != nil)

        // The team removes the file: your own settings come back, and nothing is kept.
        try FileManager.default.removeItem(at: file)
        #expect(TeamSettingsFile.load(root: folder.root, url: url, home: home) == TeamSettingsState())
        #expect(!FileManager.default.fileExists(atPath: folder.teamSettingsFile.path))

        // Linked, nothing downloaded yet; then unlinked.
        try Self.gateway.write(to: file, atomically: true, encoding: .utf8)
        _ = TeamSettingsFile.load(root: folder.root, url: url, home: home)
        #expect(TeamSettingsFile.load(root: home.appendingPathComponent("missing"), url: url, home: home) == TeamSettingsState())
        #expect(TeamSettingsFile.load(root: nil, url: nil, home: home) == TeamSettingsState())
        #expect(!FileManager.default.fileExists(atPath: folder.teamSettingsFile.path))
    }
}
