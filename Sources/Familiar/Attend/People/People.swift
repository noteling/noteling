import CSQLite
import Combine
import Foundation

/// Someone the person works with, as Who's Who keeps them: a name, their role, what they are to the person, the context
/// a helpful colleague would know, and the names they go by across tools. One of them may be the person themself.
struct Person: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var role: String = ""
    var relationship: String = ""
    var context: String = ""
    var identities: [String] = []
    var isMe: Bool = false
}

enum PeopleError: LocalizedError {
    case invalid(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let explanation), .unavailable(let explanation): return explanation
        }
    }
}

/// Who's Who: the people, kept in `people.json` in Noteling's folder, readable only by this account, written whole or
/// not at all. The minister doesn't read them yet ([the plan](../../../../docs/plans/attention-minister.md) leaves the
/// person's side to a later phase); the Who's Who screens do.
@MainActor
final class PeopleStore: ObservableObject {
    @Published private(set) var people: [Person] = []
    /// What went wrong, in plain words: nil while all is well.
    @Published private(set) var error: String?

    static let fileName = "people.json"
    let file: URL
    private var blockedReason: String?

    /// What the file holds.
    private struct Saved: Codable {
        var version = 1
        var people: [Person]
    }

    /// `directory` is Noteling's folder. `morning` is the Morning folder earlier versions kept, whose Who's Who is
    /// brought over once, the first time there is no people file; if that fails, nothing is written, so the next start
    /// tries again.
    init(directory: URL = Config.dir, morning: URL? = nil) {
        file = directory.appendingPathComponent(Self.fileName)
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: file))
                guard saved.version == 1 else { throw PeopleError.unavailable("Who's Who was saved by a newer version of Noteling.") }
                try Self.validate(saved.people)
                people = saved.people
            } catch {
                blockedReason = "Who's Who could not be opened safely. \(error.localizedDescription) Changes are paused to protect your saved people."
                self.error = blockedReason
            }
        } else if let morning {
            do {
                let found = try Self.peopleFromMorning(morning)
                if !found.isEmpty {
                    try Self.validate(found)
                    try write(found)
                    people = found
                }
            } catch {
                self.error = "Who's Who from an earlier version couldn't be read: \(error.localizedDescription)"
            }
        }
    }

    /// Adds or changes a person. One person at most is the person themself.
    func save(_ person: Person) throws {
        try transact { next in
            var person = person
            person.name = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !person.name.isEmpty else { throw PeopleError.invalid("Give this person a name.") }
            person.identities = person.identities.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if person.isMe { for index in next.indices { next[index].isMe = false } }
            if let index = next.firstIndex(where: { $0.id == person.id }) { next[index] = person } else { next.append(person) }
        }
    }

    func remove(id: UUID) throws {
        try transact { next in
            guard next.contains(where: { $0.id == id }) else { throw PeopleError.invalid("This person is no longer here.") }
            next.removeAll { $0.id == id }
        }
    }

    func person(id: UUID) -> Person? { people.first { $0.id == id } }

    private func transact(_ change: (inout [Person]) throws -> Void) throws {
        do {
            if let blockedReason { throw PeopleError.unavailable(blockedReason) }
            var next = people
            try change(&next)
            try Self.validate(next)
            try write(next)
            people = next
            error = nil
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    private func write(_ people: [Person]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JobFiles.write(try encoder.encode(Saved(people: people)), to: file)
    }

    static func validate(_ people: [Person]) throws {
        guard Set(people.map(\.id)).count == people.count else { throw PeopleError.invalid("Who's Who lists the same person twice.") }
        guard people.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw PeopleError.invalid("Every person needs a name.") }
        guard people.filter(\.isMe).count <= 1 else { throw PeopleError.invalid("Only one person can be marked as you.") }
    }

    /// Who's Who as earlier versions kept it, in the Morning folder's database (`morning.sqlite`, whose `workspace`
    /// record is one JSON document with a `people` list). Empty when there is no database or no people in it.
    static func peopleFromMorning(_ directory: URL) throws -> [Person] {
        let database = directory.appendingPathComponent("morning.sqlite")
        guard FileManager.default.fileExists(atPath: database.path) else { return [] }
        var connection: OpaquePointer?
        guard sqlite3_open_v2(database.path, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let connection else {
            let reason = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "it could not be opened"
            if let connection { sqlite3_close(connection) }
            throw PeopleError.unavailable("The Morning folder's database: \(reason).")
        }
        defer { sqlite3_close(connection) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "SELECT payload FROM workspace WHERE id = 1", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PeopleError.unavailable("The Morning folder's database: \(String(cString: sqlite3_errmsg(connection))).")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { return [] }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        struct Workspace: Decodable { var people: [Person]? }
        return try JSONDecoder().decode(Workspace.self, from: data).people ?? []
    }
}
