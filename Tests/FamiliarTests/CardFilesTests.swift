import Foundation
import SwiftUI
import Testing
@testable import Familiar

/// A card carries files: the names its card file lists under `files`, of files its script wrote beside it. Noteling
/// copies them into its own folder when it reads a new version of the card file, keeps only the latest set, and says in
/// plain words why a file wasn't attached. The Files section opens, saves and shows them through seams, so nothing is
/// opened here. Temp folders only.
@Suite @MainActor
struct CardFilesTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)
    private let written = Date(timeIntervalSince1970: 1_789_990_000)

    /// A file a script wrote beside its card files.
    @discardableResult
    private func put(_ fixture: InboxFixture, _ source: String, _ name: String, _ text: String, modified: Date? = nil) throws -> URL {
        let folder = fixture.directory.appendingPathComponent(source)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: modified ?? written], ofItemAtPath: file.path)
        return file
    }

    /// A card's own folder of files, `cards/files/<card id>/`.
    private func stored(_ fixture: InboxFixture, _ key: String) -> URL {
        CardFiles.folder(for: CardInboxFormat.cardID(key), in: fixture.root.appendingPathComponent("cards/files"))
    }

    private func permissions(_ url: URL) throws -> Int? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    }

    // MARK: taking them in

    @Test func aCardCarriesTheFilesItsFileListsAsNotelingsOwnCopies() throws {
        let fixture = InboxFixture()
        defer { fixture.remove() }
        let table = "item,price\r\n123,12\r\n", report = "%PDF-1.4 fictional"
        try put(fixture, "pack-shop", "problems.csv", table)
        try put(fixture, "pack-shop", "report.pdf", report, modified: written.addingTimeInterval(60))
        try put(fixture, "pack-shop", "notes.txt", "not listed")
        try fixture.write("pack-shop", "refunds", #"{"title": "2 refunds", "files": ["problems.csv", " report.pdf "]}"#)

        fixture.inbox.scan(at: at)

        let card = try #require(fixture.store.cards.first)
        #expect(card.files == [CardFile(name: "problems.csv", size: Int64(table.utf8.count), modifiedAt: written),
                               CardFile(name: "report.pdf", size: Int64(report.utf8.count), modifiedAt: written.addingTimeInterval(60))])
        #expect(card.inbox?.fileNotes == nil && card.inbox?.filesFrom != nil)
        let folder = stored(fixture, "pack-shop/refunds")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["problems.csv", "report.pdf"])   // only what it lists
        #expect(try String(contentsOf: folder.appendingPathComponent("problems.csv"), encoding: .utf8) == table)
        #expect(WatchListFiles.modified(folder.appendingPathComponent("report.pdf")) == written.addingTimeInterval(60))
        // Only the person can get at them, and a copy can only be read, so a change made in Excel is saved elsewhere.
        #expect(try permissions(folder) == 0o700 && permissions(folder.deletingLastPathComponent()) == 0o700)
        #expect(try permissions(folder.appendingPathComponent("problems.csv")) == 0o400)
        #expect(MorningStore(directory: fixture.morning).cards.first?.files == card.files)   // saved with the card

        // The script changes or deletes its own files: the card's copies stay as they were until its card file changes.
        try put(fixture, "pack-shop", "problems.csv", "item,price\r\n123,99\r\n", modified: written.addingTimeInterval(120))
        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("pack-shop/report.pdf"))
        fixture.inbox.scan(at: at.addingTimeInterval(60))
        #expect(fixture.store.cards.first?.files == card.files)
        #expect(try String(contentsOf: folder.appendingPathComponent("problems.csv"), encoding: .utf8) == table)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("report.pdf").path))
        // Its other files are its own, left as they are.
        #expect(try String(contentsOf: fixture.directory.appendingPathComponent("pack-shop/notes.txt"), encoding: .utf8) == "not listed")
    }

    @Test func aCardKeepsOnlyItsLatestFiles() throws {
        let fixture = InboxFixture()
        defer { fixture.remove() }
        for name in ["a.csv", "b.csv", "c.csv"] { try put(fixture, "deals", name, name) }
        try fixture.write("deals", "job", #"{"title": "Run 1", "files": ["a.csv", "b.csv"]}"#)
        fixture.inbox.scan(at: at)
        let folder = stored(fixture, "deals/job")
        #expect(fixture.store.cards.first?.files.map(\.name) == ["a.csv", "b.csv"])

        // The next run lists another file: it takes the earlier ones' place, which stay in the script's folder. A set a
        // crash left half put together goes too.
        let leftover = folder.deletingLastPathComponent().appendingPathComponent(".\(folder.lastPathComponent)-crashed.tmp")
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data("half".utf8).write(to: leftover.appendingPathComponent("a.csv"))
        try put(fixture, "deals", "c.csv", "c, run 2")
        try fixture.write("deals", "job", #"{"title": "Run 2", "files": ["c.csv"]}"#)
        fixture.inbox.scan(at: at.addingTimeInterval(60))
        #expect(fixture.store.cards.count == 1 && fixture.store.cards.first?.files.map(\.name) == ["c.csv"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["c.csv"])
        #expect(try String(contentsOf: folder.appendingPathComponent("c.csv"), encoding: .utf8) == "c, run 2")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.deletingLastPathComponent().path) == [folder.lastPathComponent])
        #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("deals/a.csv").path))

        // A run that lists none: the card carries none.
        try fixture.write("deals", "job", #"{"title": "Run 3"}"#)
        fixture.inbox.scan(at: at.addingTimeInterval(120))
        let card = try #require(fixture.store.cards.first)
        #expect(card.files.isEmpty && card.inbox?.files == nil && card.inbox?.fileNotes == nil && card.inbox?.filesFrom == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func aFileThatCantBeAttachedIsOnePlainNoteAndTheOthersStillAre() throws {
        let fixture = InboxFixture()
        defer { fixture.remove() }
        try put(fixture, "pack-shop", "fine.csv", "ok")
        // A table too big to attach, without filling the disk: a sparse file of 620 MB.
        let big = fixture.directory.appendingPathComponent("pack-shop/problems.csv")
        #expect(FileManager.default.createFile(atPath: big.path, contents: nil))
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: 620_000_000)
        try handle.close()
        for name in ["run.sh", "page.html", "picture.svg", "bundle.zip", ".hidden.csv"] { try put(fixture, "pack-shop", name, "x") }
        for name in ["Tool.app", "folder.csv"] {
            try FileManager.default.createDirectory(at: fixture.directory.appendingPathComponent("pack-shop/\(name)"), withIntermediateDirectories: true)
        }
        let outside = fixture.root.appendingPathComponent("outside.csv")
        try Data("secret".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: fixture.directory.appendingPathComponent("pack-shop/link.csv"), withDestinationURL: outside)
        try fixture.write("pack-shop", "order-1", """
        {"title": "Refund ready", "files": ["fine.csv", "problems.csv", "missing.pdf", "run.sh", "Tool.app", "page.html", "picture.svg",
         "bundle.zip", ".hidden.csv", "folder.csv", "link.csv", "FINE.csv", 42, "../outside.csv", "/etc/hosts.txt"]}
        """)

        fixture.inbox.scan(at: at)

        let card = try #require(fixture.store.cards.first)
        #expect(card.files.map(\.name) == ["fine.csv"])
        let kinds = "a card only carries csv, tsv, txt, json, md, log, xlsx, pdf, png, jpg, jpeg, gif and heic files."
        #expect(card.inbox?.fileNotes == [
            "problems.csv wasn't attached: it's 620 MB, and the most is 500 MB.",
            "missing.pdf wasn't attached: it isn't in the card's folder.",
            "run.sh wasn't attached: " + kinds,
            "Tool.app wasn't attached: " + kinds,
            "page.html wasn't attached: " + kinds,
            "picture.svg wasn't attached: " + kinds,
            "bundle.zip wasn't attached: " + kinds,
            ".hidden.csv wasn't attached: hidden files aren't attached.",
            "folder.csv wasn't attached: it isn't a plain file.",
            "link.csv wasn't attached: it's a link, and a card only carries files that are in its folder.",
            "../outside.csv wasn't attached: it must be the name of a file in the card's folder, without a path.",
            "/etc/hosts.txt wasn't attached: it must be the name of a file in the card's folder, without a path.",
        ])
        // Only the one file was copied, and nothing outside, or in the script's folder, changed.
        #expect(try FileManager.default.contentsOfDirectory(atPath: stored(fixture, "pack-shop/order-1").path) == ["fine.csv"])
        #expect(try Data(contentsOf: outside) == Data("secret".utf8))
        #expect(try FileManager.default.attributesOfItem(atPath: big.path)[.size] as? Int == 620_000_000)
        // The card is still a card: its folder in Morning Files says nothing is wrong with its file.
        #expect(card.title == "Refund ready" && fixture.store.inboxNotes[card.folderID] == nil)
    }

    @Test func aCardCarriesUpTo10Files() throws {
        let fixture = InboxFixture()
        defer { fixture.remove() }
        let names = (1...12).map { "part-\($0).csv" }
        for name in names { try put(fixture, "bulk", name, name) }
        try fixture.write("bulk", "job", #"{"title": "Twelve parts", "files": \#(JSONText.compact(names))}"#)

        fixture.inbox.scan(at: at)

        let card = try #require(fixture.store.cards.first)
        #expect(card.files.map(\.name) == Array(names.prefix(CardFiles.limit)))
        #expect(card.inbox?.fileNotes == ["part-11.csv wasn't attached: a card carries up to 10 files.",
                                          "part-12.csv wasn't attached: a card carries up to 10 files."])
        #expect(try FileManager.default.contentsOfDirectory(atPath: stored(fixture, "bulk/job").path).count == 10)
    }

    @Test func noNameReachesOutsideTheCardsFolder() throws {
        for hostile in ["..", ".", "../x.csv", "a/b.csv", "/etc/hosts.txt", "~/x.csv", "a:b.csv", "x\u{0}.csv", "line\nbreak.csv", "",
                        String(repeating: "x", count: 300) + ".csv"] {
            #expect(CardFiles.refusal(hostile) != nil, "\(hostile)")
        }
        for fine in ["Problems.CSV", "report 2026-10-05.pdf", "Überblick.xlsx", "photo.HEIC", "run.log", "notes.md"] {
            #expect(CardFiles.refusal(fine) == nil, "\(fine)")
        }
        #expect(CardFiles.names(" one.csv ") == ["one.csv"])
        #expect(CardFiles.names(["a.csv", 3, NSNull(), "  ", ["b.csv"]]) == ["a.csv"])
        #expect(CardFiles.names(["a.csv": 1]).isEmpty && CardFiles.names(nil).isEmpty)
        #expect(CardFiles.note("line\nbreak.csv", "no.") == "line break.csv wasn't attached: no.")

        // Taking hostile names copies nothing, anywhere.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("card-files-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("inbox/deals")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: root.appendingPathComponent("inbox/secret.csv"))
        let destination = root.appendingPathComponent("files/card")
        let taken = CardFiles.take(["../secret.csv", "..", "../deals/../secret.csv"], in: folder, to: destination, from: at)
        #expect(taken.files.isEmpty && taken.notes.count == 3)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    // MARK: kept with the card

    @Test func aResolvedCardKeepsItsFiles() throws {
        let fixture = InboxFixture()
        defer { fixture.remove() }
        try put(fixture, "deals", "problems.csv", "item\r\n1\r\n")
        try fixture.write("deals", "job", #"{"title": "1 problem", "files": ["problems.csv"]}"#)
        fixture.inbox.scan(at: at)
        let files = try #require(fixture.store.cards.first).files
        #expect(files.map(\.name) == ["problems.csv"])

        // The matter went away: the card file goes, and the script's files with it.
        try fixture.delete("deals", "job")
        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("deals/problems.csv"))
        fixture.inbox.scan(at: at.addingTimeInterval(60))

        let card = try #require(fixture.store.cards.first)
        #expect(card.disposition == .resolved && card.inbox?.goneAt != nil)
        #expect(card.files == files)
        #expect(FileManager.default.fileExists(atPath: stored(fixture, "deals/job").appendingPathComponent("problems.csv").path))
    }

    @Test func theSameCardFileReadAgainKeepsItsFilesWhateverItsScriptDidSince() throws {
        let fixture = InboxFixture()
        defer { fixture.remove() }
        try put(fixture, "deals", "problems.csv", "item\r\n1\r\n")
        try fixture.write("deals", "job", #"{"title": "1 problem", "files": ["problems.csv"]}"#)
        fixture.inbox.scan(at: at)
        let card = try #require(fixture.store.cards.first)
        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("deals/problems.csv"))

        // The next launch reads the same card file again: the card keeps its files and says nothing.
        let store = MorningStore(directory: fixture.morning)
        CardInbox(store: store, directory: fixture.directory).scan(at: at.addingTimeInterval(60))
        #expect(store.cards.first == card)
        #expect(FileManager.default.fileExists(atPath: stored(fixture, "deals/job").appendingPathComponent("problems.csv").path))

        // A new version of the card file takes its files again: this time the file isn't there, and the card says so.
        try fixture.write("deals", "job", #"{"title": "1 problem", "files": ["problems.csv"]}"#)
        CardInbox(store: store, directory: fixture.directory).scan(at: at.addingTimeInterval(120))
        #expect(store.cards.first?.files.isEmpty == true)
        #expect(store.cards.first?.inbox?.fileNotes == ["problems.csv wasn't attached: it isn't in the card's folder."])
        #expect(!FileManager.default.fileExists(atPath: stored(fixture, "deals/job").path))
    }

    // MARK: the Files section

    @Test func theFilesSectionOpensSavesAndShowsAFileThroughItsSeams() throws {
        let fixture = InboxFixture()
        defer { fixture.remove() }
        try put(fixture, "deals", "problems.csv", "item\r\n1\r\n")
        try fixture.write("deals", "job", #"{"title": "1 problem", "files": ["problems.csv", "gone.pdf"]}"#)
        fixture.inbox.scan(at: at)
        let card = try #require(fixture.store.cards.first)
        let file = try #require(card.files.first)
        #expect(card.inbox?.fileNotes == ["gone.pdf wasn't attached: it isn't in the card's folder."])
        let copy = stored(fixture, "deals/job").appendingPathComponent("problems.csv")
        let seen = Seen()
        seen.saveTo = fixture.root.appendingPathComponent("Desktop/problems.csv")
        try FileManager.default.createDirectory(at: fixture.root.appendingPathComponent("Desktop"), withIntermediateDirectories: true)
        let actions = CardFileActions(root: fixture.root.appendingPathComponent("cards/files"),
                                      open: { seen.opened.append($0); return seen.opens },
                                      reveal: { seen.revealed.append($0) },
                                      destination: { seen.asked.append($0); return seen.saveTo })

        // The card's page has the section, with the panel's seams.
        let navigation = MorningNavigation()
        navigation.route = .card(card.id)
        let page = MorningFilesView(store: fixture.store, navigation: navigation, close: {}, filed: {}, handoff: { _ in }, cardFiles: actions)
        let shown = try #require(findView(CardFilesSection.self, in: page.body))
        #expect(shown.card == card)
        shown.open(file)
        #expect(seen.opened == [copy])

        let section = CardFilesSection(card: card, actions: actions, report: { seen.reports.append(Report(message: $0, problem: $1)) })
        section.showInFinder(file)
        #expect(seen.revealed == [copy])
        section.saveCopy(file)
        #expect(seen.asked == ["problems.csv"])
        let saved = try #require(seen.saveTo)
        #expect(try Data(contentsOf: saved) == Data("item\r\n1\r\n".utf8))
        #expect(try permissions(saved) == 0o600)   // the person's copy is theirs to change
        #expect(seen.reports == [Report(message: "Saved a copy of problems.csv in Desktop.", problem: false)])
        section.saveCopy(file)   // over the earlier copy: the save panel asked first
        #expect(seen.reports.count == 2 && seen.reports.last?.problem == false)

        // Cancelled: nothing is saved, and nothing said.
        seen.saveTo = nil
        section.saveCopy(file)
        #expect(seen.reports.count == 2)

        // No app could open it, its copy is gone, or the card doesn't carry it: said plainly, and nothing else opens.
        seen.opens = false
        section.open(file)
        #expect(seen.reports.last == Report(message: "No app on this Mac opened problems.csv.", problem: true))
        seen.opens = true
        try FileManager.default.removeItem(at: copy)
        section.open(file)
        section.showInFinder(file)
        #expect(seen.reports.last == Report(message: "problems.csv isn't in Noteling's folder any more. It comes back when its card is written again.",
                                            problem: true))
        section.open(CardFile(name: "../../outside.csv", size: 1, modifiedAt: at))
        #expect(seen.reports.last == Report(message: "This card doesn't carry ../../outside.csv.", problem: true))
        #expect(seen.opened == [copy, copy] && seen.revealed == [copy])

        // A card that carries nothing has no section.
        try fixture.write("deals", "plain", #"{"title": "No files"}"#)
        fixture.inbox.scan(at: at.addingTimeInterval(60))
        navigation.route = .card(CardInboxFormat.cardID("deals/plain"))
        #expect(findView(CardFilesSection.self, in: page.body) == nil)
    }

    @Test func theTileShowsAPaperclipAndHowManyFiles() {
        var card = MorningCard(folderID: UUID(), title: "T", action: CardInboxFormat.placeholderAction)
        #expect(MorningFilesView.attachedLabel(card) == nil)
        card.inbox = CardInboxLink(key: "deals/job", severity: "normal", actions: [])
        card.inbox?.fileNotes = ["gone.pdf wasn't attached: it isn't in the card's folder."]
        #expect(MorningFilesView.attachedLabel(card) == nil)
        card.inbox?.files = [CardFile(name: "a.csv", size: 1, modifiedAt: at)]
        #expect(MorningFilesView.attachedLabel(card) == "1 file attached")
        card.inbox?.files?.append(CardFile(name: "b.csv", size: 2, modifiedAt: at))
        #expect(MorningFilesView.attachedLabel(card) == "2 files attached")
    }

    @Test func sizesAreSaidTheWayFinderSaysThem() {
        #expect(CardFiles.size(0) == "0 bytes" && CardFiles.size(1) == "1 byte" && CardFiles.size(999) == "999 bytes")
        #expect(CardFiles.size(820_400) == "820 KB" && CardFiles.size(1_234_567) == "1.2 MB")
        #expect(CardFiles.size(620_000_000) == "620 MB" && CardFiles.size(CardFiles.sizeLimit) == "500 MB")
        #expect(CardFiles.size(500_400_000) == "500.4 MB" && CardFiles.size(2_345_678_901) == "2.35 GB")
        #expect(CardFiles.icon("problems.csv") == "tablecells" && CardFiles.icon("report.PDF") == "doc.richtext")
        #expect(CardFiles.icon("photo.heic") == "photo" && CardFiles.icon("run.log") == "doc.text")
    }

    /// The guide's example of a card that carries a file, run by a real script: the file reaches the card.
    @Test func aPackScriptWritesAFileAndTheCardThatCarriesItWithTheGuidesLines() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("card-files-script-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = root.appendingPathComponent("tools/shop")
        try FileManager.default.createDirectory(at: pack.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try "---\nname: Shop\n---\nFixture.".write(to: pack.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try """
        def run() -> str:
            \"\"\"Writes a file and the card that carries it.\"\"\"
            \(Self.guideExample.replacingOccurrences(of: "\n", with: "\n    "))
            return folder
        """.write(to: pack.appendingPathComponent("scripts/refunds.py"), atomically: true, encoding: .utf8)
        let runner = ScriptRunner(config: Config())
        let inbox = root.appendingPathComponent("cards/inbox")
        runner.cardsRoot = inbox
        let registry = ToolRegistry(root: root.appendingPathComponent("tools"), runner: runner)
        await registry.reload()
        let script = try #require(registry.script(named: "shop__refunds"))
        let folder = try #require(try await runner.result(script) as? String)

        let store = MorningStore(directory: root.appendingPathComponent("morning"))
        CardInbox(store: store, directory: inbox).scan(at: at)
        let card = try #require(store.cards.first)
        #expect(card.title == "2 refunds ready" && card.files.map(\.name) == ["refunds.csv"])
        let copy = CardFiles.folder(for: card.id, in: root.appendingPathComponent("cards/files")).appendingPathComponent("refunds.csv")
        #expect(try Data(contentsOf: copy) == Data([0xEF, 0xBB, 0xBF]) + Data("order,refund\r\n123,10.00\r\n124,4.50\r\n".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder).sorted() == ["refunds.csv", "refunds.json"])   // no half-written leftovers
    }

    /// The example in the guide, line for line.
    static let guideExample = """
    import csv, json, os
    folder = os.environ["NOTELING_CARDS_DIR"]
    with open(os.path.join(folder, "refunds.csv.tmp"), "w", newline="", encoding="utf-8-sig") as f:   # utf-8-sig: Excel reads every language
        csv.writer(f).writerows([["order", "refund"], ["123", "10.00"], ["124", "4.50"]])
    os.replace(os.path.join(folder, "refunds.csv.tmp"), os.path.join(folder, "refunds.csv"))   # the file first
    with open(os.path.join(folder, "refunds.json.tmp"), "w") as f: json.dump({"title": "2 refunds ready", "files": ["refunds.csv"]}, f)
    os.replace(os.path.join(folder, "refunds.json.tmp"), os.path.join(folder, "refunds.json"))   # then the card that lists it
    """

    private struct Report: Equatable {
        var message: String
        var problem: Bool
    }

    /// What the seams were asked to do.
    private final class Seen {
        var opened: [URL] = []
        var revealed: [URL] = []
        var asked: [String] = []
        var opens = true
        var saveTo: URL?
        var reports: [Report] = []
    }
}

/// Finds a view composed inside a SwiftUI body, without GUI coordinates.
private func findView<T>(_ type: T.Type, in value: Any, depth: Int = 0) -> T? {
    if let value = value as? T { return value }
    guard depth < 60 else { return nil }
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle != .class else { return nil }
    for child in mirror.children {
        if let result = findView(type, in: child.value, depth: depth + 1) { return result }
    }
    return nil
}
