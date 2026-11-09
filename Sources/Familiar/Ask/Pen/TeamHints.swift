import AppKit
import Foundation

/// The team's hints: `hints/` at the root of the team's linked tools, one file per hint in the same shape as your
/// own (`~/.noteling/notes/<id>.json`), read with the packs and shown on their pages like yours. Noteling never writes
/// into the linked copy: a hint goes to the team through GitHub, with the file ready to add.
enum TeamHints {
    static let folder = "hints"

    /// The hints in a copy of the team's tools; a file that can't be read is skipped and logged, never fatal.
    static func load(root: URL) -> [StickyNote] {
        let dir = root.appendingPathComponent(folder)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            do { return try JSONDecoder().decode(StickyNote.self, from: Data(contentsOf: url)) }
            catch { Log.info("hints: cannot read \(folder)/\(url.lastPathComponent) in the team's tools: \(error.localizedDescription)"); return nil }
        }
    }

    /// The hint as a file for the team's folder: its name, as the store names it, and its JSON.
    static func file(for note: StickyNote) throws -> (name: String, json: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(note)
        return (NotesStore.file(for: note.id, in: URL(fileURLWithPath: "/")).lastPathComponent, String(decoding: data, as: UTF8.self) + "\n")
    }

    /// GitHub's page for adding this hint to the team's tools, the file already written: `…/new/<branch>` with the
    /// name and the contents in the address. Commit it there, or open a pull request, and everyone who links the
    /// tools has it at their next update.
    static func newFileURL(repo: RepoAddress, branch: String, note: StickyNote) throws -> URL {
        let (name, json) = try file(for: note)
        guard var components = URLComponents(string: repo.webURL + "/new/" + path(branch)) else { throw LinkedToolsError("The team's repository address can't be opened.") }
        components.percentEncodedQuery = "filename=" + encode(folder + "/" + name) + "&value=" + encode(json)
        guard let url = components.url else { throw LinkedToolsError("The hint can't be put in an address for GitHub.") }
        return url
    }

    /// GitHub's page for changing the team's copy of this hint; the new contents can't go in the address, so they go
    /// on the pasteboard to paste there.
    static func editURL(repo: RepoAddress, branch: String, note: StickyNote) throws -> URL {
        let (name, _) = try file(for: note)
        guard let url = URL(string: repo.webURL + "/edit/" + path(branch) + "/" + folder + "/" + encode(name)) else {
            throw LinkedToolsError("The team's repository address can't be opened.")
        }
        return url
    }

    /// A branch as part of the page's path: its slashes stay (`release/2`), the rest is encoded.
    static func path(_ branch: String) -> String { branch.split(separator: "/").map { encode(String($0)) }.joined(separator: "/") }

    /// Percent-encodes everything but unreserved characters, so a `+`, `&` or `=` in a hint reaches GitHub as itself.
    static func encode(_ text: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }
}
