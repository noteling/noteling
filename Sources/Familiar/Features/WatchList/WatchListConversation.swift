import Foundation
import FamiliarContracts
import FamiliarRuntime

/// The watch list in general chat: tools to watch items, list the watches, check one now, change one or stop it.
/// Changes go through the same store as the Watches page in Morning Files, so they show there at once. Checks the chat starts are
/// waited for (at most `waitLimit`) and their results returned, so the chat shows what each item looks like now.
@MainActor
final class WatchListConversation {
    let store: WatchListStore
    let runner: WatchListRunner
    /// The checks the tools folder offers: each pack's `watch:` script.
    var checks: () -> [WatchListCheckChoice] = { [] }
    /// Asks macOS for permission to notify; called when a watch is created.
    var askForNotifications: () -> Void = {}
    /// "on", or why notifications are off and how to turn them on.
    var notificationLine: () async -> String = { "on" }
    /// A watch was created, changed or stopped: a one-line receipt for the pad.
    var onChange: ((String) -> Void)?
    /// A check needs secrets in Settings. The chat never takes a password itself.
    var onOfferConnect: ((String) -> Void)?
    /// Whether a watch's check takes all its items in one call (a list check), so it can hold up to 200 of them.
    var takesList: (WatchListWatch) async -> Bool = { _ in false }
    /// Checks still running after this carry on; the Watches page shows them when they finish.
    var waitLimit: Double = 90
    var now: () -> Date = Date.init

    static let noChecks = "No tool can check items yet. Link your team's tools in Settings."

    init(store: WatchListStore, runner: WatchListRunner) {
        self.store = store
        self.runner = runner
    }

    // MARK: tools

    func routes() -> [ToolRoute] {
        let watch: [String: Any] = ["type": "string", "description": "The watch's name, id or path, as list_watches gives them; a team watch's path may be its last part, like \"fashion\"."]
        let items: (String) -> [String: Any] = { ["type": "array", "items": ["type": "string"], "description": $0] }
        let minutes: [String: Any] = ["type": "integer", "description": "How often to check, in minutes: 5 to 240. Default 15."]
        let expect: [String: Any] = ["type": "object", "description": "What counts as right for every item, field → value, e.g. {\"price\": 12.33, \"badges\": \"Deal\", \"in_stock\": true}. One value for a list field means the list should include it."]
        return [
            route("watch_items", Self.watchItemsDescription, [
                "items": items("The items exactly as the person gave them: ids or page addresses. Up to 50, or 200 when the check takes a whole list at once."),
                "name": ["type": "string", "description": "A short name for the watch, e.g. \"Sale items\"."],
                "every_minutes": minutes,
                "fields": items("Things the check reports to keep an eye on as its first check finds them, e.g. [\"price\", \"badges\"]. Without fields or expect, everything it reports."),
                "expect": expect,
                "args": ["type": "object", "description": "Extra details the check takes, as the person gave them, e.g. {\"zip\": \"10001\"}."],
                "check": ["type": "string", "description": "Which check to use, when there are several. Default: the only one there is."],
            ], required: ["items"]) { [unowned self] input in try await self.create(input) },
            route("list_watches", "List the watches: the person's own, and their team's from the team's tools with whether each is on for them. For each: its name, id or path, how often it checks and when it last did, when it starts or ends, and each item's status: as expected, not as expected (and how), or couldn't check (and why). A team watch that is off shows only what it is.",
                  [:], required: []) { [unowned self] _ in await self.list() },
            route("check_watch_now", "Check a watch's items now instead of waiting for its schedule, and return what each shows. Without watch, check every watch that is on. Use it when the person asks to check now.",
                  ["watch": watch], required: []) { [unowned self] input in try await self.checkNow(input) },
            route("change_watch", "Change one of the person's own watches: add or remove items, change how often it checks, change what counts as right for every item (expect, compared at once with what each item's last check showed), or pause and resume it. New items are checked now. A team watch can only be turned on or off.",
                  ["watch": watch, "add_items": items("Items to add: ids or page addresses."),
                   "remove_items": items("Items to stop watching: as given, or their titles."), "every_minutes": minutes,
                   "expect": ["type": "object", "description": "What counts as right from now on, field → value, for every item."],
                   "paused": ["type": "boolean", "description": "true pauses the watch; false resumes it."]],
                  required: ["watch"]) { [unowned self] input in try await self.change(input) },
            route("turn_on_watch", "Turn on one of the team's watches for the person, so it is checked on its schedule and they are told when an item isn't as it should be. It is checked right away, and the result is returned. (One of their own watches is resumed.)",
                  ["watch": watch], required: ["watch"]) { [unowned self] input in try await self.turn(input, on: true) },
            route("turn_off_watch", "Turn off one of the team's watches for the person: it is no longer checked and doesn't notify; what it found stays. (One of their own watches is paused.)",
                  ["watch": watch], required: ["watch"]) { [unowned self] input in try await self.turn(input, on: false) },
            route("stop_watch", "Stop watching: one of the person's own watches is removed with all its items (its folder goes to the Trash), so it no longer checks or notifies. A team watch is turned off instead.",
                  ["watch": watch], required: ["watch"]) { [unowned self] input in try self.stop(input) },
        ]
    }

    static let watchItemsDescription = "Watch items for the person and tell them when one is not as it should be right now. Use it when they ask to watch, keep an eye on or monitor items (product ids or page addresses); it is not Watch Me, which records them doing a task. Their team's check for the site checks each item on a schedule, and a Mac notification tells them when an item stops being as expected or changes again, when it is back, or when it can't be checked twice in a row. This creates the watch, checks every item once now, and returns per item its title, status, what it shows now and what counts as right. What counts as right: when expect is given, or the check says so itself, only that (plus fields, as the first check finds them); otherwise everything the first check shows, or only fields. Then confirm in one or two lines what you are watching, what counts as right, and how often, and that they can change what counts as right (expect here, or change_watch later). If notifications are off, say so."

    /// Each tool first takes in what changed in the watches folders, so it answers from the files as they are.
    private func route(_ name: String, _ description: String, _ properties: [String: Any], required: [String],
                       action: @escaping ([String: Any]) async throws -> String) -> ToolRoute {
        ToolRoute(match: .tool(name: name), definition: ["name": name, "description": description,
            "input_schema": ["type": "object", "additionalProperties": false, "properties": properties, "required": required]]) { [weak self] _, input, _ in
            self?.runner.refresh()
            do { return .text(try await action(input)) }
            catch { return .text(error.localizedDescription, isError: true) }
        }
    }

    // MARK: actions

    private func create(_ input: [String: Any]) async throws -> String {
        let keys = try Self.items(input["items"], required: true)
        guard store.watches.filter({ !$0.isTeam }).count < WatchListStore.watchLimit else {
            throw WatchListError("You're already watching \(WatchListStore.watchLimit) lists, the most Noteling keeps. Stop one first.")
        }
        let choice = try resolveCheck(input["check"])
        try Self.fit(keys.count, in: choice.itemLimit)
        let (minutes, minutesNote) = try Self.minutes(input["every_minutes"])
        var args = try Self.values(input["args"], "args")
        args.removeValue(forKey: "item")
        args.removeValue(forKey: "items")
        try Self.checkArguments(args, for: choice)
        let name = uniqueName(Self.text(input["name"]) ?? Self.defaultName(keys))
        let watch = WatchListWatch(name: name, check: choice.id, items: keys.map { WatchListItem(key: $0) }, args: args,
                                   fields: try Self.fields(input["fields"]), expect: try Self.values(input["expect"], "expect"),
                                   everyMinutes: minutes, createdAt: now())
        try store.add(watch)
        askForNotifications()
        let finished = await checkWaiting([watch.id])
        onChange?("Watching “\(Self.clip(name, 80))”: \(keys.count) item\(keys.count == 1 ? "" : "s"), \(watch.everyWords).")
        var result = store.watch(id: watch.id).map(summary) ?? [:]
        if let minutesNote { result["note"] = minutesNote }
        if !finished { result["still_checking"] = Self.stillChecking }
        if !choice.missingSecrets.isEmpty {
            result["setup"] = "The check needs \(choice.missingSecrets.joined(separator: " and ")) in Settings before it can check anything: point to the Open Settings button, and never ask for a password in chat."
            onOfferConnect?(choice.pack)
        }
        result["notifications"] = await notificationLine()
        return Self.json(result)
    }

    private func list() async -> String {
        let own = store.watches.filter { !$0.isTeam }, team = store.watches.filter(\.isTeam)
        let unreadable = store.unreadable.keys.sorted().map { ["folder": $0, "problem": store.unreadable[$0]!] }
            + store.teamUnreadable.keys.sorted().map { ["folder": $0, "from": "your team's tools", "problem": store.teamUnreadable[$0]!] }
        guard !own.isEmpty || !team.isEmpty || !unreadable.isEmpty else {
            return "Nothing is being watched." + (store.notice.map { " " + $0 } ?? "")
        }
        var result: [String: Any] = ["watches": own.map(summary)]
        if !team.isEmpty { result["team_watches"] = team.map { $0.on ? summary($0) : brief($0) } }
        if !unreadable.isEmpty { result["folders_not_watched"] = unreadable }
        if let notice = store.notice { result["notice"] = notice }
        result["notifications"] = await notificationLine()
        return Self.json(result)
    }

    private func checkNow(_ input: [String: Any]) async throws -> String {
        let chosen: [WatchListWatch]
        if Self.text(input["watch"]) == nil {
            chosen = store.watches.filter { $0.checking(at: now()) || (!$0.isTeam && $0.paused && !$0.notStarted(at: now()) && !$0.ended(at: now())) }
            guard !chosen.isEmpty else {
                throw WatchListError(store.watches.isEmpty ? "Nothing is being watched." : "No watch is on and checking right now.")
            }
        } else {
            let watch = try resolve(input["watch"])
            if watch.isTeam, !watch.on { throw WatchListError("“\(Self.clip(watch.name, 80))” is off. Turn it on to check it.") }
            if let reason = notChecking(watch) { throw WatchListError(reason) }
            chosen = [watch]
        }
        let finished = await checkWaiting(chosen.map(\.id))
        var result: [String: Any] = ["watches": chosen.compactMap { store.watch(id: $0.id) }.map(summary)]
        if !finished { result["still_checking"] = Self.stillChecking }
        return Self.json(result)
    }

    /// Before its start or after its end, a watch isn't checked at all.
    private func notChecking(_ watch: WatchListWatch) -> String? {
        let name = "“\(Self.clip(watch.name, 80))”"
        if watch.notStarted(at: now()), let starts = watch.starts { return "\(name) starts \(starts.words); nothing is checked before then." }
        if watch.ended(at: now()), let ends = watch.ends { return "\(name) ended \(ends.words), so it is no longer checked." }
        return nil
    }

    private func change(_ input: [String: Any]) async throws -> String {
        let watch = try resolve(input["watch"])
        guard !watch.isTeam else { throw WatchListError(WatchListStore.teamReadOnly + " You can turn it on or off.") }
        let adding = try Self.items(input["add_items"], required: false)
        let removing = try Self.items(input["remove_items"], required: false)
        let minutes = try input["every_minutes"].map { try Self.minutes($0) }
        let expect = try Self.values(input["expect"], "expect")
        let paused = try input["paused"].map { value -> Bool in
            if let flag = NoteCheckResult.boolean(value) { return flag }
            if let text = value as? String, let flag = WatchListRules.flag(in: text) { return flag }
            throw WatchListError("paused must be true or false.")
        }
        guard !adding.isEmpty || !removing.isEmpty || minutes != nil || !expect.isEmpty || paused != nil else {
            throw WatchListError("Nothing to change: give items to add or remove, how often, what counts as right, or paused.")
        }
        let limit = adding.isEmpty ? WatchListStore.itemLimit
            : await takesList(watch) ? WatchListStore.itemLimit : WatchListStore.itemLimitEach
        var changes: [String] = [], added: [String] = [], notFound: [String] = []
        try store.change(watch.id) { w in
            for key in removing {
                guard let index = w.items.firstIndex(where: { Self.matches($0, key) }) else { notFound.append(key); continue }
                if w.items[index].row != nil, let file = w.file {
                    throw WatchListError("“\(Self.clip(w.items[index].label, 80))” comes from \(file.name). Take it out of that file to stop watching it.")
                }
                w.items.remove(at: index)
            }
            if removing.count > notFound.count { changes.append("removed \(Self.count(removing.count - notFound.count))") }
            for key in adding where !w.items.contains(where: { $0.key == key }) {
                w.items.append(WatchListItem(key: key))
                added.append(key)
            }
            if !added.isEmpty { changes.append("added \(Self.count(added.count))") }
            guard !w.items.isEmpty else { throw WatchListError("That would leave nothing to watch. To stop watching it, use stop_watch.") }
            if !added.isEmpty { try Self.fit(w.items.count, in: limit) }
            if let every = minutes?.0, every != w.everyMinutes { w.everyMinutes = every; changes.append("checks \(w.everyWords)") }
            if !expect.isEmpty {
                for (field, value) in expect { w.expect[field] = value }
                // The chat shows the result, so it is what the person was told.
                w.reexpect(quiet: true)
                changes.append("what counts as right")
            }
            if let paused, paused != w.paused { w.paused = paused; changes.append(paused ? "paused" : "resumed") }
        }
        var finished = true
        if !added.isEmpty { finished = await checkWaiting([watch.id], items: Set(added)) }
        let name = Self.clip(watch.name, 80)
        if !changes.isEmpty { onChange?("Changed “\(name)”: \(changes.joined(separator: ", ")).") }
        var result = store.watch(id: watch.id).map(summary) ?? [:]
        result["changed"] = changes.isEmpty ? "nothing: it was already like that" : changes.joined(separator: ", ")
        if !notFound.isEmpty { result["not_in_this_watch"] = notFound }
        if let note = minutes?.1 { result["note"] = note }
        if !finished { result["still_checking"] = Self.stillChecking }
        return Self.json(result)
    }

    /// A team watch is turned on or off for the person; one of their own is resumed or paused.
    private func turn(_ input: [String: Any], on: Bool) async throws -> String {
        let watch = try resolve(input["watch"])
        let name = "“\(Self.clip(watch.name, 80))”"
        guard watch.isTeam else {
            guard watch.paused == on else { return "\(name) is \(on ? "already checking" : "already paused")." }
            try store.change(watch.id) { $0.paused = !on }
            onChange?(on ? "Resumed \(name)." : "Paused \(name).")
            return on ? "Resumed \(name): it checks \(watch.everyWords) again." : "Paused \(name): it doesn't check or notify until it's resumed."
        }
        guard watch.on != on else { return "\(name) is already \(on ? "on" : "off")." }
        let run = try runner.turn(watch.id, on: on)
        if on { askForNotifications() }
        onChange?(on ? "Turned on \(name) from your team's tools." : "Turned off \(name). It no longer checks or notifies.")
        guard on else { return "Turned off \(name). It no longer checks or notifies; what it found stays." }
        var finished = true
        if let run { finished = await WatchListRunner.wait(for: run, atMost: waitLimit) }
        var result = store.watch(id: watch.id).map(summary) ?? [:]
        result["turned_on"] = true
        if let reason = store.watch(id: watch.id).flatMap(notChecking) { result["note"] = reason }
        if !finished { result["still_checking"] = Self.stillChecking }
        result["notifications"] = await notificationLine()
        return Self.json(result)
    }

    private func stop(_ input: [String: Any]) throws -> String {
        let watch = try resolve(input["watch"])
        let name = "“\(Self.clip(watch.name, 80))”"
        if watch.isTeam {
            if watch.on { try runner.turn(watch.id, on: false) }
            onChange?("Turned off \(name). It comes from your team's tools, so it stays there for others.")
            return "\(name) comes from your team's tools, so it was turned off for the person rather than removed. It no longer checks or notifies, and can be turned on again."
        }
        runner.cancel(watch.id)
        try store.remove(watch.id)
        let receipt = "Stopped watching \(name). Its folder is in the Trash, if you want it back."
        onChange?(receipt)
        return receipt + " It no longer checks or notifies."
    }

    /// Checks watches (or some items of one) and waits for them, at most `waitLimit`. What comes back while the chat
    /// waits is what the chat shows, so it only becomes what the person was told; what lands later tells them as usual.
    private func checkWaiting(_ ids: [UUID], items: Set<String>? = nil) async -> Bool {
        if items != nil, let id = ids.first, let running = runner.current(id) {
            // A run in progress started before these items were added: they are checked once it ends.
            _ = await WatchListRunner.wait(for: running, atMost: waitLimit)
        }
        let quiet = WatchListQuiet()
        let runs = ids.compactMap { runner.run($0, items: items, quiet: quiet) }
        let all = Task { for run in runs { await run.value } }
        let finished = await WatchListRunner.wait(for: all, atMost: waitLimit)
        quiet.on = false
        return finished
    }

    // MARK: lookups

    private func resolveCheck(_ raw: Any?) throws -> WatchListCheckChoice {
        let available = checks()
        let names = available.map { "\($0.id) (\($0.pack))" }.joined(separator: ", ")
        if let asked = Self.text(raw) {
            let wanted = available.first { $0.id == asked }
                ?? available.first { $0.packDir.caseInsensitiveCompare(asked) == .orderedSame || $0.pack.caseInsensitiveCompare(asked) == .orderedSame }
            if let wanted { return wanted }
            throw WatchListError(available.isEmpty ? Self.noChecks : "There's no check called “\(Self.clip(asked, 80))”. Use one of: \(names).")
        }
        guard let only = available.first else { throw WatchListError(Self.noChecks) }
        guard available.count == 1 else { throw WatchListError("Several tools can check items: \(names). Say which one with check.") }
        return only
    }

    /// By id, or by name; without one, the only watch there is.
    /// By id (a team watch's is its path), by name, by path, or by the end of a path that only one watch's has
    /// ("fashion" for holiday/oct/fashion).
    private func resolve(_ raw: Any?) throws -> WatchListWatch {
        let names = store.watches.map { "“\(Self.clip($0.name, 60))”" + ($0.isTeam ? " (\($0.path))" : "") }.joined(separator: ", ")
        guard let key = Self.text(raw) else {
            throw WatchListError(store.watches.isEmpty ? "Nothing is being watched." : "Say which watch: \(names).")
        }
        if let id = UUID(uuidString: key), let watch = store.watch(id: id) { return watch }
        let path = key.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        for matching in [
            { (w: WatchListWatch) in w.path.lowercased() == path },
            { (w: WatchListWatch) in w.name.caseInsensitiveCompare(key) == .orderedSame },
            { (w: WatchListWatch) in !path.isEmpty && w.path.lowercased().hasSuffix("/" + path) },
        ] {
            let found = store.watches.filter(matching)
            if found.count == 1 { return found[0] }
            if found.count > 1 {
                throw WatchListError("Several watches go by “\(Self.clip(key, 80))”: "
                    + found.map { "“\(Self.clip($0.name, 60))” (\($0.isTeam ? $0.path : $0.id.uuidString))" }.joined(separator: ", ") + ". Say which.")
            }
        }
        throw WatchListError(store.watches.isEmpty ? "Nothing is being watched."
            : "No watch is called “\(Self.clip(key, 80))”. Watches: \(names).")
    }

    private static func matches(_ item: WatchListItem, _ key: String) -> Bool {
        item.key == key || item.key.caseInsensitiveCompare(key) == .orderedSame || item.label.caseInsensitiveCompare(key) == .orderedSame
    }

    private func uniqueName(_ base: String) -> String {
        let name = String(base.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let taken = Set(store.watches.map { $0.name.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        var number = 2
        while taken.contains("\(name) \(number)".lowercased()) { number += 1 }
        return "\(name) \(number)"
    }

    // MARK: what the chat reads

    /// Items file columns that name nothing any checked item's check reports.
    static func unreportedColumns(_ watch: WatchListWatch) -> [String] {
        let checked = watch.items.filter { $0.status?.isVerdict == true }
        guard let file = watch.file, !checked.isEmpty else { return [] }
        let reported = Set(checked.flatMap { $0.state.map { Array($0.keys) } ?? [] })
        return file.columns.filter { !$0.isEmpty && WatchListRules.field(for: $0, in: reported) == nil }
    }

    static let stillChecking = "Some items are still being checked. The Watches page in Morning Files shows them when they are done, and a notification comes only if one is not as expected later."

    /// A team watch that is off, as the chat lists it: what it is, and that it's off.
    private func brief(_ watch: WatchListWatch) -> [String: Any] {
        var result: [String: Any] = ["watch": watch.name, "id": watch.path, "from": "your team's tools", "on": false,
                                     "every_minutes": watch.everyMinutes, "items": watch.items.count]
        result.merge(window(watch)) { _, new in new }
        if let problem = store.problems[watch.id] { result["problem"] = problem }
        return result
    }

    /// When it starts and ends, if it does, and whether that keeps it from checking now.
    private func window(_ watch: WatchListWatch) -> [String: Any] {
        var result: [String: Any] = [:]
        if let starts = watch.starts { result["starts"] = starts.words }
        if let ends = watch.ends { result["ends"] = ends.words }
        if let reason = notChecking(watch) { result["not_checking"] = reason }
        return result
    }

    /// A watch as the chat reads it, compact: per item its title, status, what it shows now, what counts as right and
    /// what the check said in its own words; where it comes from, whether its files can be read, and when it runs.
    private func summary(_ watch: WatchListWatch) -> [String: Any] {
        var result: [String: Any] = ["watch": watch.name, "id": watch.isTeam ? watch.path : watch.id.uuidString, "every_minutes": watch.everyMinutes,
                                     "check": store.ownCheck(for: watch.id) == nil ? watch.check : "its own check.py"]
        if watch.isTeam {
            result["from"] = "your team's tools"
            result["on"] = watch.on
        } else {
            result["path"] = watch.path
            if let folder = store.folder(for: watch.id) { result["folder"] = (folder.path as NSString).abbreviatingWithTildeInPath }
        }
        result.merge(window(watch)) { _, new in new }
        if let problem = store.problems[watch.id] { result["problem"] = problem + " Until it's fixed, the watch keeps what it had." }
        if let file = watch.file {
            result["items_file"] = file.name
            if !file.skipped.isEmpty { result["rows_left_out"] = file.skipped }
            let columns = Self.unreportedColumns(watch)
            if !columns.isEmpty {
                result["columns_not_reported"] = columns
                result["columns_note"] = columns.map { "column \($0) isn't something the check reports" }.joined(separator: "; ") + "."
            }
        }
        if let note = watch.fileNote { result["files_note"] = note }
        if watch.paused { result["paused"] = true }
        if let fields = watch.fields {
            result["fields"] = fields
            let reported = Set(watch.items.flatMap { $0.state.map { Array($0.keys) } ?? [] })
            let counted = Set((fields + watch.expect.keys).compactMap { WatchListRules.field(for: $0, in: reported) })
            let other = reported.subtracting(counted)
            if !other.isEmpty { result["also_reported"] = other.sorted() }
            // A name the check doesn't use would never be watched: say so, rather than stay green.
            let checked = watch.items.filter { $0.status?.isVerdict == true }
            let missing = checked.isEmpty ? [] : fields.filter { field in
                checked.allSatisfy { WatchListRules.field(for: field, in: Set($0.state?.keys.map { $0 } ?? [])) == nil }
            }
            if !missing.isEmpty {
                result["fields_not_reported"] = missing
                result["fields_note"] = "The check doesn't report \(missing.joined(separator: " or ")), so \(missing.count == 1 ? "it isn't" : "they aren't") watched. "
                    + (reported.isEmpty ? "" : "It reports: \(reported.sorted().joined(separator: ", ")). ")
                    + "Tell the person, and to watch the right ones, stop this watch and create it again with those names in fields."
            }
        }
        if !watch.expect.isEmpty { result["expect"] = watch.expect.mapValues(Self.brief) }
        if !watch.args.isEmpty { result["args"] = watch.args.mapValues(\.json) }
        if let last = watch.lastRunAt { result["last_checked"] = Self.time(last, now: now()) }
        let checking = runner.checking.contains(watch.id)
        result["items"] = watch.items.map { item -> [String: Any] in
            var row: [String: Any] = ["item": item.key]
            if let title = item.title { row["title"] = title }
            if let url = item.url { row["url"] = url }
            switch item.status {
            case nil: row["status"] = checking ? "checking" : "not checked yet"
            case .asExpected?: row["status"] = "as expected"
            case .notAsExpected(let differences)?:
                row["status"] = "not as expected"
                row["differences"] = differences.map(\.words)
            case .couldNotCheck(let reason)?:
                row["status"] = "couldn't check"
                row["reason"] = reason
            }
            if let expected = item.expected {
                row["counts_as_right"] = expected.mapValues(Self.brief)
                if item.status?.isVerdict == true, let state = item.state {
                    row["now"] = state.filter { expected[$0.key] != nil }.mapValues(Self.brief)
                }
            } else {
                row["counts_as_right"] = watch.terms.explicit ? "only what is said: expect, its row in the items file, or the check's own"
                    : "what its first check that works shows" + (watch.fields == nil ? "" : " of the fields named")
            }
            let unreported = item.unreported(named: watch.fields)
            if !unreported.isEmpty { row["not_reported"] = unreported }
            // The check's own words: quote them as they are, never in other words.
            if !item.whyNow.isEmpty { row["why"] = item.whyNow }
            if let checked = item.checkedAt { row["checked"] = Self.time(checked, now: now()) }
            return row
        }
        return result
    }

    private static func brief(_ value: WatchListValue) -> Any {
        switch value {
        case .text(let text): return clip(text, 120)
        case .list(let list): return Array(list.prefix(10)).map { clip($0, 80) } + (list.count > 10 ? ["…and \(list.count - 10) more"] : [])
        default: return value.json
        }
    }

    static func time(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    static func json(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "\(object)" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: input

    static func text(_ raw: Any?) -> String? {
        let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// A watch holds up to 50 items, or 200 when its check takes them all at once.
    static func fit(_ count: Int, in limit: Int) throws {
        guard count > limit else { return }
        throw WatchListError(limit == WatchListStore.itemLimitEach
            ? "Its check takes one item at a time, so a watch holds up to \(limit) items. Split them into watches of \(limit)."
            : "A watch holds up to \(limit) items. Split them into two watches.")
    }

    /// Items as given: texts (or numbers, for ids), trimmed, each once.
    static func items(_ raw: Any?, required: Bool) throws -> [String] {
        let values: [Any]
        if raw == nil || raw is NSNull { values = [] }
        else if let list = raw as? [Any] { values = list }
        else if let one = raw as? String { values = [one] }
        else { throw WatchListError("Give the items as a list of ids or page addresses.") }
        var keys: [String] = []
        for value in values {
            var key: String
            if let text = value as? String { key = text }
            else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { key = number.stringValue }
            else { continue }
            key = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !keys.contains(key) else { continue }
            guard key.count <= 1_000 else { throw WatchListError("An item is too long: give its id or page address.") }
            keys.append(key)
        }
        if required, keys.isEmpty { throw WatchListError("Give the items to watch: their ids or page addresses.") }
        guard keys.count <= WatchListStore.itemLimit else {
            throw WatchListError("A watch holds up to \(WatchListStore.itemLimit) items. Split them into two watches.")
        }
        return keys
    }

    /// How often, held to 5–240 minutes, and a note for the chat when it had to be.
    static func minutes(_ raw: Any?) throws -> (Int, String?) {
        guard let raw, !(raw is NSNull) else { return (WatchListWatch.defaultMinutes, nil) }
        var value: Double?
        if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { value = number.doubleValue }
        else if let text = raw as? String { value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let value, value.isFinite else { throw WatchListError("every_minutes must be a number of minutes, 5 to 240.") }
        let asked = Int(min(max(value.rounded(), -1_000_000), 1_000_000))
        let minutes = WatchListWatch.clamp(asked)
        guard minutes != asked else { return (minutes, nil) }
        return (minutes, minutes > asked ? "It checks every 5 minutes, the most often it can."
                                         : "It checks every 240 minutes (4 hours), the least often it can.")
    }

    static func fields(_ raw: Any?) throws -> [String]? {
        guard let raw, !(raw is NSNull) else { return nil }
        guard let values = (raw as? [Any]) ?? (raw as? String).map({ [$0] }) else { throw WatchListError("fields must be a list of names.") }
        var fields: [String] = []
        for case let name as String in values {
            let field = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !field.isEmpty, !fields.contains(field) { fields.append(field) }
        }
        return fields.isEmpty ? nil : fields
    }

    /// An object of field → value (some models send it as JSON text).
    static func values(_ raw: Any?, _ name: String) throws -> [String: WatchListValue] {
        guard let raw, !(raw is NSNull) else { return [:] }
        var object = raw as? [String: Any]
        if object == nil, let text = raw as? String, let data = text.data(using: .utf8) {
            object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        guard let object else { throw WatchListError("\(name) must be an object of field → value.") }
        var values: [String: WatchListValue] = [:]
        for (key, value) in object {
            let field = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !field.isEmpty { values[field] = WatchListValue(json: value) }
        }
        guard values.count <= WatchListReading.fieldLimit else { throw WatchListError("\(name) has too many fields.") }
        return values
    }

    /// A check takes only the extra arguments it declares, and can't run without the ones it requires.
    static func checkArguments(_ args: [String: WatchListValue], for choice: WatchListCheckChoice) throws {
        func described(_ names: [String]) -> String {
            names.map { name in (choice.arguments[name] ?? "").isEmpty ? name : "\(name) (\(choice.arguments[name]!))" }.joined(separator: ", ")
        }
        let unknown = args.keys.filter { choice.arguments[$0] == nil }.sorted()
        if !unknown.isEmpty {
            throw WatchListError("The check doesn't take \(unknown.joined(separator: ", ")). "
                + (choice.arguments.isEmpty ? "It takes nothing besides the items." : "It takes: \(described(choice.arguments.keys.sorted()))."))
        }
        let missing = choice.required.filter { args[$0] == nil }
        if !missing.isEmpty {
            throw WatchListError("The check needs \(described(missing)) besides the items. Ask the person, then pass it in args.")
        }
    }

    static func defaultName(_ keys: [String]) -> String {
        guard let first = keys.first else { return "Watch" }
        var short = first
        if let url = URL(string: first), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            short = url.pathComponents.last { $0 != "/" } ?? url.host ?? first
        }
        short = String(short.prefix(40))
        return keys.count == 1 ? short : "\(short) and \(keys.count - 1) more"
    }

    private static func count(_ n: Int) -> String { "\(n) item\(n == 1 ? "" : "s")" }

    static func clip(_ text: String, _ limit: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}
