import Combine
import Foundation

/// What a look at the watches folders found changed since the last one.
struct WatchListChanges: Equatable {
    /// Watches that turned up: a folder someone put there, one that can be read now, or one a team update brought.
    var added: [UUID] = []
    /// Watches whose folder went away (deleted, moved to the Trash, or gone from the team's tools): they stop.
    var removed: [UUID] = []
    /// Items someone added to a watch's files, by watch.
    var newItems: [UUID: Set<String>] = [:]
}

/// The watches: yours, one folder each (at any depth) in `watches/` in Noteling's folder, which people can read, edit
/// and hand to a teammate the way they do a tool pack; and your team's, the folders in the linked tools' `watches/`,
/// which Noteling only reads, and checks once you turn them on. A watch's watch.json (and items file) changed by hand,
/// or by an update of the team's tools, is read again at the next look. One that can't be read is never written over
/// or deleted, and the watch keeps its last good definition until it's fixed. Stopping a watch of yours moves its
/// folder to the Trash, where it can be put back. What your team's watches find, and which you turned on, are kept in
/// `team-watches/` in Noteling's folder, since every update replaces the team's copy.
@MainActor
final class WatchListStore: ObservableObject {
    @Published private(set) var watches: [WatchListWatch] = []
    /// Watches whose watch.json (or items file) can't be read right now: "Can't read watch.json: <reason>".
    @Published private(set) var problems: [UUID: String] = [:]
    /// Your folders in `watches/` with a watch.json Noteling couldn't read or take, by path, with why.
    @Published private(set) var unreadable: [String: String] = [:]
    /// The same for your team's.
    @Published private(set) var teamUnreadable: [String: String] = [:]
    /// Something to say about the list as a whole: that an earlier watch list couldn't be moved into folders.
    @Published private(set) var notice: String?
    let directory: URL
    /// Your team's watches, `watches/` in the linked tools, when they are linked. Asked at every look.
    let teamDirectory: () -> URL?
    /// What your team's watches found, and which of them you turned on (`on.json`).
    let teamResults: URL
    /// Moves a stopped watch's folder to the Trash. Tests put their own here, so nothing reaches the real Trash.
    var trash: (URL) throws -> Void

    nonisolated static let watchLimit = 20
    /// Team watches turned on at once, and team watches listed at all.
    nonisolated static let teamOnLimit = 20
    nonisolated static let teamLimit = 200
    /// Items in one watch: a list check takes them all at once; a check that takes one item at a time, 50.
    nonisolated static let itemLimit = 200
    nonisolated static let itemLimitEach = 50
    nonisolated static let teamReadOnly = "This job comes from your team's tools. Change it in the team repository."

    private struct Place: Hashable {
        var source: WatchListSource
        var path: String
        var key: String { (source == .team ? "team:" : "own:") + path }
    }

    private struct Record {
        var place: Place
        /// What its files looked like when Noteling last read or wrote them: anything else means reading them again.
        var stamp: WatchListFiles.Stamp
        /// Keys a person added to watch.json that Noteling doesn't use, written back as they were.
        var other: String?
    }
    private var records: [UUID: Record] = [:]
    /// The files of each folder that couldn't be read, so they are read (and logged) again only once they change.
    private var unreadableSeen: [String: WatchListFiles.Stamp] = [:]
    /// The team watches you turned on, by path.
    private var teamOn: Set<String> = []

    init(directory: URL = Config.dir.appendingPathComponent("watches"),
         legacyFile: URL? = Config.dir.appendingPathComponent("watch-list.json"),
         teamResults: URL = Config.dir.appendingPathComponent("team-watches"),
         teamDirectory: @escaping () -> URL? = { nil },
         trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.directory = directory
        self.teamResults = teamResults
        self.teamDirectory = teamDirectory
        self.trash = trash
        if let legacyFile { migrate(from: legacyFile) }
        teamOn = Self.readOn(teamResults)
        refresh()
        cleanUpTeam()
    }

    func watch(id: UUID) -> WatchListWatch? { watches.first { $0.id == id } }

    /// The watch's folder: yours, or the team's in the linked tools (which is only ever read).
    func folder(for id: UUID) -> URL? {
        guard let place = records[id]?.place, let root = root(place.source) else { return nil }
        return root.appendingPathComponent(place.path)
    }

    /// The watch's own check, when its folder has one.
    func ownCheck(for id: UUID) -> URL? {
        guard let file = folder(for: id)?.appendingPathComponent(WatchListFiles.ownCheck),
              FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }

    private func root(_ source: WatchListSource) -> URL? { source == .own ? directory : teamDirectory() }

    func add(_ watch: WatchListWatch) throws {
        guard watches.filter({ !$0.isTeam }).count < Self.watchLimit else {
            throw WatchListError("You're already watching \(Self.watchLimit) lists, the most Noteling keeps. Stop one first.")
        }
        try Self.validate(watch)
        var watch = watch
        watch.source = .own
        watch.on = true
        watch.createdAt = Date(timeIntervalSince1970: watch.createdAt.timeIntervalSince1970.rounded(.down))   // as watch.json writes it
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let taken = Set((try? manager.contentsOfDirectory(atPath: directory.path)) ?? [])
        let name = WatchListFiles.slug(watch.name, taken: taken)
        let folder = directory.appendingPathComponent(name)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        watch.path = name
        records[watch.id] = Record(place: Place(source: .own, path: name), stamp: WatchListFiles.Stamp())
        do {
            try writeDefinition(watch)
            try writeResults(watch)
        } catch {
            records[watch.id] = nil
            try? manager.removeItem(at: folder)
            throw error
        }
        watches.append(watch)
    }

    /// Changes one watch. A run keeps what its checks find in memory (`persist: false`) and saves at its end; anything
    /// the person changes is saved at once, and put back if saving fails. A hand edit made since the last look is taken
    /// in first, so a change never writes over it, and a watch.json that can't be read is never written over. A team
    /// watch's definition is the team's: only what its checks find changes here.
    @discardableResult
    func change(_ id: UUID, persist: Bool = true, _ body: (inout WatchListWatch) throws -> Void) throws -> WatchListWatch {
        if persist { refresh(id) }
        guard let index = watches.firstIndex(where: { $0.id == id }) else { throw WatchListError("That watch was stopped.") }
        let before = watches[index]
        var watch = before
        try body(&watch)
        try Self.validate(watch)
        let redefined = watch.definition != before.definition
        if redefined, before.isTeam { throw WatchListError(Self.teamReadOnly) }
        if redefined, let problem = problems[id] {
            throw WatchListError("\(problem) Fix the file, or put back the one it had, first: Noteling doesn't write over a watch.json it can't read.")
        }
        watches[index] = watch
        guard persist || redefined else { return watch }
        do {
            if redefined { try writeDefinition(watch) }
            try writeResults(watch)
        } catch {
            watches[index] = before
            throw error
        }
        return watch
    }

    /// Turns a team watch on or off for you. Off, it isn't checked and doesn't notify; what it found stays.
    func setOn(_ id: UUID, _ on: Bool) throws {
        guard let index = watches.firstIndex(where: { $0.id == id }) else { throw WatchListError("That watch is gone.") }
        let watch = watches[index]
        guard watch.isTeam else { throw WatchListError("Only your team's watches are turned on and off; pause or resume your own.") }
        guard watch.on != on else { return }
        if on, watches.filter({ $0.isTeam && $0.on }).count >= Self.teamOnLimit {
            throw WatchListError("You can have up to \(Self.teamOnLimit) team watches on. Turn one off first.")
        }
        var next = teamOn
        if on { next.insert(watch.path) } else { next.remove(watch.path) }
        try writeOn(next)
        teamOn = next
        watches[index].on = on
    }

    /// Stops a watch of yours: its folder goes to the Trash, so it can be put back.
    func remove(_ id: UUID) throws {
        guard let index = watches.firstIndex(where: { $0.id == id }) else { return }
        guard !watches[index].isTeam else { throw WatchListError(Self.teamReadOnly) }
        if let folder = folder(for: id), FileManager.default.fileExists(atPath: folder.path) {
            do { try trash(folder) }
            catch { throw WatchListError("Couldn't move its folder to the Trash: \(error.localizedDescription)") }
        }
        watches.remove(at: index)
        records[id] = nil
        problems[id] = nil
    }

    /// Writes what a watch's checks found to its latest.json.
    func save(_ id: UUID) throws {
        guard let watch = watch(id: id) else { return }
        try writeResults(watch)
    }

    func save() throws {
        var failure: Error?
        for watch in watches {
            do { try writeResults(watch) } catch { failure = error }
        }
        if let failure { throw failure }
    }

    // MARK: looking at the folders

    /// Looks at both watches folders for what changed: files with a new date or size are read again, a new folder
    /// becomes a watch, and a folder that went away takes its watch with it. Cheap enough for every tick: it reads only
    /// files that changed.
    @discardableResult
    func refresh() -> WatchListChanges {
        var changes = WatchListChanges()
        let own = WatchListFiles.watchFolders(in: directory).map { Place(source: .own, path: $0) }
        let team = teamDirectory().map { WatchListFiles.watchFolders(in: $0) }?.map { Place(source: .team, path: $0) } ?? []
        let present = Set(own + team)
        var gone = records.filter { !present.contains($0.value.place) }
        let known = Dictionary(records.map { ($0.value.place, $0.key) }, uniquingKeysWith: { first, _ in first })
        var found: [Found] = []
        for place in own + team {
            if let id = known[place] { reread(id, changes: &changes) }
            else if let new = read(place) { found.append(new) }
        }
        // Oldest first, so a copy of a folder comes after the one it copies, and past the limit the newest wait.
        for new in found.sorted(by: { ($0.definition.createdAt, $0.place.key) < ($1.definition.createdAt, $1.place.key) }) {
            take(new, gone: &gone, changes: &changes)
        }
        for (id, record) in gone {
            watches.removeAll { $0.id == id }
            records[id] = nil
            problems[id] = nil
            changes.removed.append(id)
            Log.info("watch list: \(record.place.source == .team ? "the team's " : "")\(record.place.path) is gone, so it is no longer watched")
        }
        let paths = Set(present.map(\.key))
        for path in unreadable.keys where !paths.contains("own:" + path) { unreadable[path] = nil }
        for path in teamUnreadable.keys where !paths.contains("team:" + path) { teamUnreadable[path] = nil }
        for key in unreadableSeen.keys where !paths.contains(key) { unreadableSeen[key] = nil }
        if !changes.added.isEmpty { sort() }
        return changes
    }

    /// Looks again at one watch's files, right before a run or a change.
    @discardableResult
    func refresh(_ id: UUID) -> WatchListChanges {
        var changes = WatchListChanges()
        reread(id, changes: &changes)
        return changes
    }

    /// A folder's files, read: what its watch.json and items file say.
    private struct Found {
        var place: Place
        var stamp: WatchListFiles.Stamp
        var definition: WatchListDefinition
        var hadID: Bool
        var file: WatchListItemsFile?
        var fileNote: String?
    }

    /// Reads a watch's files: watch.json and its items file. Throws, in plain words, what can't be read.
    private func parse(_ place: Place, folder: URL) throws -> Found {
        let stamp = WatchListFiles.stamp(of: folder)
        guard stamp.definition != nil else { throw WatchListError("Can't read watch.json: it isn't in the folder.") }
        var file: WatchListItemsFile?
        var note: String?
        if let items = WatchListFiles.itemsFile(in: folder) {
            do { file = try WatchListFiles.parseItems(Data(contentsOf: items.url), name: items.url.lastPathComponent) }
            catch { throw WatchListError("Can't read \(items.url.lastPathComponent): " + Self.reason(error)) }
            note = items.note
        }
        // A team folder is made anew by every update: its own date would make each update look like a change.
        let created = place.source == .team ? Date(timeIntervalSince1970: 0)
            : (try? FileManager.default.attributesOfItem(atPath: folder.path))?[.creationDate] as? Date ?? Date()
        do {
            let data = try Data(contentsOf: folder.appendingPathComponent(WatchListFiles.definition))
            var (definition, hadID) = try WatchListFiles.parseDefinition(data, folder: place.path, created: created, hasItemsFile: file != nil)
            if place.source == .team { definition.id = Self.teamID(place.path) }   // a team job is its path
            return Found(place: place, stamp: stamp, definition: definition, hadID: hadID, file: file, fileNote: note)
        } catch {
            throw WatchListError("Can't read watch.json: " + Self.reason(error))
        }
    }

    /// A team watch's id, the same on every Mac and through every update: made from its path.
    static func teamID(_ path: String) -> UUID { WatchListFiles.derivedID(folder: "team:" + path) }

    private func reread(_ id: UUID, changes: inout WatchListChanges) {
        guard var record = records[id], let root = root(record.place.source) else { return }
        let folder = root.appendingPathComponent(record.place.path)
        // Before reading, so a write that ends after the read is seen next time.
        let stamp = WatchListFiles.stamp(of: folder)
        guard stamp != record.stamp else { return }
        record.stamp = stamp
        records[id] = record
        do {
            let found = try parse(record.place, folder: folder)
            if problems[id] != nil { Log.info("watch list: \(record.place.path) can be read again") }
            problems[id] = nil
            record.other = found.definition.other
            records[id] = record
            guard let index = watches.firstIndex(where: { $0.id == id }) else { return }
            watches[index].fileNote = found.fileNote
            guard !found.definition.sameSettings(as: watches[index].definition) || found.file != watches[index].file else { return }
            let before = watches[index]
            watches[index].adopt(found.definition, file: found.file, quiet: false)
            let added = Set(watches[index].items.map(\.key)).subtracting(before.items.map(\.key))
            if !added.isEmpty { changes.newItems[id] = added }
            Log.info("watch list: took in the changes to \(record.place.source == .team ? "the team's " : "")\(record.place.path)")
        } catch {
            let problem = Self.reason(error)
            if problems[id] != problem { Log.info("watch list: \(record.place.path): \(problem) Its last good definition is used until it's fixed.") }
            problems[id] = problem
        }
    }

    /// Reads a folder not seen before. One whose files can't be read is reported, once until they change.
    private func read(_ place: Place) -> Found? {
        guard let root = root(place.source) else { return nil }
        let folder = root.appendingPathComponent(place.path)
        let stamp = WatchListFiles.stamp(of: folder)
        if unreadableSeen[place.key] == stamp { return nil }
        do { return try parse(place, folder: folder) }
        catch {
            cannot(place, stamp: stamp, Self.reason(error))
            return nil
        }
    }

    /// A folder not watched, and why. Files that can't be read are read again only once they change; a folder past the
    /// limit is looked at again each time, so it is watched as soon as another watch stops.
    private func cannot(_ place: Place, stamp: WatchListFiles.Stamp, _ why: String, untilChanged: Bool = true) {
        let earlier = place.source == .team ? teamUnreadable[place.path] : unreadable[place.path]
        if earlier != why { Log.info("watch list: not watching \(place.source == .team ? "the team's " : "")\(place.path): \(why)") }
        if place.source == .team { teamUnreadable[place.path] = why } else { unreadable[place.path] = why }
        if untilChanged { unreadableSeen[place.key] = stamp } else { unreadableSeen.removeValue(forKey: place.key) }
    }

    /// Takes a folder not seen before: a watch someone put there or copied, one that changed its folder name, one whose
    /// files couldn't be read until now, or one a team update brought.
    private func take(_ found: Found, gone: inout [UUID: Record], changes: inout WatchListChanges) {
        let place = found.place
        if place.source == .team { teamUnreadable[place.path] = nil } else { unreadable[place.path] = nil }
        unreadableSeen[place.key] = nil
        var definition = found.definition
        if place.source == .own, let renamed = gone.removeValue(forKey: definition.id), renamed.place.source == .own {
            // The same watch, in a folder with a new name.
            records[definition.id] = Record(place: place, stamp: found.stamp, other: definition.other)
            Log.info("watch list: \(renamed.place.path) is now \(place.path)")
            guard let index = watches.firstIndex(where: { $0.id == definition.id }) else { return }
            watches[index].path = place.path
            watches[index].fileNote = found.fileNote
            guard !definition.sameSettings(as: watches[index].definition) || found.file != watches[index].file else { return }
            let before = watches[index]
            watches[index].adopt(definition, file: found.file, quiet: false)
            let added = Set(watches[index].items.map(\.key)).subtracting(before.items.map(\.key))
            if !added.isEmpty { changes.newItems[definition.id] = added }
            return
        }
        let count = watches.filter { $0.source == place.source }.count
        guard count < (place.source == .team ? Self.teamLimit : Self.watchLimit) else {
            cannot(place, stamp: found.stamp, place.source == .team
                   ? "Not listed: Noteling lists up to \(Self.teamLimit) of your team's watches."
                   : "Not watched: Noteling watches up to \(Self.watchLimit) lists. Stop one to watch this one.", untilChanged: false)
            return
        }
        let copy = place.source == .own && records[definition.id] != nil   // a copy of another watch's folder is a watch of its own
        if copy { definition.id = WatchListFiles.derivedID(folder: place.path) }
        var watch = WatchListWatch(id: definition.id, name: definition.name, check: definition.check, items: [])
        watch.source = place.source
        watch.path = place.path
        watch.on = place.source == .own || teamOn.contains(place.path)
        watch.adopt(definition, file: found.file, quiet: false)
        watch.fileNote = found.fileNote
        if let data = try? Data(contentsOf: resultsFile(place)) {
            do { try WatchListFiles.readResults(data, into: &watch) }
            catch { Log.info("watch list: \(place.path)/latest.json can't be read (\(Self.reason(error))); its items are checked afresh") }
        }
        // Its files may have changed while Noteling wasn't looking: what counts as right is worked out again.
        watch.reexpect(quiet: false)
        records[watch.id] = Record(place: place, stamp: found.stamp, other: definition.other)
        watches.append(watch)
        changes.added.append(watch.id)
        // An id of its own, written down, so it stays the same if the folder is renamed or copied again.
        if place.source == .own, copy || !found.hadID { try? writeDefinition(watch) }
    }

    private func sort() {
        watches.sort { ($0.createdAt, $0.path) < ($1.createdAt, $1.path) }
    }

    // MARK: writing

    private func writeDefinition(_ watch: WatchListWatch) throws {
        guard var record = records[watch.id], record.place.source == .own else { return }
        var definition = watch.definition
        definition.other = record.other
        let folder = directory.appendingPathComponent(record.place.path)
        try WatchListFiles.write(WatchListFiles.definitionText(definition), to: folder.appendingPathComponent(WatchListFiles.definition))
        record.stamp = WatchListFiles.stamp(of: folder)
        records[watch.id] = record
    }

    private func resultsFile(_ place: Place) -> URL {
        place.source == .own ? directory.appendingPathComponent(place.path).appendingPathComponent(WatchListFiles.results)
            : teamResults.appendingPathComponent(place.path).appendingPathComponent(WatchListFiles.results)
    }

    /// Yours: never makes the folder, so a watch whose folder went away is not brought back by a run that ends after it.
    /// The team's: in `team-watches/`, by the job's path, made when needed.
    private func writeResults(_ watch: WatchListWatch) throws {
        guard let record = records[watch.id] else { return }
        let file = resultsFile(record.place)
        let manager = FileManager.default
        if record.place.source == .team {
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } else if !manager.fileExists(atPath: file.deletingLastPathComponent().path) {
            return
        }
        try WatchListFiles.write(WatchListFiles.resultsText(watch), to: file)
    }

    private static func validate(_ watch: WatchListWatch) throws {
        guard watch.items.count <= itemLimit else {
            throw WatchListError("A watch holds up to \(itemLimit) items. Split them into two watches.")
        }
    }

    static func reason(_ error: Error) -> String {
        (error as? WatchListError)?.message ?? error.localizedDescription
    }

    // MARK: your team's watches

    private static func onFile(_ teamResults: URL) -> URL { teamResults.appendingPathComponent("on.json") }

    private static func readOn(_ teamResults: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: onFile(teamResults)),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        return Set(object["on"] as? [String] ?? [])
    }

    private func writeOn(_ paths: Set<String>) throws {
        try FileManager.default.createDirectory(at: teamResults, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try WatchListFiles.write(WatchListJSON.pretty(["on": paths.sorted()], indent: "") + "\n", to: Self.onFile(teamResults))
    }

    /// At launch: what team watches that are no longer in the team's tools found, and whether they were on, go. Only
    /// while the team's tools are there, so a copy that is missing for a moment takes nothing with it.
    private func cleanUpTeam() {
        guard let root = teamDirectory(), FileManager.default.fileExists(atPath: root.path) else { return }
        let paths = Set(WatchListFiles.watchFolders(in: root))
        let manager = FileManager.default
        if let walk = manager.enumerator(at: teamResults, includingPropertiesForKeys: nil) {
            let base = teamResults.standardizedFileURL.path + "/"
            for case let url as URL in walk where url.lastPathComponent == WatchListFiles.results {
                let path = String(url.deletingLastPathComponent().standardizedFileURL.path.dropFirst(base.count))
                guard !paths.contains(path) else { continue }
                try? manager.removeItem(at: url)
                Log.info("watch list: the team's \(path) is gone from its tools, so what it found was deleted")
            }
        }
        let kept = teamOn.intersection(paths)
        if kept != teamOn, (try? writeOn(kept)) != nil { teamOn = kept }
    }

    // MARK: the earlier single file

    /// Moves the watches of an earlier `watch-list.json` into folders, once: only while there is no watches folder
    /// yet. The folders are made beside it and moved into place whole, and only then is the old file renamed
    /// `watch-list.json.moved-<time>`; if anything fails, the old file stays as it is and the move is tried again at
    /// the next launch.
    private func migrate(from legacy: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: legacy.path), !manager.fileExists(atPath: directory.path) else { return }
        let staging = directory.deletingLastPathComponent().appendingPathComponent(".watches-moving-\(UUID().uuidString)")
        do {
            let old = try SourceRunJSON.decoder().decode(LegacyWatchList.self, from: Data(contentsOf: legacy))
            try manager.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var taken = Set<String>()
            for var watch in old.watches.prefix(Self.watchLimit) {
                // What counted as right is where it starts from now, so a value taken out of expect later goes back to it.
                for index in watch.items.indices { watch.items[index].captured = watch.items[index].expected }
                let name = WatchListFiles.slug(watch.name, taken: taken)
                taken.insert(name)
                let folder = staging.appendingPathComponent(name)
                try manager.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                try WatchListFiles.write(WatchListFiles.definitionText(watch.definition), to: folder.appendingPathComponent(WatchListFiles.definition))
                try WatchListFiles.write(WatchListFiles.resultsText(watch), to: folder.appendingPathComponent(WatchListFiles.results))
            }
            try manager.moveItem(at: staging, to: directory)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
            let moved = legacy.deletingLastPathComponent().appendingPathComponent(legacy.lastPathComponent + ".moved-" + stamp)
            do { try manager.moveItem(at: legacy, to: moved) }
            catch { Log.info("watch list: moved the watches, but couldn't rename \(legacy.lastPathComponent): \(error.localizedDescription)") }
            Log.info("watch list: moved \(min(old.watches.count, Self.watchLimit)) watch(es) from \(legacy.lastPathComponent) into \(directory.lastPathComponent)/")
        } catch {
            try? manager.removeItem(at: staging)
            notice = "Your earlier watch list couldn't be moved into the watches folder, so it was left as \(legacy.lastPathComponent): "
                + Self.reason(error)
            Log.info("watch list: couldn't move \(legacy.lastPathComponent) into folders: \(Self.reason(error))")
        }
    }
}

/// The earlier single `watch-list.json`: every watch with its results, in one file.
struct LegacyWatchList: Codable {
    var version = 1
    var watches: [WatchListWatch]
}
