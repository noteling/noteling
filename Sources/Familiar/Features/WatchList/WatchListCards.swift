import CryptoKit
import Foundation

/// A watch's items as cards in Morning Files, through the cards inbox (`CardInbox`): a file for each item that isn't as
/// expected or couldn't be checked (every item, with `"cards": "all"`), in `cards/inbox/<the watch's source>/`,
/// written right after a check changes what it shows, and deleted when the item is back to as expected, so its card
/// resolves. A card says what the check found as it came: no model writes any of it. Noteling's files are named
/// `item-…json`; anything else a check script writes in the same folder is the script's, and left alone.
@MainActor
final class WatchListCards {
    /// The cards inbox; nil writes no cards.
    let root: URL?
    /// Which check a watch uses, as a card's last line says it.
    var checkLabel: (WatchListWatch) -> String = { $0.check }
    /// What Noteling last wrote, by `<source>/<file name>`, so an unchanged card isn't written again.
    private var written: [String: String] = [:]
    /// Card files of Noteling's that are there, by `<source>/<file name>`.
    private var present: Set<String> = []
    private var listed = false

    static let factsLimit = 4_000

    init(root: URL? = Config.dir.appendingPathComponent("cards/inbox")) { self.root = root }

    /// A watch's folder in the inbox, the same one its check gets as NOTELING_CARDS_DIR: `watch-<path>` for one of
    /// yours, `watch-team-<path>` for a team's, the path's `/` made `-`.
    static func source(for watch: WatchListWatch) -> String {
        CardInboxFormat.safe((watch.isTeam ? "watch-team-" : "watch-") + watch.path.replacingOccurrences(of: "/", with: "-"))
    }

    /// An item's card file: `item-`, its key made safe, and a short hash of the key so two keys never share a file.
    static func fileName(for key: String) -> String {
        let hash = SHA256.hash(data: Data(key.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
        return "item-" + CardInboxFormat.safe(key, limit: 60) + "-" + hash + ".json"
    }

    /// What an item's card says, or nil when it has none: the watch's cards are off, it is a team watch that's off, it
    /// hasn't been checked, or it is as expected and only problems get cards.
    static func card(for item: WatchListItem, in watch: WatchListWatch, checkedBy: String) -> [String: Any]? {
        guard watch.cards != .off, watch.on, let status = item.status, let checked = item.checkedAt else { return nil }
        var lines: [String] = []
        let lead: String, severity: String
        switch status {
        case .notAsExpected(let differences):
            lead = "Not as expected"
            severity = "high"
            lines = differences.map(\.words)
        case .couldNotCheck(let reason):
            lead = "Couldn't check"
            severity = "normal"
            lines = ["Couldn't check: \(reason)"]
        case .asExpected:
            guard watch.cards == .all else { return nil }
            lead = "As expected"
            severity = "low"
            lines = ["As expected"]
        }
        if status.isVerdict {
            lines += item.whyNow
            lines += (item.state ?? [:]).keys.sorted().map { "\($0): \(item.state![$0]!.words)" }
        }
        lines.append("Checked \(time(checked)) by \(checkedBy)")
        var card: [String: Any] = ["title": "\(lead) · \(item.label)", "body": lines.joined(separator: "\n"), "severity": severity]
        var actions: [[String: Any]] = []
        if let url = item.pageURL, !CardInboxFormat.webAddress(url).isEmpty {
            card["url"] = url
            actions.append(["label": "Open page", "url": url])
        }
        if item.needsExplaining { actions.append(["label": "Why?", "ask": WatchListExplanation.question(for: item)]) }
        if !actions.isEmpty { card["actions"] = actions }
        if status.isVerdict, let facts = item.facts, !facts.isEmpty {
            card["details"] = facts.count > factsLimit ? String(facts.prefix(factsLimit - 1)) + "…" : facts
        }
        return card
    }

    /// "Oct 4, 9:30 PM", in this Mac's time.
    static func time(_ date: Date, in timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    /// Brings one item's card file in line with what its latest check shows. True when a file changed.
    @discardableResult
    func update(_ watch: WatchListWatch, item: WatchListItem) -> Bool {
        guard root != nil else { return false }
        let file = Self.source(for: watch) + "/" + Self.fileName(for: item.key)
        guard let card = Self.card(for: item, in: watch, checkedBy: checkLabel(watch)) else { return delete(file) }
        return write(card, to: file)
    }

    /// Every watch's cards as they should be, and none for watches that are gone, turned off or have cards off: at
    /// launch, at each tick, after a run, and when a team watch is turned on or off. Cheap when nothing changed: it
    /// remembers what it wrote.
    @discardableResult
    func reconcile(_ watches: [WatchListWatch]) -> Bool {
        guard let root else { return false }
        if !listed { list(root) }
        var wanted: [String: [String: Any]] = [:]
        for watch in watches {
            let source = Self.source(for: watch)
            for item in watch.items {
                if let card = Self.card(for: item, in: watch, checkedBy: checkLabel(watch)) {
                    wanted[source + "/" + Self.fileName(for: item.key)] = card
                }
            }
        }
        var changed = false
        for (file, card) in wanted.sorted(by: { $0.key < $1.key }) {
            changed = write(card, to: file) || changed
        }
        for file in present.subtracting(wanted.keys).sorted() {
            changed = delete(file) || changed
        }
        return changed
    }

    /// The card files of Noteling's already in the inbox, once: what an earlier launch wrote. Files are known by
    /// `<source>/<name>`, never by a full path, which can be spelled more than one way.
    private func list(_ root: URL) {
        listed = true
        let manager = FileManager.default
        let folders = ((try? manager.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0.hasPrefix("watch-") }
        for folder in folders {
            for name in (try? manager.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path)) ?? []
            where name.hasPrefix("item-") && name.hasSuffix(".json") {
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
