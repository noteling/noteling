import Combine
import Foundation

/// What pressing a finding's button came to: the button, when, what the function said, and whether it failed. Kept on
/// the finding's matter.
struct FindingPress: Equatable, Codable {
    var label: String
    var at: Date
    var said: String
    var failed: Bool
}

/// The buttons on a job's findings, which run its own code. A job's `job.json` names its actions: each a function of
/// its `job.py` with arguments filled from the finding's row. Pressing one runs that function, as the person, with the
/// job's secrets, its input folder and its imports. Which job.py is the job that reported the finding, never anything a
/// row says, and the function must be one that job.py defines itself. Presses don't wait behind the jobs' runs; each
/// finding runs one at a time.
@MainActor
final class FolderJobButtons: ObservableObject {
    /// The findings with a button running, by finding (`FolderJobButtons.key`), with which button.
    @Published private(set) var pressing: [String: String] = [:]
    let store: FolderJobStore
    private let execute: FolderJobRunner.Execute
    private let now: () -> Date
    /// Folders a job.py may import from, asked at each press.
    var importPaths: () -> [URL] = { [] }
    var hasSecret: (String) -> Bool = { Secrets.has($0) || ProcessInfo.processInfo.environment[$0] != nil }
    /// What a press came to, for whoever shows the finding and for the log.
    var record: ((FolderJob, FindingRow, FolderJobAction, FindingPress) -> Void)?

    /// How long one press may take.
    static let timeLimit: TimeInterval = 120

    init(store: FolderJobStore, execute: @escaping FolderJobRunner.Execute, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.execute = execute
        self.now = now
    }

    /// A finding's key: its job and its id, as the log names them.
    nonisolated static func key(_ job: FolderJob, _ row: FindingRow) -> String { MemoryLog.name(of: job) + "/" + row.id }

    /// Why the job's buttons can't run now, in one line; nil when they can.
    func unavailable(_ job: FolderJob) -> String? {
        guard let current = store.job(id: job.id) else { return "Its job isn't here any more, so this button can't run." }
        if current.isTeam && !current.on { return "Turn its job on in Jobs to use this button." }
        switch current.phase(at: now()) {
        case .upcoming: return "Its job hasn't started yet, so this button can't run."
        case .ended: return "Its job has ended, so this button can't run."
        case .live: break
        }
        let missing = current.requires.filter { !hasSecret($0) }
        return missing.isEmpty ? nil : Jobs.needs(missing)
    }

    /// Runs the button's function for the finding's row, and says what came of it.
    @discardableResult
    func press(_ job: FolderJob, _ action: FolderJobAction, for row: FindingRow) async -> FindingPress {
        let key = Self.key(job, row)
        let said: String
        var failed = true
        if pressing[key] != nil {
            said = "A button of this finding is still running."
        } else if let why = unavailable(job) {
            said = why
        } else if let current = store.job(id: job.id), current.actions.contains(action), let folder = store.folder(for: current),
                  FileManager.default.fileExists(atPath: folder.appendingPathComponent(FolderJobFiles.entry).path) {
            pressing[key] = action.id
            let arguments = JSONText.pretty(action.arguments(for: row), indent: "")
            let run = FolderJobRun(job: current, folder: folder, input: folder.appendingPathComponent(FolderJobFiles.input),
                                   output: store.output(for: current), importPaths: importPaths(), timeout: Self.timeLimit,
                                   function: action.run, args: arguments)
            do {
                said = FolderJobRunner.said(try await execute(run)) ?? "Done."
                failed = false
            } catch {
                said = Self.reason(error)
            }
            pressing[key] = nil
        } else if store.job(id: job.id)?.actions.contains(action) == false {
            said = "Its job no longer has this button."
        } else {
            said = "Its job.py isn't there any more."
        }
        Log.info("jobs: \(key)'s button \(action.run)() " + (failed ? "didn't run: \(said)" : "ran"))
        let press = FindingPress(label: action.label, at: now(), said: said, failed: failed)
        record?(job, row, action, press)
        return press
    }

    /// Why a press failed, in its first line.
    static func reason(_ error: Error) -> String {
        if let error = error as? ScriptRunnerError, error.timedOut { return "It took longer than \(Int(timeLimit / 60)) minutes, so it was stopped." }
        return FolderJobRunner.reason(error)
    }
}
