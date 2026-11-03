import Combine
import Foundation

/// The buttons on a job's cards that run its own code. A card its job.py wrote names a function of that job.py and its
/// arguments (`run` and `args` in one of its `actions`); pressing the button runs that function, as the person, with
/// the job's secrets, its input folder, its folder in the cards inbox and its imports. Which job.py is the job whose
/// cards folder holds the card, never anything the card says, and the function must be one that job.py defines itself:
/// a card written from data the job doesn't control can choose only among its own job's buttons. Presses don't wait
/// behind the jobs' runs; each card runs one at a time. What a press came to stays on its card, and a function that
/// rewrites or deletes its card's file changes or resolves the card at once.
@MainActor
final class FolderJobButtons: ObservableObject {
    /// The cards with a button running, by card, with which button.
    @Published private(set) var pressing: [UUID: String] = [:]
    let store: FolderJobStore
    private let execute: FolderJobRunner.Execute
    private let now: () -> Date
    /// Folders a job.py may import from, asked at each press.
    var importPaths: () -> [URL] = { [] }
    var hasSecret: (String) -> Bool = { Secrets.has($0) || ProcessInfo.processInfo.environment[$0] != nil }
    /// Keeps what a press came to on its card.
    var record: ((UUID, CardPress) -> Void)?
    /// After a press: the app looks at the cards inbox, where the function may have changed or deleted its card's file.
    var onCardsChanged: (() -> Void)?

    /// How long one press may take.
    static let timeLimit: TimeInterval = 120

    init(store: FolderJobStore, execute: @escaping FolderJobRunner.Execute, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.execute = execute
        self.now = now
    }

    /// The job whose job.py wrote this card into its own folder, when exactly one job has that folder.
    func job(for card: MorningCard) -> FolderJob? {
        guard let source = card.inbox?.key.split(separator: "/").first.map(String.init),
              source.hasPrefix(FolderJobCards.scriptPrefix) else { return nil }
        let jobs = store.jobs.filter { FolderJobCards.scriptSource(for: $0) == source }
        return jobs.count == 1 ? jobs[0] : nil
    }

    /// Why the card's buttons that run its job's code can't now, in one line; nil when they can.
    func unavailable(_ card: MorningCard) -> String? {
        guard let job = job(for: card) else { return "Its job isn't here any more, so this button can't run." }
        if job.isTeam && !job.on { return "Turn its job on in Jobs to use this button." }
        switch job.phase(at: now()) {
        case .upcoming: return "Its job hasn't started yet, so this button can't run."
        case .ended: return "Its job has ended, so this button can't run."
        case .live: break
        }
        let missing = job.requires.filter { !hasSecret($0) }
        return missing.isEmpty ? nil : Jobs.needs(missing)
    }

    /// Runs the button's function and keeps what came of it on the card.
    func press(_ card: MorningCard, _ action: CardInboxAction) async {
        guard let function = action.run, pressing[card.id] == nil else { return }
        let said: String
        var failed = true
        if let why = unavailable(card) {
            said = why
        } else if let job = job(for: card), let folder = store.folder(for: job),
                  FileManager.default.fileExists(atPath: folder.appendingPathComponent(FolderJobFiles.entry).path) {
            pressing[card.id] = action.id
            let run = FolderJobRun(job: job, folder: folder, input: folder.appendingPathComponent(FolderJobFiles.input), output: store.output(for: job),
                                   cardsSource: FolderJobCards.scriptSource(for: job), importPaths: importPaths(), timeout: Self.timeLimit,
                                   function: function, args: action.args)
            do {
                said = FolderJobRunner.said(try await execute(run)) ?? "Done."
                failed = false
            } catch {
                said = Self.reason(error)
            }
            pressing[card.id] = nil
        } else {
            said = "Its job.py isn't there any more."
        }
        Log.info("jobs: \(card.inbox?.key ?? "a card")'s button \(function)() " + (failed ? "didn't run: \(said)" : "ran"))
        record?(card.id, CardPress(label: action.label, at: now(), said: said, failed: failed))
        onCardsChanged?()
    }

    /// Why a press failed, in its first line.
    static func reason(_ error: Error) -> String {
        if let error = error as? ScriptRunnerError, error.timedOut { return "It took longer than \(Int(timeLimit / 60)) minutes, so it was stopped." }
        return FolderJobRunner.reason(error)
    }
}
