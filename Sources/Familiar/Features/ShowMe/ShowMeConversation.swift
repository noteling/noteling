import AppKit
import FamiliarContracts
import FamiliarRuntime

/// "Teach me" in chat: the teach_the_way tool, the paths the packs keep, and the one way taught on screen at a time.
/// The chat names a kept path (or one control on the screen now); this shows it, and keeps the pad's list of the steps
/// up to date as the person clicks through.
@MainActor
final class ShowMeConversation {
    let registry: ToolRegistry
    var hideFromScreenShare: () -> Bool = { false }
    /// A tour started: the chat puts its list of steps on the pad and says which message holds it.
    var onStart: ((ShowPath, TourProgress) -> UUID)?
    /// The tour moved on, ended or was stopped: the pad's list follows.
    var onProgress: ((UUID, TourProgress) -> Void)?
    private(set) var tour: ShowTour?
    /// Each list on the pad and the path it shows, for "Show again".
    private var shown: [UUID: (path: ShowPath, bundleID: String?)] = [:]

    init(registry: ToolRegistry) {
        self.registry = registry
    }

    static let toolName = "teach_the_way"

    /// The tool, in the team's word for teaching so the model ties it to the tab the person tapped.
    static func definition(_ words: IntentWords) -> [String: Any] { [
        "name": toolName,
        "description": """
        Teach the person the way on their own screen: everything else dims, a ring sits on the control to click, \
        Noteling's arrow points at it, and a card says what to do; when they click it, the next step lights up. They \
        do every click themselves, so next time they know the way; it never clicks for them, so it is never the way \
        to do a task for them. Use it when they want the ability (they chose "\(words.teach)", or asked where \
        something is or how to get to it). Give `path` for a way someone showed Noteling (listed under "Ways you can \
        teach"), or `steps` for one or two controls on the screen now, named exactly as the page names them. It \
        starts from the furthest step already on screen. Returns at once, saying which step is ringed; the tour \
        then runs on its own.
        """,
        "input_schema": [
            "type": "object", "additionalProperties": false,
            "properties": [
                "path": ["type": "string", "description": "A kept path as listed, pack/slug, e.g. \"waxwing/create-agent-token\""],
                "until": ["type": "integer", "description": "Stop after this step (1-based) when they only asked for part of the way"],
                "steps": ["type": "array", "maxItems": 4, "description": "Instead of a path: controls on the screen now, in order",
                          "items": ["type": "object", "additionalProperties": false, "required": ["label", "say"], "properties": [
                              "label": ["type": "string", "description": "The control's name exactly as shown on the page"],
                              "say": ["type": "string", "description": "What to tell them, under 8 words, e.g. \"Open Account and access\""],
                              "role": ["type": "string", "description": "Optional: button, link, tab, field, menu item"],
                          ]]],
                "title": ["type": "string", "description": "With steps: what they are looking for, a few words"],
            ],
        ] as [String: Any],
    ] }

    func routes(context ctx: ScreenContext?, words: IntentWords = .standard) -> [ToolRoute] {
        [ToolRoute(match: .tool(name: Self.toolName), definition: Self.definition(words)) { [weak self] _, input, _ in
            guard let self else { return .text("unavailable", isError: true) }
            do { return .text(try await self.show(input, bundleID: ctx?.bundleID)) }
            catch { return .text(error.localizedDescription, isError: true) }
        }]
    }

    /// The paths a pack keeps, as the chat names them: "pack/slug".
    func path(named name: String) -> ShowPath? {
        let parts = name.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return registry.packs.first { $0.dirName == parts[0] }?.paths[parts[1]]
    }

    func show(_ input: [String: Any], bundleID: String?) async throws -> String {
        var path: ShowPath
        if let name = input["path"] as? String, !name.isEmpty {
            guard let kept = self.path(named: name) else {
                throw ClaudeError(message: "No path “\(name)”. Use one listed under “Ways you can teach”, or steps for controls on the screen now.")
            }
            path = kept
        } else if let given = input["steps"] as? [[String: Any]], !given.isEmpty {
            let steps = given.compactMap { s -> ShowStep? in
                guard let label = (s["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else { return nil }
                let say = (s["say"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return ShowStep(say: say?.isEmpty == false ? say! : "Click “\(label)”", role: Self.axRole(s["role"] as? String), label: label)
            }
            guard !steps.isEmpty else { throw ClaudeError(message: "Each step needs the control's label as shown.") }
            path = ShowPath(title: (input["title"] as? String) ?? steps.last!.name, recorded: nil, steps: steps)
        } else {
            throw ClaudeError(message: "Give a path, or steps for controls on the screen now.")
        }
        if let until = (input["until"] as? NSNumber)?.intValue { path = path.slice(from: nil, until: until) }

        // Someone partway along starts where they are: the furthest step whose control shows now.
        let (from, readable) = await furthestOnScreen(path, bundleID: bundleID)
        start(from.map { path.slice(from: $0 + 1, until: nil) } ?? path, bundleID: bundleID)
        var reply = "Teaching “\(path.title)” now: \(path.steps.count) step\(path.steps.count == 1 ? "" : "s"), \(path.route)."
        if let from {
            reply += from == 0 ? " Step 1 is ringed on their screen." : " They are already partway: step \(from + 1) of \(path.steps.count) is ringed."
        } else if !readable {
            reply += " The page in front can't be read yet (it is still being prepared for Noteling), so whether step 1 is on it is"
                + " unknown; the ring appears as soon as it can be read. Don't send them anywhere: tell them to follow the ring."
        } else if let place = path.start, path.steps[0].url != nil || path.steps[0].app != nil {
            reply += " Step 1 (“\(path.steps[0].name)”) isn't on the screen in front: the way starts on \(place), which the tour"
                + " is opening for them now (a new tab in their browser, or the app brought forward); the ring appears when it"
                + " shows. Don't send them anywhere: tell them to follow the ring."
        } else {
            reply += " Step 1 (“\(path.steps[0].name)”) isn't on the screen in front yet. The card waits for it a few seconds,"
                + " then says it can't see it. Tell them where to start."
        }
        reply += " Reply in one short line: they are following the ring, so don't write out the steps."
        return reply
    }

    /// Starts showing `path` (stopping any other tour) and puts its list on the pad. Returns the list's message.
    @discardableResult
    func start(_ path: ShowPath, bundleID: String?) -> UUID? {
        tour?.stop()
        let tour = ShowTour(path: path, bundleID: bundleID, hideFromScreenShare: hideFromScreenShare())
        let message = onStart?(path, tour.progress)
        if let message { shown[message] = (path, bundleID) }
        tour.onProgress = { [weak self] progress in
            guard let self, let message else { return }
            self.onProgress?(message, progress)
        }
        tour.onEnd = { [weak self, weak tour] progress in
            guard let self else { return }
            if let message { self.onProgress?(message, progress) }
            if self.tour === tour { self.tour = nil }
        }
        self.tour = tour
        tour.start()
        return message
    }

    /// The pad's Stop on a running tour, and Show again on one that is over.
    func stop() { tour?.stop() }

    func again(_ message: UUID) {
        guard let shown = shown[message] else { return }
        start(shown.path, bundleID: shown.bundleID)
    }

    /// The pad was cleared: no list is left to show again.
    func clear() {
        tour?.stop()
        shown = [:]
    }

    /// The index of the last step whose control is on the page in front now (in view, or scrolled out of it), or nil
    /// when none is. A control the page hides, such as in a closed menu, isn't in its tree at all.
    private func furthestOnScreen(_ path: ShowPath, bundleID: String?) async -> (index: Int?, readable: Bool) {
        guard let (app, window) = ShowFinder.window(fallback: bundleID) else { return (nil, true) }
        let held = BrowserAccessibility.hold(app)
        defer { if held { BrowserAccessibility.release(app.processIdentifier) } }
        let target = Target(app: app, window: window)
        let steps = path.steps
        // A browser just told someone is listening builds its page tree in a moment, a few seconds at most: look again
        // until then. One already on answers the first time.
        var readable = true
        for attempt in 0..<(held ? 12 : 2) {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 400_000_000) }
            let (found, canRead) = await Task.detached(priority: .userInitiated) { () -> (Int?, Bool) in
                for index in steps.indices.reversed() {
                    guard let f = ShowFinder.findOnScreen(steps[index], app: target.app, window: target.window) else { continue }
                    // A later step proves the person is partway only as itself, on the page it was recorded on: the
                    // first page may well have a "Create" or "Next" of its own. The first step, by name alone, only on
                    // its own page too.
                    let sure = index == 0
                        ? f.how >= .kindAndName || (f.how > .partOfName && ShowFinder.onPage(steps[index], window: target.window))
                        : f.how >= .kindAndName && ShowFinder.samePlace(steps[index], app: target.app, window: target.window)
                    if sure { return (index, true) }
                }
                return (nil, ShowFinder.readable(app: target.app, window: target.window))
            }.value
            if let found { return (found, true) }
            readable = canRead
            if canRead, attempt >= 1 { break }   // read and not there: no point waiting
        }
        return (nil, readable)
    }

    private struct Target: @unchecked Sendable {
        let app: NSRunningApplication
        let window: AXUIElement
    }

    /// "button" → AXButton, so a step the chat names matches its kind; unknown words match any kind.
    nonisolated static func axRole(_ word: String?) -> String? {
        switch word?.lowercased().trimmingCharacters(in: .whitespaces) {
        case "button": return "AXButton"
        case "link": return "AXLink"
        case "tab": return "AXTab"
        case "field", "text field": return "AXTextField"
        case "menu item": return "AXMenuItem"
        case "checkbox": return "AXCheckBox"
        default: return nil
        }
    }
}
