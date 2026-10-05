import CryptoKit
import Foundation

/// A watch's card in Morning Files, through the cards inbox (`CardInbox`): one card per watch, `job.json` in the
/// watch's folder of the inbox, written by Noteling at the end of each run with what that run found, as it found it.
/// No model writes any of it, so a job holding a long list is one card to manage, not one per item. A run with nothing
/// wrong deletes the file, so the card resolves; problems coming back write it again. With `"cards": "all"` the card
/// is always there; with `"cards": false`, and for a team job that's off, there is none. Noteling's file in a watch's
/// folder is `job.json`: anything else a check writes there is the check's own and left alone, except the per-item
/// files earlier versions wrote (`item-…json`), which are deleted so their cards resolve.
@MainActor
final class WatchListCards {
    /// The cards inbox; nil writes no cards.
    let root: URL?
    /// Which check a watch uses, as a card's first line says it.
    var checkLabel: (WatchListWatch) -> String = { $0.check }
    /// What Noteling last wrote, by `<source>/<file name>`, so an unchanged card isn't written again.
    private var written: [String: String] = [:]
    /// Card files of Noteling's that are there, by `<source>/<file name>`: job.json, and earlier versions' item files.
    private var present: Set<String> = []
    private var listed = false

    static let fileName = "job.json"
    /// Items a card lists one by one; the rest are counted.
    static let listLimit = 50

    init(root: URL? = Config.dir.appendingPathComponent("cards/inbox")) { self.root = root }

    /// A watch's folder in the inbox, the same one its check gets as NOTELING_CARDS_DIR: `watch-<path>` for one of
    /// yours, `watch-team-<path>` for a team's, the path's `/` made `-`.
    static func source(for watch: WatchListWatch) -> String {
        CardInboxFormat.safe((watch.isTeam ? "watch-team-" : "watch-") + watch.path.replacingOccurrences(of: "/", with: "-"))
    }

    /// The card's key in the inbox: `<source>/job`.
    static func key(for watch: WatchListWatch) -> String { source(for: watch) + "/job" }

    /// What a watch's card says, or nil when it has none: its cards are off, it is a team job that's off, or nothing
    /// is wrong and only problems get a card. Its words come from the run as it found them:
    /// - title: "Sale items: 2 of 8 not as expected · 6:31 PM", "Sale items: couldn't check 1 of 8 · 6:31 PM", or,
    ///   with `"all"`, "Sale items: all 8 as expected · 6:31 PM";
    /// - body: a summary line ("2 not as expected · 1 couldn't check · 5 as expected · checked 6:31 PM by <check>"),
    ///   then each problem item, red first, then grey: its title (and key), its difference lines as the notification
    ///   writes them and the check's why as it said it, or "Couldn't check: <reason>"; with `"all"`, then every other
    ///   item's one line. Up to 50 items, within what the inbox shows of a body; the rest are counted.
    /// - details: the facts of the problem items it lists; parts: which items are wrong, so a card the person resolved
    ///   opens again only for an item that wasn't wrong then;
    /// - buttons: Open job, and Why?, which asks the chat about the job.
    static func card(for watch: WatchListWatch, checkedBy: String) -> [String: Any]? {
        var budget = CardInboxFormat.bodyLimit, details = CardInboxFormat.detailsLimit
        while true {
            guard let card = card(for: watch, checkedBy: checkedBy, budget: budget, details: details) else { return nil }
            // Well inside the inbox's 64 KB, whatever the words are made of.
            if JSONText.pretty(card, indent: "").utf8.count < CardInboxFormat.fileLimit - 1_024 || budget < 1_000 { return card }
            if details > 0 { details = 0 } else { budget /= 2 }
        }
    }

    private static func card(for watch: WatchListWatch, checkedBy: String, budget: Int, details detailsLimit: Int) -> [String: Any]? {
        guard watch.cards != .off, watch.on else { return nil }
        let items = watch.items
        let red = items.filter(\.isRed)
        let grey = items.filter { if case .couldNotCheck? = $0.status { return true }; return false }
        let green = items.filter { $0.status == .asExpected }
        let unchecked = items.filter { $0.status == nil }
        let problems = red + grey
        guard !problems.isEmpty || watch.cards == .all else { return nil }
        let checked = items.compactMap(\.checkedAt).max()
        let at = checked.map { " · " + time($0) } ?? ""
        let title: String
        if !red.isEmpty { title = "\(watch.name): \(red.count) of \(items.count) not as expected\(at)" }
        else if !grey.isEmpty { title = "\(watch.name): couldn't check \(grey.count) of \(items.count)\(at)" }
        else if items.isEmpty { title = "\(watch.name): no items yet" }
        else if checked == nil { title = "\(watch.name): not checked yet" }
        else if green.count == items.count { title = "\(watch.name): all \(items.count) as expected\(at)" }
        else { title = "\(watch.name): \(green.count) of \(items.count) as expected\(at)" }

        let counts = [(red.count, "not as expected"), (grey.count, "couldn't check"), (green.count, "as expected"),
                      (unchecked.count, "not checked yet")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        var body = (counts.isEmpty ? ["no items"] : counts).joined(separator: " · ")
            + (checked.map { " · checked \(time($0)) by \(checkedBy)" } ?? "")
        // Red first, then grey, each a block of its own; with "all", then every other item's one line.
        let entries = problems.map { (text: block($0), block: true) }
            + (watch.cards == .all ? (green + unchecked).map { (text: line($0), block: false) } : [])
        var listed = 0
        for (index, entry) in entries.enumerated() where listed < listLimit {
            let gap = entry.block || index == 0 || entries[index - 1].block ? "\n\n" : "\n"
            // Room for it, and for the line that counts the rest.
            guard body.count + gap.count + entry.text.count + 80 <= budget else { break }
            body += gap + entry.text
            listed += 1
        }
        if listed < entries.count { body += "\n\n" + more(entries.count - listed) }

        var card: [String: Any] = ["title": title, "body": body, "severity": !red.isEmpty ? "high" : !grey.isEmpty ? "normal" : "low"]
        var actions: [[String: Any]] = [["label": "Open job", "watch": watch.id.uuidString]]
        if !red.isEmpty { actions.append(["label": "Why?", "ask": "Why are items in \(watch.name) not as expected right now?"]) }
        else if !grey.isEmpty { actions.append(["label": "Why?", "ask": "Why couldn't Noteling check items in \(watch.name)?"]) }
        card["actions"] = actions
        let facts = problems.prefix(listed).compactMap { item -> String? in
            guard let facts = item.facts, !facts.isEmpty else { return nil }
            return name(item) + ": " + facts
        }.joined(separator: "\n")
        if !facts.isEmpty, detailsLimit > 0 {
            card["details"] = facts.count > detailsLimit ? String(facts.prefix(detailsLimit - 1)) + "…" : facts
        }
        if !problems.isEmpty { card["parts"] = problems.map { part($0.key) } }
        return card
    }

    /// A problem item: its title (and key), then its difference lines exactly as the notification writes them and
    /// what the check said in its own words, or why it couldn't be checked.
    static func block(_ item: WatchListItem) -> String {
        var lines = [name(item)]
        switch item.status {
        case .notAsExpected(let differences)?: lines += differences.map(\.words)
        case .couldNotCheck(let reason)?: lines.append("Couldn't check: \(reason)")
        default: break
        }
        return (lines + item.whyNow).joined(separator: "\n")
    }

    /// Any other item, in one line: "Blue kettle (123): As expected".
    static func line(_ item: WatchListItem) -> String {
        name(item) + ": " + WatchListWords.words(item, checking: false)
    }

    /// "Blue kettle (123)", or the key alone when the check gave no title.
    static func name(_ item: WatchListItem) -> String {
        item.label == item.key ? item.key : "\(item.label) (\(item.key))"
    }

    /// "…and 1,234 more. Open the job to see them all."
    static func more(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        return "…and \(formatter.string(from: NSNumber(value: count)) ?? String(count)) more. Open the job to see them all."
    }

    /// An item as one of the card's parts: a short digest of its key, so a long page address never fills the file.
    static func part(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// "6:31 PM", in this Mac's time.
    static func time(_ date: Date, in timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// Every watch's card as it should be, and none for watches that are gone, turned off or have cards off: at
    /// launch, at each tick, at the end of each run, and when a team job is turned on or off. A watch being checked
    /// keeps its card as it is until its run ends. Earlier versions' per-item files are deleted. Cheap when nothing
    /// changed: it remembers what it wrote.
    @discardableResult
    func reconcile(_ watches: [WatchListWatch], running: Set<UUID> = []) -> Bool {
        guard let root else { return false }
        if !listed { list(root) }
        var wanted: [String: [String: Any]] = [:]
        var kept: Set<String> = []
        for watch in watches {
            let file = Self.source(for: watch) + "/" + Self.fileName
            if running.contains(watch.id) { kept.insert(file); continue }
            if let card = Self.card(for: watch, checkedBy: checkLabel(watch)) { wanted[file] = card }
        }
        var changed = false
        for (file, card) in wanted.sorted(by: { $0.key < $1.key }) {
            changed = write(card, to: file) || changed
        }
        for file in present.subtracting(wanted.keys).subtracting(kept).sorted() {
            changed = delete(file) || changed
        }
        return changed
    }

    /// The card files of Noteling's already in the inbox, once: what an earlier launch wrote, and the per-item files of
    /// earlier versions. Files are known by `<source>/<name>`, never by a full path, which can be spelled more than one way.
    private func list(_ root: URL) {
        listed = true
        let manager = FileManager.default
        let folders = ((try? manager.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0.hasPrefix("watch-") }
        for folder in folders {
            for name in (try? manager.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path)) ?? []
            where name == Self.fileName || name.hasPrefix("item-") && name.hasSuffix(".json") {
                present.insert(folder + "/" + name)
            }
        }
    }

    private func url(_ file: String) -> URL? {
        guard let root else { return nil }
        let parts = file.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return root.appendingPathComponent(parts[0]).appendingPathComponent(parts[1])
    }

    private func write(_ card: [String: Any], to file: String) -> Bool {
        guard let url = url(file) else { return false }
        let text = JSONText.pretty(card, indent: "") + "\n"
        if written[file] == text, FileManager.default.fileExists(atPath: url.path) { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let same = (try? String(contentsOf: url, encoding: .utf8)) == text
            if !same { try WatchListFiles.write(text, to: url) }
            written[file] = text
            present.insert(file)
            return !same
        } catch {
            Log.info("watch list: couldn't write the card \(file): \(error.localizedDescription)")
            return false
        }
    }

    private func delete(_ file: String) -> Bool {
        written[file] = nil
        present.remove(file)
        guard let url = url(file), FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            Log.info("watch list: couldn't delete the card \(file): \(error.localizedDescription)")
            return false
        }
    }
}
