import Foundation
import FamiliarContracts
import FamiliarRuntime

/// The scribe: the chat's way to write one of your notes. You say it on the pad ("remind me to send Lena the Q4
/// numbers this afternoon"); the paper goes up at once with your words; the model, given the write_note tool, writes
/// the note properly onto that same paper: a headline, the words, the when, the page you were looking at. A turn that
/// writes no note takes the draft down again. After that first draft the note is yours: change_note only does what you
/// ask on the pad.
@MainActor
final class MemoScribe {
    let store: MemoStore
    /// Shows the note on the screen; nil keeps notes in the store only (tests).
    let windows: MemoWindows?
    /// The page on the screen when the person spoke, for "this page".
    private(set) var pageOnScreen: String?
    /// The note put up with the person's own words when they asked, until the model writes it or the turn ends.
    private(set) var draft: String?

    static let headlineLimit = 40
    static let wordsLimit = 240
    static let itemsLimit = 8
    static let itemLimit = 80
    static let writeTool = "write_note"
    static let changeTool = "change_note"

    init(store: MemoStore, windows: MemoWindows?) {
        self.store = store
        self.windows = windows
    }

    // MARK: the turn

    /// The person sent a question with a page on the screen: if it reads as a note, the paper goes up now with their words.
    func began(_ question: String, page: String?) {
        pageOnScreen = page
        if let draft { store.remove(draft) }
        draft = nil
        guard Self.looksLikeNote(question) else { return }
        var memo = store.blank()
        memo.text = Self.oneLine(question)
        memo.asked = Self.oneLine(question)
        draft = memo.id
        pin(memo)
    }

    /// The turn ended: a draft the model never wrote on comes down.
    func turnEnded() {
        if let draft { store.remove(draft) }
        draft = nil
    }

    /// Whether what the person typed asks for a note, by its opening words; a guess, shown at once and taken back if wrong.
    nonisolated static func looksLikeNote(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return false }
        let openers = ["remind me", "note to self", "note:", "write a note", "write me a note", "make a note", "take a note", "jot down",
                       "jot this", "write down", "write this down", "put a note", "pin a note", "new note", "sticky note", "sticky:",
                       "remember to", "remember that", "don't let me forget", "dont let me forget", "reminder:", "reminder to",
                       "set a reminder", "add a reminder", "note that", "pin this", "pin that"]
        return openers.contains { lower.hasPrefix($0) }
    }

    // MARK: the tools

    func routes() -> [ToolRoute] {
        let now = Date()
        let weekday = now.formatted(Date.FormatStyle().weekday(.wide))
        let fields: [String: Any] = [
            "headline": ["type": ["string", "null"], "description": "At most \(Self.headlineLimit) characters naming the thing: a name, a subject. None for a one-liner."],
            "words": ["type": "string", "description": "The note as the person would write it on a sticky, at most \(Self.wordsLimit) characters, in their voice, not yours: never \"you asked me to\"."],
            "when": ["type": ["string", "null"], "description": "The moment they named, as ISO 8601 with offset; now is \(MemoFile.stamp(now)), a \(weekday). This afternoon is 3 PM today, tonight 7 PM, tomorrow morning 9 AM, end of day 6 PM, unless they said a time. Null when they named none."],
            "page": ["type": ["string", "null"], "description": "\"here\" when they said this or here and a page is on their screen; a web address they named; else null."],
            "items": ["type": "array", "items": ["type": "string"], "description": "A checklist of up to \(Self.itemsLimit) short lines when they listed things to do or get; else leave it out."],
            "colour": ["type": "string", "enum": PaperColour.yours.map(\.rawValue), "description": "Yellow unless they asked for a colour."],
        ]
        let write = ToolRoute(match: .tool(name: Self.writeTool), definition: [
            "name": Self.writeTool,
            "description": "Pin one of the person's own notes on their screen, a sticky in their hand. Use it whenever they ask you to note, remind, remember, jot or write something down for them, without asking first; when they asked that way the paper is already up with their words, and this writes it properly. Say in one line what you pinned.",
            "input_schema": ["type": "object", "additionalProperties": false, "required": ["words"], "properties": fields],
        ]) { [weak self] _, input, _ in
            await MainActor.run {
                guard let self else { return .text("unavailable", isError: true) }
                do { return .text(try self.write(input)) } catch { return .text(error.localizedDescription, isError: true) }
            }
        }
        var changing = fields
        changing["words"] = ["type": ["string", "null"], "description": "New words for the note; null keeps them."]
        changing["note"] = ["type": "string", "description": "The note's id, as write_note gave it or the notes root in recall lists them (n-1a2b3c4d)."]
        changing["remove"] = ["type": "boolean", "description": "True takes the note away."]
        let change = ToolRoute(match: .tool(name: Self.changeTool), definition: [
            "name": Self.changeTool,
            "description": "Change one of the person's notes, only as they ask: any of its fields, or take it away. The note is theirs after it is written; never change one they didn't ask about.",
            "input_schema": ["type": "object", "additionalProperties": false, "required": ["note"], "properties": changing],
        ]) { [weak self] _, input, _ in
            await MainActor.run {
                guard let self else { return .text("unavailable", isError: true) }
                do { return .text(try self.change(input)) } catch { return .text(error.localizedDescription, isError: true) }
            }
        }
        return [write, change]
    }

    /// The write tool: onto the draft when there is one, else a new note.
    func write(_ input: [String: Any]) throws -> String {
        var memo = draft.flatMap { store.memo(id: $0) } ?? store.blank()
        draft = nil
        guard let words = input["words"] as? String, !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MinisterError("Give words: what the note says.")
        }
        try fill(&memo, from: input)
        pin(memo)
        return "Pinned note \(memo.id): \(memo.firstLine)" + (memo.when.map { " · \(PaperWhen.words($0, now: Date()))" } ?? "")
    }

    /// The change tool: the fields given, on the note named; or its removal.
    func change(_ input: [String: Any]) throws -> String {
        guard let id = input["note"] as? String, var memo = store.memo(id: id) else {
            throw MinisterError("No note \(input["note"] ?? "named"). The notes root in recall lists them.")
        }
        if input["remove"] as? Bool == true {
            store.remove(id)
            return "Took note \(id) away."
        }
        try fill(&memo, from: input)
        store.save(memo)
        return "Changed note \(memo.id): \(memo.firstLine)"
    }

    /// Each field given, checked and put on the note; a null clears the when, the page or the headline.
    private func fill(_ memo: inout Memo, from input: [String: Any]) throws {
        if input.keys.contains("headline") {
            let headline = (input["headline"] as? String).map { Self.oneLine($0) } ?? ""
            memo.headline = headline.isEmpty ? nil : JobWords.clip(headline, Self.headlineLimit)
        }
        if let words = input["words"] as? String {
            let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count <= Self.wordsLimit else { throw MinisterError("The words are \(trimmed.count) characters; a note holds \(Self.wordsLimit).") }
            memo.text = trimmed
        }
        if input.keys.contains("when") {
            if let stamp = input["when"] as? String, !stamp.isEmpty {
                guard let moment = JobMoment.parse(stamp) else { throw MinisterError("when must be a date and time, such as 2026-11-05T15:00:00-05:00, or null.") }
                memo.when = moment.date
            } else {
                memo.when = nil
            }
        }
        if input.keys.contains("page") {
            if let page = input["page"] as? String, !page.isEmpty {
                let lower = page.lowercased()
                if lower == "here" || lower == "this" || lower == "this page" {
                    memo.page = pageOnScreen
                } else if let url = URL(string: page), url.scheme != nil {
                    memo.page = page
                } else {
                    throw MinisterError("page must be \"here\", a web address, or null.")
                }
            } else {
                memo.page = nil
            }
        }
        if let items = input["items"] as? [String] {
            let lines = items.map { Self.oneLine($0) }.filter { !$0.isEmpty }
            guard lines.count <= Self.itemsLimit else { throw MinisterError("A checklist holds \(Self.itemsLimit) lines at most.") }
            memo.items = lines.map { PaperItem(text: JobWords.clip($0, Self.itemLimit)) }
        }
        if let colour = input["colour"] as? String {
            guard let chosen = PaperColour(rawValue: colour), PaperColour.yours.contains(chosen) else {
                throw MinisterError("colour must be one of \(PaperColour.yours.map(\.rawValue).joined(separator: ", ")).")
            }
            memo.colour = chosen
        }
    }

    private func pin(_ memo: Memo) {
        if let windows { windows.newNote(memo) } else { store.save(memo) }
    }

    private nonisolated static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
