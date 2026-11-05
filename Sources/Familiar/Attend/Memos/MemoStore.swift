import AppKit
import Combine
import Foundation

/// Your notes on this Mac: one file each in `memos/`, read at launch and again whenever the folder changes, so a note
/// edited or deleted in Finder changes or goes here too. The store writes a note whole when it changes, remembers in the
/// log what was removed, and wakes a note when its when comes.
@MainActor
final class MemoStore: ObservableObject {
    @Published private(set) var all: [Memo] = []
    /// nil keeps the notes in memory only: renders and tests.
    let directory: URL?
    var clock: () -> Date = Date.init
    /// Where a note's coming and going is written down, so recall still finds a note that was removed.
    var memory: MemoryLog?
    /// A note's when came: the app brings it forward.
    var onWake: ((Memo) -> Void)?
    /// Whether a removed note's file goes to the Trash rather than away; tests keep the Trash clean.
    var trashes = true

    static let folder = "memos"

    private var source: DispatchSourceFileSystemObject?
    private var reloadWork: DispatchWorkItem?
    private var wakeWork: DispatchWorkItem?

    init(directory: URL?) {
        self.directory = directory
        all = Self.read(directory)
        watch()
        scheduleWake()
    }

    deinit { source?.cancel() }

    func memo(id: String) -> Memo? { all.first { $0.id == id } }

    /// An id no note has.
    func freshID() -> String {
        var id = Memo.newID()
        while all.contains(where: { $0.id == id }) { id = Memo.newID() }
        return id
    }

    /// A new blank note on yellow paper, not yet placed; saved only once something is written on it or it is moved.
    func blank() -> Memo {
        let now = clock()
        return Memo(id: freshID(), createdAt: now, updatedAt: now)
    }

    /// Writes the note, new or changed, and remembers a new one in the log.
    func save(_ memo: Memo) {
        var copy = memo
        copy.updatedAt = clock()
        let isNew = !all.contains { $0.id == memo.id }
        if let i = all.firstIndex(where: { $0.id == memo.id }) { all[i] = copy } else { all.append(copy); sort() }
        write(copy)
        if isNew { memory?.append(["note": copy.id, "written": copy.firstLine] + (copy.asked.map { ["asked": $0] } ?? [:])) }
        scheduleWake()
    }

    /// Takes the note away for good; what it said stays in the log.
    /// Takes a note away. Its file goes to the Trash, where a wrong click is undone in Finder; a blank note, or a draft
    /// the scribe never claimed, just goes. The log remembers its first line either way.
    func remove(_ id: String, toTrash: Bool = true) {
        guard let memo = memo(id: id) else { return }
        all.removeAll { $0.id == id }
        if let directory {
            let file = Self.file(id, in: directory)
            let trashed = toTrash && trashes && (try? FileManager.default.trashItem(at: file, resultingItemURL: nil)) != nil
            if !trashed { try? FileManager.default.removeItem(at: file) }
        }
        memory?.append(["note": id, "removed": memo.firstLine])
        scheduleWake()
    }

    /// Ticks or unticks a checklist line.
    func toggle(_ id: String, item index: Int) {
        guard var memo = memo(id: id), memo.items.indices.contains(index) else { return }
        memo.items[index].done.toggle()
        save(memo)
    }

    /// Reads the folder again; publishes only when something differs.
    func reload() {
        let fresh = Self.read(directory)
        if fresh != all { all = fresh; scheduleWake() }
    }

    // MARK: files

    static func file(_ id: String, in directory: URL) -> URL { directory.appendingPathComponent(id).appendingPathExtension(MemoFile.ext) }

    static func read(_ directory: URL?) -> [Memo] {
        guard let directory else { return [] }
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var out: [Memo] = []
        for url in files where url.pathExtension == MemoFile.ext && !url.lastPathComponent.hasPrefix(".") {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            out.append(MemoFile.parse(text, id: url.deletingPathExtension().lastPathComponent, modified: modified))
        }
        return sorted(out)
    }

    private static func sorted(_ memos: [Memo]) -> [Memo] {
        memos.sorted { a, b in a.createdAt != b.createdAt ? a.createdAt < b.createdAt : a.id < b.id }
    }
    private func sort() { all = Self.sorted(all) }

    private func write(_ memo: Memo) {
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JobFiles.write(MemoFile.text(memo), to: Self.file(memo.id, in: directory))
        } catch {
            Log.info("memos: couldn't write \(memo.id): \(error.localizedDescription)")
        }
    }

    /// Finder is the folder: a file added, renamed or removed there reads the folder again, a moment after the last change.
    private func watch() {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .extend, .attrib], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.changedOnDisk() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func changedOnDisk() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: the when

    /// Waits for the nearest when still to come.
    private func scheduleWake() {
        wakeWork?.cancel()
        wakeWork = nil
        let now = clock()
        guard let next = all.compactMap(\.when).filter({ $0 > now }).min() else { return }
        let work = DispatchWorkItem { [weak self] in self?.wakeDue() }
        wakeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + next.timeIntervalSince(now) + 0.5, execute: work)
    }

    /// Every note whose when has just come opens if it was collapsed and is brought forward.
    func wakeDue() {
        let now = clock()
        for memo in all where memo.when.map({ $0 <= now && $0 > now.addingTimeInterval(-120) }) == true {
            var woken = memo
            if woken.collapsed { woken.collapsed = false; save(woken) }
            onWake?(woken)
        }
        scheduleWake()
    }
}

private func + (lhs: [String: Any], rhs: [String: Any]) -> [String: Any] { lhs.merging(rhs) { _, new in new } }
