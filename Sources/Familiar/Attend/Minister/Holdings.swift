import Foundation

/// What Noteling holds right now, for the chat's prompt at every turn: the person's notes, the deck's cards, the sources
/// the chat scanned, what the person taught and told the minister, and today's tally, each with where the rest is
/// readable. The chat is the person's interlocutor and reads the shared state; this is the map of it, so a question about
/// their day is answered from what is there, never with "no data". Built from the files, so the app and the headless ask
/// read the same state; capped, so it stays a page.
@MainActor
enum Holdings {
    static let noteLimit = 20
    static let cardLimit = 10
    static let scanLimit = 10
    static let toldLimit = 10

    static func digest(home: URL, now: Date = Date()) -> String {
        let notes = MemoStore.read(home.appendingPathComponent(MemoStore.folder))
        let matters = Matters(directory: home.appendingPathComponent(Matters.folder))
        matters.clock = { now }
        let results = home.appendingPathComponent("job-results")
        let scans = ChatSource.all(in: results.appendingPathComponent(JobSource.chat.key))
        let lessons = Lessons(file: home.appendingPathComponent(Matters.folder).appendingPathComponent(Lessons.fileName))
        let log = MemoryLog(directory: home.appendingPathComponent(MemoryLog.folder))

        var out = "\n\n## What Noteling holds right now\n"
        out += "Read these before answering anything about the person's day, their time, what is due or what is on their plate; never say you have no data before looking.\n"
        if notes.isEmpty {
            out += "Their notes: none.\n"
        } else {
            out += "Their notes (the notes root, one markdown file each; read one for its words):\n"
            for memo in notes.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(noteLimit) { out += "- " + noteLine(memo, now: now) + "\n" }
            if notes.count > noteLimit { out += "- and \(notes.count - noteLimit) more\n" }
        }
        let cards = matters.stickers
        if !cards.isEmpty {
            out += "The deck (the minister's cards; matters/<id>/matter.json and notes.md):\n"
            for card in cards.prefix(cardLimit) {
                var line = "- \(card.id): \(card.headline ?? card.text)"
                if card.urgent { line += " (urgent)" }
                if let next = card.next { line += " · next: \(next)" }
                if let action = card.action { line += " · action: \(action.label)" }
                out += line + "\n"
            }
            if cards.count > cardLimit { out += "- and \(cards.count - cardLimit) more\n" }
        }
        if !scans.isEmpty {
            out += "Scans the chat did for them (read the rows with rows on the file named):\n"
            for scan in scans.prefix(scanLimit) {
                let folder = results.appendingPathComponent(JobSource.chat.key).appendingPathComponent(scan.slug)
                let state = Self.state(in: folder)
                var line = "- \(scan.name): "
                if let found = state?.found { line += "\(found) row\(found == 1 ? "" : "s")" } else { line += "rows" }
                if let last = state?.lastRunAt { line += ", scanned \(JobWords.time(last, now: now))" }
                line += " · results/chat/\(scan.slug)/output/\(FolderJobFiles.findings)"
                if !scan.about.isEmpty { line += " · \(JobWords.clip(scan.about, 120))" }
                out += line + "\n"
            }
        }
        if !lessons.told.isEmpty {
            out += "Told to the minister, in their words:\n"
            for told in lessons.told.prefix(toldLimit) { out += "- \(told.text)\n" }
        }
        if !lessons.all.isEmpty { out += "Taught: the findings of " + lessons.all.map(\.name).joined(separator: ", ") + " stay quiet unless one can't wait.\n" }
        out += "Today: " + Receipt.today(log: log, matters: matters, now: now).tally + "\n"
        return out
    }

    /// One note: its first line, its time in the paper's words, its page, what is left to tick, and where it came from.
    static func noteLine(_ memo: Memo, now: Date) -> String {
        var parts = ["\(memo.id): \(JobWords.clip(memo.firstLine, 80))"]
        if let when = memo.when { parts.append(PaperWhen.words(when, now: now)) }
        if let page = memo.page { parts.append(page) }
        let open = memo.items.filter { !$0.done }.count
        if !memo.items.isEmpty { parts.append(open == 0 ? "all ticked" : "\(open) of \(memo.items.count) to tick") }
        if let from = memo.from { parts.append("from \(from)") } else if let matter = memo.matter { parts.append("was card \(matter)") }
        return parts.joined(separator: " · ")
    }

    private static func state(in folder: URL) -> FolderJobState? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(FolderJobFiles.state)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FolderJobState.self, from: data)
    }
}
