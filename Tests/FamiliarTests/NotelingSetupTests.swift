import Foundation
import Testing
@testable import Familiar

/// A team's setup file links its tools and saves the secrets they need, and nothing else: it says what it will do first,
/// refuses what it doesn't understand, and never holds the repository's token among the secrets.
@Suite @MainActor
struct NotelingSetupTests {
    private func parse(_ json: String) throws -> NotelingSetup { try NotelingSetup.parse(Data(json.utf8)) }

    private func refusal(_ json: String) -> String? {
        do { _ = try parse(json); return nil } catch { return error.localizedDescription }
    }

    @Test func aSetupFileLinksTheTeamsToolsAndSavesItsSecrets() throws {
        let setup = try parse("""
        {"noteling_setup": 1, "name": "Holiday pilot",
         "tools_repo": {"url": "git@github.example.com:team/tools.git", "token": " github_pat_abc ", "branch": "pilot"},
         "secrets": {"SHOP_API_KEY": "k1", "SHOP_REGION": "east"}, "theme": "dark"}
        """)
        #expect(setup.name == "Holiday pilot")
        #expect(setup.toolsRepo == .init(url: "https://github.example.com/team/tools", token: "github_pat_abc", branch: "pilot"))
        #expect(setup.secrets == ["SHOP_API_KEY": "k1", "SHOP_REGION": "east"])
        #expect(setup.unused == ["theme"])

        var config = Config()
        var saved: [String: String] = [:]
        try setup.apply(to: &config) { saved[$0] = $1; return true }
        #expect(config.toolsRepo == "https://github.example.com/team/tools" && config.toolsRepoBranch == "pilot")
        #expect(saved == [LinkedTools.tokenKey: "github_pat_abc", "SHOP_API_KEY": "k1", "SHOP_REGION": "east"])
    }

    @Test func itSaysWhatItWillDoBeforeDoingIt() throws {
        let setup = try parse("""
        {"noteling_setup": 1, "name": "Holiday pilot", "tools_repo": {"url": "https://github.example.com/team/tools", "token": "t"},
         "secrets": {"SHOP_API_KEY": "k1"}, "extra": 1}
        """)
        let text = setup.summary(currentRepo: "https://github.example.com/other/tools")
        #expect(text.contains("Link your team's tools from github.example.com/team/tools, keeping its token in your Keychain."))
        #expect(text.contains("This replaces the team tools linked now: github.example.com/other/tools."))
        #expect(text.contains("Save 1 secret in your Keychain: SHOP_API_KEY."))
        #expect(text.contains("Your own settings stay as they are."))
        #expect(text.contains("Not used by this version of Noteling: extra."))
        #expect(!setup.summary(currentRepo: "https://github.example.com/team/tools").contains("replaces"))
        #expect(!text.contains("k1") && !text.contains(#""t""#))   // never a secret's value
    }

    @Test func aPublicRepositoryNeedsNoTokenAndDropsAnEarlierOne() throws {
        let setup = try parse(#"{"noteling_setup": 1, "tools_repo": {"url": "https://github.com/acme/tools"}}"#)
        #expect(setup.name == "your team" && setup.toolsRepo?.token == nil)
        var config = Config()
        var saved: [String: String] = [:]
        try setup.apply(to: &config) { saved[$0] = $1; return true }
        #expect(saved == [LinkedTools.tokenKey: ""] && config.toolsRepoBranch == "main")
        #expect(setup.summary(currentRepo: "").contains("from github.com/acme/tools."))
    }

    @Test func whatIsntASetupFileIsRefusedPlainly() {
        #expect(refusal("not json")?.contains("isn't a Noteling setup file") == true)
        #expect(refusal(#"{"name": "x"}"#)?.contains("\"noteling_setup\": 1") == true)
        #expect(refusal(#"{"noteling_setup": 2, "secrets": {"A": "b"}}"#)?.contains("newer Noteling") == true)
        #expect(refusal(#"{"noteling_setup": 1}"#)?.contains("doesn't set anything") == true)
        #expect(refusal(#"{"noteling_setup": 1, "tools_repo": {"token": "t"}}"#)?.contains("needs a \"url\"") == true)
        #expect(refusal(#"{"noteling_setup": 1, "tools_repo": {"url": "not a repo"}}"#)?.contains("address can't be used") == true)
        #expect(refusal(#"{"noteling_setup": 1, "secrets": {"lower": "x"}}"#)?.contains("can't be used") == true)
        #expect(refusal(#"{"noteling_setup": 1, "secrets": {"NOTELING_TOOLS_REPO_TOKEN": "x"}}"#)?.contains("under tools_repo") == true)
        #expect(refusal(#"{"noteling_setup": 1, "secrets": {"EMPTY": "  "}}"#)?.contains("has no value") == true)
        let many = (1...21).map { "\"S\($0)\": \"v\"" }.joined(separator: ", ")
        #expect(refusal("{\"noteling_setup\": 1, \"secrets\": {\(many)}}")?.contains("up to 20") == true)
        let big = "{\"noteling_setup\": 1, \"name\": \"" + String(repeating: "x", count: 70_000) + "\"}"
        #expect(refusal(big)?.contains("too big") == true)
    }

    @Test func aSecretTheKeychainWontTakeIsSaid() throws {
        let setup = try parse(#"{"noteling_setup": 1, "secrets": {"SHOP_API_KEY": "k1"}}"#)
        var config = Config()
        do {
            try setup.apply(to: &config) { _, _ in false }
            Issue.record("a failed save should be said")
        } catch {
            #expect(error.localizedDescription.contains("Couldn't save SHOP_API_KEY in your Keychain"))
        }
    }

    @Test func teamJobsAreCountedInTheLinkedCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("setup-jobs-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["watches/holiday/oct/fashion", "watches/holiday/oct/gm", "watches/notes"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try "{}".write(to: root.appendingPathComponent("watches/holiday/oct/fashion/watch.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: root.appendingPathComponent("watches/holiday/oct/gm/watch.json"), atomically: true, encoding: .utf8)
        #expect(NotelingSetup.teamJobCount(in: root) == 2)
        #expect(NotelingSetup.teamJobCount(in: nil) == 0)
    }
}
