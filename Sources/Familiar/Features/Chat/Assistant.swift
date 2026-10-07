import FamiliarContracts
import FamiliarRuntime
import Combine
import AppKit
import Foundation
import SwiftUI

struct ChatMessage: Identifiable {
    enum Role { case user, wand, assistant, error, draft, learned, note, receipt, check }   // draft/learned: a note Noteling starts itself (a watched workflow's title), before and after Keep; note: a sticky note someone left on the control; receipt: the last frame of a background job
    let id = UUID()
    let role: Role
    let text: String
    var meta: String? = nil        // note: who left it and when
    var warning = false            // note: a warning rather than a tip
    var image: CGImage? = nil      // receipt: the target window when the job ended
    var holds: Bool? = nil         // check: whether a note's check found its claim holds; nil when it only informs
    var seen: SeenScreen? = nil    // user/wand: what Claude was shown from the screen for this question
}

@MainActor
final class Assistant: ObservableObject {
    @Published var question = ""
    @Published var transcript: [ChatMessage] = []
    @Published var chatBusy = false { didSet { learning.setPurposeDeliveryPaused(chatBusy) } }
    var busy: Bool { chatBusy || learning.busy }
    @Published var status = ""
    @Published var contextLine = "Watching…"
    @Published var suggestions: [String] = []
    var watching: Bool { learning.watching }
    var pendingDraft: PackDraft? { learning.pendingDraft }
    @Published var backgroundControl = true   // mirror of config.controlInBackground for the pad's hand button
    /// The notes on the page or window in front, for the bubble's badge. Set by the app on every scene change.
    @Published var notesHere: [StickyNote] = []

    var config: Config
    let watcher: ContextWatcher
    let registry: ToolRegistry
    var onStartWand: (() -> Void)?
    var onCancelWand: (() -> Void)?       // the app drops an active pen before a recording starts
    var onNotesChanged: (() -> Void)?     // a note was kept or removed: the app recounts the badge
    var onShowNotes: (() -> Void)?        // the badge was clicked: the app shows the notes on the page
    /// The app shows the capture moment (`CaptureFlash`) each time a question takes the screen.
    var onCaptured: ((CaptureMoment) -> Void)?
    /// Where how notes get used is kept, on this Mac only.
    var notesUsage: NotesUsageLog?
    /// The page's own tools, run ahead when a page arrives; the pen and typed questions answer from them.
    var briefs: PageBriefs?
    var onOpenWatchDraft: ((_ title: String, _ markdown: String) -> Void)?
    var onSetControlLane: ((_ allow: Bool, _ background: Bool) -> Void)?   // the app persists both and reconfigures
    var cardConversation: CardConversation?
    /// Saved sources ("jobs") in general chat: listed every turn, changeable through tools, runnable only by a tap.
    var sourceConversation: SourceConversation? {
        didSet {
            sourceConversation?.onChange = { [weak self] receipt in self?.sourceChanged(receipt) }
            sourceConversation?.onOfferRun = { [weak self] id, name in self?.offerSourceRun(id: id, name: name) }
            sourceConversation?.onOfferConnect = { [weak self] _ in self?.offerConnect() }
        }
    }
    /// The Open Jobs tab: Jobs in Morning Files, every reading job and watch in one list.
    var onOpenJobs: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRunSource: ((UUID) -> Void)?
    /// The watch list in general chat: tools to watch items on a schedule, and to list, check, change or stop watches.
    var watchList: WatchListConversation? {
        didSet {
            watchList?.onChange = { [weak self] receipt in self?.watchListChanged(receipt) }
            watchList?.onOfferConnect = { [weak self] _ in self?.offerConnect() }
        }
    }
    private var pendingSourceTabs: [String] = []   // added to the reply's tabs when the turn ends
    private var offeredRuns: [String: UUID] = [:]  // Run now tab title → job

    let learning: WatchLearnSession
    let notes: ContextNotesService
    private var subscriptions = Set<AnyCancellable>()
    let shell: ShellState
    let execution: ExecutionCoordinator
    let desktop: DesktopExecutionService?
    private let idlePeek = PeekFeed()
    var peek: PeekFeed { desktop?.peek ?? idlePeek }
    var backgroundTaskRunning: Bool { desktop?.tasks.activeTask != nil }
    var chatResponding: Bool { chatBusy && !backgroundTaskRunning }
    var chatPresentationBusy: Bool { chatResponding || learning.busy }
    private var requestMessageID: UUID?
    private var diagnosticTurnID: UUID?

    /// The pad's hand: on = work in the window you asked from. Clicking it while control is off turns control on
    /// (the user is flipping the gate themselves), in the background lane, which never takes the mouse unasked.
    var backgroundOn: Bool { config.allowControl && backgroundControl }
    func toggleBackgroundControl() {
        if !config.allowControl {
            onSetControlLane?(true, true)
            status = "Control is on — I'll work in the window while you carry on, and ask before I ever take the mouse."
        } else {
            onSetControlLane?(true, !backgroundControl)
            status = backgroundControl ? "I'll take the mouse when you ask me to do things." : "I'll work in the window while you carry on."
        }
    }

    private var client: (any ConversationClient)?
    private var captureGeneration = 0   // invalidates a screen capture prepared before Clear/provider change
    private var lastCapture: (at: Date, scene: ScreenContext?)?
    private var awaitingPurpose: Bool { learning.awaitingPurpose }
    private var awaitingContext: Bool { learning.awaitingContext }
    private var draftFailed: Bool { learning.draftFailed }
    private var purposeMessageID: UUID?          // the typed purpose line, folded into the draft note when it arrives
    private var contextMessageID: UUID?

    static let continueTab = "Skip the description"
    static let skipContextTab = "Skip context"
    static let keepTab = "Keep it"
    static let fullDraftTab = "Open full draft"
    static let discardTab = "Discard"
    static let retryTab = "Try again"
    /// A saved job or a watch changed in chat: where to see it.
    static let openJobsTab = "Open Jobs"
    static let openSettingsTab = "Open Settings"
    static let reservedTabs = [continueTab, skipContextTab, keepTab, fullDraftTab, discardTab, retryTab]

    init(config: Config, watcher: ContextWatcher, registry: ToolRegistry, shell: ShellState, learning: WatchLearnSession,
         execution: ExecutionCoordinator? = nil, desktop: DesktopExecutionService? = nil) {
        self.learning = learning
        self.notes = ContextNotesService(registry: registry)
        self.shell = shell
        self.execution = execution ?? ExecutionCoordinator()
        self.desktop = desktop
        self.config = config
        self.watcher = watcher
        self.registry = registry
        backgroundControl = config.controlInBackground
        client = ConversationBackend.make(config: config)
        desktop?.tasks.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        learning.onEvent = { [weak self] in self?.presentLearning($0) }
        learning.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        learning.$phase.scan((wasWatching: false, watching: false)) { previous, phase in
            (wasWatching: previous.watching, watching: phase == .recording || phase == .stopping)
        }.sink { [weak self] change in
            guard let self, change.wasWatching, !change.watching else { return }
            self.contextLine = self.watcher.current?.summaryLine ?? (self.watcher.isRunning ? "Watching…" : "Watcher off")
        }.store(in: &subscriptions)
        learning.$phase.sink { [weak self] phase in
            if phase == .summarizing { self?.suggestions = [] }
        }.store(in: &subscriptions)
        learning.$status.dropFirst().sink { [weak self] in self?.status = $0 }.store(in: &subscriptions)
        learning.$clickCount.dropFirst().sink { [weak self] count in
            guard let self, self.watching else { return }
            self.contextLine = self.recordingLine(count)
        }.store(in: &subscriptions)
    }

    var hasConnection: Bool { client != nil }

    /// Transfer the submitted instruction to the task screen once desktop work starts.
    /// The request continues in the coordinator; closing or clearing chat does not own its result.
    func backgroundTaskDidBegin() {
        guard backgroundTaskRunning else { return }
        if let requestMessageID { transcript.removeAll { $0.id == requestMessageID } }
        status = ""
        suggestions = []
        shell.expanded = false
    }

    func showBackgroundTasks() { desktop?.tasks.show() }

    func clearConversation() {
        cardConversation?.clear()
        captureGeneration += 1
        transcript.removeAll()
        execution.conversation.clear()
        suggestions.removeAll()
        status = ""
        lastCapture = nil
        learning.clear()
        purposeMessageID = nil
        contextMessageID = nil
        pendingSourceTabs = []
        offeredRuns = [:]
    }

    func startWand() {
        guard !busy else { return }
        guard !awaitingPurpose, !awaitingContext else { status = "Finish or discard Watch Me before using the pen."; return }
        guard !watching else { status = "Watching — stop watching before picking up the pen."; return }
        onStartWand?()
    }

    func askSuggestion(_ s: String) {
        if s == Self.openJobsTab, let onOpenJobs { onOpenJobs(); return }
        if s == Self.openSettingsTab, let onOpenSettings { onOpenSettings(); return }
        if let id = offeredRuns.removeValue(forKey: s) {
            suggestions.removeAll { $0 == s }
            onRunSource?(id)
            return
        }
        if s == "Back to general chat", cardConversation?.cardID != nil {
            cardConversation?.clear()
            execution.conversation.clear()
            suggestions = []
            status = "Back to general chat."
            return
        }
        if awaitingPurpose {
            if s == Self.continueTab {
                if learning.submitDescription(nil) { question = "" }
                return
            }
            if s == Self.discardTab { learning.discard(); return }
        }
        if awaitingContext {
            if s == Self.skipContextTab {
                if learning.submitContext(nil) != nil { question = "" }
                return
            }
            if s == Self.discardTab { learning.discard(); return }
        }
        if pendingDraft != nil || draftFailed {
            if s == Self.fullDraftTab, let draft = pendingDraft {
                onOpenWatchDraft?(Self.reviewExcerpt(draft.parsed ? draft.workflowTitle : "Unparsed Watch Me draft", limit: 100),
                    Self.draftDocument(draft, purpose: learning.pendingRecording?.meta.purpose,
                                       context: learning.pendingRecording?.meta.context, root: registry.root,
                                       teachingCalendar: learning.isTeachingSource))
                return
            }
            if s == Self.keepTab { Task { await learning.keep() }; return }
            if s == Self.discardTab { learning.discard(); return }
            if s == Self.retryTab { learning.retry(); return }
        }
        if Self.reservedTabs.contains(s) { suggestions = reviewTabs([]); return }   // a stale tab: never a question for Claude
        question = s
        ask()
    }

    /// The tabs a note should carry given what is pending, on top of Claude's own follow-ups.
    private func reviewTabs(_ sugg: [String]) -> [String] {
        if awaitingPurpose { return [Self.continueTab, Self.discardTab] }
        if awaitingContext { return [Self.skipContextTab, Self.discardTab] }
        if let draft = pendingDraft {
            return sugg + [Self.fullDraftTab, draft.parsed ? Self.keepTab : Self.retryTab, Self.discardTab]
        }
        if draftFailed { return sugg + [Self.retryTab, Self.discardTab] }
        if cardConversation?.cardID != nil {
            return sugg.filter { $0 != "Back to general chat" } + ["Back to general chat"]
        }
        return sugg
    }

    // MARK: Watch presentation adapter

    func toggleWatching() { if watching { stopWatching() } else { startWatching() } }

    private func recordingLine(_ clicks: Int) -> String {
        let hotkey = HotKey.display(config.hotkey.isEmpty ? "control+option+space" : config.hotkey)
        return "Recording — \(clicks) click\(clicks == 1 ? "" : "s") · \(hotkey) to stop"
    }

    /// Permissions and presentation belong to the app; recording/draft lifetime belongs to learning.
    func startWatching(calendar: Bool = false, source: Bool = false) {
        guard !busy, !watching, !learning.stopping else { return }
        if learning.hasPendingReview {
            shell.expanded = true
            transcript.append(ChatMessage(role: .error, text: "Finish or discard the current Watch Me session first."))
            suggestions = reviewTabs([])
            return
        }
        guard Permissions.screenRecordingGranted else {
            shell.expanded = true
            transcript.append(ChatMessage(role: .error, text: ScreenCaptureError.notPermitted.localizedDescription))
            return
        }
        onCancelWand?()
        var warned = false
        if !Permissions.accessibilityGranted {
            Permissions.requestAccessibility()
            transcript.append(ChatMessage(role: .error, text: "Without Accessibility I can't see what you click or type, so this will be screenshots only. Grant it in the menu bar (Accessibility: not granted) for a useful write-up."))
            warned = true
        }
        do {
            guard try learning.start(calendar: calendar, source: source) else { return }
            shell.expanded = warned || calendar || source
        } catch {
            shell.expanded = true
            transcript.append(ChatMessage(role: .error, text: "Could not start recording: \(error.localizedDescription)"))
        }
    }

    func stopWatching() { learning.stop() }
    func abortWatching() { learning.abort() }

    private func presentLearning(_ event: WatchLearnSession.Event) {
        switch event {
        case .started:
            suggestions = []
            status = ""
            contextLine = recordingLine(0)
            if learning.isTeachingSource {
                transcript.append(ChatMessage(role: .assistant, text: "Show me the information you want in your morning read: an inbox, a calendar, or another page. Show its address and account, then the limited view I should read—for example, the first page of Primary in Gmail. For a calendar, show its selection and time zone. Stop watching when you're done, then review and keep it as a job in Jobs. The information shown while teaching is only an example."))
            }
        case .stopped:
            contextLine = watcher.current?.summaryLine ?? (watcher.isRunning ? "Watching…" : "Watcher off")
        case .purposeRequested(let recording):
            shell.expanded = true
            let question = "Give this a short name or description—for example, ‘Check unread email.’ You can add context next."
            transcript.append(ChatMessage(role: .assistant, text: "Got it — \(recording.meta.clicks) click\(recording.meta.clicks == 1 ? "" : "s"). " + question))
            suggestions = reviewTabs([])
        case .contextRequested:
            shell.expanded = true
            let example = learning.isTeachingSource ? " For example, ‘Only unread emails from the last 2 days. Skip promotions.’" : " Include anything to skip, exceptions, or where to stop."
            transcript.append(ChatMessage(role: .assistant, text: "Any rules or limits I should follow?" + example + " Add context below, or choose Skip context."))
            suggestions = reviewTabs([])
        case .emptyRecording:
            shell.expanded = true
            transcript.append(ChatMessage(role: .assistant, text: "I didn't see you do anything, so there is nothing to write up."))
            suggestions = []
        case .draftReady(let draft, let recording, _):
            if let id = purposeMessageID { transcript.removeAll { $0.id == id } }
            if let id = contextMessageID { transcript.removeAll { $0.id == id } }
            purposeMessageID = nil
            contextMessageID = nil
            transcript.append(ChatMessage(role: .draft, text: draft.parsed ? Self.reviewExcerpt(draft.workflowTitle, limit: 100) : "Could not write this up"))
            transcript.append(ChatMessage(role: .assistant, text: Self.draftBody(draft, purpose: recording.meta.purpose,
                context: recording.meta.context, root: registry.root, teachingCalendar: learning.isTeachingCalendar)))
            suggestions = reviewTabs([])
        case .kept(let draft, let files):
            let packRoot = registry.root.appendingPathComponent(draft.packDir).path + "/"
            let rel = files.map { $0.path.replacingOccurrences(of: packRoot, with: "") }
            let whereText = Self.reviewExcerpt(draft.matchURLs.first ?? draft.matchTitles.first.map { "“\($0)”" } ?? draft.matchBundles.first ?? draft.packName, limit: 100)
            if let i = transcript.lastIndex(where: { $0.role == .draft }) {
                transcript[i] = ChatMessage(role: .learned, text: transcript[i].text)
            }
            transcript.append(ChatMessage(role: .assistant, text: Self.sourceReceipt(draft) + "Kept as \(Self.reviewExcerpt(draft.packName, limit: 80)). I'll use it whenever you're on \(whereText). The recording itself is deleted.\n" + rel.map { "- \($0)" }.joined(separator: "\n")))
            suggestions = []
            status = ""
        case .failed(_, let error):
            transcript.append(ChatMessage(role: .error, text: error.localizedDescription))
            suggestions = reviewTabs([])
        case .discarded(let savedFiles):
            purposeMessageID = nil
            contextMessageID = nil
            suggestions = []
            status = ""
            let receipt = savedFiles.isEmpty ? "Discarded. The recording was deleted and nothing was saved."
                : "Discarded the remaining review. The recording was deleted. These files were already saved and remain on disk:\n" + savedFiles.map { "- \($0.path)" }.joined(separator: "\n")
            transcript.append(ChatMessage(role: .assistant, text: receipt))
        }
    }

    /// A reading source without an account reads the one its taught view shows.
    static let accountShownWhenRun = "Whichever one it shows when it runs"

    /// The saved address, or the app for a native source.
    static func location(of source: LearnedReadingSource) -> String {
        source.url.isEmpty && !source.application.isEmpty ? "The \(source.application) app" : source.url
    }

    /// What Keep registered as a job, and whether it can run yet.
    static func sourceReceipt(_ draft: PackDraft) -> String {
        var s = draft.calendarSource.map { "Calendar source kept: \(reviewExcerpt($0.name, limit: 80)). It's a job in Jobs now. Review any missing details before reading.\n\n" } ?? ""
        if let source = draft.readingSource {
            s += "Reading source kept: \(reviewExcerpt(source.name, limit: 80)). It's a job in Jobs now. "
            if let missing = source.missingSetup {
                s += "It can't run yet: \(reviewExcerpt(missing, limit: 200)) Tell me here, or add it on its page in Jobs.\n\n"
            } else {
                s += source.requiresReview ? "Confirm its address on its page in Jobs before reading; it was learned from screenshot evidence.\n\n" : "Each run reads fresh information within the saved scope.\n\n"
            }
        }
        return s.isEmpty ? "No reading source was registered, so Jobs won't run this workflow.\n\n" : s
    }

    /// Keep generated documents out of the animated chat layout. Only bounded, single-line fields go on the note.
    static func draftBody(_ d: PackDraft, purpose: String? = nil, context: String? = nil, root: URL, teachingCalendar: Bool = false) -> String {
        var lines: [String] = []
        if let purpose, !purpose.isEmpty { lines.append("_You said: “\(reviewExcerpt(purpose, limit: 140))”_") }
        guard d.parsed else {
            return (lines + ["I couldn't turn this into a skill. Open full draft to inspect the response, try again, or tell me what to change."]).joined(separator: "\n\n")
        }
        func field(_ label: String, _ value: String, limit: Int = 100) {
            lines.append("**\(label):** \(reviewExcerpt(value.isEmpty ? "Not established" : value, limit: limit))")
        }
        func uncertainties(_ values: [String]) {
            guard let first = values.first else { return }
            field("Still unclear", first, limit: 140)
            if values.count > 1 { lines.append("\(values.count - 1) more uncertainties in the full draft.") }
        }
        func assumptions(_ values: [String]) {
            guard let first = values.first else { return }
            field("Assuming", first, limit: 140)
            if values.count > 1 { lines.append("\(values.count - 1) more in the full draft.") }
        }
        if let source = d.readingSource {
            lines.append("**Reading source to keep**")
            field("Name", source.name, limit: 70)
            field("Meaning", source.meaning, limit: 100)
            field("Account", source.account.isEmpty ? Self.accountShownWhenRun : source.account, limit: 80)
            field("Location", Self.location(of: source), limit: 100)
            field("Reading rules", source.scope, limit: 220)
            assumptions(source.uncertainties)
            if let missing = source.missingSetup, !source.requiresReview {
                lines.append("**Before it can run:** \(reviewExcerpt(missing, limit: 200)) Tell me here and I'll write it again, or keep it and add it later on its page in Jobs.")
            } else {
                lines.append(source.requiresReview
                    ? "Keep adds it to Jobs. Confirm its address there before it can run."
                    : "Keep adds it to Jobs, where Run now and Run all reading jobs read it.")
            }
        } else if let source = d.calendarSource {
            lines.append("**Calendar source to keep**")
            field("Name", source.name, limit: 70)
            field("Meaning", source.meaning, limit: 100)
            field("Account", source.account, limit: 80)
            field("Calendar", source.calendarName, limit: 80)
            field("Time zone", source.timeZoneID, limit: 60)
            uncertainties(source.uncertainties)
            lines.append("Keep adds it to Jobs, where Run now and Run all reading jobs read it.")
        } else if teachingCalendar {
            lines.append("**Reading source not established**\nKeep cannot add this draft to Jobs. Tell me what is missing (the page address, the account, or what to read) and I'll write it again, or discard it and teach it again.")
        } else {
            field("Skill", d.packName)
            field("Description", d.packDescription.isEmpty ? d.workflowTitle : d.packDescription, limit: 180)
            if let context, !context.isEmpty { field("Your context", context, limit: 180) }
            lines.append("The workflow instructions are ready to review.")
        }
        if let caveat = d.caveats.first {
            field("Caution", caveat, limit: 120)
            if d.caveats.count > 1 { lines.append("\(d.caveats.count - 1) more cautions in the full draft.") }
        }
        lines.append("Open full draft for complete instructions and any shortened details. To change something, just tell me, and I'll write it again.")
        return lines.joined(separator: "\n\n")
    }

    private static func reviewExcerpt(_ value: String, limit: Int) -> String {
        let line = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }

    /// Full review is built only on demand and displayed outside the bubble, without changing the saved draft.
    static func draftDocument(_ d: PackDraft, purpose: String? = nil, context: String? = nil, root: URL, teachingCalendar: Bool = false) -> String {
        var s = ""
        if let purpose, !purpose.isEmpty { s += "_You said: “\(purpose)”_\n\n" }
        if let context, !context.isEmpty { s += "## Your additional context\n\(context)\n\n" }
        guard d.parsed else {
            return s + "I couldn't turn this into a pack entry. Here is what came back:\n\n" + d.raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        s += d.workflowMarkdown
        if let source = d.readingSource {
            func known(_ value: String) -> String { value.isEmpty ? "Not established" : value }
            s += "\n\n**Reading source to keep**\n"
            let fields = [("Name", source.name), ("Kind", source.kind == .mail ? "Mail" : "Web"),
                          ("Meaning", source.meaning), ("Application", source.application),
                          ("Application identifier", source.bundleID), ("Location", location(of: source)),
                          ("Account", source.account.isEmpty ? accountShownWhenRun : source.account),
                          ("Reading rules", source.scope), ("Navigation", source.navigationHints), ("Completion checks", source.completionChecks)]
            s += fields.map { "**\($0.0):** \(known($0.1))" }.joined(separator: "\n")
            s += "\n**Assuming:** " + (source.uncertainties.isEmpty ? "Nothing beyond what's above." : source.uncertainties.joined(separator: "; "))
            if let missing = source.missingSetup { s += "\n**Before it can run:** \(missing)" }
            s += source.requiresReview ? "\nKeep adds it to Jobs. Confirm its address there before it can run."
                : source.missingSetup == nil ? "\nKeep adds it to Jobs, where Run now and Run all reading jobs read it. Each run reads fresh information within this scope."
                : "\nKeep adds it to Jobs, but it won't run until then."
            s += "\nThe demonstration is an example, not a collected result or permission to send, edit, or scan the whole account."
        }
        if let source = d.calendarSource {
            func known(_ value: String) -> String { value.isEmpty ? "Not established" : value }
            s += "\n\n**Calendar source to keep**\n"
            let fields = [("Name", source.name), ("Meaning", source.meaning), ("Application", source.application),
                          ("Application identifier", source.bundleID), ("Location", source.url), ("Account", source.account),
                          ("Calendar", source.calendarName), ("Time zone", source.timeZoneID),
                          ("Navigation", source.navigationHints), ("Completion checks", source.completionChecks)]
            s += fields.map { "**\($0.0):** \(known($0.1))" }.joined(separator: "\n")
            s += "\n**Still unclear:** " + (source.uncertainties.isEmpty ? "No additional uncertainties recorded; review any fields marked Not established." : source.uncertainties.joined(separator: "; "))
            s += "\nThe demonstrated dates and events are examples. A calendar read will collect fresh results separately."
        } else if teachingCalendar && d.readingSource == nil {
            s += "\n\n**Reading source not established**\nKeep cannot add this draft to Jobs. Show the source address, account and the bounded information to read, then discard this draft and teach it again."
        }
        if !d.screensMarkdown.isEmpty { s += "\n\n## Screens\n" + d.screensMarkdown }
        if !d.glossaryMarkdown.isEmpty { s += "\n\n## Glossary\n" + d.glossaryMarkdown }
        if !d.caveats.isEmpty { s += "\n\n" + d.caveats.map { "_\($0)_" }.joined(separator: "\n") }
        let matches = d.matchURLs + d.matchTitles.map { "“\($0)”" } + d.matchBundles
        s += "\n\nMatches: " + (matches.isEmpty ? "nothing (would not be saved)" : matches.joined(separator: ", "))
        s += "\nKeep it → \(root.lastPathComponent)/\(d.packDir)/docs/workflows/\(d.workflowSlug).md"
        return s
    }

    /// Typed question. Always attaches a fresh screenshot as context (the chat card itself is excluded from the capture),
    /// unless `screenshotReuseSeconds` allows reusing the last one for a quick follow-up on the same screen.
    func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        diagnosticTurnID = UUID()
        diagnoseChat(.chatSubmitted)
        question = ""
        let teaching = awaitingPurpose || awaitingContext
        let m = ChatMessage(role: .user, text: teaching ? Self.reviewExcerpt(q, limit: 220) : q)
        transcript.append(m)
        diagnoseChat(.transcriptUpdated)
        if awaitingPurpose {
            purposeMessageID = m.id
            suggestions = []
            if !learning.submitDescription(q) {
                question = q
                transcript.removeAll { $0.id == m.id }
                purposeMessageID = nil
            }
            return
        }
        if awaitingContext {
            contextMessageID = m.id
            suggestions = []
            if learning.submitContext(q) == nil {
                question = q
                transcript.removeAll { $0.id == m.id }
                contextMessageID = nil
            }
            return
        }
        if pendingDraft != nil || draftFailed {
            // Talking about the draft revises it: the feedback joins the recording's context and it is written again.
            suggestions = []
            if learning.revise(q) == nil {
                transcript.append(ChatMessage(role: .error, text: "Keep or discard the draft above first."))
                suggestions = reviewTabs([])
            }
            return
        }
        let ctx = watcher.current ?? watcher.sample()
        chatBusy = true
        let generation = captureGeneration
        let briefing = cardConversation?.card == nil && briefs?.source(for: ctx) != nil
        if briefing { briefs?.prefetch(ctx) }

        Task {
            var content: [[String: Any]] = []
            let evidence = cardConversation?.card != nil ? ScreenEvidence.none
                : Self.evidence(for: q, mode: config.screenshotMode, bundleID: ctx?.bundleID)
            var attach = evidence == .screenshot, page = ""
            // A question about the screen takes it now, for the whole answer, and shows that it did (the flash and the
            // chip): after that the person can switch away. The picture is taken beside the page read.
            let held = evidence == .none ? nil : FrozenScreen(scene: ctx)
            var seen = SeenScreen(kind: .screen, at: held?.at ?? Date(), place: SeenScreen.place(ctx))
            let maxEdge = config.maxImageLongEdge
            let capturing = Task { () -> CGImage? in
                guard let held else { return nil }
                do {
                    let raw = try await ScreenCapture.captureDisplay()
                    let picture = ScreenCapture.downscale(raw.image, maxLongEdge: maxEdge)
                    held.keep(picture: picture)
                    if generation == captureGeneration { onCaptured?(CaptureMoment(image: picture, screen: raw.screen)) }
                    return picture
                } catch {
                    Log.info("ask: no screenshot: \(error.localizedDescription)")
                    return nil
                }
            }
            if evidence == .page, let bundle = ctx?.bundleID {
                status = "Reading the page…"
                let read = await Task.detached(priority: .userInitiated) { PageReader.read(bundleID: bundle) }.value
                guard generation == captureGeneration else { finishRequest(); return }
                if let read, !(read.elements.isEmpty && read.sheet == nil) {
                    page = Self.pageSection(read)
                    let text = read.text()
                    held?.keep(pageText: text)
                    seen.pageText = text
                    Log.info("ask: page read attached (\(read.elements.count) things, \(Int(read.elapsed * 1_000)) ms)")
                } else {
                    attach = true   // nothing readable, such as a PDF or a canvas: a picture instead
                    Log.info("ask: page unreadable; screenshot instead")
                }
            }
            Log.info("ask: screenshot \(attach ? "attached" : "skipped") (mode \(config.screenshotMode))")
            let picture = await capturing.value
            guard generation == captureGeneration else { finishRequest(); return }
            if let picture, attach, needsFreshCapture(for: ctx), let shot = ScreenCapture.encode(picture) {
                content.append(imageBlock(shot))
                lastCapture = (Date(), ctx)
                seen.pictures.append(picture)
                Log.info("ask: screenshot \(shot.width)x\(shot.height) \(shot.sizeKB)KB")
            }
            if held != nil {
                seen.held = !controlsForeground
                setSeen(seen, on: m.id)
            }
            var brief = ""
            if briefing {
                status = "Checking this page…"
                if let b = await briefs?.brief(for: ctx, wait: 10) { brief = Prompt.brief(b) }
                guard generation == captureGeneration else { finishRequest(); return }
            }
            let context = cardConversation?.card == nil
                ? Prompt.context(ctx, recent: watcher.history) + packsSection(ctx) + (sourceConversation?.context ?? "") : ""
            let text = context + brief + page + "\n## Question\n\(q)\n"
            content.append(["type": "text", "text": text])
            diagnoseChat(.contextReady)
            await send(content: content, ctx: ctx, title: q, messageID: m.id, held: held)
        }
    }

    /// Wand pick: full screenshot with a ring at the click (or the ink stroke, for a circled region), plus a zoomed crop,
    /// then a short identify-and-offer reply. Notes stuck on the target go on the pad first, and into the prompt.
    func wandPick(_ target: WandTarget) {
        guard !busy else { status = "Still answering the last one."; return }
        guard !awaitingPurpose, !awaitingContext else { status = "Finish or discard Watch Me before using the pen."; return }
        shell.expanded = true
        let pick = ChatMessage(role: .wand, text: target.shortLabel)
        transcript.append(pick)
        // What people wrote comes first, at once and labelled: on this control, then for things not on screen.
        let off = Array(target.notOnScreen.prefix(5))
        var rows: [String: UUID] = [:]
        for n in target.notes {
            let row = ChatMessage(role: .note, text: n.text, meta: n.peopleSay(), warning: n.isWarning)
            rows[n.id] = row.id
            transcript.append(row)
        }
        for n in off {
            let place = target.furtherDown.contains(n.id) ? "further down the page" : "not on your screen"
            transcript.append(ChatMessage(role: .note, text: n.text, meta: "For \(n.anchor.controlSummary), \(place) · " + n.peopleSay(),
                                          warning: n.isWarning))
        }
        let ctx = watcher.sample() ?? watcher.current
        chatBusy = true
        let generation = captureGeneration
        // Only the notes on what was pointed at run their checks; a note elsewhere is checked when its sticker is picked.
        let checked = target.notes.filter { $0.check != nil }
        notesUsage?.record("pick", counts: ["onTarget": target.notes.count, "notOnScreen": target.notOnScreen.count, "checks": checked.count],
                           tags: ["kind": target.isRegion ? "circle" : target.named != nil ? "sticker" : "point"],
                           notes: (target.notes + off).map(\.id))

        let briefing = briefs?.source(for: ctx) != nil
        if briefing { briefs?.prefetch(ctx) }

        Task {
            status = "Capturing screen…"
            var content: [[String: Any]] = []
            // The screen is taken once, at the pick, for the whole answer, and the pick shows it: the flash, the picked
            // part flying to the pad, and the chip under the pick.
            var held: FrozenScreen?
            var seen = SeenScreen(kind: target.isRegion ? .circled : .pointed, at: Date(), place: SeenScreen.place(ctx))
            do {
                let raw = try await ScreenCapture.captureDisplay(containing: target.screenPoint)
                guard generation == captureGeneration else { finishRequest(); return }
                let full = ScreenCapture.downscale(raw.image, maxLongEdge: config.maxImageLongEdge)
                held = FrozenScreen(scene: ctx, at: seen.at, picture: full)
                let f = CGFloat(full.width) / CGFloat(raw.image.width)
                let picked: NSRect
                if let stroke = target.stroke, let region = target.region {
                    picked = region
                    let pts = stroke.map { raw.imagePoint($0) }
                    let annotated = ScreenCapture.annotate(full, stroke: pts.map { CGPoint(x: $0.x * f, y: $0.y * f) })
                    if let shot = ScreenCapture.encode(annotated) { content.append(imageBlock(shot)); seen.pictures.append(annotated) }
                    let tl = raw.imagePoint(NSPoint(x: region.minX, y: region.maxY))
                    let rect = CGRect(x: tl.x, y: tl.y, width: region.width * raw.pixelsPerPoint, height: region.height * raw.pixelsPerPoint)
                    let pad = max(40 * raw.pixelsPerPoint, CGFloat(min(raw.image.width, raw.image.height)) * 0.04)
                    if let cropped = ScreenCapture.crop(raw.image, around: rect, padding: pad, maxLongEdge: 1568), let shot = ScreenCapture.encode(cropped) {
                        content.append(imageBlock(shot))
                        seen.pictures.append(cropped)
                    }
                    Log.info("wand: images \(content.count), region \(Int(rect.width))x\(Int(rect.height))px")
                } else {
                    let p = raw.imagePoint(target.screenPoint)
                    let annotated = ScreenCapture.annotate(full, ringAt: CGPoint(x: p.x * f, y: p.y * f))
                    if let shot = ScreenCapture.encode(annotated) { content.append(imageBlock(shot)); seen.pictures.append(annotated) }
                    let cropSize = CGSize(width: 900 * raw.pixelsPerPoint / 2, height: 560 * raw.pixelsPerPoint / 2)
                    if let cropped = ScreenCapture.crop(raw.image, around: p, size: cropSize), let shot = ScreenCapture.encode(cropped) {
                        content.append(imageBlock(shot))
                        seen.pictures.append(cropped)
                    }
                    picked = NSRect(x: target.screenPoint.x - 225, y: target.screenPoint.y - 140, width: 450, height: 280)
                    Log.info("wand: images \(content.count), point \(Int(p.x)),\(Int(p.y))")
                }
                onCaptured?(CaptureMoment(image: full, screen: raw.screen, region: picked))
                seen.held = !controlsForeground
                setSeen(seen, on: pick.id)
                lastCapture = (Date(), ctx)
            } catch {
                guard generation == captureGeneration else { finishRequest(); return }
                transcript.append(ChatMessage(role: .error, text: error.localizedDescription))
                Log.info("wand: capture failed: \(error.localizedDescription)")
            }
            guard generation == captureGeneration else { finishRequest(); return }

            // The checks run as you, all at once, each stopped at its time limit; each answer goes right under its note.
            var checks: [String: NoteCheckResult] = [:]
            if !checked.isEmpty {
                status = "Checking what the notes say…"
                let checker = NoteChecker(registry: registry)
                let results = await withTaskGroup(of: (String, NoteCheckResult)?.self) { group in
                    for note in checked {
                        guard let check = note.check else { continue }
                        group.addTask { @MainActor in (note.id, await checker.run(check, context: ctx)) }
                    }
                    var out: [(String, NoteCheckResult)] = []
                    for await result in group { if let result { out.append(result) } }
                    return out
                }
                guard generation == captureGeneration else { status = ""; finishRequest(); return }
                for note in checked {
                    guard let result = results.first(where: { $0.0 == note.id })?.1 else { continue }
                    checks[note.id] = result
                    let row = ChatMessage(role: .check, text: result.line, holds: result.verdict == .holds ? true : result.verdict == .fails ? false : nil)
                    if let id = rows[note.id], let index = transcript.firstIndex(where: { $0.id == id }) { transcript.insert(row, at: index + 1) }
                    else { transcript.append(row) }
                    notesUsage?.record("check", counts: ["ms": result.milliseconds], tags: ["script": result.script, "result": result.verdict.rawValue],
                                       notes: [note.id])
                }
            }
            var brief = ""
            if briefing {
                status = "Checking this page…"
                if let b = await briefs?.brief(for: ctx, wait: 10) { brief = Prompt.brief(b) }
                guard generation == captureGeneration else { status = ""; finishRequest(); return }
            }
            let sent = Set((target.notes + off).map(\.id))
            let elsewhere = registry.notes(for: ctx).filter { !sent.contains($0.id) }
            let text = Prompt.context(ctx, recent: watcher.history) + packsSection(ctx, notes: false) + brief + "\n"
                + Prompt.wandInstruction(target: target, ctx: ctx)
                + Prompt.notes(onTarget: target.notes, notOnScreen: off, furtherDown: target.furtherDown, elsewhere: elsewhere, checks: checks)
            content.append(["type": "text", "text": text])
            await send(content: content, ctx: ctx, title: target.shortLabel, held: held, seenOn: pick.id)
        }
    }

    // MARK: notes

    /// A note written with the pen: into the first active pack for the scene, or a pack made for it.
    func saveNote(_ note: StickyNote) {
        let ctx = watcher.current ?? watcher.sample()
        Task {
            do {
                let place = try await notes.keep(note, appName: ctx?.appName)
                status = "Note kept"
                notesUsage?.record("note_kept", tags: ["kind": note.kind, "check": note.check == nil ? "no" : "yes"], notes: [note.id])
                Log.info("notes: kept \(note.kind) on \(note.anchor.summary) in \(place)")
                onNotesChanged?()
            } catch {
                shell.expanded = true
                transcript.append(ChatMessage(role: .error, text: "Could not keep the note: \(error.localizedDescription)"))
            }
        }
    }

    func deleteNote(_ id: String) {
        do {
            try notes.remove(id)
            status = "Note removed"
            notesUsage?.record("note_removed", notes: [id])
            onNotesChanged?()
        }
        catch { transcript.append(ChatMessage(role: .error, text: "Could not remove the note: \(error.localizedDescription)")) }
    }

    // MARK: internals

    @discardableResult
    func discussCard(_ card: MorningCard) -> Bool {
        guard !busy, !watching, !awaitingPurpose, !awaitingContext, pendingDraft == nil, !draftFailed,
              let cardConversation else {
            status = "Finish the current conversation or Watch Me step before discussing this card."
            return false
        }
        cardConversation.select(card.id)
        execution.conversation.clear()
        transcript.append(ChatMessage(role: .assistant, text: "Let’s discuss “\(card.title)”. Tell me what you’d like to change or understand."))
        suggestions = ["What should I do?", "Adjust the action", "Back to general chat"]
        shell.expanded = true
        status = "Discussing this card"
        diagnoseChat(.chatPanelShown)
        return true
    }

    /// What a typed question takes from the screen: nothing, the page's text, or a picture. In a browser a question
    /// about the screen gets the page itself, read through Accessibility, which is exact on small text, numbers and
    /// links and sends no image; a picture only when the question is about how something looks. Other apps, and the
    /// "always" setting, keep the picture; "never" takes nothing. The model can always ask for a picture with
    /// look_at_screen, or for the page with read_screen.
    enum ScreenEvidence: Equatable { case none, page, screenshot }

    static func evidence(for question: String, mode: String, bundleID: String?) -> ScreenEvidence {
        switch mode {
        case "never": return .none
        case "always": return .screenshot
        default:
            guard soundsScreenRelated(question) else { return .none }
            if let bundleID, ContextWatcher.browserBundles.contains(bundleID), !soundsVisual(question) { return .page }
            return .screenshot
        }
    }

    /// The question is about how something looks, which only a picture shows.
    static func soundsVisual(_ q: String) -> Bool {
        let t = " " + q.lowercased().replacingOccurrences(of: "[^a-z0-9' ]", with: " ", options: .regularExpression) + " "
        let cues = [" look at", " looks ", " look like", " looking ", " colour", " color", " chart", " graph", " plot ", " diagram",
                    " image", " picture", " photo", " screenshot", " layout", " design", " font", " logo", " icon", " style",
                    " aligned", " alignment", " overlap", " blurry", " visual", " appearance", " map "]
        return cues.contains { t.contains($0) }
    }

    /// The page in front, as the question's context: what it says and what can be clicked, and how to see it instead.
    static func pageSection(_ page: PageSnapshot) -> String {
        "\n## The page in front (read through Accessibility, not a picture)\n"
            + "If the question is about how something looks, call look_at_screen to see it.\n\n"
            + page.text(limit: 12_000)
    }

    /// Cheap intent guess for typed questions: deictic words and UI nouns mean "about the screen".
    static func soundsScreenRelated(_ q: String) -> Bool {
        let t = " " + q.lowercased().replacingOccurrences(of: "[^a-z0-9' ]", with: " ", options: .regularExpression) + " "
        if t.split(separator: " ").count <= 3 { return true }   // "why?", "and this?", "what now" refer to the screen
        let cues = [" this ", " that ", " these ", " those ", " here ", " it ", " its ", " screen", " page", " button", " field",
                    " form", " tab ", " menu", " dialog", " popup", " error", " message", " window", " greyed", " grayed",
                    " disabled", " highlighted", " selected", " why is", " why can't", " why cant", " why does", " what does",
                    " what is this", " what's this", " where is", " where's", " which one", " on my screen", " in front of me",
                    " cell", " column", " row ", " sheet", " formula", " dropdown", " checkbox", " link", " icon"]
        return cues.contains { t.contains($0) }
    }

    /// The look_at_screen tool: the screen as it was when they asked, while the answer holds it; else a fresh
    /// screenshot, shown with the capture moment. Either way the question's chip gets the picture.
    private func lookAtScreen(_ ctx: ScreenContext?, generation: Int, held: FrozenScreen? = nil, seenOn: UUID? = nil) async -> ToolResult {
        if let held, let picture = held.picture, let shot = ScreenCapture.encode(picture) {
            addSeen(picture: picture, on: seenOn, ctx: ctx)
            Log.info("look_at_screen: as asked \(Int(Date().timeIntervalSince(held.at)))s ago, \(shot.width)x\(shot.height) \(shot.sizeKB)KB")
            return .blocks([["type": "text", "text": held.pictureLine], imageBlock(shot)])
        }
        do {
            let raw = try await ScreenCapture.captureDisplay()
            let picture = ScreenCapture.downscale(raw.image, maxLongEdge: config.maxImageLongEdge)
            guard let shot = ScreenCapture.encode(picture) else {
                return .text("Could not encode the screenshot.", isError: true)
            }
            if generation == captureGeneration { lastCapture = (Date(), ctx) }
            onCaptured?(CaptureMoment(image: picture, screen: raw.screen))
            held?.keep(picture: picture)
            addSeen(picture: picture, on: seenOn, ctx: ctx)
            Log.info("look_at_screen: \(shot.width)x\(shot.height) \(shot.sizeKB)KB")
            return .blocks([imageBlock(shot)])
        } catch { return .text(error.localizedDescription, isError: true) }
    }

    /// The read_screen tool: while the answer holds the screen, the window in front when they asked (`FrozenScreen.read`);
    /// else the window in front now.
    private func readScreen(held: FrozenScreen?, seenOn: UUID?, ctx: ScreenContext?) async -> ToolResult {
        guard let held else {
            let result = await ScreenText.readFrontmost()
            if !result.isError, let text = result.content as? String { addSeen(pageText: text, on: seenOn, ctx: ctx) }
            return result
        }
        let (result, kept) = await held.read(now: watcher.sample()) { await ScreenText.readFrontmost() }
        if let kept { addSeen(pageText: kept, on: seenOn, ctx: ctx) }
        return result
    }

    /// Whether an answer now could take the mouse and keyboard on the person's own screen: control on, in the
    /// foreground lane. Such an answer has to see what its actions did, so it doesn't hold the screen.
    private var controlsForeground: Bool {
        config.allowControl && desktop != nil && !watching && cardConversation?.card == nil && !backgroundControl
    }

    private func setSeen(_ seen: SeenScreen, on id: UUID?) {
        guard let id, let i = transcript.firstIndex(where: { $0.id == id }) else { return }
        transcript[i].seen = seen
    }

    /// Adds what a look during the answer showed Claude to the question's chip, starting one if it has none.
    private func addSeen(picture: CGImage? = nil, pageText: String? = nil, on id: UUID?, ctx: ScreenContext?) {
        guard let id, let i = transcript.firstIndex(where: { $0.id == id }) else { return }
        var seen = transcript[i].seen ?? SeenScreen(kind: .screen, at: Date(), place: SeenScreen.place(ctx))
        if let picture, !seen.pictures.contains(where: { $0 === picture }) { seen.pictures.append(picture) }
        if let pageText { seen.pageText = pageText }
        transcript[i].seen = seen
    }

    private func needsFreshCapture(for ctx: ScreenContext?) -> Bool {
        guard config.screenshotReuseSeconds > 0, let last = lastCapture else { return true }
        if Date().timeIntervalSince(last.at) > config.screenshotReuseSeconds { return true }
        if let a = last.scene, let b = ctx { return !a.sameScene(as: b) }
        return true
    }

    private func imageBlock(_ shot: Screenshot) -> [String: Any] {
        ["type": "image", "source": ["type": "base64", "media_type": shot.mediaType, "data": shot.data.base64EncodedString()]]
    }

    func packsSection(_ ctx: ScreenContext?, notes: Bool = true) -> String {
        PackContextProvider.context(for: ctx, registry: registry, docsLimit: config.docsStuffLimitChars,
                                    includeNotes: notes).promptSection
    }

    /// Re-create the API client after settings change.
    func reconfigure(_ newConfig: Config) {
        // Keep the visible conversation while dropping provider-specific tools and image state.
        if newConfig.connectionMode != config.connectionMode {
            captureGeneration += 1
            execution.conversation.retainTextForProviderChange()
            lastCapture = nil
        }
        config = newConfig
        backgroundControl = newConfig.controlInBackground
        client = ConversationBackend.make(config: newConfig)
        objectWillChange.send()
    }

    /// Set by the app; nil in headless runs without control.
    var control: ComputerController? { desktop?.control }

    /// `allowsControl: false` keeps the mouse and keyboard out of a request that only reads and explains.
    /// `held` is the screen as it was when the person asked: the answer's looks use it unless the answer controls the
    /// foreground. `seenOn` is the question whose chip shows what Claude was shown (the typed question by default).
    func send(content: [[String: Any]], ctx: ScreenContext?, title: String, messageID: UUID? = nil, allowsControl: Bool = true,
              held: FrozenScreen? = nil, seenOn: UUID? = nil) async {
        guard let client else {
            transcript.append(ChatMessage(role: .error, text: ConversationBackend.setupMessage(config: config)))
            finishRequest()
            return
        }
        chatBusy = true
        suggestions = []
        status = "Thinking…"
        let discussingCard = cardConversation?.card != nil
        let controlAllowed = allowsControl && config.allowControl && desktop != nil && !watching && !discussingCard
        let background = controlAllowed && backgroundControl
        let id = UUID()
        requestMessageID = messageID
        defer { requestMessageID = nil }
        let generation = captureGeneration
        var task: TaskExecution?
        do {
            var turnContent = content
            if discussingCard, let cardConversation {
                turnContent.append(["type": "text", "text": cardConversation.context])
            }
            let plan = TaskPlan(content: turnContent, prepareImages: true, prepare: { [self] in
                if discussingCard, let cardConversation {
                    return PreparedExecution(system: Self.cardConversationSystem,
                        router: try ToolRouter(routes: cardConversation.routes()))
                }
                let holding = controlAllowed && !background ? nil : held
                let chip = seenOn ?? messageID
                let capture: () async -> ToolResult = { [weak self] in
                    guard let self else { return .text("unavailable", isError: true) }
                    return await self.lookAtScreen(ctx, generation: generation, held: holding, seenOn: chip)
                }
                let read: () async -> ToolResult = { [weak self] in
                    guard let self else { return .text("unavailable", isError: true) }
                    return await self.readScreen(held: holding, seenOn: chip, ctx: ctx)
                }
                let sourceRoutes = (sourceConversation?.routes() ?? []) + (watchList?.routes() ?? [])
                if controlAllowed, let desktop {
                    return try await desktop.prepare(id: id, registry: registry, context: ctx, background: background,
                                                     title: title, additionalRoutes: sourceRoutes, lookAtScreen: capture, readScreen: read)
                }
                let router = try ExecutionTools.make(registry: registry, context: ctx, control: nil,
                                                     background: false, additionalRoutes: sourceRoutes, lookAtScreen: capture, readScreen: read)
                return PreparedExecution(system: Prompt.system, router: router)
            })
            let onStatus: (String) -> Void = { [weak self] value in
                guard let self, !self.backgroundTaskRunning else { return }
                self.status = value
            }
            let result: ExecutionResult
            diagnoseChat(.executionStarted)
            if let desktop {
                let handle = try desktop.executor.begin(
                    TaskRequest(id: id, title: title, presentation: .conversation), coordinator: execution,
                    onPromoted: { [weak self] in self?.backgroundTaskDidBegin() })
                task = handle
                result = try await handle.run(plan, client: client, onStatus: onStatus)
            } else {
                // Headless conversations have no desktop or task panel lifetime to manage.
                result = try await execution.run(client: client, content: plan.content,
                    prepareImages: plan.prepareImages, prepare: plan.prepare, onStatus: onStatus)
            }
            diagnoseChat(.executionReturned)
            completeExecution(result, task: task)
        } catch {
            let wasTask = task?.isPresented == true
            task?.finish(outcome: .failed, text: error.localizedDescription, elapsed: 0)
            if !wasTask {
                transcript.append(ChatMessage(role: .error, text: error.localizedDescription))
            }
            status = ""
        }
        finishRequest()
    }

    /// Chat interprets its response; the executor owns any promoted task's result.
    func completeExecution(_ result: ExecutionResult, task: TaskExecution?) {
        let wasTask = task?.isPresented == true
        if let task {
            let outcome: BackgroundTaskOutcome
            let text: String
            switch result.outcome {
            case .reply(let reply):
                outcome = task.receipt?.stopped == true ? .stopped : .completed
                text = Self.splitSuggestions(reply.text).0
            case .cancelled: outcome = .stopped; text = "Stopped."
            case .failed(let error): outcome = .failed; text = error.localizedDescription
            }
            task.finish(outcome: outcome, text: text, elapsed: result.elapsed)
        }
        presentExecutionResult(result, wasTask: wasTask)
    }

    /// Task output stays outside the chat even if its conversation was cleared mid-run.
    func presentExecutionResult(_ result: ExecutionResult, wasTask: Bool = false) {
        diagnoseChat(.presentationStarted)
        defer { diagnoseChat(.transcriptUpdated) }
        if wasTask {
            status = ""
            suggestions = []
            return
        }
        guard result.accepted else { status = ""; return }
        switch result.outcome {
        case .reply(let reply):
            let (text, tabs) = Self.splitSuggestions(reply.text)
            transcript.append(ChatMessage(role: .assistant, text: text))
            suggestions = reviewTabs(tabs) + takeSourceTabs(excluding: tabs)
            let secs = String(format: "%.1f", result.elapsed)
            status = "\(reply.inputTokens) in · \(reply.outputTokens) out · \(reply.toolCalls) tool call\(reply.toolCalls == 1 ? "" : "s") · \(secs)s"
            Log.info("reply: \(reply.outputTokens) out, \(reply.inputTokens) in (cache read \(reply.cacheRead)), \(reply.toolCalls) tool calls, \(secs)s")
        case .cancelled:
            transcript.append(ChatMessage(role: .assistant, text: "Stopped."))
            suggestions = reviewTabs([]) + takeSourceTabs(excluding: [])
            status = ""
        case .failed(let error):
            transcript.append(ChatMessage(role: .error, text: error.localizedDescription))
            suggestions = reviewTabs([]) + takeSourceTabs(excluding: [])
            status = ""
            Log.info("error: \(error.localizedDescription)")
        }
    }

    // MARK: saved jobs

    /// A saved-job tool changed something: a factual line on the pad, and a way to see it in Jobs.
    private func sourceChanged(_ receipt: String) {
        transcript.append(ChatMessage(role: .receipt, text: receipt))
        if !pendingSourceTabs.contains(Self.openJobsTab) { pendingSourceTabs.append(Self.openJobsTab) }
    }

    /// A watch-list tool changed something: a factual line on the pad, and a way to see it in Jobs.
    private func watchListChanged(_ receipt: String) {
        transcript.append(ChatMessage(role: .receipt, text: receipt))
        if !pendingSourceTabs.contains(Self.openJobsTab) { pendingSourceTabs.append(Self.openJobsTab) }
    }

    /// The chat offered to run a job: a tab the person can tap. Nothing runs until they do.
    private func offerSourceRun(id: UUID, name: String) {
        let tab = "Run “\(Self.reviewExcerpt(name, limit: 40))” now"
        offeredRuns[tab] = id
        if !pendingSourceTabs.contains(tab) { pendingSourceTabs.append(tab) }
    }

    /// A new job needs connecting: secrets go in Settings, never through the chat.
    private func offerConnect() {
        if !pendingSourceTabs.contains(Self.openSettingsTab) { pendingSourceTabs.append(Self.openSettingsTab) }
    }

    /// The tabs saved-job tools asked for during this turn, handed out once.
    private func takeSourceTabs(excluding shown: [String]) -> [String] {
        defer { pendingSourceTabs = [] }
        return pendingSourceTabs.filter { !shown.contains($0) }
    }

    private func finishRequest() {
        chatBusy = false
        diagnoseChat(.requestFinished)
    }

    /// Record transition metadata without retaining the conversation or source contents.
    private func diagnoseChat(_ phase: MainThreadDiagnostics.Phase) {
        let characters = transcript.reduce(0) { $0 + $1.text.utf8.count }
        MainThreadDiagnostics.shared.mark(phase, itemCount: transcript.count, characterCount: characters)
        let longest = transcript.map { $0.text.utf8.count }.max() ?? 0
        let lines = transcript.reduce(0) { $0 + $1.text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 } }
        Log.info("[chat] turn=\(diagnosticTurnID?.uuidString ?? "none") phase=\(phase.rawValue) messages=\(transcript.count) bytes=\(characters) longest=\(longest) lines=\(lines) notes=\(Note.group(transcript).count) tabs=\(suggestions.count) busy=\(chatBusy) card=\(cardConversation?.card != nil) size=\(Int(shell.cardSize.width))x\(Int(shell.cardSize.height))")
    }

    private static var cardConversationSystem: String { CardConversation.system }

    static func splitSuggestions(_ text: String) -> (String, [String]) {
        var lines = text.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        guard let last = lines.last?.trimmingCharacters(in: .whitespaces),
              let range = last.range(of: #"^\**Suggestions\**:\s*"#, options: [.regularExpression, .caseInsensitive]) else { return (text, []) }
        let items = last[range.upperBound...].split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*_")) }
            .filter { !$0.isEmpty }
        lines.removeLast()
        return (lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), Array(items.prefix(3)))
    }
}
