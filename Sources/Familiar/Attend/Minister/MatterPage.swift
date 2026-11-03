import AppKit
import SwiftUI

/// A matter's page, opened from its sticker: the sticker's words, who it comes from, the minister's notes (why it is
/// shown, or kept quiet), the findings behind it as their jobs reported them, the buttons their jobs have, and the page
/// it lives on.
struct MatterPage: View {
    @ObservedObject var matters: Matters
    let store: FolderJobStore
    var buttons: FolderJobButtons?
    let id: String
    var now: () -> Date = Date.init

    var body: some View {
        if let matter = matters.matter(id: id) {
            page(matter)
        } else {
            Text("This sticker is no longer here.").font(.system(size: 14)).foregroundStyle(Pad.inkSoft).padding(24)
        }
    }

    private func page(_ matter: Matter) -> some View {
        let findings = Self.findings(of: matter, store: store)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let view = matter.view {
                    Text(view.text).font(HandFont.font(size: 20)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                } else {
                    Text(matter.state == .closed ? "This is over." : "The minister hasn't written this one up yet.")
                        .font(.system(size: 14)).foregroundStyle(Pad.inkSoft)
                }
                Text(Self.byline(matter, now: now())).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                if let line = Self.stateLine(matter) {
                    Label(line, systemImage: matter.state == .closed ? "checkmark.circle" : matter.state == .quiet ? "moon.zzz" : "exclamationmark.circle")
                        .font(.system(size: 12)).foregroundStyle(matter.isUrgent && matter.state == .open ? Pad.redInk : Pad.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if matter.state == .open {
                    if let buttons {
                        MatterControls(matters: matters, buttons: buttons, matter: matter, findings: findings, now: now)
                    } else {
                        MatterControls.plain(matters: matters, matter: matter, findings: findings)
                    }
                }
                if let press = matter.presses.last {
                    Label("\(press.label) · \(JobWords.time(press.at, now: now())) · \(press.said)", systemImage: press.failed ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.system(size: 12)).foregroundStyle(press.failed ? Pad.redInk : Pad.inkSoft)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if let notes = matters.notes(for: matter.id) {
                    FolderJobSection(title: "Why", icon: "text.alignleft") { Self.markdown(notes) }
                }
                if !findings.isEmpty {
                    FolderJobSection(title: "Findings", icon: "tablecells") {
                        ForEach(Self.byJob(findings), id: \.job.id) { group in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(group.job.name).font(.system(size: 13, weight: .semibold))
                                FolderJobTable(rows: Self.table(group.rows))
                            }
                        }
                    }
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: words

    /// "Stuck orders · shared by Lena Park · 9:02 AM".
    static func byline(_ matter: Matter, now: Date) -> String {
        [matter.jobName, matter.byline.map { "shared by " + $0 }, JobWords.time(matter.shownAt, now: now)].compactMap { $0 }.joined(separator: " · ")
    }

    /// Why it isn't on a sticker, or that it is over; "Urgent" while it is and urgent; nil otherwise.
    static func stateLine(_ matter: Matter) -> String? {
        switch matter.state {
        case .open: return matter.isUrgent ? "Urgent" : nil
        case .quiet: return "Kept quiet: " + (matter.why ?? "no reason kept.")
        case .closed: return "Over: its findings are gone."
        }
    }

    /// The page the sticker points at, or the first finding's.
    static func page(of matter: Matter, findings: [(job: FolderJob, row: FindingRow)]) -> String? {
        matter.view?.page ?? findings.lazy.compactMap { $0.job.map?.place(of: $0.row) }.first
    }

    // MARK: the findings

    /// Each finding of the matter as its job last reported it, read once per job; one whose job or row is gone is left out.
    static func findings(of matter: Matter, store: FolderJobStore) -> [(job: FolderJob, row: FindingRow)] {
        var snapshots: [UUID: FindingsSnapshot] = [:]
        return matter.findings.compactMap { ref in
            guard let job = store.jobs.first(where: { MemoryLog.name(of: $0) == ref.job }) else { return nil }
            let snapshot = snapshots[job.id] ?? FindingsSnapshot.read(store.findingsFile(for: job))
            snapshots[job.id] = snapshot
            return snapshot.rows[ref.id].map { (job, $0.row) }
        }
    }

    static func byJob(_ findings: [(job: FolderJob, row: FindingRow)]) -> [(job: FolderJob, rows: [FindingRow])] {
        var order: [UUID] = [], rows: [UUID: (FolderJob, [FindingRow])] = [:]
        for finding in findings {
            if rows[finding.job.id] == nil { order.append(finding.job.id); rows[finding.job.id] = (finding.job, []) }
            rows[finding.job.id]?.1.append(finding.row)
        }
        return order.compactMap { rows[$0] }.map { (job: $0.0, rows: $0.1) }
    }

    /// Rows of one job as a table with the job's columns across, the way the chat sees them: secrets hidden.
    static func table(_ rows: [FindingRow]) -> [[String]] {
        let columns = rows.first?.columns ?? []
        return FolderJobFindings.redacted([columns] + rows.map { row in columns.map { row.text($0) ?? "" } })
    }

    /// Markdown as the notes have it, line by line: headings bold, bullets as bullets, the rest inline.
    @ViewBuilder static func markdown(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#") {
                    Text(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)).font(.system(size: 13, weight: .semibold))
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        inline(String(line.dropFirst(2)))
                    }
                } else if !line.isEmpty {
                    inline(line)
                }
            }
        }.font(.system(size: 13)).textSelection(.enabled)
    }

    static func inline(_ line: String) -> Text {
        if let attributed = try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) { return Text(attributed) }
        return Text(line)
    }
}

/// A matter's buttons: each finding's job's actions (asking first when the action says so, showing while one runs),
/// the page it lives on, and Put away. Watches the buttons, so a press shows as it runs.
struct MatterControls: View {
    @ObservedObject var matters: Matters
    @ObservedObject var buttons: FolderJobButtons
    let matter: Matter
    let findings: [(job: FolderJob, row: FindingRow)]
    var now: () -> Date = Date.init
    @State private var confirming: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 9) { controls }
            VStack(alignment: .leading, spacing: 8) { controls }
        }
    }

    @ViewBuilder private var controls: some View {
        ForEach(Array(findings.enumerated()), id: \.offset) { _, finding in
            ForEach(finding.job.actions) { action in
                actionButton(job: finding.job, row: finding.row, action: action,
                             primary: matter.view?.action?.run == action.run && matter.view?.action?.finding.id == finding.row.id)
            }
        }
        Self.common(matters: matters, matter: matter, findings: findings)
    }

    @ViewBuilder private func actionButton(job: FolderJob, row: FindingRow, action: FolderJobAction, primary: Bool) -> some View {
        let key = FolderJobButtons.key(job, row) + "|" + action.id
        let running = buttons.pressing[FolderJobButtons.key(job, row)] == action.id
        let why = buttons.unavailable(job)
        if confirming == key {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(action.label)? \(job.name) runs this as you.", systemImage: "exclamationmark.circle").font(.system(size: 12))
                HStack(spacing: 12) {
                    Button(action.label) { confirming = nil; press(job, row, action) }.buttonStyle(PaperActionButton(primary: true))
                    Button("Cancel") { confirming = nil }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
                }
            }.padding(12).background(Pad.paperTop.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
        } else {
            Button {
                if action.confirm { confirming = key } else { press(job, row, action) }
            } label: {
                if running { HStack(spacing: 6) { ProgressView().controlSize(.small); Text(action.label) } } else { Text(action.label) }
            }
            .buttonStyle(PaperActionButton(primary: primary))
            .disabled(running || why != nil)
            .help(why ?? "Runs \(action.run)() in \(job.name)'s job.py, as you")
        }
    }

    private func press(_ job: FolderJob, _ row: FindingRow, _ action: FolderJobAction) {
        Task { await buttons.press(job, action, for: row) }
    }

    /// The buttons every matter has, with or without a way to press its job's: Open page and Put away.
    @ViewBuilder static func common(matters: Matters, matter: Matter, findings: [(job: FolderJob, row: FindingRow)]) -> some View {
        if let page = MatterPage.page(of: matter, findings: findings), let url = URL(string: page) {
            Button("Open page") { NSWorkspace.shared.open(url) }.buttonStyle(PaperActionButton()).help(page)
        }
        Button("Put away") { matters.putAway(matter.id) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
            .help("Takes the sticker down. It comes back only if something about this changes and the minister thinks you should see it.")
    }

    /// Without the buttons (a render): the job's actions shown but not pressable, and the common ones.
    @ViewBuilder static func plain(matters: Matters, matter: Matter, findings: [(job: FolderJob, row: FindingRow)]) -> some View {
        HStack(spacing: 9) {
            ForEach(Array(findings.enumerated()), id: \.offset) { _, finding in
                ForEach(finding.job.actions) { action in Button(action.label) {}.buttonStyle(PaperActionButton()).disabled(true) }
            }
            common(matters: matters, matter: matter, findings: findings)
        }
    }
}
