import Foundation
import SwiftUI

/// What came of the deck, for the person to read any time: today's tally, the matters they took (Yours), what Noteling
/// did for them, what they put away, and when each job last looked. Read from the memory log and the matters; nothing
/// is kept for it.
struct Receipt: Equatable {
    /// One thing Noteling did: the card, the action, when, and what the press came to.
    struct Done: Equatable, Identifiable {
        var id: String { matter + "·" + label + "·" + MemoryLog.stamp(at, in: .current) }
        let matter: String
        let headline: String
        let label: String
        let at: Date
        var said: String?
        var failed = false
    }
    /// When a job last looked.
    /// A card whose next step the person took into the chat.
    struct Handed: Equatable, Identifiable {
        var id: String { matter + "·" + step }
        var matter: String
        var headline: String
        var step: String
        var at: Date
    }

    struct Looked: Equatable, Identifiable {
        var id: String { job }
        let job: String
        let name: String
        let at: Date
    }

    var day: Date
    /// Noteling did it: presses that ran after a Do it.
    var did: [Done] = []
    /// What the person stamped today, Do it included, Undo not.
    var decided = 0
    var undone = 0
    /// The matters the person took, newest first.
    var yours: [Matter] = []
    /// The matters the person put away, newest first.
    var putAway: [Matter] = []
    /// The next steps taken into the chat today, newest first.
    var handed: [Handed] = []
    var looked: [Looked] = []
    /// Notes made today by jobs, for the rows they mark as notes (`JobNotes`).
    var noted = 0

    static let listLimit = 30

    /// Today, as the log and the matters have it.
    @MainActor static func today(log: MemoryLog?, matters: Matters, now: Date, calendar: Calendar = .current) -> Receipt {
        var receipt = Receipt(day: calendar.startOfDay(for: now))
        let lines = log?.lines(on: now) ?? []
        var lastLooked: [String: Looked] = [:]
        for line in lines {
            guard let stamp = line["t"] as? String, let at = JobMoment.parse(stamp)?.date else { continue }
            if let verdict = line["stamp"] as? String {
                switch verdict {
                case "do":
                    if let label = line["did"] as? String, let id = line["matter"] as? String {
                        let matter = matters.matter(id: id)
                        let press = matter?.presses.last { $0.label == label }
                        receipt.did.append(Done(matter: id, headline: matter?.view?.headline ?? matter?.view?.text ?? matter?.jobName ?? id,
                                                label: label, at: at, said: press?.said, failed: press?.failed ?? false))
                        receipt.decided += 1
                    }
                case "mine", "not now": receipt.decided += 1
                case "next":
                    if let step = line["step"] as? String, let id = line["matter"] as? String {
                        let matter = matters.matter(id: id)
                        receipt.handed.append(Handed(matter: id, headline: matter?.view?.headline ?? matter?.view?.text ?? matter?.jobName ?? id, step: step, at: at))
                        receipt.decided += 1
                    }
                case "undo": receipt.undone += 1
                default: break
                }
            }
            if line["ran"] != nil, let job = line["job"] as? String {
                lastLooked[job] = Looked(job: job, name: line["name"] as? String ?? job, at: at)
            }
            if line["note"] != nil, line["made"] != nil { receipt.noted += 1 }
        }
        receipt.did.reverse()
        receipt.handed.reverse()
        receipt.yours = matters.all.filter { $0.state == .yours }.sorted { $0.updatedAt > $1.updatedAt }
        receipt.putAway = Array(matters.all.filter { $0.state == .quiet && $0.why == Matter.putAway }.sorted { $0.updatedAt > $1.updatedAt }.prefix(listLimit))
        receipt.looked = lastLooked.values.sorted { $0.at > $1.at }
        return receipt
    }

    var isEmpty: Bool { did.isEmpty && decided == 0 && yours.isEmpty && putAway.isEmpty && handed.isEmpty && noted == 0 }

    /// "Noteling did 2 · you decided 5", "Nothing came through the deck today."
    var tally: String {
        guard did.count > 0 || decided > 0 || noted > 0 else { return "Nothing came through the deck today." }
        var parts = ["Noteling did \(did.count)", "you decided \(decided)"]
        if undone > 0 { parts.append("\(undone) taken back") }
        if noted > 0 { parts.append("\(noted) on your notes") }
        return parts.joined(separator: " · ")
    }

    /// "Pages up 2 min ago · Orders 1 h ago", the newest first, three at most; nil with none.
    func lookedLine(now: Date) -> String? {
        guard !looked.isEmpty else { return nil }
        return looked.prefix(3).map { "\($0.name) \(JobWords.time($0.at, now: now))" }.joined(separator: " · ")
    }
}

/// The receipt's page in the Jobs window: the tally, when each job last looked, and the lists.
struct ReceiptPage: View {
    @ObservedObject var matters: Matters
    var log: MemoryLog?
    var lessons: Lessons?
    var now: () -> Date = Date.init
    /// Opens a matter's page.
    var open: (String) -> Void = { _ in }

    var body: some View {
        let now = now()
        let receipt = Receipt.today(log: log, matters: matters, now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(receipt.tally).font(HandFont.font(size: 22)).fixedSize(horizontal: false, vertical: true)
                if let looked = receipt.lookedLine(now: now) {
                    Text("Last looked: " + looked).font(.system(size: 12)).foregroundStyle(Pad.inkSoft).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No job has looked today.").font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                }
                if !receipt.yours.isEmpty {
                    FolderJobSection(title: "Yours", icon: "hand.raised") {
                        ForEach(receipt.yours) { matter in row(matter, line: "On a note of your own · " + JobWords.time(matter.updatedAt, now: now)) }
                    }
                }
                if !receipt.handed.isEmpty {
                    FolderJobSection(title: "Next steps", icon: "arrow.turn.down.right") {
                        ForEach(receipt.handed) { handed in
                            Button { open(handed.matter) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(handed.headline).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                    Text(handed.step + " · handed to the chat · " + JobWords.time(handed.at, now: now)).font(.system(size: 12)).foregroundStyle(Pad.inkSoft).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if !receipt.did.isEmpty {
                    FolderJobSection(title: "Done by Noteling", icon: "checkmark.circle") {
                        ForEach(receipt.did) { done in
                            Button { open(done.matter) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(done.headline).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                    Text([done.label, JobWords.time(done.at, now: now), done.said.map { JobWords.clip($0, 120) }].compactMap { $0 }.joined(separator: " · "))
                                        .font(.system(size: 12)).foregroundStyle(done.failed ? Pad.redInk : Pad.inkSoft).lineLimit(3)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if !receipt.putAway.isEmpty {
                    FolderJobSection(title: "Put away", icon: "moon.zzz") {
                        ForEach(receipt.putAway) { matter in row(matter, line: "Comes back if something about it changes · " + JobWords.time(matter.updatedAt, now: now)) }
                    }
                }
                FolderJobSection(title: "Taught", icon: "graduationcap") {
                    if let lessons { TaughtList(lessons: lessons, now: now) } else { TaughtList.nothingYet }
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ matter: Matter, line: String) -> some View {
        Button { open(matter.id) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(matter.view?.headline ?? matter.view?.text ?? matter.jobName).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Text(line).font(.system(size: 12)).foregroundStyle(Pad.inkSoft).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// What the person taught, each with Forget; or that nothing was taught yet and how it comes about.
struct TaughtList: View {
    @ObservedObject var lessons: Lessons
    var now: Date

    static let nothingYet = Text("Nothing yet. Put away two cards from one job within a week and the minister asks whether to stop showing its findings; or tell the chat a standing rule for your cards, in your words.")
        .font(.system(size: 12)).foregroundStyle(Pad.inkSoft)

    var body: some View {
        if lessons.all.isEmpty && lessons.told.isEmpty {
            Self.nothingYet.fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(lessons.told) { told in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("“" + told.text + "”").font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                        Text("Told " + JobWords.time(told.at, now: now)).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                    }
                    Spacer(minLength: 8)
                    Button("Forget") { lessons.forget(instruction: told.id) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
                        .help("The minister stops following it")
                }
            }
            ForEach(lessons.all) { lesson in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lesson.words).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                        Text("Since " + JobWords.time(lesson.at, now: now)).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                    }
                    Spacer(minLength: 8)
                    Button("Forget") { lessons.forget(job: lesson.job) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
                        .help("The minister shows its findings again as it sees fit")
                }
            }
        }
    }
}
