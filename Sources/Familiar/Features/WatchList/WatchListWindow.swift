import AppKit
import SwiftUI

/// Every watch with its items: a status dot per item (green as expected, red not as expected, grey couldn't check),
/// what isn't as expected in plain words and what the check said, when it was checked, and Why? and Open. A watch of
/// your own can be checked now, paused, resumed, shown in the Finder or stopped here; your team's watches are listed
/// below them, each with a switch to turn it on for you.
struct WatchListView: View {
    @ObservedObject var store: WatchListStore
    @ObservedObject var runner: WatchListRunner
    @ObservedObject var notifier: WatchListNotifier
    let onWhy: (UUID, String) -> Void
    var now: () -> Date = Date.init
    @State private var problem: String?
    @State private var stopping: WatchListWatch?

    static let empty = "Nothing is being watched. Ask in chat: “watch these items: …”"
    static let fromTeam = "From your team's tools"

    private var own: [WatchListWatch] { store.watches.filter { !$0.isTeam } }
    private var team: [WatchListWatch] { store.watches.filter(\.isTeam) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.watches.isEmpty && store.unreadable.isEmpty && store.teamUnreadable.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "eye").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text(Self.empty).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        notices
                        if !team.isEmpty, !own.isEmpty { Text("Your watches").font(.title3.weight(.semibold)) }
                        ForEach(own) { watch in section(watch) }
                        if !team.isEmpty || !store.teamUnreadable.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Team watches").font(.title3.weight(.semibold))
                                Text(Self.teamIntro).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.top, own.isEmpty ? 0 : 8)
                            ForEach(store.teamUnreadable.keys.sorted(), id: \.self) { path in
                                Label("Not listing \(path). \(store.teamUnreadable[path] ?? "")", systemImage: "exclamationmark.triangle")
                                    .font(.callout).foregroundStyle(.orange)
                            }
                            ForEach(team) { watch in teamSection(watch) }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 300)
        .confirmationDialog(stopping.map { "Stop watching “\($0.name)”?" } ?? "", isPresented: Binding(
            get: { stopping != nil }, set: { if !$0 { stopping = nil } }), titleVisibility: .visible, presenting: stopping) { watch in
            Button("Stop watching", role: .destructive) { stop(watch) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Noteling stops checking these items and won't notify you about them again. Its folder goes to the Trash, so you can put it back.")
        }
    }

    @ViewBuilder
    private var notices: some View {
        if let off = notifier.offReason {
            Label(off, systemImage: "bell.slash").font(.callout).foregroundStyle(.orange)
        }
        if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
        if let problem { Text(problem).font(.callout).foregroundStyle(.red) }
        ForEach(store.unreadable.keys.sorted(), id: \.self) { folder in
            HStack(alignment: .top) {
                Label("Not watching the “\(folder)” folder. \(store.unreadable[folder] ?? "")", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                Spacer(minLength: 8)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.directory.appendingPathComponent(folder)]) }
                    .controlSize(.small)
            }
        }
    }

    static let teamIntro = "Jobs your team keeps in its tools. Turn on the ones that are yours: only those are checked and tell you."

    private func section(_ watch: WatchListWatch) -> some View {
        let checking = runner.checking.contains(watch.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(watch.name).font(.headline).lineLimit(2)
                    Text(Self.subtitle(watch, checking: checking, now: now())).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Group {
                    Button(checking ? "Checking…" : "Check now") { runner.run(watch.id) }
                        .disabled(checking || watch.notStarted(at: now()) || watch.ended(at: now()))
                    Button(watch.paused ? "Resume" : "Pause") { change(watch) { $0.paused.toggle() } }
                    if let folder = store.folder(for: watch.id) {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    }
                    Button("Stop watching") { stopping = watch }
                }
                .controlSize(.small)
            }
            details(watch)
            items(watch, checking: checking)
        }
    }

    /// A team watch: what it is and a switch; once on, its items as for a watch of your own. No Stop, no folder.
    private func teamSection(_ watch: WatchListWatch) -> some View {
        let checking = runner.checking.contains(watch.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(watch.name).font(.headline).lineLimit(2)
                    Text(Self.teamSubtitle(watch, checking: checking, now: now())).font(.caption).foregroundStyle(.secondary)
                    Text(Self.fromTeam).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if watch.on {
                    Button(checking ? "Checking…" : "Check now") { runner.run(watch.id) }
                        .disabled(checking || !watch.checking(at: now()))
                        .controlSize(.small)
                }
                Toggle("On", isOn: Binding(get: { watch.on }, set: { turn(watch, on: $0) }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .accessibilityLabel(watch.on ? "Turn off \(watch.name)" : "Turn on \(watch.name)")
            }
            details(watch)
            if watch.on { items(watch, checking: checking) }
        }
    }

    @ViewBuilder
    private func details(_ watch: WatchListWatch) -> some View {
        if let problem = store.problems[watch.id] {
            Label(problem + " Until it's fixed, the watch keeps what it had.", systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
        }
        ForEach(Self.notes(watch), id: \.self) { note in
            Text(note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    private func items(_ watch: WatchListWatch, checking: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(watch.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider() }
                row(watch, item, checking: checking)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    private func turn(_ watch: WatchListWatch, on: Bool) {
        do {
            try runner.turn(watch.id, on: on)
            if on { notifier.requestPermission() }
            problem = nil
        } catch { problem = error.localizedDescription }
    }

    private func row(_ watch: WatchListWatch, _ item: WatchListItem, checking: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            dot(item).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.label).lineLimit(2).textSelection(.enabled)
                Text(Self.words(item, fields: watch.fields, checking: checking)).font(.callout)
                    .foregroundStyle(item.isRed ? Color.red : Color.secondary)
                    .textSelection(.enabled)
                if item.isRed, let unreported = Self.unreported(item, fields: watch.fields) {
                    Text(unreported).font(.callout).foregroundStyle(.secondary)
                }
                if let why = Self.why(item) {
                    Text(why).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let checked = item.checkedAt {
                    Text("Checked " + Self.time(checked)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if item.needsExplaining { Button("Why?") { onWhy(watch.id, item.key) } }
            if let url = Self.openable(item) { Button("Open") { NSWorkspace.shared.open(url) } }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func dot(_ item: WatchListItem) -> some View {
        switch item.status {
        case .asExpected?: Circle().fill(Color.green).frame(width: 10, height: 10).accessibilityLabel("As expected")
        case .notAsExpected?: Circle().fill(Color.red).frame(width: 10, height: 10).accessibilityLabel("Not as expected")
        case .couldNotCheck?: Circle().fill(Color.gray).frame(width: 10, height: 10).accessibilityLabel("Couldn't check")
        case nil: Circle().stroke(Color.gray, lineWidth: 1.5).frame(width: 10, height: 10).accessibilityLabel("Not checked yet")
        }
    }

    private func change(_ watch: WatchListWatch, _ body: (inout WatchListWatch) -> Void) {
        do { try store.change(watch.id, body); problem = nil }
        catch { problem = error.localizedDescription }
    }

    private func stop(_ watch: WatchListWatch) {
        runner.cancel(watch.id)
        do { try store.remove(watch.id); problem = nil }
        catch { problem = error.localizedDescription }
    }

    // MARK: words

    /// The row's line: its differences in plain words, "As expected" (with what counts, or was named, but the check
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

    static func subtitle(_ watch: WatchListWatch, checking: Bool, now: Date = Date()) -> String {
        let items = "\(watch.items.count) item\(watch.items.count == 1 ? "" : "s")"
        if watch.paused { return "Paused · \(items)" }
        let every = watch.everyWords.prefix(1).uppercased() + watch.everyWords.dropFirst()
        if let window = window(watch, now: now, running: true), watch.notStarted(at: now) || watch.ended(at: now) {
            return "\(window) · \(every) · \(items)"
        }
        if checking { return "\(every) · \(items) · checking now" }
        let ends = window(watch, now: now, running: true).map { " · " + $0 } ?? ""
        return "\(every) · \(items) · " + (watch.lastRunAt.map { "last checked " + time($0) } ?? "not checked yet") + ends
    }

    /// A team watch's line: its path, how often, how many items, when it starts or ends, and whether it is on.
    static func teamSubtitle(_ watch: WatchListWatch, checking: Bool, now: Date = Date()) -> String {
        let items = "\(watch.items.count) item\(watch.items.count == 1 ? "" : "s")"
        let every = watch.everyWords.prefix(1).uppercased() + watch.everyWords.dropFirst()
        var parts = [watch.path, every, items]
        if let window = window(watch, now: now, running: watch.on) { parts.append(window) }
        if !watch.on { parts.append("off") }
        else if watch.paused { parts.append("paused in the team's tools") }
        else if checking { parts.append("checking now") }
        else if watch.checking(at: now) { parts.append(watch.lastRunAt.map { "last checked " + time($0) } ?? "not checked yet") }
        return parts.joined(separator: " · ")
    }

    /// "Starts Mon Oct 5, 12:00 AM", "Ended Sat Oct 31, 11:59 PM", or "Ends …" while it runs.
    static func window(_ watch: WatchListWatch, now: Date, running: Bool) -> String? {
        if let starts = watch.starts, now < starts.date { return "Starts " + starts.words }
        if let ends = watch.ends { return (now > ends.date ? "Ended " : "Ends ") + ends.words }
        if let starts = watch.starts, !running { return "Started " + starts.words }
        return nil
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

    static func time(_ date: Date, now: Date = Date()) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Only web pages open from a check's answer: never a file or another app's link.
    static func openable(_ item: WatchListItem) -> URL? {
        guard let text = item.pageURL, let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
}

/// The Watch List window, opened from the menu bar's Watch List… and from the chat after a watch is created.
@MainActor
final class WatchListWindowController {
    private var window: NSWindow?
    private let store: WatchListStore
    private let runner: WatchListRunner
    private let notifier: WatchListNotifier
    /// Why? on a row: the app opens the chat on that item.
    var onWhy: ((UUID, String) -> Void)?

    init(store: WatchListStore, runner: WatchListRunner, notifier: WatchListNotifier) {
        self.store = store
        self.runner = runner
        self.notifier = notifier
    }

    func show(hideFromScreenShare: Bool) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Watch List"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 420, height: 300)
            window.contentView = NSHostingView(rootView: WatchListView(store: store, runner: runner, notifier: notifier,
                                                                       onWhy: { [weak self] watch, item in self?.onWhy?(watch, item) }))
            window.center()
            self.window = window
        }
        updateSharing(hideFromScreenShare)
        Task { await notifier.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateSharing(_ hideFromScreenShare: Bool) {
        window?.sharingType = hideFromScreenShare ? .none : .readOnly
    }

    func close() {
        window?.orderOut(nil)
        window?.close()
    }
}
