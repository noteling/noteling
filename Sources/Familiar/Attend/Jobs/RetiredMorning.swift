import Foundation

/// What earlier versions kept for the Morning folder and the reading jobs, which Noteling no longer reads or writes:
/// the cards inbox and the files cards carried (`cards/`), the attention test (`attention/`), the reading jobs
/// (`calendar/`) and their run archive, everything their scripts read (`runs/`). Deleted once, at launch; one that
/// can't be deleted is said in the log and tried again next time. The Morning folder's own database (`morning/`), with
/// the notes a person wrote there and the Who's Who they kept, is left for them.
enum RetiredMorning {
    static let folders = ["cards", "attention", "calendar", "runs"]

    /// Deletes what is there, and says which folders went.
    @discardableResult
    static func cleanUp(home: URL) -> [String] {
        let manager = FileManager.default
        var removed: [String] = []
        for name in folders {
            let folder = home.appendingPathComponent(name)
            guard manager.fileExists(atPath: folder.path) else { continue }
            do {
                try manager.removeItem(at: folder)
                removed.append(name)
            } catch {
                Log.info("couldn't delete \(name)/, left by an earlier version: \(error.localizedDescription)")
            }
        }
        if !removed.isEmpty { Log.info("deleted what earlier versions kept: \(removed.joined(separator: ", "))") }
        return removed
    }
}
