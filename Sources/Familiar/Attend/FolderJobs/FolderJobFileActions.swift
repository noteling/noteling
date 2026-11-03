import AppKit
import UniformTypeIdentifiers

/// What a job's page does with one of the files its run left: open it in its default app, save a copy where the person
/// picks, or show it in Finder. NSWorkspace and the save panel sit behind these seams, so tests and renders open nothing.
@MainActor
struct JobFileActions {
    /// Opens a file in its default app; false when nothing could.
    var open: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    /// Shows a file, selected, in Finder.
    var reveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    /// Asks where to save a copy, with the file's name filled in; nil when the person cancels.
    var destination: (String) -> URL? = { JobFileActions.askWhereToSave($0) }

    static func askWhereToSave(_ name: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let type = UTType(filenameExtension: (name as NSString).pathExtension) { panel.allowedContentTypes = [type] }
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Small words for a file on a job's page: its kind's icon, and its size as Finder counts it.
enum JobFileWords {
    /// The kinds of file that open in their app without running anything.
    static let kinds = ["csv", "tsv", "txt", "json", "md", "log", "xlsx", "pdf", "png", "jpg", "jpeg", "gif", "heic"]

    /// "620 MB", "1.2 MB", "820 KB", "12 bytes": counted as Finder does, 1,000 bytes to a KB.
    static func size(_ bytes: Int64) -> String {
        func number(_ value: Double, digits: Int) -> String {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.maximumFractionDigits = digits
            return formatter.string(from: NSNumber(value: value)) ?? String(value)
        }
        if bytes < 1_000 { return bytes == 1 ? "1 byte" : "\(max(0, bytes)) bytes" }
        if bytes < 999_500 { return number(Double(bytes) / 1e3, digits: 0) + " KB" }
        if bytes < 999_950_000 { return number(Double(bytes) / 1e6, digits: 1) + " MB" }
        return number(Double(bytes) / 1e9, digits: 2) + " GB"
    }

    /// The symbol a file's kind shows with.
    static func icon(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "csv", "tsv", "xlsx": return "tablecells"
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "heic": return "photo"
        default: return "doc.text"
        }
    }
}
