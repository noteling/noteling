import AppKit
import SwiftUI

/// The words the pages of jobs kept as folders use, apart from the views so they can be tested: how often a job runs,
/// when it starts or ends, and how its last run went.
@MainActor
enum FolderJobWords {
    /// "every 15 minutes", "every hour", "every 2 hours", "every day", or "when you run it".
    static func every(_ job: FolderJob) -> String {
        guard let minutes = job.everyMinutes else { return "when you run it" }
        if minutes == 1_440 { return "every day" }
        if minutes % 60 == 0 { return minutes == 60 ? "every hour" : "every \(minutes / 60) hours" }
        return "every \(minutes) minutes"
    }

    /// "Starts Mon Oct 5, 12:00 AM", "Ended Sat Oct 31, 11:59 PM", or "Ends …" while it runs.
    static func window(_ job: FolderJob, now: Date) -> String? {
        if let starts = job.starts, now < starts.date { return "Starts " + starts.words }
        if let ends = job.ends { return (now > ends.date ? "Ended " : "Ends ") + ends.words }
        return nil
    }

    /// A row's first line after what it does: "Every hour · Ends Sat Oct 31, 11:59 PM", "When you run it".
    static func schedule(_ job: FolderJob, now: Date) -> String {
        ([capitalized(every(job))] + [window(job, now: now)].compactMap { $0 }).joined(separator: " · ")
    }

    /// "Last run 6:31 PM · 2 of 8 prices wrong", "… · something to look at", "… · nothing to look at", "… · failed",
    /// or "Not run yet".
    static func lastRun(_ job: FolderJob, now: Date) -> String {
        guard let last = job.state.lastRunAt else { return Jobs.notRunYet }
        let how: String
        if job.state.error != nil { how = "failed" }
        else if let said = job.state.said { how = JobWords.clip(said.components(separatedBy: .newlines).first ?? said, 80) }
        else { how = job.state.preview == nil ? "nothing to look at" : "something to look at" }
        return "Last run " + JobWords.time(last, now: now) + " · " + how
    }

    /// The line on a job's folder in Morning Files: "Last run 6:31 PM · every hour", or "Running now · every hour".
    static func folderLine(_ job: FolderJob, running: Bool, now: Date) -> String {
        (running ? "Running now" : job.state.lastRunAt.map { "Last run " + JobWords.time($0, now: now) } ?? Jobs.notRunYet)
            + " · " + every(job)
    }

    /// Above the latest result when the last run failed and an earlier one worked: whose result it is.
    static func from(_ job: FolderJob, now: Date) -> String? {
        guard job.state.error != nil, let success = job.state.lastSuccessAt else { return nil }
        return "From the last run that worked, " + JobWords.time(success, now: now) + "."
    }

    /// What a Run now came to, where it was pressed: "“GM” ran: 2 of 8 items need a look. Thanks to Yang for sharing
    /// this job." A run that failed says why, and thanks nobody.
    static func receipt(_ job: FolderJob) -> String {
        let name = "“" + JobWords.clip(job.name, 60) + "”"
        if let error = job.state.error { return "\(name) couldn't finish: " + error }
        let said = job.state.said.map { JobWords.clip($0.components(separatedBy: .newlines).first ?? $0, 120) }
            ?? (job.state.preview == nil ? "nothing to look at" : "something to look at")
        let line = "\(name) ran: " + said + (said.hasSuffix(".") ? "" : ".")
        return [line, thanks(job, run: job.state.lastSuccessAt)].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: thanks

    /// The ways a job thanks whoever shared it, one at a time; `{name}` is their names.
    static let thanks = [
        "Thanks to {name} for sharing this job.",
        "{name} shared this so nobody has to check it by hand.",
        "This check is {name}'s work. A thank-you goes a long way.",
        "Made by {name} for the team, and run here on your Mac.",
        "{name} built this. If it helped, tell them.",
        "Shared by {name}. One less thing to click through.",
    ]

    /// "Yang", "Yang and Ana", "Yang, Ana and Sam"; nil with nobody.
    static func names(_ names: [String]) -> String? {
        switch names.count {
        case 0: return nil
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }

    /// "Shared by Yang", on its row and its page; nil when its job.json names nobody.
    static func sharedBy(_ job: FolderJob) -> String? { names(job.contributors).map { "Shared by " + $0 } }

    /// The thank-you for one run of a job: picked by the run, so it stays the same while that run's result is shown and
    /// changes from one run to the next. Nil when its job.json names nobody, or before a run worked.
    static func thanks(_ job: FolderJob, run: Date?) -> String? {
        guard let names = names(job.contributors), let run else { return nil }
        let seed = (job.path + "|" + String(Int(run.timeIntervalSince1970.rounded()))).utf8.reduce(UInt64(5_381)) { ($0 &* 33) &+ UInt64($1) }
        return thanks[Int(seed % UInt64(thanks.count))].replacingOccurrences(of: "{name}", with: names)
    }

    /// Why a job's card was put away, said on the card in place of "Its script no longer reports this": the job ended,
    /// hasn't started, or is off. Nil while it runs, or when the card went away before the job ended (`gone`, when the
    /// inbox found its file gone), for another reason.
    static func putAway(_ job: FolderJob, gone: Date, now: Date) -> String? {
        switch job.phase(at: now) {
        case .ended:
            guard let ends = job.ends, gone >= ends.date else { return nil }
            return "This job ended \(ends.words), so its card was put away."
        case .upcoming:
            guard let starts = job.starts else { return nil }
            return "This job starts \(starts.words); its card is put away until then."
        case .live:
            return job.on ? nil : "This job is off, so its card was put away."
        }
    }

    private static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }
}

/// A job's page among the jobs: the header every job's page has (its name, what it does and how often, its last run and
/// how it stands, Run now or the on/off switch, and its card), what it is for, what's wrong, its input files, and its
/// latest result: the preview's files shown as they are, then every file to open or save.
struct FolderJobPage: View {
    @ObservedObject var store: FolderJobStore
    @ObservedObject var runner: FolderJobRunner
    @ObservedObject var morning: MorningStore
    let id: UUID
    var openCard: (UUID) -> Void = { _ in }
    var files = CardFileActions()
    var setup = JobsSetup()
    var now: () -> Date = Date.init
    /// Asked for permission when a team job is turned on here.
    var notifier: JobNotifier? = nil
    @State private var problem: String?
    @State private var notice: String?

    private var panel: FolderJobsPanel { FolderJobsPanel(store: store, runner: runner, notifier: notifier) }
    private var input: Jobs.Input { Jobs.Input(sources: nil, morning: morning, setup: setup, now: now(), folderJobs: panel) }

    var body: some View {
        if let folderJob = store.job(id: id) {
            page(folderJob, job: Jobs.folderJob(folderJob, input))
        } else {
            Text("This job is no longer here.").font(.system(size: 14)).foregroundStyle(Pad.inkSoft).padding(24)
        }
    }

    private func page(_ folderJob: FolderJob, job: Job) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                JobHeader(job: job,
                          controls: JobControls(job: job, actions: JobActions(now: now, folderJobs: panel), openSettings: setup.openSettings,
                                                problem: { problem = $0 }),
                          card: JobCardLink(cards: Jobs.cards(for: job, input), open: openCard))
                // All of what it's for, when its line above had to shorten it.
                if Jobs.aboutShortened(folderJob) {
                    Text(folderJob.about).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if !folderJob.isTeam, let folder = store.folder(for: folderJob) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }.buttonStyle(MorningActionButton())
                }
                if let problem { Text(problem).font(.system(size: 12)).foregroundStyle(Pad.redInk).textSelection(.enabled) }
                if let notice { Text(notice).font(.system(size: 12)).foregroundStyle(Pad.penInk) }
                if let receipt = runner.receipt, receipt.jobID == id { FolderJobReceiptLine(receipt: receipt, dismiss: runner.dismissReceipt) }
                ForEach(job.allProblems, id: \.self) { line in
                    Label(line, systemImage: "exclamationmark.triangle").font(.system(size: 12))
                        .foregroundStyle(job.isLive ? Pad.redInk : Pad.inkSoft).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if let input = store.input(for: folderJob), FileManager.default.fileExists(atPath: input.path) {
                    let found = FolderJobFiles.files(in: input)
                    FolderJobSection(title: "Input", icon: "tray.and.arrow.down") {
                        if found.files.isEmpty {
                            Text("Its input folder is empty.").font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                        } else {
                            FolderJobFilesList(files: found.files, more: found.more, actions: files, report: report)
                        }
                    }
                }
                FolderJobSection(title: "Latest result", icon: "tray.and.arrow.up") {
                    if let result = store.result(for: folderJob) {
                        if let from = FolderJobWords.from(folderJob, now: now()) {
                            Text(from).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                        }
                        FolderJobResultView(result: result, actions: files, report: report)
                    } else {
                        Text(folderJob.state.lastRunAt == nil ? "It hasn't run yet." : "No run has worked yet.")
                            .font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                    }
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func report(_ message: String, _ isProblem: Bool) {
        if isProblem { problem = message; notice = nil } else { notice = message; problem = nil }
    }
}

/// A section of a job's page: a small heading, then what's in it.
struct FolderJobSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(Pad.inkSoft)
            content
        }
    }
}

/// A job's latest result: each file in its preview shown as it is (a table or a text), then every file of the output
/// to open or save. A job's page and its card show the same.
struct FolderJobResultView: View {
    let result: FolderJobResult
    var actions = CardFileActions()
    var report: (_ message: String, _ problem: Bool) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(result.shown) { file in
                FolderJobPreviewView(file: file, open: { open(file) })
            }
            if result.files.isEmpty {
                Text("Its last run left no files.").font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Files", systemImage: "paperclip").font(.system(size: 12, weight: .semibold)).foregroundStyle(Pad.inkSoft)
                    FolderJobFilesList(files: result.files, more: result.more, actions: actions, report: report)
                }
            }
        }
    }

    private func open(_ file: FolderJobFile) {
        if !actions.open(file.url) { report("No app on this Mac opened \(file.name).", true) }
    }
}

/// One preview file, as it is: its name, then a table's first rows or a text's beginning, and how to see the rest.
struct FolderJobPreviewView: View {
    let file: FolderJobFile
    let open: () -> Void

    var body: some View {
        let preview = FolderJobPreviewCache.shared.preview(file)
        VStack(alignment: .leading, spacing: 7) {
            Text(String(file.path.dropFirst(FolderJobFiles.preview.count + 1))).font(.system(size: 13, weight: .semibold))
            switch preview {
            case .table(let rows, _):
                if rows.isEmpty { Text("It's empty.").font(.system(size: 12)).foregroundStyle(Pad.inkSoft) }
                else { FolderJobTable(rows: rows) }
            case .text(let text, _):
                Text(text.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)).font(.system(size: 12)).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
            case .unreadable(let why):
                Text("\(file.name) can't be shown: \(why)").font(.system(size: 12)).foregroundStyle(Pad.redInk)
            }
            if let more = FolderJobPreview.more(preview) {
                Button(more, action: open).buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Pad.penInk)
            }
        }
    }
}

/// A table as its file has it: the first row as the heading, each cell on up to three lines. A table wider than the
/// page scrolls sideways, with its scroll bar always showing and a line under it that says so, rather than cutting off
/// its last columns.
struct FolderJobTable: View {
    let rows: [[String]]
    /// Columns drawn; a wider table is opened in its app.
    static let columnLimit = 30

    var body: some View {
        ViewThatFits(in: .horizontal) {
            framed(grid)
            VStack(alignment: .leading, spacing: 5) {
                framed(ScrollView(.horizontal) { grid }.scrollIndicators(.visible))
                Text(Self.wideLine(columns: width)).font(.system(size: 11)).foregroundStyle(Pad.inkSoft)
            }
        }
    }

    private var width: Int { min(Self.columnLimit, rows.map(\.count).max() ?? 0) }

    /// Under a table too wide for the page: "Scroll sideways for all 6 columns."
    static func wideLine(columns: Int) -> String { "Scroll sideways for all \(columns) columns." }

    private func framed(_ content: some View) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Pad.tabEdge.opacity(0.5)))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var grid: some View {
        let width = self.width
        return Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(0..<width, id: \.self) { column in
                        Text(column < row.count ? row[column] : "")
                            .font(.system(size: 12, weight: index == 0 ? .semibold : .regular)).lineLimit(3)
                            .frame(minWidth: 40, maxWidth: 240, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .textSelection(.enabled)
                    }
                }
                .background(index == 0 ? Pad.paperTop.opacity(0.8) : index.isMultiple(of: 2) ? Color.white.opacity(0.4) : Color.white.opacity(0.75))
            }
        }.fixedSize(horizontal: true, vertical: false)
    }
}

/// Previews read once per version of their file, so a page drawn again doesn't read them again.
@MainActor
final class FolderJobPreviewCache {
    static let shared = FolderJobPreviewCache()
    private var cache: [String: FolderJobPreview] = [:]

    func preview(_ file: FolderJobFile) -> FolderJobPreview {
        let key = "\(file.url.path)|\(file.size)|\(file.modifiedAt.timeIntervalSince1970)"
        if let hit = cache[key] { return hit }
        if cache.count > 40 { cache = [:] }
        let preview = FolderJobPreview.read(file)
        cache[key] = preview
        return preview
    }
}

/// Files to take away: each with its kind's icon, its path and size, and Open (for kinds that open without running
/// anything), Save as… and Show in Finder.
struct FolderJobFilesList: View {
    let files: [FolderJobFile]
    var more = 0
    var actions = CardFileActions()
    var report: (_ message: String, _ problem: Bool) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(files) { file in
                FileRow(icon: CardFiles.icon(file.name), name: file.path, size: CardFiles.size(file.size),
                        open: file.opens ? { if !actions.open(file.url) { report("No app on this Mac opened \(file.name).", true) } } : nil,
                        save: { save(file) }, reveal: { actions.reveal(file.url) })
            }
            if more > 0 {
                Text("…and \(more) more \(more == 1 ? "file" : "files"). Show in Finder for all of them.")
                    .font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
            }
        }
    }

    private func save(_ file: FolderJobFile) {
        guard let target = actions.destination(file.name) else { return }
        guard target.standardizedFileURL != file.url.standardizedFileURL else { return }
        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }   // the save panel asked first
            try manager.copyItem(at: file.url, to: target)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            report("Saved a copy of \(file.name) in \(target.deletingLastPathComponent().lastPathComponent).", false)
        } catch {
            report("\(file.name) couldn't be saved: \(error.localizedDescription)", true)
        }
    }
}

/// One file to take away, as a card's Files section and a job's page show it: its kind's icon, its name and size, and
/// Open, Save as… and Show in Finder. Without `open`, it isn't offered.
struct FileRow: View {
    let icon: String
    let name: String
    let size: String
    var open: (() -> Void)?
    let save: () -> Void
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Pad.inkSoft).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle).help(name)
                Text(size).font(.system(size: 11)).foregroundStyle(Pad.inkSoft)
            }
            Spacer(minLength: 8)
            HStack(spacing: 14) {
                if let open { Button("Open", action: open).accessibilityLabel("Open \(name)") }
                Button("Save as…", action: save).accessibilityLabel("Save a copy of \(name)")
                Button("Show in Finder", action: reveal).accessibilityLabel("Show \(name) in Finder")
            }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Pad.penInk).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
    }
}

/// The line on a job's folder in Morning Files: when it last ran and how often, Run now, and Open job.
struct FolderJobFolderLine: View {
    @ObservedObject var store: FolderJobStore
    @ObservedObject var runner: FolderJobRunner
    let jobID: UUID
    let openJob: () -> Void
    var now: () -> Date = Date.init

    var body: some View {
        if let job = store.job(id: jobID) {
            HStack(spacing: 6) {
                Image(systemName: "folder").foregroundStyle(Pad.inkSoft)
                Text(FolderJobWords.folderLine(job, running: runner.running == job.id, now: now())).foregroundStyle(Pad.inkSoft)
                if job.running(at: now()) && !runner.isBusy(job.id) {
                    Text("·").foregroundStyle(Pad.inkSoft)
                    Button("Run now") { runner.run(job.id) }
                }
                Text("·").foregroundStyle(Pad.inkSoft)
                Button("Open job", action: openJob).help("Open this job’s page, with its input and its latest result")
                Spacer(minLength: 0)
            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
            if let receipt = runner.receipt, receipt.jobID == job.id { FolderJobReceiptLine(receipt: receipt, dismiss: runner.dismissReceipt) }
        }
    }
}

/// What a Run now came to, until it's dismissed: one line, and a way to put it away.
struct FolderJobReceiptLine: View {
    let receipt: FolderJobReceipt
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(receipt.text).font(.system(size: 12)).foregroundStyle(Pad.penInk).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Pad.inkSoft)
                .accessibilityLabel("Dismiss")
        }.padding(10).background(Pad.paperTop.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
    }
}
