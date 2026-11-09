import Foundation
import FamiliarContracts
import FamiliarRuntime

/// A source the chat read for the person and reported as findings, kept as `source.json` under
/// `job-results/chat/<slug>/` so the next scan is the same source: its name, what a row is (for the minister), and its
/// map. It stands in the jobs as one of the chat's kind: never run on a schedule, scanned again when the person asks.
struct ChatSource {
    var slug: String
    var name: String
    var about: String
    var map: FindingsMap
    /// The map as the chat gave it, written back as it is.
    var raw: [String: Any]

    static let file = "source.json"

    var job: FolderJob {
        FolderJob(id: FolderJobFiles.id(.chat, slug), source: .chat, path: slug, name: name, about: about, map: map)
    }

    /// "Slack #ops" → "slack-ops": letters and digits, the rest a dash, at most 40; "scan" for a name with none.
    static func slug(_ name: String) -> String {
        var out = "", dash = false
        for scalar in name.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII { out.unicodeScalars.append(scalar); dash = false }
            else if !dash, !out.isEmpty { out.append("-"); dash = true }
        }
        while out.hasSuffix("-") { out.removeLast() }
        let cut = String(out.prefix(40))
        return cut.isEmpty ? "scan" : (cut.hasSuffix("-") ? String(cut.dropLast()) : cut)
    }

    /// Every source kept under the chat's folder, by slug.
    static func all(in folder: URL) -> [ChatSource] {
        let manager = FileManager.default
        let names = ((try? manager.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        return names.compactMap { slug in read(folder.appendingPathComponent(slug).appendingPathComponent(file), slug: slug) }
    }

    static func read(_ url: URL, slug: String) -> ChatSource? {
        guard let data = try? Data(contentsOf: url), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = object["name"] as? String, let raw = object["map"] as? [String: Any], let map = try? FindingsMap.parse(raw) else { return nil }
        return ChatSource(slug: slug, name: name, about: object["about"] as? String ?? "", map: map, raw: raw)
    }

    func write(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let object: [String: Any] = ["name": name, "about": about, "map": raw]
        try JobFiles.write(try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), to: folder.appendingPathComponent(Self.file))
    }
}

/// The chat as a source of findings. "Scan my calendar and Slack and tell me what needs me" is judgment over sources,
/// which is the minister's work: the chat gathers rows from what it can read and hands them over as a job would, rows
/// with an id and a map saying which column is what. Each source is a job of the chat kind, kept with its findings
/// under `job-results/chat/<slug>/`, so the next scan is diffed against the last and the minister sees what is new,
/// changed and gone. The minister takes its turn at once, since the person is waiting, and the answer says what became
/// of each row. A reminder the person dictates is not this: that is the scribe's, and nothing judges it. The chat also
/// carries what the person tells the minister in words (`tell_the_minister`): standing rules kept with the lessons.
@MainActor
final class ChatFindings {
    let store: FolderJobStore
    let matters: Matters
    let memory: MemoryLog
    var clock: () -> Date = Date.init
    /// What a report sets off, as a job's run does: the notes keeper and the minister.
    var onFindings: ((FolderJob, FindingsChange) -> Void)?
    /// The minister's turn, now, awaited.
    var takeTurn: () async -> Void = {}
    /// Where what the person tells the minister is kept, beside what the deck taught it.
    var lessons: Lessons?

    static let tool = "report_findings"
    static let tellTool = "tell_the_minister"
    static let rowLimit = 200
    static let aboutLimit = 600

    init(store: FolderJobStore, matters: Matters, memory: MemoryLog) {
        self.store = store
        self.matters = matters
        self.memory = memory
    }

    func routes() -> [ToolRoute] {
        let route = ToolRoute(match: .tool(name: Self.tool), definition: [
            "name": Self.tool,
            "description": "Hand what you read to Noteling's minister as findings, the way a job reports them, when the person asks what needs them from somewhere: their calendar, Slack, an inbox, a page (\"scan my calendar and Slack and give me my to-dos\", \"anything I need to deal with in #ops?\"). Gather the rows from what you can see or run, then call this once per source. The minister sorts them with the other jobs' findings into matters, keeps quiet what fails its tests, puts a card on the deck for what needs the person, and this returns what became of each row: answer from that, and say the deck has the cards. A reminder the person dictates (\"remind me to…\") is write_note instead: that is theirs, and nothing judges it.",
            "input_schema": ["type": "object", "additionalProperties": false, "required": ["source", "about", "map", "rows"], "properties": [
                "source": ["type": "string", "description": "What was read, in a few words: \"Calendar\", \"Slack #ops\", \"Inbox\". The same name next time is the same source, so the minister sees what is new, changed or gone since."],
                "about": ["type": "string", "description": "What a row is and whom it serves, as a job's description would say it, at most \(Self.aboutLimit) characters: \"Each row is a meeting on the person's calendar today; start is when it begins; link opens it; attendees is who is in it.\""],
                "map": ["type": "object", "additionalProperties": false, "required": ["id"],
                        "description": "Which column is which. id is required: the column that makes a row the same row next time (an event's id or link, a message's permalink).",
                        "properties": [
                            "id": ["type": "string"], "what": ["type": ["string", "null"], "description": "A column holding a ready sentence."],
                            "where": ["type": ["string", "null"], "description": "The link column, or an address with {column} in it."],
                            "since": ["type": ["string", "null"]], "due": ["type": ["string", "null"]],
                            "at": ["type": ["string", "null"], "description": "When it happened: rows are then events, never gone."],
                            "about": ["type": "array", "items": ["type": "string"], "description": "Columns naming who and what a row concerns."],
                        ]],
                "rows": ["type": "array", "items": ["type": "object"], "description": "The rows, flat objects of the same columns, each with the id column; at most \(Self.rowLimit)."],
            ]],
        ]) { [weak self] _, input, _ in
            guard let self else { return .text("unavailable", isError: true) }
            do { return .text(try await self.report(input)) } catch { return .text(error.localizedDescription, isError: true) }
        }
        let tell = ToolRoute(match: .tool(name: Self.tellTool), definition: [
            "name": Self.tellTool,
            "description": "Tell Noteling's minister a standing rule in the person's own words, when they say how they want their cards from now on (\"for all meetings, make the link the thing to open\", \"anything from Lena goes on top\", \"stop telling me about newsletters\"), or make it forget one. The minister reads them at every turn as preferences within its rules: they never make a finding sure that isn't, and never add a button. Not for a one-off (\"show my notes\", \"remind me to…\"): those have their own tools.",
            "input_schema": ["type": "object", "additionalProperties": false, "properties": [
                "instruction": ["type": ["string", "null"], "description": "The rule, in the person's words, one line, at most \(Lessons.instructionLimit) characters."],
                "forget": ["type": ["string", "null"], "description": "Words of a rule to forget (or its id); the receipt lists them under Taught."],
            ]],
        ]) { [weak self] _, input, _ in
            await MainActor.run {
                guard let self else { return .text("unavailable", isError: true) }
                do { return .text(try self.tell(input)) } catch { return .text(error.localizedDescription, isError: true) }
            }
        }
        return [route, tell]
    }

    /// The person told the minister something, or took it back.
    func tell(_ input: [String: Any]) throws -> String {
        guard let lessons else { throw MinisterError("The minister isn't here to tell.") }
        if let key = input["forget"] as? String, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let gone = lessons.forget(instruction: key) else {
                throw MinisterError("Nothing told matches “\(JobWords.clip(key, 80))”. Told so far: " + (lessons.told.isEmpty ? "nothing." : lessons.told.map { "“\($0.text)”" }.joined(separator: "; ") + "."))
            }
            return "The minister forgot: “\(gone.text)”."
        }
        guard let words = input["instruction"] as? String else { throw MinisterError("Give instruction: the rule in the person's words, or forget: words of one to take back.") }
        let kept = try lessons.tell(words)
        return "Told the minister: “\(kept.text)”. It applies from its next turn, to its cards and to what it says; the receipt lists it under Taught, where Forget takes it back."
    }

    /// One report: the source kept, the rows diffed against its last scan and recorded, the minister's turn taken, and
    /// what became of each row told back.
    func report(_ input: [String: Any]) async throws -> String {
        guard let rawName = input["source"] as? String, !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MinisterError("Give source: what you read, in a few words.")
        }
        let name = JobWords.clip(rawName.trimmingCharacters(in: .whitespacesAndNewlines), FindingsOutcome.sourceLimit)
        guard let rawAbout = input["about"] as? String, !rawAbout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MinisterError("Give about: what a row is and whom it serves, as a job's description would say it.")
        }
        let about = JobWords.clip(rawAbout.trimmingCharacters(in: .whitespacesAndNewlines), Self.aboutLimit)
        guard let rawMap = input["map"] as? [String: Any] else { throw MinisterError("Give map: which column is which, with id.") }
        let map = try FindingsMap.parse(rawMap)
        guard let list = input["rows"] as? [Any], list.allSatisfy({ $0 is [String: Any] }) else {
            throw MinisterError("rows must be a list of flat objects, each with the \(map.id) column.")
        }
        guard list.count <= Self.rowLimit else { throw MinisterError("At most \(Self.rowLimit) rows a report; boil it down first, as a job would.") }
        let outcome = try FindingsOutcome.parse(["source": name, "read": list.count, "findings": list], map: map)
        let rows = outcome.rows ?? []
        let source = ChatSource(slug: ChatSource.slug(name), name: name, about: about, map: map, raw: rawMap)
        try store.addChatSource(source)
        guard var job = store.jobs.first(where: { $0.source == .chat && $0.path == source.slug }) else { throw MinisterError("The source couldn't be kept.") }

        // Diffed against the last scan, kept for the next, and the table beside it; then recorded, as a run is.
        let now = clock()
        let file = store.findingsFile(for: job)
        let previous = FindingsSnapshot.read(file)
        let first = previous.rows.isEmpty && previous.events.isEmpty
        let (change, snapshot) = FolderJobFindings.diff(previous: previous, rows: rows, map: map, at: now)
        try snapshot.write(to: file)
        let output = store.output(for: job)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JobFiles.write(FolderJobFindings.csv(rows, columns: outcome.columns), to: output.appendingPathComponent(FolderJobFiles.findings))
        var state = job.state
        state.lastRunAt = now
        state.lastSuccessAt = now
        state.error = nil
        state.said = nil
        state.source = name
        state.read = list.count
        state.found = rows.count
        state.note = outcome.notes.isEmpty ? nil : outcome.notes.joined(separator: " ")
        try store.record(job.id, state)
        job = store.job(id: job.id) ?? job
        memory.ran(job, outcome: outcome)
        memory.record(job, change: change)
        onFindings?(job, change)
        await takeTurn()
        return Self.answer(job, rows: rows.count, change: change, first: first, snapshot: FindingsSnapshot.read(file), matters: matters, now: clock())
    }

    /// What the chat is told: how many rows and what changed since the last scan, the minister's summary, and its
    /// verdict on each row, so the chat answers from what was shown and what was kept quiet.
    static func answer(_ job: FolderJob, rows: Int, change: FindingsChange, first: Bool, snapshot: FindingsSnapshot, matters: Matters, now: Date) -> String {
        let since = first ? "the first scan of it"
            : "\(change.new.count) new, \(change.changed.count) changed, \(change.gone.count) gone since the last scan"
        var lines = ["Handed to the minister: \(rows) row\(rows == 1 ? "" : "s") from \(job.name) (\(since))."]
        let verdicts = FindingVerdicts.lines(for: job, snapshot: snapshot, matters: matters, now: now)
        if let summary = FindingVerdicts.summary(verdicts) { lines.append(summary + ".") }
        for line in verdicts.prefix(FindingVerdicts.lineLimit) { lines.append("- \(line.label) · \(FindingVerdicts.words(line.verdict))") }
        if let more = FindingVerdicts.more(verdicts) { lines.append(more + ".") }
        lines.append(verdicts.isEmpty ? "Nothing to judge: no row had an id."
                     : "The deck has the cards. Tell the person what needs them, in your words, and that the rest was kept quiet on purpose.")
        return lines.joined(separator: "\n")
    }
}
