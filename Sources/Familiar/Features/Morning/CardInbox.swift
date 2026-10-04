import CryptoKit
import Foundation

/// One card a script wrote into the inbox, as its file says it.
struct CardInboxEntry: Equatable {
    var source: String
    var id: String
    var title: String
    var body = ""
    var url = ""
    var severity = "normal"
    var actions: [CardInboxAction] = []
    /// Longer text: shown under Show original, and part of what Noteling reads when the card is discussed.
    var details = ""
    var modifiedAt = Date()
    var key: String { source + "/" + id }
}

/// What a look at the inbox found: the cards it could read; every card file there, read or not, so that a file that
/// can't be read never resolves its card; folder names; and what couldn't be read, in plain words.
struct CardInboxSnapshot: Equatable {
    var cards: [CardInboxEntry] = []
    var present: Set<String> = []
    /// Sources whose folder couldn't be listed: their cards are left as they are.
    var unlisted: Set<String> = []
    /// The card view's folder name for each source with cards.
    var folders: [String: String] = [:]
    var notes: [String: [String]] = [:]
}

struct CardInboxSummary: Equatable {
    var created = 0
    var updated = 0
    var gone = 0
}

/// The cards inbox: `cards/inbox/<source>/<id>.json` in Noteling's folder, one file per card, so a script makes a card
/// just by writing a file. Whatever is there in the right format is a card in Morning Files, with no model involved:
/// writing the same file again changes the same card's words, deleting it means the matter went away, and nothing
/// the person did to the card is ever changed by a file. Cards from the inbox never run anything: their buttons only
/// open a web page or ask Noteling about the card in chat.
enum CardInboxFormat {
    static let fileLimit = 64 * 1024
    static let perSource = 500
    static let sourceLimit = 100
    static let titleLimit = 200
    static let bodyLimit = 8_000
    static let detailsLimit = 8_000
    static let actionLimit = 6
    static let labelLimit = 40
    static let askLimit = 1_000

    /// Reads one card file. Only `title` is required; keys it doesn't know are left out, and so is any button that
    /// would do more than open a web page or ask a question.
    static func parse(_ data: Data, source: String, id: String, modifiedAt: Date) throws -> CardInboxEntry {
        let value: Any
        do { value = try JSONSerialization.jsonObject(with: data) }
        catch {
            let detail = ((error as NSError).userInfo["NSDebugDescription"] as? String).map {
                ($0.prefix(1).lowercased() + $0.dropFirst()).replacingOccurrences(of: ". around line", with: " around line")
                    .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            }
            throw CardInboxError("it isn't valid JSON" + (detail.map { " (\($0))" } ?? "") + ".")
        }
        guard let object = value as? [String: Any] else { throw CardInboxError("it must be one JSON object: { … }.") }
        func text(_ key: String, _ limit: Int) -> String {
            let raw: String
            switch object[key] {
            case let string as String: raw = string
            case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): raw = number.stringValue
            default: raw = ""
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count > limit ? String(trimmed.prefix(limit - 1)) + "…" : trimmed
        }
        let title = text("title", titleLimit)
        guard !title.isEmpty else { throw CardInboxError("it needs a title.") }
        var entry = CardInboxEntry(source: source, id: id, title: title, body: text("body", bodyLimit), url: webAddress(text("url", 2_000)),
                                   modifiedAt: modifiedAt)
        let severity = text("severity", 20).lowercased()
        entry.severity = ["high", "normal", "low"].contains(severity) ? severity : "normal"
        if let details = object["details"], !(details is NSNull) {
            let raw = details as? String ?? JSONText.compact(details)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.details = trimmed.count > detailsLimit ? String(trimmed.prefix(detailsLimit - 1)) + "…" : trimmed
        }
        for case let action as [String: Any] in object["actions"] as? [Any] ?? [] where entry.actions.count < actionLimit {
            let label = ((action["label"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }
            let short = label.count > labelLimit ? String(label.prefix(labelLimit - 1)) + "…" : label
            if let url = action["url"] as? String, !webAddress(url).isEmpty {
                entry.actions.append(CardInboxAction(label: short, url: webAddress(url)))
            } else if let ask = (action["ask"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !ask.isEmpty {
                entry.actions.append(CardInboxAction(label: short, ask: ask.count > askLimit ? String(ask.prefix(askLimit - 1)) + "…" : ask))
            }
        }
        return entry
    }

    /// An http or https address, or nothing: a card never opens a file, an app or a script.
    static func webAddress(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else { return "" }
        return trimmed
    }

    /// A folder or file name from anything: letters, digits, `.`, `_` and `-`, so it stays one folder in the inbox.
    static func safe(_ text: String, limit: Int = 100) -> String {
        var name = ""
        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII || "._-".unicodeScalars.contains(scalar) {
                name.unicodeScalars.append(scalar)
            } else if !name.hasSuffix("-") {
                name += "-"
            }
        }
        name = String(name.prefix(limit)).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return name.isEmpty ? "cards" : name
    }

    /// A card's id, the same every time for the same `<source>/<id>`.
    static func cardID(_ key: String) -> UUID { uuid("noteling-card-inbox:" + key) }
    /// The card view's folder for a source.
    static func folderID(_ source: String) -> UUID { uuid("noteling-card-inbox-folder:" + source) }
    static func sourceID(_ key: String, _ index: Int) -> UUID { uuid("noteling-card-inbox-source:\(index):" + key) }

    private static func uuid(_ text: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// What an inbox card's one action is: never queued (`MorningStore.enqueue` refuses inbox cards), only there
    /// because every card has one.
    static var placeholderAction: MorningAction {
        MorningAction(title: "Ask Noteling", instruction: "This card came from a script. It only opens its page or asks Noteling about it in chat.",
                      mode: .prepare)
    }

    static let noWork = "This card came from a script. It can open its page or ask Noteling about it in chat, but Noteling doesn't work on it."

    /// Takes in what the inbox holds now. A new file is a new card in its source's folder; a changed file changes
    /// the card's words, page, severity and buttons, and nothing else; a deleted file means the matter went away: the
    /// card is resolved if the person hadn't decided anything about it, and otherwise keeps their decision and says
    /// its script no longer reports it. A file that comes back opens a card its deletion resolved. Cards not from the
    /// inbox are never touched.
    static func apply(_ snapshot: CardInboxSnapshot, to workspace: inout MorningWorkspace, at: Date) -> CardInboxSummary {
        var summary = CardInboxSummary()
        for (source, name) in snapshot.folders.sorted(by: { $0.key < $1.key }) {
            let id = folderID(source)
            guard !workspace.folders.contains(where: { $0.id == id }) else { continue }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            workspace.folders.append(MorningFolder(id: id, name: trimmed.isEmpty ? source : trimmed))
        }
        for entry in snapshot.cards {
            let id = cardID(entry.key)
            if let index = workspace.cards.firstIndex(where: { $0.id == id }) {
                guard workspace.cards[index].inbox != nil else { continue }
                let before = workspace.cards[index]
                var card = before
                fill(&card, from: entry)
                if var link = card.inbox, link.goneAt != nil {
                    link.goneAt = nil
                    if link.resolvedByInbox, card.disposition == .resolved { card.disposition = .unreviewed }
                    link.resolvedByInbox = false
                    card.inbox = link
                }
                guard card != before else { continue }
                card.updatedAt = at
                workspace.cards[index] = card
                summary.updated += 1
            } else {
                var card = MorningCard(id: id, folderID: folderID(entry.source), title: entry.title, action: placeholderAction, updatedAt: at)
                card.inbox = CardInboxLink(key: entry.key, severity: entry.severity, actions: entry.actions)
                fill(&card, from: entry)
                workspace.cards.append(card)
                summary.created += 1
            }
        }
        for index in workspace.cards.indices {
            guard var link = workspace.cards[index].inbox, link.goneAt == nil, !snapshot.present.contains(link.key),
                  !snapshot.unlisted.contains(String(link.key.split(separator: "/").first ?? "")) else { continue }
            link.goneAt = at
            if workspace.cards[index].disposition == .unreviewed {
                workspace.cards[index].disposition = .resolved
                link.resolvedByInbox = true
            }
            workspace.cards[index].inbox = link
            workspace.cards[index].updatedAt = at
            summary.gone += 1
        }
        return summary
    }

    /// The card's words come from its file: title, body, page, severity, buttons, and the longer details. Its
    /// decision, the person's context and its folder are theirs.
    private static func fill(_ card: inout MorningCard, from entry: CardInboxEntry) {
        card.title = entry.title
        card.summary = entry.body
        card.rationale = ""
        let kind = entry.source.hasPrefix("watch-") ? "Watch" : "Card"
        var sources = [MorningSource(id: sourceID(entry.key, 0), title: entry.title, kind: kind, excerpt: entry.body, url: entry.url,
                                     capturedAt: entry.modifiedAt)]
        if !entry.details.isEmpty {
            sources.append(MorningSource(id: sourceID(entry.key, 1), title: "Details", kind: kind, excerpt: entry.details, capturedAt: entry.modifiedAt))
        }
        card.sources = sources
        card.inbox?.severity = entry.severity
        card.inbox?.actions = entry.actions
    }
}

struct CardInboxError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Looks at the cards inbox and hands what it finds to the card store. It reads only files that changed since the
/// last look, says once in the log what it couldn't read, and never deletes or changes a file.
@MainActor
final class CardInbox {
    let directory: URL
    let store: MorningStore
    /// The card view's folder name for a source: a watch's name, a pack's; nil keeps the folder's own name.
    var folderName: (String) -> String? = { _ in nil }
    private var cache: [String: (stamp: Stamp, result: Result<CardInboxEntry, CardInboxError>)] = [:]
    private var logged: Set<String> = []

    private struct Stamp: Equatable {
        var date: Date?
        var size: Int
    }

    init(store: MorningStore, directory: URL = Config.dir.appendingPathComponent("cards/inbox")) {
        self.store = store
        self.directory = directory
    }

    /// Looks at the inbox and takes in what changed. Nothing is saved when nothing changed.
    @discardableResult
    func scan(at: Date = Date()) -> CardInboxSnapshot? {
        let snapshot: CardInboxSnapshot
        do { snapshot = try look() } catch {
            if logged.insert("inbox: \(error.localizedDescription)").inserted {
                Log.info("cards inbox: can't look at \(directory.path): \(error.localizedDescription)")
            }
            return nil
        }
        do { try store.syncInbox(snapshot, at: at) }
        catch {
            // Said once: the scan comes back every 30 seconds, and the store says why in Morning Files.
            if logged.insert("save: \(error.localizedDescription)").inserted {
                Log.info("cards inbox: couldn't save the cards: \(error.localizedDescription)")
            }
        }
        return snapshot
    }

    func look() throws -> CardInboxSnapshot {
        let manager = FileManager.default
        var snapshot = CardInboxSnapshot()
        guard manager.fileExists(atPath: directory.path) else { return snapshot }
        let sources = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var seen = Set<String>()
        for folder in sources.prefix(CardInboxFormat.sourceLimit) {
            let source = folder.lastPathComponent
            var notes: [String] = []
            let files: [URL]
            do {
                files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                                                        options: [.skipsHiddenFiles])
                    .filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            } catch {
                snapshot.unlisted.insert(source)
                note(source, "The folder can't be read: \(error.localizedDescription)", into: &snapshot)
                continue
            }
            for (index, file) in files.enumerated() {
                let id = file.deletingPathExtension().lastPathComponent
                let key = source + "/" + id
                snapshot.present.insert(key)
                guard index < CardInboxFormat.perSource else { continue }
                seen.insert(file.path)
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let stamp = Stamp(date: values?.contentModificationDate, size: values?.fileSize ?? 0)
                guard stamp.size <= CardInboxFormat.fileLimit else {
                    notes.append("\(file.lastPathComponent) is bigger than 64 KB, so it wasn't read.")
                    continue
                }
                let result: Result<CardInboxEntry, CardInboxError>
                if let cached = cache[file.path], cached.stamp == stamp { result = cached.result }
                else {
                    do {
                        let data = try Data(contentsOf: file)
                        result = .success(try CardInboxFormat.parse(data, source: source, id: id, modifiedAt: stamp.date ?? Date()))
                    } catch {
                        result = .failure(error as? CardInboxError ?? CardInboxError(error.localizedDescription))
                    }
                    cache[file.path] = (stamp, result)
                }
                switch result {
                case .success(let entry): snapshot.cards.append(entry)
                case .failure(let error): notes.append("\(file.lastPathComponent) can't be read: \(error.message)")
                }
            }
            if files.count > CardInboxFormat.perSource {
                let more = files.count - CardInboxFormat.perSource
                notes.append("\(more) more \(more == 1 ? "card wasn't" : "cards weren't") read: a folder shows up to \(CardInboxFormat.perSource).")
            }
            if !files.isEmpty { snapshot.folders[source] = folderName(source) ?? source }
            for line in notes { note(source, line, into: &snapshot) }
        }
        if sources.count > CardInboxFormat.sourceLimit {
            // Not read, so not gone either: their cards stay as they are.
            for folder in sources.dropFirst(CardInboxFormat.sourceLimit) { snapshot.unlisted.insert(folder.lastPathComponent) }
            if logged.insert("inbox: too many folders").inserted {
                Log.info("cards inbox: \(sources.count - CardInboxFormat.sourceLimit) folders past the first \(CardInboxFormat.sourceLimit) weren't read")
            }
        }
        cache = cache.filter { seen.contains($0.key) }
        return snapshot
    }

    private func note(_ source: String, _ line: String, into snapshot: inout CardInboxSnapshot) {
        snapshot.notes[source, default: []].append(line)
        if logged.insert(source + "/" + line).inserted { Log.info("cards inbox: \(source): \(line)") }
    }
}
