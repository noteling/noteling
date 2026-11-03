import Foundation
import Testing
@testable import Familiar

/// Who's Who: the people kept in Noteling's folder, what a save refuses, and the one-time move from the Morning
/// folder's database earlier versions kept. Temp folders only.
@Suite @MainActor
struct PeopleStoreTests {
    @Test func peopleAreSavedWholeReadBackAndOnlyOneIsMe() throws {
        let home = temp()
        defer { try? FileManager.default.removeItem(at: home) }
        let store = PeopleStore(directory: home)
        #expect(store.people.isEmpty && store.error == nil)
        try store.save(Person(name: "  Maya Chen ", role: "Product lead", identities: [" maya@example.com ", "", "mchen"], isMe: true))
        let alex = Person(name: "Alex", isMe: true)
        try store.save(alex)
        #expect(store.people.map(\.name) == ["Maya Chen", "Alex"])
        #expect(store.people.map(\.isMe) == [false, true])   // the newer "this is me" wins
        #expect(store.people[0].identities == ["maya@example.com", "mchen"])

        // Refused, and nothing changes.
        #expect(throws: PeopleError.self) { try store.save(Person(name: "   ")) }
        #expect(store.error == "Give this person a name.")
        #expect(throws: PeopleError.self) { try store.remove(id: UUID()) }
        #expect(store.people.count == 2)

        // Changed, removed, and read back by the next launch, from a file only this account can read.
        var maya = store.people[0]
        maya.role = "Platform lead"
        try store.save(maya)
        try store.remove(id: alex.id)
        let again = PeopleStore(directory: home)
        #expect(again.people.map(\.name) == ["Maya Chen"] && again.people[0].role == "Platform lead" && again.error == nil)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func aFileThatCantBeReadPausesChangesInsteadOfLosingPeople() throws {
        let home = temp()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: home.appendingPathComponent(PeopleStore.fileName))
        let store = PeopleStore(directory: home)
        #expect(store.people.isEmpty && store.error?.hasPrefix("Who's Who could not be opened safely.") == true)
        #expect(throws: PeopleError.self) { try store.save(Person(name: "Maya")) }
        #expect(try String(contentsOf: home.appendingPathComponent(PeopleStore.fileName), encoding: .utf8) == "not json")
    }

    @Test func whosWhoFromTheMorningFolderIsBroughtOverOnce() throws {
        let home = temp()
        defer { try? FileManager.default.removeItem(at: home) }
        let morning = home.appendingPathComponent("morning")
        let id = UUID()
        let workspace = #"{"version": 1, "folders": [], "people": [{"id": "\#(id.uuidString)", "name": "Maya Chen", "role": "Product lead", "relationship": "", "context": "", "identities": ["maya@example.com"], "isMe": false}], "cards": [], "workItems": []}"#
        try morningDatabase(at: morning, workspace: workspace)

        // Found in the database, and written to Noteling's folder for good.
        let store = PeopleStore(directory: home, morning: morning)
        #expect(store.error == nil && store.people.map(\.name) == ["Maya Chen"] && store.people.first?.id == id)
        #expect(FileManager.default.fileExists(atPath: store.file.path))

        // From then on the file is what counts, whatever the database says.
        try FileManager.default.removeItem(at: morning)
        try morningDatabase(at: morning, workspace: #"{"version": 1, "people": [{"name": "Someone else"}]}"#)
        #expect(PeopleStore(directory: home, morning: morning).people.map(\.name) == ["Maya Chen"])

        // No database, or none with people: nothing is written, so a later start can still bring them over.
        let empty = temp()
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(PeopleStore(directory: empty, morning: empty.appendingPathComponent("morning")).people.isEmpty)
        try morningDatabase(at: empty.appendingPathComponent("morning"), workspace: #"{"version": 1, "people": []}"#)
        let none = PeopleStore(directory: empty, morning: empty.appendingPathComponent("morning"))
        #expect(none.people.isEmpty && none.error == nil && !FileManager.default.fileExists(atPath: none.file.path))
    }

    @Test func whatEarlierVersionsKeptIsDeletedOnceAndTheMorningFolderIsLeft() throws {
        let home = temp()
        defer { try? FileManager.default.removeItem(at: home) }
        for folder in ["cards/inbox/pack-shop", "attention", "calendar", "runs/2026-09-29_09-00-00", "morning", "jobs"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try Data("{}".utf8).write(to: home.appendingPathComponent("cards/inbox/pack-shop/order-1.json"))
        #expect(RetiredMorning.cleanUp(home: home) == ["cards", "attention", "calendar", "runs"])
        let left = try FileManager.default.contentsOfDirectory(atPath: home.path).sorted()
        #expect(left == ["jobs", "morning"])
        #expect(RetiredMorning.cleanUp(home: home).isEmpty)
    }

    private func temp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("people-\(UUID().uuidString)") }

    /// A Morning folder's database as earlier versions wrote it: one `workspace` record holding the JSON document.
    private func morningDatabase(at directory: URL, workspace: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let hex = Data(workspace.utf8).map { String(format: "%02x", $0) }.joined()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [directory.appendingPathComponent("morning.sqlite").path,
                             "PRAGMA user_version = 1; CREATE TABLE workspace (id INTEGER PRIMARY KEY CHECK (id = 1), payload BLOB NOT NULL); INSERT INTO workspace (id, payload) VALUES (1, X'\(hex)');"]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
