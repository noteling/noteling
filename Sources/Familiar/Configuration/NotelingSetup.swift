import Foundation

/// A setup file a team hands out (`Holiday pilot.notelingsetup`): it links the team's tools and saves the secrets they
/// need, so a person double-clicks once instead of filling in Settings. It can set nothing else, it is never run, and
/// Noteling asks before applying it. The Claude connection then comes from the team's `noteling.json`, as for anyone
/// linked by hand.
///
/// ```json
/// {"noteling_setup": 1, "name": "Holiday pilot",
///  "tools_repo": {"url": "https://github.example.com/team/tools", "token": "github_pat_…"},
///  "secrets": {"SHOP_API_KEY": "…"}}
/// ```
struct NotelingSetup: Equatable {
    static let fileExtension = "notelingsetup"
    static let version = 1
    static let maxBytes = 64 * 1024
    static let maxSecrets = 20

    struct ToolsRepo: Equatable {
        /// The repository's plain web address, as Settings keeps it.
        var url: String
        var token: String?
        var branch: String?
    }

    var name: String
    var toolsRepo: ToolsRepo?
    var secrets: [String: String]
    /// Keys this version of Noteling doesn't use: shown before applying, never applied.
    var unused: [String]

    static func parse(_ data: Data) throws -> NotelingSetup {
        guard data.count <= maxBytes else {
            throw NotelingSetupError("This file is too big to be a Noteling setup file (\(data.count / 1024) KB; a setup file is a few lines).")
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NotelingSetupError("This isn't a Noteling setup file: it isn't readable as one.")
        }
        guard let version = object["noteling_setup"] as? Int else {
            throw NotelingSetupError("This isn't a Noteling setup file: it doesn't say \"noteling_setup\": 1.")
        }
        guard version <= Self.version else {
            throw NotelingSetupError("This setup file is for a newer Noteling. Update Noteling, then open the file again.")
        }
        var unused = object.keys.filter { !["noteling_setup", "name", "tools_repo", "secrets"].contains($0) }

        let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var repo: ToolsRepo?
        if let raw = object["tools_repo"] {
            guard let fields = raw as? [String: Any], let url = fields["url"] as? String else {
                throw NotelingSetupError("Its tools_repo needs a \"url\": the address of your team's tools repository.")
            }
            let address: RepoAddress
            do { address = try RepoAddress.parse(url) } catch {
                throw NotelingSetupError("Its tools_repo address can't be used: \(error.localizedDescription)")
            }
            let token = (fields["token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let branch = (fields["branch"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            repo = ToolsRepo(url: address.webURL, token: token?.isEmpty == false ? token : nil,
                             branch: branch?.isEmpty == false ? branch : nil)
            unused += fields.keys.filter { !["url", "token", "branch"].contains($0) }.map { "tools_repo.\($0)" }
        }

        var secrets: [String: String] = [:]
        if let raw = object["secrets"] {
            guard let fields = raw as? [String: Any] else { throw NotelingSetupError("Its secrets must be names and their values.") }
            for (key, value) in fields {
                guard key.range(of: "^[A-Z][A-Z0-9_]{0,63}$", options: .regularExpression) != nil else {
                    throw NotelingSetupError("The secret name \"\(key)\" can't be used: names are capital letters, digits and _, like SHOP_API_KEY.")
                }
                guard key != LinkedTools.tokenKey else {
                    throw NotelingSetupError("Put the repository's token under tools_repo as \"token\", not among the secrets.")
                }
                guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                    throw NotelingSetupError("The secret \(key) has no value.")
                }
                secrets[key] = text
            }
            guard secrets.count <= maxSecrets else {
                throw NotelingSetupError("It has \(secrets.count) secrets; a setup file holds up to \(maxSecrets).")
            }
        }
        guard repo != nil || !secrets.isEmpty else {
            throw NotelingSetupError("This setup file doesn't set anything: it has no tools_repo and no secrets.")
        }
        return NotelingSetup(name: name?.isEmpty == false ? name! : "your team", toolsRepo: repo, secrets: secrets,
                             unused: unused.sorted())
    }

    /// What applying it will do, said before the person agrees. `currentRepo` is the team tools linked now, if any.
    func summary(currentRepo: String) -> String {
        var lines: [String] = []
        if let repo = toolsRepo {
            let place = repo.url.replacingOccurrences(of: "https://", with: "") + (repo.branch.map { ", branch \($0)" } ?? "")
            lines.append("• Link your team's tools from \(place)" + (repo.token == nil ? "." : ", keeping its token in your Keychain."))
            let current = currentRepo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !current.isEmpty, current != repo.url {
                lines.append("  This replaces the team tools linked now: \(current.replacingOccurrences(of: "https://", with: "")).")
            }
        }
        if !secrets.isEmpty {
            let names = secrets.keys.sorted().joined(separator: ", ")
            lines.append("• Save \(secrets.count == 1 ? "1 secret" : "\(secrets.count) secrets") in your Keychain: \(names).")
        }
        var text = "It will:\n" + lines.joined(separator: "\n") + "\n\nYour own settings stay as they are."
        if !unused.isEmpty { text += "\n\nNot used by this version of Noteling: \(unused.joined(separator: ", "))." }
        return text
    }

    /// Links the team's tools and saves the secrets. `setSecret` is the Keychain (or a test's stand-in); an empty value
    /// removes a secret, so a repository given without a token drops one kept for an earlier repository.
    func apply(to config: inout Config, setSecret: (String, String) -> Bool) throws {
        var failed: [String] = []
        if let repo = toolsRepo {
            config.toolsRepo = repo.url
            config.toolsRepoBranch = repo.branch ?? "main"
            if !setSecret(LinkedTools.tokenKey, repo.token ?? "") { failed.append("the repository's token") }
        }
        for (key, value) in secrets.sorted(by: { $0.key < $1.key }) where !setSecret(key, value) { failed.append(key) }
        guard failed.isEmpty else {
            throw NotelingSetupError("Couldn't save \(failed.joined(separator: ", ")) in your Keychain. Open the file again to retry.")
        }
    }

    /// Team jobs in a linked copy of the team's tools: folders under `watches/` holding a `watch.json`.
    static func teamJobCount(in linkedRoot: URL?) -> Int {
        guard let watches = linkedRoot?.appendingPathComponent(ToolRegistry.watchesFolder),
              let walk = FileManager.default.enumerator(at: watches, includingPropertiesForKeys: nil) else { return 0 }
        return walk.compactMap { $0 as? URL }.filter { $0.lastPathComponent == "watch.json" }.count
    }
}

struct NotelingSetupError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
