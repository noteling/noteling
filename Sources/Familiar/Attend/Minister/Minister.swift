import Combine
import Foundation
import FamiliarContracts

/// The attention minister: the model, in two turns, deciding what deserves the person's attention. Code tells it what
/// changed (the jobs' findings, new, changed and gone), it sorts the findings into matters and says show or quiet, and
/// why (triage); then it writes each open matter's sticker and notes (compose). Code keeps every state, checks every
/// answer, closes a matter whose findings are gone, keeps a put-away matter quiet until a finding changes, and never
/// runs anything. Changes are batched for about a minute, so one run of several jobs is one turn.
@MainActor
final class Minister: ObservableObject {
    @Published private(set) var status = ""
    @Published private(set) var isRunning = false

    let matters: Matters
    let memory: MemoryLog
    private let store: FolderJobStore
    private let config: () -> Config
    private let makeClient: (Config) -> (any ConversationClient)?
    /// How long changes gather before a turn; nil takes no turn by itself, for tests that call `flush()`.
    var batchSeconds: TimeInterval? = 60
    var clock: () -> Date = Date.init
    /// An urgent sticker was written for the first time: the app tells the person.
    var onUrgent: ((Matter) -> Void)?

    private var pending: [String: MinisterPrompt.Shown] = [:]
    private var timer: Task<Void, Never>?
    private var worker: Task<Void, Never>?
    /// A turn that failed is tried once more with the next batch; after that its findings are logged as unjudged.
    private var retried = false

    init(matters: Matters, memory: MemoryLog, store: FolderJobStore, config: @escaping () -> Config,
         makeClient: @escaping (Config) -> (any ConversationClient)? = ConversationBackend.make) {
        self.matters = matters
        self.memory = memory
        self.store = store
        self.config = config
        self.makeClient = makeClient
    }

    // MARK: what the jobs report

    /// A run reported findings. Gone ones leave their matters now, in code; new and changed ones wait for the next turn.
    func notice(_ job: FolderJob, change: FindingsChange) {
        let name = MemoryLog.name(of: job)
        for id in change.gone {
            let ref = FindingRef(job: name, id: id)
            pending[ref.key] = nil
            if let matter = matters.remove(ref) {
                if matter.state == .closed { memory.append(["matter": matter.id, "closed": "its findings are gone"]) }
                else { memory.append(["matter": matter.id, "left": ref.key]) }
            }
        }
        for row in change.new {
            let ref = FindingRef(job: name, id: row.id)
            pending[ref.key] = MinisterPrompt.Shown(ref: ref, job: job, row: row, changed: nil, putAwayAt: matters.matter(containing: ref)?.putAwayAt)
        }
        for changed in change.changed {
            let ref = FindingRef(job: name, id: changed.row.id)
            pending[ref.key] = MinisterPrompt.Shown(ref: ref, job: job, row: changed.row, changed: changed.columns,
                                                    putAwayAt: matters.matter(containing: ref)?.putAwayAt)
        }
        if !pending.isEmpty || matters.open.contains(where: \.recompose) { schedule() }
    }

    private func schedule() {
        guard let seconds = batchSeconds else { return }
        timer?.cancel()
        timer = Task { [weak self] in
            if seconds > 0 { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            guard !Task.isCancelled, let self else { return }
            await self.flush()
        }
    }

    /// A turn now, with whatever has gathered; waits for one under way first. Tests and the batch timer call it.
    func flush() async {
        if let worker { await worker.value }
        guard !pending.isEmpty || matters.open.contains(where: \.recompose) else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            isRunning = true
            await turn()
            isRunning = false
        }
        worker = task
        await task.value
        worker = nil
    }

    func stop() {
        timer?.cancel()
        worker?.cancel()
    }

    // MARK: a turn

    private func turn() async {
        let batch = pending
        pending = [:]
        let settings = config()
        guard let client = makeClient(settings) else {
            status = ConversationBackend.setupMessage(config: settings)
            pending.merge(batch) { _, kept in kept }   // for a wake after Settings
            return
        }
        do {
            if !batch.isEmpty { try await triage(Array(batch.values), client: client) }
            // Oldest matter first, so a sticker that has waited longest is written first.
            let waiting = matters.open.filter(\.recompose).sorted {
                $0.createdAt == $1.createdAt ? ($0.findings.first?.key ?? "") < ($1.findings.first?.key ?? "") : $0.createdAt < $1.createdAt
            }
            for matter in waiting { try await compose(matter, client: client) }
            retried = false
            status = ""
        } catch {
            let message = error.localizedDescription
            Log.info("minister: \(message)")
            status = message
            if !retried, !batch.isEmpty {
                retried = true
                pending.merge(batch) { _, kept in kept }
                schedule()
            } else {
                for shown in batch.values {
                    memory.append(["finding": shown.ref.key, "verdict": "unjudged", "why": "The minister couldn't judge it: \(message)"])
                }
                retried = false
            }
        }
    }

    /// The first turn: every finding in the batch gets a matter and a verdict.
    private func triage(_ findings: [MinisterPrompt.Shown], client: any ConversationClient) async throws {
        let shown = findings.sorted { $0.ref.key < $1.ref.key }
        let current = matters.current
        let prompt = MinisterPrompt.triage(shown, descriptions: descriptions(for: shown), matters: current, now: clock())
        var result: (verdicts: [MinisterPrompt.Verdict], recompose: Set<String>)?
        let ids = Set(current.map(\.id))
        let refs = shown.map(\.ref)
        try await converse(client, system: MinisterPrompt.triageSystem, prompt: prompt, tool: MinisterPrompt.triageDefinition, effort: "low") { input in
            result = try MinisterPrompt.parseTriage(input, findings: refs, matters: ids)
        }
        guard let result else { throw MinisterError("The minister gave no verdicts.") }
        apply(result.verdicts, recompose: result.recompose, findings: shown)
    }

    /// Verdicts become matters: a new label makes one matter for every finding that shares it, an id adds to that
    /// matter. A matter shows if any of its findings should; otherwise it is quiet, with the first reason given.
    private func apply(_ verdicts: [MinisterPrompt.Verdict], recompose: Set<String>, findings: [MinisterPrompt.Shown]) {
        var newIDs: [String: String] = [:]   // label → matter id
        var touched: [String: (matter: Matter, show: Bool, why: String?, joined: Bool)] = [:]
        for verdict in verdicts {
            var matter: Matter
            if verdict.isNew {
                if let id = newIDs[verdict.matter], let made = touched[id]?.matter {
                    matter = made
                } else {
                    let job = findings.first { $0.ref == verdict.finding }?.job
                    matter = Matter(id: Matter.newID(), findings: [], state: .quiet, jobName: job?.name ?? verdict.finding.job,
                                    byline: job.flatMap { FolderJobWords.names($0.contributors) }, createdAt: clock(), updatedAt: clock())
                    newIDs[verdict.matter] = matter.id
                }
            } else if let existing = touched[verdict.matter]?.matter ?? matters.matter(id: verdict.matter) {
                matter = existing
            } else { continue }
            // A finding moving to another matter leaves the one it was in.
            if let elsewhere = matters.matter(containing: verdict.finding), elsewhere.id != matter.id { _ = matters.remove(verdict.finding) }
            var joined = touched[matter.id]?.joined ?? false
            if !matter.findings.contains(verdict.finding) { matter.findings.append(verdict.finding); joined = true }
            let show = (touched[matter.id]?.show ?? false) || verdict.show
            let why = touched[matter.id]?.why ?? (verdict.show ? nil : verdict.why)
            touched[matter.id] = (matter, show, why, joined)
            memory.append(["finding": verdict.finding.key, "matter": matter.id, "verdict": verdict.show ? "show" : "quiet", "why": verdict.why])
        }
        for (id, entry) in touched {
            var matter = entry.matter
            let wasOpen = matter.state == .open
            matter.state = entry.show ? .open : .quiet
            matter.why = entry.show ? nil : (entry.why ?? matter.why)
            if entry.show { matter.putAwayAt = nil }
            if matter.state == .open, entry.joined || !wasOpen || recompose.contains(id) || matter.view == nil { matter.recompose = true }
            matters.save(matter)
        }
        for id in recompose where touched[id] == nil {
            guard var matter = matters.matter(id: id), matter.state == .open else { continue }
            matter.recompose = true
            matters.save(matter)
        }
    }

    /// The second turn: one open matter's sticker and notes.
    private func compose(_ matter: Matter, client: any ConversationClient) async throws {
        let findings = rows(of: matter)
        guard !findings.isEmpty else {
            var closed = matter
            closed.state = .closed
            closed.closedAt = clock()
            closed.view = nil
            closed.recompose = false
            matters.save(closed)
            memory.append(["matter": matter.id, "closed": "its findings are gone"])
            return
        }
        let prompt = MinisterPrompt.compose(matter, findings: findings, descriptions: descriptions(for: findings), notes: matters.notes(for: matter.id), now: clock())
        var result: (view: MatterView, notes: String?)?
        try await converse(client, system: MinisterPrompt.composeSystem, prompt: prompt, tool: MinisterPrompt.composeDefinition, effort: config().effort) { input in
            result = try MinisterPrompt.parseCompose(input, findings: findings)
        }
        guard let result else { throw MinisterError("The minister wrote no sticker for \(matter.id).") }
        var written = matter
        written.view = result.view
        written.recompose = false
        if let lead = findings.first { written.jobName = lead.job.name; written.byline = FolderJobWords.names(lead.job.contributors) }
        let tellsNow = result.view.tone == .urgent && !written.notified
        if tellsNow { written.notified = true }
        matters.save(written, notes: result.notes ?? matters.notes(for: matter.id))
        memory.append(["matter": matter.id, "sticker": result.view.text, "tone": result.view.tone.rawValue, "findings": findings.map(\.ref.key)])
        if tellsNow { onUrgent?(written) }
    }

    /// One turn with one tool: the model must call it with input the check accepts; a refusal goes back to it once.
    private func converse(_ client: any ConversationClient, system: String, prompt: String, tool: [String: Any], effort: String,
                          accept: @escaping ([String: Any]) throws -> Void) async throws {
        client.effort = effort
        client.maxToolRounds = 2
        var messages: [[String: Any]] = [["role": "user", "content": [["type": "text", "text": prompt]]]]
        let name = tool["name"] as? String ?? ""
        let reply = try await client.converse(system: system, tools: [tool], messages: &messages, executor: { called, input, _ in
            guard called == name else { return .text("Only \(name) is available.", isError: true) }
            do { try accept(input); return .text("Noted.") } catch { return .text(error.localizedDescription, isError: true) }
        }, onStatus: { _ in })
        Log.info("minister: \(name) \(reply.inputTokens) in, \(reply.outputTokens) out, \(reply.toolCalls) tool call(s)")
    }

    // MARK: what a matter is made of

    /// Each finding of a matter as its job last reported it, from the snapshot; one whose job or row is gone is left out.
    private func rows(of matter: Matter) -> [MinisterPrompt.Shown] {
        matter.findings.compactMap { ref in
            guard let job = store.jobs.first(where: { MemoryLog.name(of: $0) == ref.job }),
                  let kept = FindingsSnapshot.read(store.findingsFile(for: job)).rows[ref.id] else { return nil }
            return MinisterPrompt.Shown(ref: ref, job: job, row: kept.row, changed: nil, putAwayAt: matter.putAwayAt)
        }
    }

    private func descriptions(for findings: [MinisterPrompt.Shown]) -> [String: String] {
        var out: [String: String] = [:]
        for shown in findings where out[shown.ref.job] == nil {
            if let text = store.description(for: shown.job) { out[shown.ref.job] = text }
        }
        return out
    }
}
