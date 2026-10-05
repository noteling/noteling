import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What a card's Files section does with one of its files: open it in its default app, save a copy where the person
/// picks, or show it in Finder. NSWorkspace and the save panel sit behind these seams, so tests open nothing. Only the
/// card's own copy is ever used: a plain file in its folder in `cards/files/`, of a kind a card may carry.
@MainActor
struct CardFileActions {
    /// Where cards keep their files.
    var root = CardFiles.root
    /// Opens a file in its default app; false when nothing could.
    var open: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    /// Shows a file, selected, in Finder.
    var reveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    /// Asks where to save a copy, with the file's name filled in; nil when the person cancels.
    var destination: (String) -> URL? = { CardFileActions.askWhereToSave($0) }

    /// The card's copy of one of its files, or why it can't be used.
    func location(of file: CardFile, on card: MorningCard) throws -> URL {
        guard card.files.contains(file), CardFiles.refusal(file.name) == nil else {
            throw CardInboxError("This card doesn't carry \(CardFiles.shown(file.name)).")
        }
        let url = CardFiles.folder(for: card.id, in: root).appendingPathComponent(file.name)
        guard (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeRegular else {
            throw CardInboxError("\(CardFiles.shown(file.name)) isn't in Noteling's folder any more. It comes back when its card is written again.")
        }
        return url
    }

    func open(_ file: CardFile, on card: MorningCard) throws {
        guard open(try location(of: file, on: card)) else { throw CardInboxError("No app on this Mac opened \(CardFiles.shown(file.name)).") }
    }

    /// Copies the file where the person picks, and returns where; nil when they cancel. The copy is theirs to change.
    func saveCopy(_ file: CardFile, of card: MorningCard) throws -> URL? {
        let url = try location(of: file, on: card)
        guard let target = destination(file.name) else { return nil }
        guard target.standardizedFileURL != url.standardizedFileURL else { return target }
        let manager = FileManager.default
        if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }   // the save panel asked first
        try manager.copyItem(at: url, to: target)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        return target
    }

    func showInFinder(_ file: CardFile, on card: MorningCard) throws {
        reveal(try location(of: file, on: card))
    }

    /// The save panel, above the floating Morning panel, with the file's name filled in.
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

/// A card's Files section: each file it carries, with its kind's icon, its name and size, and Open, Save as… and
/// Show in Finder; then a plain note for each file its card file listed that wasn't attached.
struct CardFilesSection: View {
    let card: MorningCard
    var actions: CardFileActions
    /// What to tell the person: a problem, or where a copy was saved.
    var report: (_ message: String, _ problem: Bool) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Files", systemImage: "paperclip").font(.system(size: 12, weight: .semibold)).foregroundStyle(Pad.inkSoft)
            ForEach(card.files) { file in row(file) }
            ForEach(card.inbox?.fileNotes ?? [], id: \.self) { note in
                Label(note, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Pad.redInk)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }

    private func row(_ file: CardFile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: CardFiles.icon(file.name)).font(.system(size: 16)).foregroundStyle(Pad.inkSoft).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle).help(file.name)
                Text(CardFiles.size(file.size)).font(.system(size: 11)).foregroundStyle(Pad.inkSoft)
            }
            Spacer(minLength: 8)
            HStack(spacing: 14) {
                Button("Open") { open(file) }.accessibilityLabel("Open \(file.name)")
                Button("Save as…") { saveCopy(file) }.accessibilityLabel("Save a copy of \(file.name)")
                Button("Show in Finder") { showInFinder(file) }.accessibilityLabel("Show \(file.name) in Finder")
            }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Pad.penInk).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
    }

    func open(_ file: CardFile) { perform { try actions.open(file, on: card) } }

    func saveCopy(_ file: CardFile) {
        perform {
            guard let saved = try actions.saveCopy(file, of: card) else { return }
            report("Saved a copy of \(file.name) in \(saved.deletingLastPathComponent().lastPathComponent).", false)
        }
    }

    func showInFinder(_ file: CardFile) { perform { try actions.showInFinder(file, on: card) } }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { report(error.localizedDescription, true) }
    }
}
