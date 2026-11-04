import SwiftUI

/// What became of a job's findings, on its page: the minister's receipt. "3 findings: 1 on a sticker, 2 kept quiet",
/// then each finding with its verdict and why; one with a matter opens it. This is what a developer sees happened to
/// their work, and what tells a person that an empty screen was a judgment, not a failure.
@MainActor
enum FindingVerdicts {
    enum Verdict: Equatable {
        /// Open, its sticker on the screen.
        case shown(urgent: Bool)
        /// Open, its sticker not written yet.
        case waiting
        /// Kept in memory: the minister's reason, or that the person put it away or its time passed.
        case quiet(String?)
        /// No matter yet: the minister hasn't seen it, or couldn't judge it.
        case unjudged
    }

    struct Line: Equatable, Identifiable {
        /// The finding's id, as the job reported it.
        var id: String
        var label: String
        var verdict: Verdict
        /// Its matter, to open.
        var matter: String?
    }

    /// Lines on the page before "and N more".
    static let lineLimit = 12
    static let labelLimit = 90

    /// Each finding the job last reported, with its verdict: on stickers first (urgent ones before the rest), then
    /// waiting for a sticker, then not judged yet, then kept quiet; within a group the newest first.
    static func lines(for job: FolderJob, snapshot: FindingsSnapshot, matters: Matters, now: Date) -> [Line] {
        let judged = snapshot.rows.values.map { kept -> (line: Line, seen: Date) in
            let matter = matters.matter(containing: FindingRef(job: job, id: kept.row.id))
            return (Line(id: kept.row.id, label: label(kept.row, map: job.map), verdict: verdict(matter, now: now), matter: matter?.id), kept.firstSeen)
        }
        return judged.sorted { a, b in
            let ra = rank(a.line.verdict), rb = rank(b.line.verdict)
            if ra != rb { return ra < rb }
            if a.seen != b.seen { return a.seen > b.seen }
            return a.line.id < b.line.id
        }.map(\.line)
    }

    private static func rank(_ verdict: Verdict) -> Int {
        switch verdict {
        case .shown(let urgent): return urgent ? 0 : 1
        case .waiting: return 2
        case .unjudged: return 3
        case .quiet: return 4
        }
    }

    /// A matter's state as its finding's verdict; no matter means the minister hasn't judged it.
    static func verdict(_ matter: Matter?, now: Date) -> Verdict {
        guard let matter else { return .unjudged }
        switch matter.state {
        case .open:
            if matter.isShown(at: now) { return .shown(urgent: matter.isUrgent) }
            return matter.view == nil ? .waiting : .quiet(Matter.timePassed)
        case .quiet: return .quiet(matter.why)
        case .closed: return .unjudged   // a closed matter has no findings left, so this isn't reached
        }
    }

    /// A finding in a few words, from the job's map: whom it is about and what it says ("Lena Park · Deck by 3?"), the
    /// id first when nothing says whom ("K-1 · price shows 18.99"); the id alone without a map.
    static func label(_ row: FindingRow, map: FindingsMap?) -> String {
        var parts: [String] = []
        if let map {
            parts += map.about(of: row)
            if let what = map.what.flatMap({ row.text($0) })?.trimmingCharacters(in: .whitespacesAndNewlines), !what.isEmpty { parts.append(what) }
        }
        if map?.about(of: row).isEmpty ?? true { parts.insert(row.id, at: 0) }
        let text = parts.map { $0.split(whereSeparator: \.isNewline).joined(separator: " ") }.filter { !$0.isEmpty }.joined(separator: " · ")
        return JobWords.clip(text.isEmpty ? row.id : text, labelLimit)
    }

    /// "3 findings: 1 on a sticker, 2 kept quiet"; "1 finding: kept quiet"; "4 findings: all kept quiet"; nil with none.
    static func summary(_ lines: [Line]) -> String? {
        guard !lines.isEmpty else { return nil }
        var shown = 0, waiting = 0, unjudged = 0, quiet = 0
        for line in lines {
            switch line.verdict {
            case .shown: shown += 1
            case .waiting: waiting += 1
            case .unjudged: unjudged += 1
            case .quiet: quiet += 1
            }
        }
        let total = lines.count
        func part(_ n: Int, one: String, many: String, all: String) -> String? {
            guard n > 0 else { return nil }
            if total == 1 { return one }
            if n == total { return all }
            return n == 1 ? "1 " + one : "\(n) " + many
        }
        let parts = [part(shown, one: "on a sticker", many: "on stickers", all: "all on stickers"),
                     part(waiting, one: "waiting for its sticker", many: "waiting for their stickers", all: "all waiting for their stickers"),
                     part(unjudged, one: "not judged yet", many: "not judged yet", all: "none judged yet"),
                     part(quiet, one: "kept quiet", many: "kept quiet", all: "all kept quiet")].compactMap { $0 }
        return (total == 1 ? "1 finding: " : "\(total) findings: ") + parts.joined(separator: ", ")
    }

    /// "and 3 more" under the lines past the limit; nil when they all fit.
    static func more(_ lines: [Line]) -> String? {
        let rest = lines.count - lineLimit
        return rest > 0 ? "and \(rest) more" : nil
    }

    /// Each verdict in words, beside its finding.
    static func words(_ verdict: Verdict) -> String {
        switch verdict {
        case .shown(let urgent): return urgent ? "On a sticker, urgent" : "On a sticker"
        case .waiting: return "Its sticker is being written"
        case .quiet(let why): return "Kept quiet: " + (why ?? "no reason kept.")
        case .unjudged: return "Not judged yet"
        }
    }

    /// The symbol before each line: a note on a sticker (an exclamation mark when urgent), an hourglass while it waits,
    /// a dotted circle before judgment, a moon when kept quiet, as the matter's page has it.
    static func symbol(_ verdict: Verdict) -> String {
        switch verdict {
        case .shown(let urgent): return urgent ? "exclamationmark.circle" : "note.text"
        case .waiting: return "hourglass"
        case .quiet: return "moon.zzz"
        case .unjudged: return "circle.dotted"
        }
    }
}

/// The minister's receipt on a job's page: the summary line, then each finding with its verdict; one with a matter opens it.
struct FindingVerdictsView: View {
    @ObservedObject var matters: Matters
    let store: FolderJobStore
    let job: FolderJob
    var now: () -> Date = Date.init
    var open: ((String) -> Void)?

    var body: some View {
        let lines = FindingVerdicts.lines(for: job, snapshot: FindingsSnapshot.read(store.findingsFile(for: job)), matters: matters, now: now())
        if let summary = FindingVerdicts.summary(lines) {
            VStack(alignment: .leading, spacing: 6) {
                Text(summary).font(.system(size: 12, weight: .medium)).foregroundStyle(Pad.ink)
                ForEach(lines.prefix(FindingVerdicts.lineLimit)) { line in
                    if let matter = line.matter, let open {
                        Button { open(matter) } label: { row(line) }.buttonStyle(.plain).help("Open it")
                    } else {
                        row(line)
                    }
                }
                if let more = FindingVerdicts.more(lines) { Text(more).font(.system(size: 12)).foregroundStyle(Pad.inkSoft) }
            }
        }
    }

    private func row(_ line: FindingVerdicts.Line) -> some View {
        let urgent = line.verdict == .shown(urgent: true)
        return HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: FindingVerdicts.symbol(line.verdict)).font(.system(size: 11)).foregroundStyle(urgent ? Pad.redInk : Pad.inkSoft).frame(width: 14)
            Text(line.label).font(.system(size: 12)).foregroundStyle(Pad.ink).lineLimit(1)
            Text(FindingVerdicts.words(line.verdict)).font(.system(size: 12)).foregroundStyle(urgent ? Pad.redInk : Pad.inkSoft).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.contentShape(Rectangle())
    }
}
