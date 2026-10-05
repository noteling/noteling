import AppKit
import SwiftUI

/// What Morning Files needs to show the watches among the jobs: where they are kept, what checks them, whether
/// notifications are on, and what Why? on an item does (the chat explains it).
@MainActor
struct WatchListPanel {
    let store: WatchListStore
    let runner: WatchListRunner
    let notifier: WatchListNotifier
    var why: (UUID, String) -> Void = { _, _ in }
}

/// A watch's cards in Morning Files: their folder, how many are still open, and the pile to show (To review when
/// any is there, else where the open ones are, else the resolved ones).
struct WatchCardsLink: Equatable {
    var folderID: UUID
    var open: Int
    var disposition: MorningCardDisposition
    var label: String { "Cards folder (\(open))" }
}

/// The watch pages' words, apart from the views so they can be tested: each item in plain words, each watch's
/// schedule, when it last checked and how its items stand, what's wrong with its files, and where its cards are.
@MainActor
enum WatchListWords {
    static let fromTeam = "From your team's tools"

    // MARK: items

    /// An item's line: its differences in plain words, "As expected" (with what counts, or was named, but the check
    /// didn't report), why it couldn't check, or that it hasn't been yet.
    static func words(_ item: WatchListItem, fields: [String]? = nil, checking: Bool) -> String {
        switch item.status {
        case nil: return checking ? "Checking…" : "Not checked yet"
        case .asExpected?: return "As expected" + (unreported(item, fields: fields).map { " · " + $0.prefix(1).lowercased() + $0.dropFirst() } ?? "")
        case .notAsExpected(let differences)?: return differences.map(\.words).joined(separator: "\n")
        case .couldNotCheck(let reason)?: return "Couldn't check: \(reason)"
        }
    }

    /// "Not reported: Colour": what counts, or was named, but the check didn't report. Shown, never a difference.
    static func unreported(_ item: WatchListItem, fields: [String]? = nil) -> String? {
        let names = item.unreported(named: fields).map(WatchListRules.label)
        return names.isEmpty ? nil : "Not reported: " + names.joined(separator: ", ")
    }

    /// What the check said about the item in its own words, under the differences; nothing when it said nothing.
    static func why(_ item: WatchListItem) -> String? {
        item.whyNow.isEmpty ? nil : item.whyNow.joined(separator: "\n")
    }

    /// Only web pages open from a check's answer: never a file or another app's link.
    static func openable(_ item: WatchListItem) -> URL? {
        guard let text = item.pageURL, let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    // MARK: watches

    /// "Every 15 minutes · 3 items · last checked 6:31 PM", with when it starts or ends, or "Paused · 3 items".
    static func subtitle(_ watch: WatchListWatch, checking: Bool, now: Date = Date()) -> String {
        let items = itemCount(watch.items.count)
        if watch.paused { return "Paused · \(items)" }
        let every = capitalized(watch.everyWords)
        if let window = window(watch, now: now, running: true), watch.notStarted(at: now) || watch.ended(at: now) {
            return "\(window) · \(every) · \(items)"
        }
        if checking { return "\(every) · \(items) · checking now" }
        let ends = window(watch, now: now, running: true).map { " · " + $0 } ?? ""
        return "\(every) · \(items) · " + (watch.lastRunAt.map { "last checked " + time($0, now: now) } ?? "not checked yet") + ends
    }

    /// A team job's line: its path, how often, how many items, when it starts or ends, and whether it is on.
    static func teamSubtitle(_ watch: WatchListWatch, checking: Bool, now: Date = Date()) -> String {
        let every = capitalized(watch.everyWords)
        var parts = [watch.path, every, itemCount(watch.items.count)]
        if let window = window(watch, now: now, running: watch.on) { parts.append(window) }
        if !watch.on { parts.append("off") }
        else if watch.paused { parts.append("paused in the team's tools") }
        else if checking { parts.append("checking now") }
        else if watch.checking(at: now) { parts.append(watch.lastRunAt.map { "last checked " + time($0, now: now) } ?? "not checked yet") }
        return parts.joined(separator: " · ")
    }

    /// "Starts Mon Oct 5, 12:00 AM", "Ended Sat Oct 31, 11:59 PM", or "Ends …" while it runs.
    static func window(_ watch: WatchListWatch, now: Date, running: Bool) -> String? {
        if let starts = watch.starts, now < starts.date { return "Starts " + starts.words }
        if let ends = watch.ends { return (now > ends.date ? "Ended " : "Ends ") + ends.words }
        if let starts = watch.starts, !running { return "Started " + starts.words }
        return nil
    }

    /// A row's first line: how often it runs, then when it starts, ends or ended, if it says.
    static func schedule(_ watch: WatchListWatch, now: Date) -> String {
        ([capitalized(watch.everyWords)] + [window(watch, now: now, running: true)].compactMap { $0 }).joined(separator: " · ")
    }

    /// What it is doing, or when it last checked: "Off", "Paused", "Checking now", "Checked 6:31 PM" or "Not checked yet".
    static func checked(_ watch: WatchListWatch, checking: Bool, now: Date) -> String {
        if watch.isTeam && !watch.on { return "Off" }
        if watch.paused { return watch.isTeam ? "Paused in the team's tools" : "Paused" }
        if checking { return "Checking now" }
        return watch.lastRunAt.map { "Checked " + time($0, now: now) } ?? "Not checked yet"
    }

    /// How its items stand: "3 as expected · 2 not as expected · 1 couldn't check", and those not checked yet; how
    /// many items there are when none has been checked.
    static func counts(_ watch: WatchListWatch) -> String {
        guard !watch.items.isEmpty else { return "No items" }
        var green = 0, red = 0, grey = 0, unchecked = 0
        for item in watch.items {
            switch item.status {
            case .asExpected?: green += 1
            case .notAsExpected?: red += 1
            case .couldNotCheck?: grey += 1
            case nil: unchecked += 1
            }
        }
        guard unchecked < watch.items.count else { return itemCount(unchecked) }
        return [(green, "as expected"), (red, "not as expected"), (grey, "couldn't check"), (unchecked, "not checked yet")]
            .filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
    }

    /// A row's second line: when it last checked, then how its items stand. A team job that's off says only how many
    /// items it has.
    static func status(_ watch: WatchListWatch, checking: Bool, now: Date) -> String {
        checked(watch, checking: checking, now: now) + " · " + (watch.isTeam && !watch.on ? itemCount(watch.items.count) : counts(watch))
    }

    /// The line on a watch's cards folder, before Run now and Open job: "Checked 6:31 PM · every 15 minutes".
    static func cardsFolderLine(_ watch: WatchListWatch, checking: Bool, now: Date) -> String {
        checked(watch, checking: checking, now: now) + " · " + watch.everyWords
    }

    /// Check now works for a watch of your own between its start and end, even paused, and for a team job that's on
    /// and running.
    static func canCheckNow(_ watch: WatchListWatch, checking: Bool, now: Date) -> Bool {
        guard !checking else { return false }
        return watch.isTeam ? watch.checking(at: now) : !watch.notStarted(at: now) && !watch.ended(at: now)
    }

    /// What to know about a watch's files: its items file, the rows it leaves out, columns the check doesn't report,
    /// and that there are several items files.
    static func notes(_ watch: WatchListWatch) -> [String] {
        var notes: [String] = []
        if let file = watch.file {
            notes.append("Items from \(file.name)")
            if !file.skipped.isEmpty { notes.append("Left out: " + file.skipped.joined(separator: "; ")) }
            let columns = WatchListConversation.unreportedColumns(watch)
            if !columns.isEmpty { notes.append(columns.map { "Column \($0) isn't something the check reports." }.joined(separator: " ")) }
        }
        if let note = watch.fileNote { notes.append(note) }
        return notes
    }

    /// A watch whose watch.json or items file can't be read keeps its last good definition: the problem, said so.
    static func problem(_ reason: String?) -> String? {
        reason.map { $0 + " Until it's fixed, the job keeps what it had." }
    }

    // MARK: cards

    /// The watch whose cards a Morning Files folder holds, if any.
    static func watch(forFolder id: UUID, in watches: [WatchListWatch]) -> WatchListWatch? {
        watches.first { CardInboxFormat.folderID(WatchListCards.source(for: $0)) == id }
    }

    /// A watch's link to its cards; nil until its first card made its folder.
    static func cardsLink(for watch: WatchListWatch, folders: [MorningFolder], cards: [MorningCard]) -> WatchCardsLink? {
        let folderID = CardInboxFormat.folderID(WatchListCards.source(for: watch))
        guard folders.contains(where: { $0.id == folderID }) else { return nil }
        let open = cards.filter { $0.folderID == folderID && !$0.isResolved }
        let disposition = open.contains { $0.displayDisposition == .unreviewed } ? .unreviewed : open.first?.displayDisposition ?? .resolved
        return WatchCardsLink(folderID: folderID, open: open.count, disposition: disposition)
    }

    // MARK: helpers

    static func itemCount(_ count: Int) -> String { "\(count) item\(count == 1 ? "" : "s")" }

    static func time(_ date: Date, now: Date = Date()) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }
}

/// What the watch pages do to a watch, saying in plain words what went wrong.
@MainActor
struct WatchListActions {
    let store: WatchListStore
    let runner: WatchListRunner
    let notifier: WatchListNotifier

    func checkNow(_ watch: WatchListWatch) { runner.run(watch.id) }

    func setPaused(_ watch: WatchListWatch, _ paused: Bool) -> String? {
        do { try store.change(watch.id) { $0.paused = paused }; return nil } catch { return error.localizedDescription }
    }

    func turn(_ watch: WatchListWatch, on: Bool) -> String? {
        do {
            try runner.turn(watch.id, on: on)
            if on { notifier.requestPermission() }
            return nil
        } catch { return error.localizedDescription }
    }

    /// Stops checking it, and moves its folder to the Trash.
    func stop(_ watch: WatchListWatch) -> String? {
        runner.cancel(watch.id)
        do { try store.remove(watch.id); return nil } catch { return error.localizedDescription }
    }
}

/// A watch's page among the jobs: the header every job's page has (its name, what it checks and how often, its last
/// run and how it stands, Run now, Pause or the on/off switch, and its card); for a watch of your own Show in Finder
/// and Stop watching; what's wrong with its files; its cards folder; and every item with its dot, what it shows, what
/// the check said, when it was checked, and Why? and Open page.
struct WatchJobPage: View {
    @ObservedObject var store: WatchListStore
    @ObservedObject var runner: WatchListRunner
    @ObservedObject var notifier: WatchListNotifier
    @ObservedObject var morning: MorningStore
    let id: UUID
    let why: (UUID, String) -> Void
    let openCards: (WatchCardsLink) -> Void
    /// Stop watching moved its folder to the Trash: back to Jobs.
    let stopped: () -> Void
    /// Opens its card, from the header.
    var openCard: (UUID) -> Void = { _ in }
    var setup = JobsSetup()
    var now: () -> Date = Date.init
    @State private var problem: String?
    @State private var confirmingStop = false

    private var actions: WatchListActions { WatchListActions(store: store, runner: runner, notifier: notifier) }
    private var panel: WatchListPanel { WatchListPanel(store: store, runner: runner, notifier: notifier) }
    private var input: Jobs.Input { Jobs.Input(sources: nil, watches: panel, morning: morning, setup: setup, now: now()) }

    var body: some View {
        if let watch = store.watch(id: id) {
            page(watch, job: Jobs.watchJob(watch, input))
        } else {
            Text("This job is no longer here.").font(.system(size: 14)).foregroundStyle(Pad.inkSoft).padding(24)
        }
    }

    private func page(_ watch: WatchListWatch, job: Job) -> some View {
        let checking = runner.checking.contains(watch.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                JobHeader(job: job,
                          controls: JobControls(job: job, actions: JobActions(watches: panel, now: now), openSettings: setup.openSettings,
                                                problem: { problem = $0 }),
                          card: JobCardLink(cards: Jobs.cards(for: job, input), open: openCard))
                if !watch.isTeam {
                    HStack(spacing: 8) {
                        if let folder = store.folder(for: watch.id) {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }.buttonStyle(MorningActionButton())
                        }
                        Button("Stop watching…") { confirmingStop = true }.buttonStyle(MorningActionButton())
                    }
                }
                if confirmingStop { stopConfirmation(watch) }
                if let problem { Text(problem).font(.system(size: 12)).foregroundStyle(Pad.redInk).textSelection(.enabled) }
                ForEach(job.problems, id: \.self) { line in
                    Label(line, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Pad.redInk)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                ForEach(job.notes, id: \.self) { note in
                    Text(note).font(.system(size: 11)).foregroundStyle(Pad.inkSoft).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if let link = WatchListWords.cardsLink(for: watch, folders: morning.folders, cards: morning.cards) {
                    Button { openCards(link) } label: { Label(link.label, systemImage: "folder") }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Pad.penInk)
                        .help("Open the folder with this job’s cards in Morning Files")
                }
                if watch.isTeam && !watch.on {
                    Text("Turn it on to check its \(WatchListWords.itemCount(watch.items.count)) and hear about them.")
                        .font(.system(size: 13)).foregroundStyle(Pad.inkSoft)
                } else if watch.items.isEmpty {
                    Text("No items yet.").font(.system(size: 13)).foregroundStyle(Pad.inkSoft)
                } else {
                    WatchItemsList(watch: watch, checking: checking, why: why)
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await notifier.refresh() }
    }

    private func stopConfirmation(_ watch: WatchListWatch) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Stop watching “\(watch.name)”?").font(.system(size: 13, weight: .semibold))
            Text("Noteling stops checking these items and won't notify you about them again. Its folder goes to the Trash, so you can put it back.")
                .font(.system(size: 12)).foregroundStyle(Pad.inkSoft).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Stop watching") {
                    confirmingStop = false
                    if let failure = actions.stop(watch) { problem = failure } else { stopped() }
                }.buttonStyle(MorningActionButton(primary: true))
                Button("Cancel") { confirmingStop = false }.buttonStyle(MorningActionButton())
            }
        }.padding(12).background(Pad.paperTop.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A watch's items, one row each: a dot (green as expected, red not as expected, grey couldn't check, an open circle
/// not checked yet), what it shows in plain words, what the check said, when it was checked, and Why? and Open page.
struct WatchItemsList: View {
    let watch: WatchListWatch
    let checking: Bool
    let why: (UUID, String) -> Void

    static let green = Color(red: 0.24, green: 0.56, blue: 0.33)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(watch.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().overlay(Pad.tabEdge.opacity(0.3)) }
                row(item)
            }
        }
        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Pad.tabEdge.opacity(0.45)))
    }

    private func row(_ item: WatchListItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            dot(item).padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.label).font(.system(size: 13, weight: .medium)).lineLimit(2).textSelection(.enabled)
                Text(WatchListWords.words(item, fields: watch.fields, checking: checking)).font(.system(size: 12))
                    .foregroundStyle(item.isRed ? Pad.redInk : Pad.inkSoft).textSelection(.enabled)
                if item.isRed, let unreported = WatchListWords.unreported(item, fields: watch.fields) {
                    Text(unreported).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                }
                if let reason = WatchListWords.why(item) {
                    Text(reason).font(.system(size: 12)).foregroundStyle(Pad.inkSoft).textSelection(.enabled)
                }
                if let checked = item.checkedAt {
                    Text("Checked " + WatchListWords.time(checked)).font(.system(size: 10)).foregroundStyle(Pad.inkSoft)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if item.needsExplaining { Button("Why?") { why(watch.id, item.key) }.buttonStyle(MorningActionButton()) }
            if let url = WatchListWords.openable(item) {
                Button("Open page") { NSWorkspace.shared.open(url) }.buttonStyle(MorningActionButton()).help(url.absoluteString)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
    }

    @ViewBuilder private func dot(_ item: WatchListItem) -> some View {
        switch item.status {
        case .asExpected?: Circle().fill(Self.green).frame(width: 9, height: 9).accessibilityLabel("As expected")
        case .notAsExpected?: Circle().fill(Pad.redInk).frame(width: 9, height: 9).accessibilityLabel("Not as expected")
        case .couldNotCheck?: Circle().fill(Pad.inkSoft).frame(width: 9, height: 9).accessibilityLabel("Couldn't check")
        case nil: Circle().stroke(Pad.inkSoft, lineWidth: 1.5).frame(width: 9, height: 9).accessibilityLabel("Not checked yet")
        }
    }
}

/// The line on a watch's cards folder in Morning Files: when it last checked and how often, Run now, and Open job.
struct WatchCardsFolderLine: View {
    @ObservedObject var store: WatchListStore
    @ObservedObject var runner: WatchListRunner
    let watchID: UUID
    let openJob: () -> Void
    var now: () -> Date = Date.init

    var body: some View {
        if let watch = store.watch(id: watchID) {
            let checking = runner.checking.contains(watch.id)
            HStack(spacing: 6) {
                Image(systemName: "eye").foregroundStyle(Pad.inkSoft)
                Text(WatchListWords.cardsFolderLine(watch, checking: checking, now: now())).foregroundStyle(Pad.inkSoft)
                if WatchListWords.canCheckNow(watch, checking: checking, now: now()) {
                    Text("·").foregroundStyle(Pad.inkSoft)
                    Button("Run now") { runner.run(watch.id) }
                }
                Text("·").foregroundStyle(Pad.inkSoft)
                Button("Open job", action: openJob).help("Open this job’s page, with all its items")
                Spacer(minLength: 0)
            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
        }
    }
}
