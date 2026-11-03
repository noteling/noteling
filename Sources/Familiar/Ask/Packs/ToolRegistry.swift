import FamiliarContracts
import Foundation

/// Where a pack applies: its SKILL.md `match:` rules, each a page, an app or a window. A pack leads on the pages its
/// rules name; `match: anywhere` is the explicit everywhere; a pack with no rules is a library, reached only through a
/// pack that `uses:` it. Matching is a plain rule, run on the Mac: a rule someone wrote decides which scripts run with
/// which secrets on which page, never a guess.
struct MatchRules {
    var urls: [String] = []
    var bundles: [String] = []
    var titles: [String] = []
    /// `match: anywhere`: on every page and in every app.
    var anywhere = false
    var isEmpty: Bool { urls.isEmpty && bundles.isEmpty && titles.isEmpty }

    /// How well a rule fits the scene: a page rule with a path beats one for the whole host, which beats an app,
    /// which beats words in a window title. `rule` is the one that hit, in the author's words.
    struct Hit: Equatable {
        var specificity: Int
        var rule: String
    }

    func matches(_ ctx: ScreenContext) -> Bool { hit(ctx) != nil }

    /// The best-fitting rule that hits the scene, if any.
    func hit(_ ctx: ScreenContext) -> Hit? {
        var best: Hit?
        func consider(_ hit: Hit?) {
            guard let hit, hit.specificity > (best?.specificity ?? -1) else { return }
            best = hit
        }
        if let u = ctx.url, !u.isEmpty { for p in urls { consider(Self.urlHit(p, u)) } }
        for p in bundles where Self.bundleMatches(p, ctx.bundleID) { consider(Hit(specificity: 200, rule: p.trimmingCharacters(in: .whitespaces))) }
        for p in titles where Self.match(p, ctx.windowTitle) { consider(Hit(specificity: 100, rule: "windows titled “\(p.trimmingCharacters(in: .whitespaces))”")) }
        return best
    }

    /// A url rule is a host, its subdomains, and the paths under its path: `orders.example.com/order/` is every
    /// order page, with any id, query or fragment. A host with a port is that port; without one, any port. A `*` in
    /// the path stands for anything; a rule that is only a path (`/reports/new`) is that path on any host; `/…/` is a
    /// regex over the whole address, as before. A rule's fit is how deep its path goes, so `example.com/order/`
    /// outranks `example.com`, and `/order/4417` outranks `/order/`.
    static func urlHit(_ pattern: String, _ url: String) -> Hit? {
        let p = pattern.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return nil }
        if isRegex(p) { return match(p, url) ? Hit(specificity: 300, rule: p) : nil }
        guard let components = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host?.lowercased(), !host.isEmpty else {
            return match(p, url) ? Hit(specificity: 300, rule: p) : nil   // not an address: the old substring rule
        }
        var rule = p
        if let scheme = rule.range(of: "://") { rule = String(rule[scheme.upperBound...]) }
        if let query = rule.firstIndex(where: { $0 == "?" }) { rule = String(rule[..<query]) }   // a rule names no query
        let slash = rule.firstIndex(of: "/")
        var ruleHost = (slash.map { String(rule[..<$0]) } ?? rule).lowercased()
        let rulePath = slash.map { String(rule[$0...]) } ?? ""
        if ruleHost.hasPrefix("*.") { ruleHost.removeFirst(2) }
        if !ruleHost.isEmpty {
            if let colon = ruleHost.lastIndex(of: ":"), let port = Int(ruleHost[ruleHost.index(after: colon)...]) {
                guard components.port == port || (components.port == nil && defaultPort(components.scheme) == port) else { return nil }
                ruleHost = String(ruleHost[..<colon])
            }
            guard host == ruleHost || host.hasSuffix("." + ruleHost) else { return nil }
        }
        let depth = pathDepth(rulePath)
        guard !ruleHost.isEmpty || depth > 0 else { return nil }
        guard pathMatches(rulePath, pagePath(components)) else { return nil }
        return Hit(specificity: depth == 0 ? 300 : 400 + min(depth, 99), rule: p)
    }

    /// How deep a rule's path goes: its parts, not counting a `*` or the `#` of a route, so `/*` is as broad as no
    /// path, and `/order/4417` is deeper than `/order/`.
    private static func pathDepth(_ rulePath: String) -> Int {
        rulePath.split(separator: "/").filter { $0 != "*" && $0 != "#" }.count
    }

    /// The page's path, with an app's `#/route` as part of it, the way the notes' page key sees it.
    private static func pagePath(_ components: URLComponents) -> String {
        var path = components.path.isEmpty ? "/" : components.path
        if let fragment = components.fragment, fragment.hasPrefix("/") {
            path += "#" + String(fragment.split(separator: "?", maxSplits: 1).first ?? "")
        }
        return path.lowercased()
    }

    /// `/order/` and `/order` both cover `/order`, `/order/123` and `/order#/x`, never `/orders`; `*` stands for
    /// anything, and what follows it ends at a part's end too: `/*/reviews` is not `/9/reviews-archive`.
    private static func pathMatches(_ rulePath: String, _ path: String) -> Bool {
        var prefix = rulePath.lowercased()
        while prefix.count > 1, prefix.hasSuffix("/") { prefix.removeLast() }
        if prefix.isEmpty || prefix == "/" { return true }
        if prefix.contains("*") {
            let regex = "^" + prefix.split(separator: "*", omittingEmptySubsequences: false)
                .map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: ".*") + "(?:$|[/#])"
            return path.range(of: regex, options: .regularExpression) != nil
        }
        return path == prefix || path.hasPrefix(prefix + "/") || path.hasPrefix(prefix + "#")
    }

    private static func defaultPort(_ scheme: String?) -> Int? {
        switch scheme?.lowercased() { case "https": return 443; case "http": return 80; default: return nil }
    }

    /// An app rule is its bundle id, whole (case doesn't matter), or `/…/` as a regex.
    static func bundleMatches(_ pattern: String, _ bundleID: String) -> Bool {
        let p = pattern.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, !bundleID.isEmpty else { return false }
        if isRegex(p) { return match(p, bundleID) }
        return p.caseInsensitiveCompare(bundleID) == .orderedSame
    }

    private static func isRegex(_ p: String) -> Bool { p.count > 2 && p.hasPrefix("/") && p.hasSuffix("/") }

    /// `/regex/` matches as a case-insensitive regex, anything else as a case-insensitive substring.
    static func match(_ pattern: String, _ s: String) -> Bool {
        let p = pattern.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, !s.isEmpty else { return false }
        if isRegex(p) {
            let body = String(p.dropFirst().dropLast())
            return s.range(of: body, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return s.range(of: p, options: .caseInsensitive) != nil
    }

    /// Where the pack applies, in a few words, for the model and for people.
    var words: String {
        if anywhere { return "anywhere" }
        var parts = urls
        parts += bundles.map { "the app \($0)" }
        parts += titles.map { "windows titled “\($0)”" }
        return parts.joined(separator: ", ")
    }
}

struct DocFile {
    let relPath: String   // relative to the tools root, e.g. "expenses/docs/expense-reports.md"
    let text: String
}

struct ScriptTool {
    let id: String        // API tool name, e.g. "expenses__report_status"
    let packDir: String
    let fileName: String
    let path: URL
    var description: String
    var inputSchema: [String: Any]
    var dependencies: [String]

    var definition: [String: Any] { definition(scope: nil) }

    /// The tool as the model sees it. `scope` says where its pack applies on this turn ("for this page", "anywhere",
    /// "used here by Orders"), so a tool for the page in front reads differently from one that works everywhere.
    func definition(scope: String?) -> [String: Any] {
        let place = scope.map { ", \($0)" } ?? ""
        return ["name": id, "description": "[\(packDir)/scripts/\(fileName)\(place)] \(description)", "input_schema": inputSchema]
    }
}

final class ToolPack {
    let dirName: String
    let dir: URL
    var name: String
    var description: String
    var match = MatchRules()
    var uses: [String] = []         // packs (by folder name) whose tools come along on this pack's pages (SKILL.md `uses:`)
    var requires: [String] = []     // env var names the scripts need (secrets from the Keychain)
    var irreversible: [String] = [] // control labels the background lane must confirm before pressing (SKILL.md `irreversible:`)
    var sources: [String] = []      // scripts a saved job can read through (SKILL.md `sources:`, script names without .py)
    var brief: String?              // script run ahead for the page in front, so the pen answers from it (SKILL.md `brief:`)
    var pen: [String] = []          // questions the pen offers as taps on this pack's pages (SKILL.md `pen:`), up to 3
    var body = ""
    var docs: [DocFile] = []
    var scripts: [ScriptTool] = []
    var notes: [StickyNote] = []    // notes.json: what people stuck to this tool's controls with the pen
    var paths: [String: ShowPath] = [:]   // paths/*.json: ways someone showed with Watch Me, to show the next person
    var linked = false              // from the team's linked tools (`LinkedTools`), which only an update changes
    /// `match: anywhere`: with every page, in every app.
    var isGlobal: Bool { match.anywhere }
    /// No rules at all: a library, whose tools and words reach a page only through a pack that uses it.
    var isLibrary: Bool { match.isEmpty && !match.anywhere }

    init(dirName: String, dir: URL) {
        self.dirName = dirName
        self.dir = dir
        self.name = dirName
        self.description = ""
    }
}

/// The packs for one scene. `active` are the packs whose rules hit it, the best fit first: that one leads (its brief,
/// its pen questions, its answer shape). `hooked` are the packs the active ones use here. `global` apply anywhere.
/// `others` are packs for other pages and libraries nobody uses here: named to the model, never their tools.
struct PackSelection {
    var active: [ToolPack] = []
    var hooked: [ToolPack] = []
    var global: [ToolPack] = []
    var others: [ToolPack] = []
    /// The rule each active pack hit, by folder name.
    var hits: [String: MatchRules.Hit] = [:]
    /// Which packs use each hooked one here, by the hooked pack's folder name.
    var usedBy: [String: [String]] = [:]

    var lead: ToolPack? { active.first }
    /// The packs whose scripts are tools and whose words go with the request.
    var offered: [ToolPack] { active + hooked + global }

    /// Where a pack stands on this turn, for the model: beside its tools and over its words.
    func scope(of pack: ToolPack) -> String {
        if active.contains(where: { $0 === pack }) { return "for this page" }
        if pack.isGlobal { return "anywhere" }
        if let by = usedBy[pack.dirName], !by.isEmpty { return "used here by \(by.joined(separator: " and "))" }
        return pack.isLibrary ? "a library" : "for other pages"
    }
}

/// `~/.noteling/tools/<pack>/{SKILL.md, docs/**, scripts/*.py}`, then the team's linked tools, in the same shape.
@MainActor
final class ToolRegistry {
    /// Your own tools folder: the only one Noteling writes packs, notes or workflows into.
    let root: URL
    /// The team's tools: a copy of the linked repository, replaced whole on each update, so never written to. A pack
    /// of your own with the same folder name is used instead of the linked one.
    var linkedRoot: URL?
    /// The scripts that make secrets (`secretScripts`), as `pack/script`: never tools, briefs or a job's sources, so a
    /// token never reaches Claude or a conversation.
    var secretScripts: () -> Set<String> = { [] }
    let runner: ScriptRunner
    private(set) var packs: [ToolPack] = []
    private(set) var lastError: String?
    private var reloading: Task<Void, Never>?

    init(root: URL, runner: ScriptRunner) {
        self.root = root
        self.runner = runner
    }

    /// Reloads run one after another, so the one started last is the one that counts, even when an update replaces
    /// the linked tools while an earlier reload is still reading them.
    func reload() async {
        let previous = reloading
        let next = Task { await previous?.value; await self.load() }
        reloading = next
        await next.value
    }

    private func load() async {
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        var result: [ToolPack] = []
        let own = Self.packFolders(in: root)
        let ownNames = Set(own.map(\.lastPathComponent))
        let linked = linkedRoot.map { Self.packFolders(in: $0) } ?? []
        for dir in linked where ownNames.contains(dir.lastPathComponent) {
            Log.info("tools: your own \(dir.lastPathComponent) is used instead of the linked one")
        }
        for (dir, isLinked) in own.map({ ($0, false) }) + linked.filter({ !ownNames.contains($0.lastPathComponent) }).map({ ($0, true) }) {
            let pack = ToolPack(dirName: dir.lastPathComponent, dir: dir)
            pack.linked = isLinked
            if let skill = try? String(contentsOf: dir.appendingPathComponent("SKILL.md"), encoding: .utf8) {
                let (fm, body) = Self.parseFrontmatter(skill)
                pack.name = fm["name"] as? String ?? pack.dirName
                pack.description = fm["description"] as? String ?? ""
                pack.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
                pack.requires = Self.list(fm["requires"]).filter { $0 != LinkedTools.tokenKey }   // that token is Noteling's own
                pack.irreversible = Self.list(fm["irreversible"])
                pack.sources = Self.list(fm["sources"])
                pack.brief = Self.list(fm["brief"]).first
                pack.pen = Self.list(fm["pen"]).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                var used = Set<String>()
                pack.uses = Self.list(fm["uses"]).map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && $0 != pack.dirName && used.insert($0).inserted }
                pack.match = Self.matchRules(fm["match"])
            }
            pack.docs = loadDocs(pack)
            pack.scripts = await loadScripts(pack)
            pack.notes = NoteStore.load(packDir: dir)
            pack.paths = ShowPathStore.load(packDir: dir)
            result.append(pack)
        }
        packs = result
        let scriptCount = packs.reduce(0) { $0 + $1.scripts.count }
        let noteCount = packs.reduce(0) { $0 + $1.notes.count }
        let linkedCount = packs.filter(\.linked).count
        let place = root.path + (linkedCount > 0 ? " and \(linkedCount) linked in \(linkedRoot?.path ?? "")" : "")
        Log.info("tools: \(packs.count) pack(s), \(scriptCount) script(s), \(noteCount) note(s) in \(place); runtime: \(runner.summary)")
        let libraries = packs.filter(\.isLibrary).map(\.dirName)
        if !libraries.isEmpty {
            Log.info("tools: libraries (no match, so used only through a pack that uses them): \(libraries.joined(separator: ", "))")
        }
    }

    /// The `match:` value of a SKILL.md: `anywhere`, or `urls:`/`bundles:`/`titles:` lists.
    nonisolated static func matchRules(_ value: Any?) -> MatchRules {
        var rules = MatchRules()
        if let m = value as? [String: Any] {
            rules.urls = list(m["urls"])
            rules.bundles = list(m["bundles"])
            rules.titles = list(m["titles"])
            if let a = m["anywhere"] as? String, ["true", "yes"].contains(a.lowercased()) { rules.anywhere = true }
        } else if let s = value as? String, s.trimmingCharacters(in: .whitespaces).lowercased() == "anywhere" {
            rules.anywhere = true
        }
        return rules
    }

    /// A tools folder's `watches/` held watches, which no longer run: the name stays reserved, so a folder of them left
    /// behind isn't taken for a pack (Jobs says it's there).
    nonisolated static let watchesFolder = "watches"
    /// Its `jobs/` holds jobs kept as folders (`FolderJobStore`).
    nonisolated static let jobsFolder = "jobs"

    /// The packs a tools folder holds: its folders (or links to one), not hidden ones, `watches/` or `jobs/`, by name.
    nonisolated static func packFolders(in root: URL) -> [URL] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries.filter { dir in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue   // follows symlinks
                && !dir.lastPathComponent.hasPrefix(".") && dir.lastPathComponent != watchesFolder && dir.lastPathComponent != jobsFolder
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The folder in your own tools for a new pack called `name`: that name, unless only the linked tools have a pack
    /// of it. One of yours would hide theirs, so yours gets a name of its own beside it.
    func personalPackDir(for name: String) -> String {
        let fm = FileManager.default
        func linkedOnly(_ n: String) -> Bool {
            guard let linkedRoot else { return false }
            return fm.fileExists(atPath: linkedRoot.appendingPathComponent(n).path) && !fm.fileExists(atPath: root.appendingPathComponent(n).path)
        }
        guard linkedOnly(name) else { return name }
        var candidate = name + "-mine", n = 2
        while linkedOnly(candidate) { candidate = "\(name)-mine-\(n)"; n += 1 }
        return candidate
    }

    // MARK: notes

    /// Where notes are kept now; tool packs only hold notes from before it, until they are moved.
    var notesStore: NotesStore?

    /// Every note whose anchor is on the current scene: the store's, then any still kept in a pack that the store
    /// has no copy of and didn't remove (a linked pack's copy is never changed, so the store's word counts).
    func notes(for ctx: ScreenContext?) -> [StickyNote] {
        let stored = notesStore?.notes(for: ctx) ?? []
        return stored + packNotes(for: ctx).filter { notesStore?.supersedes($0.id) != true }
    }

    /// Each note once: your own packs come first, so your copy of a team note wins.
    private func packNotes(for ctx: ScreenContext?) -> [StickyNote] {
        guard let ctx else { return [] }
        var seen = Set<String>()
        return packs.flatMap { $0.notes.filter { $0.anchor.matchesScene(ctx) } }.filter { seen.insert($0.id).inserted }
    }

    func pack(holding noteID: String) -> ToolPack? {
        packs.first { $0.notes.contains { $0.id == noteID } }
    }

    /// The pack a new note belongs to: the best-fitting of your own packs whose match rules cover the note's scene,
    /// else one created for it in your own tools folder.
    func packForNote(anchor: NoteAnchor, appName: String?) async throws -> ToolPack {
        if let p = select(for: anchor.sceneContext).active.first(where: { !$0.linked }) { return p }
        let dir = try NoteStore.ensurePack(for: anchor, appName: appName, root: root,
                                           dirName: personalPackDir(for: NoteStore.packSlug(for: anchor, appName: appName)))
        await reload()
        guard let p = packs.first(where: { !$0.linked && $0.dir.lastPathComponent == dir.lastPathComponent }) else {
            throw ClaudeError(message: "Could not create a pack for the note in \(dir.path).")
        }
        return p
    }

    /// Adds or replaces a note (by id) in its pack and writes notes.json. Never in a linked pack.
    func put(_ note: StickyNote, in pack: ToolPack) throws {
        guard !pack.linked else {
            throw ClaudeError(message: "\(pack.name) comes from the team's linked tools, which Noteling doesn't change. The note wasn't saved there.")
        }
        var notes = pack.notes.filter { $0.id != note.id }
        notes.append(note)
        try NoteStore.save(notes, packDir: pack.dir)
        pack.notes = notes
    }

    /// Takes a note out of its pack. A linked pack's file stays as the team wrote it; the notes store remembers the removal.
    func removeNote(id: String) throws {
        guard let pack = pack(holding: id) else { return }
        let notes = pack.notes.filter { $0.id != id }
        if !pack.linked { try NoteStore.save(notes, packDir: pack.dir) }
        pack.notes = notes
    }

    private func loadDocs(_ pack: ToolPack) -> [DocFile] {
        let docsDir = pack.dir.appendingPathComponent("docs")
        guard let e = FileManager.default.enumerator(at: docsDir, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var out: [DocFile] = []
        let base = docsDir.resolvingSymlinksInPath().path + "/"   // the enumerator may hand back resolved paths (/private/tmp vs /tmp)
        for case let url as URL in e {
            guard ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let rel = pack.dirName + "/docs/" + url.resolvingSymlinksInPath().path.replacingOccurrences(of: base, with: "")
            out.append(DocFile(relPath: rel, text: text))
        }
        return out.sorted { $0.relPath < $1.relPath }
    }

    private func loadScripts(_ pack: ToolPack) async -> [ScriptTool] {
        let dir = pack.dir.appendingPathComponent("scripts")
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "py" && !$0.lastPathComponent.hasPrefix("_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { return [] }
        guard runner.available else {
            lastError = "Scripts found but no Python runtime (install uv)."
            return []
        }
        var out: [ScriptTool] = []
        let withheld = secretScripts()
        for f in files {
            let stem = f.deletingPathExtension().lastPathComponent
            if withheld.contains("\(pack.dirName)/\(stem)") {
                Log.info("tools: \(pack.dirName)/scripts/\(f.lastPathComponent) makes a secret, so it isn't a tool")
                continue
            }
            let id = Self.toolName("\(pack.dirName)__\(stem)")
            do {
                let s = try await runner.introspect(f)
                out.append(ScriptTool(id: id, packDir: pack.dirName, fileName: f.lastPathComponent, path: f,
                                      description: s.description, inputSchema: s.inputSchema, dependencies: s.dependencies))
            } catch {
                Log.info("tools: skipping \(pack.dirName)/scripts/\(f.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return out
    }

    /// The packs for a scene: those whose rules hit it, best fit first (a tie goes to your own pack, then by folder
    /// name: `packs` holds them in that order); then the packs they use here, each once, following what those use in
    /// turn; then the packs for anywhere. With no scene, nothing is active: the packs for anywhere are all that's offered.
    func select(for ctx: ScreenContext?) -> PackSelection {
        var selection = PackSelection()
        var scored: [(pack: ToolPack, hit: MatchRules.Hit, order: Int)] = []
        for (order, p) in packs.enumerated() {
            if p.isGlobal { selection.global.append(p) }
            else if let ctx, let hit = p.match.hit(ctx) { scored.append((p, hit, order)) }
            else { selection.others.append(p) }
        }
        scored.sort { a, b in a.hit.specificity != b.hit.specificity ? a.hit.specificity > b.hit.specificity : a.order < b.order }
        selection.active = scored.map(\.pack)
        for s in scored { selection.hits[s.pack.dirName] = s.hit }

        var taken = Set((selection.active + selection.global).map(\.dirName))
        var queue = (selection.active + selection.global).map { (user: $0, uses: $0.uses) }
        while !queue.isEmpty {
            let (user, uses) = queue.removeFirst()
            for name in uses {
                // A pack for anywhere is there already, as itself: using it changes nothing.
                guard let used = packs.first(where: { $0.dirName == name }), !used.isGlobal else { continue }
                if !selection.usedBy[name, default: []].contains(user.name) { selection.usedBy[name, default: []].append(user.name) }
                guard taken.insert(name).inserted else { continue }
                selection.hooked.append(used)
                selection.others.removeAll { $0 === used }
                queue.append((used, used.uses))
            }
        }
        return selection
    }

    /// Required secrets that are not in the Keychain, per pack.
    func missingRequirements(for packs: [ToolPack]) -> [(pack: ToolPack, keys: [String])] {
        packs.compactMap { p in
            let missing = p.requires.filter { !Secrets.has($0) && ProcessInfo.processInfo.environment[$0] == nil }
            return missing.isEmpty ? nil : (p, missing)
        }
    }

    /// Scripts a saved job can read through, with the pack that holds each.
    func sourceScripts() -> [(pack: ToolPack, script: ScriptTool)] {
        packs.flatMap { pack in
            pack.scripts.filter { pack.sources.contains(($0.fileName as NSString).deletingPathExtension) }.map { (pack, $0) }
        }
    }

    /// A pack's named script (`brief:` in its SKILL.md), when the pack has it.
    func script(_ name: String?, in pack: ToolPack) -> ScriptTool? {
        guard let name, !name.isEmpty else { return nil }
        let stem = (name as NSString).deletingPathExtension
        return pack.scripts.first { ($0.fileName as NSString).deletingPathExtension == stem }
    }

    /// The pack that holds a script, for its required secrets.
    func pack(holdingScript id: String) -> ToolPack? {
        packs.first { $0.scripts.contains { $0.id == id } }
    }

    /// Packs that shipped before `.bundled-packs` existed: an install without one of them removed it on purpose.
    nonisolated static let earlierBundledPacks: Set<String> = ["expenses", "hr-portal", "it-access", "shared", "waxwing"]

    /// Copies bundled packs this tools folder has never been offered, so a pack added in an update reaches existing
    /// installs. Packs people edited or removed are left alone: `.bundled-packs` records what was offered before.
    @discardableResult
    nonisolated static func addMissingPacks(from bundled: URL, to root: URL) -> [String] {
        let fm = FileManager.default
        let record = root.appendingPathComponent(".bundled-packs")
        let names = ((try? fm.contentsOfDirectory(atPath: bundled.path)) ?? []).filter { name in
            var isDir: ObjCBool = false
            return !name.hasPrefix(".") && fm.fileExists(atPath: bundled.appendingPathComponent(name).path, isDirectory: &isDir) && isDir.boolValue
        }.sorted()
        var offered: Set<String>
        if let text = try? String(contentsOf: record, encoding: .utf8) {
            offered = Set(text.split(whereSeparator: \.isNewline).map(String.init))
        } else {
            offered = earlierBundledPacks.union((try? fm.contentsOfDirectory(atPath: root.path)) ?? [])
        }
        var added: [String] = []
        for name in names where !offered.contains(name) {
            let target = root.appendingPathComponent(name)
            if !fm.fileExists(atPath: target.path) {
                guard (try? fm.copyItem(at: bundled.appendingPathComponent(name), to: target)) != nil else { continue }
                added.append(name)
            }
            offered.insert(name)
        }
        try? (offered.sorted().joined(separator: "\n") + "\n").write(to: record, atomically: true, encoding: .utf8)
        return added
    }

    /// Written into a tools folder once its packs have been asked where they apply (`markOwnPacksAnywhereOnce`).
    nonisolated static let placesAskedMarker = ".packs-say-where"

    /// Before packs said `match: anywhere`, a pack with no rules applied everywhere. The first time a tools folder
    /// is read since, every pack of the person's own with no rules at all is marked `match: anywhere`, once, so it
    /// keeps applying as it did: the person's helpers, and their copies of the bundled shared helpers and mail. A
    /// marker file remembers it was done, so a pack they later leave without rules is a library, as they mean it.
    /// Returns the packs marked.
    @discardableResult
    nonisolated static func markOwnPacksAnywhereOnce(in root: URL) -> [String] {
        let fm = FileManager.default
        let marker = root.appendingPathComponent(placesAskedMarker)
        guard fm.fileExists(atPath: root.path), !fm.fileExists(atPath: marker.path) else { return [] }
        var marked: [String] = []
        for dir in packFolders(in: root) {
            let skill = dir.appendingPathComponent("SKILL.md")
            // A `match:` line with nothing under it is left as it is: that pack says, in its way, nowhere.
            guard let text = try? String(contentsOf: skill, encoding: .utf8), parseFrontmatter(text).0["match"] == nil,
                  let updated = markedAnywhere(text), (try? updated.write(to: skill, atomically: true, encoding: .utf8)) != nil else { continue }
            marked.append(dir.lastPathComponent)
        }
        try? "The packs here say where they apply; one with no match: is a library.\n".write(to: marker, atomically: true, encoding: .utf8)
        return marked
    }

    /// The SKILL.md text with `match: anywhere` as the last line of its front matter, or nil when it has none. A
    /// file with Windows line endings keeps them.
    nonisolated static func markedAnywhere(_ text: String) -> String? {
        let crlf = text.contains("\r\n")
        var lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) else { return nil }
        lines.insert("match: anywhere" + (crlf ? "\r" : ""), at: end)
        return lines.joined(separator: "\n")
    }

    /// The packs of a tools folder that apply nowhere: no `match:` at all, and nothing says `anywhere`. For the
    /// team's linked tools, which Noteling never changes, so Settings can say so.
    nonisolated static func libraryPacks(in root: URL) -> [String] {
        packFolders(in: root).filter { dir in
            guard let text = try? String(contentsOf: dir.appendingPathComponent("SKILL.md"), encoding: .utf8) else { return true }
            let rules = matchRules(parseFrontmatter(text).0["match"])
            return rules.isEmpty && !rules.anywhere
        }.map(\.lastPathComponent)
    }

    func script(named id: String) -> ScriptTool? {
        for p in packs { if let s = p.scripts.first(where: { $0.id == id }) { return s } }
        return nil
    }

    // MARK: parsing helpers

    static func toolName(_ s: String) -> String {
        let cleaned = s.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : Character("_") }
        return String(String(cleaned).prefix(64))
    }

    nonisolated static func list(_ v: Any?) -> [String] {
        if let a = v as? [String] { return a }
        if let s = v as? String, !s.isEmpty { return [s] }
        return []
    }

    /// Tiny YAML subset: `key: value`, `key:` + indented `sub: value`, lists as `[a, b]` or `- item` lines, and a
    /// comment from a `#` after a space to the end of the line, outside quotes. Windows line endings are fine.
    nonisolated static func parseFrontmatter(_ text: String) -> ([String: Any], String) {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return ([:], text) }
        lines.removeFirst()
        guard let end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return ([:], text) }
        let fmLines = Array(lines[..<end])
        let body = lines[(end + 1)...].joined(separator: "\n")

        var top: [String: Any] = [:]
        var currentTop: String?
        var currentSub: String?
        for raw in fmLines {
            let line = uncommented(raw.replacingOccurrences(of: "\t", with: "  "))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = line.prefix { $0 == " " }.count
            if trimmed.hasPrefix("- ") {
                let item = scalar(String(trimmed.dropFirst(2)))
                if let t = currentTop, let s = currentSub, var nested = top[t] as? [String: Any] {
                    nested[s] = (nested[s] as? [String] ?? []) + [item]
                    top[t] = nested
                } else if let t = currentTop {
                    top[t] = (top[t] as? [String] ?? []) + [item]
                }
                continue
            }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if indent == 0 {
                currentTop = key
                currentSub = nil
                top[key] = rest.isEmpty ? [String: Any]() : value(rest)
            } else if let t = currentTop {
                var nested = top[t] as? [String: Any] ?? [:]
                nested[key] = rest.isEmpty ? [String]() : value(rest)
                top[t] = nested
                currentSub = key
            }
        }
        return (top, body)
    }

    /// The line without a comment: from a `#` that follows a space, outside quotes, as YAML has it.
    nonisolated static func uncommented(_ line: String) -> String {
        var quote: Character?
        var previous: Character = " "
        for (i, c) in line.enumerated() {
            if let q = quote { if c == q { quote = nil } }
            else if c == "\"" || c == "'" { quote = c }
            else if c == "#", previous == " " { return String(line.prefix(i)) }
            previous = c
        }
        return line
    }

    private nonisolated static func value(_ s: String) -> Any {
        if s.hasPrefix("[") && s.hasSuffix("]") {
            let inner = s.dropFirst().dropLast()
            return inner.split(separator: ",").map { scalar(String($0)) }.filter { !$0.isEmpty }
        }
        return scalar(s)
    }

    private nonisolated static func scalar(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.count >= 2, (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }
}
