import Foundation

struct MorningFolder: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
}

struct MorningPerson: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var role: String = ""
    var relationship: String = ""
    var context: String = ""
    var identities: [String] = []
    var isMe: Bool = false
}

struct MorningSource: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var kind: String = "Personal note"
    var excerpt: String
    var url: String = ""
    var capturedAt: Date = Date()
}

enum MorningActionMode: String, Codable, CaseIterable {
    case prepare, desktop
    var label: String { self == .prepare ? "Prepare a local result" : "Work in an app" }
}

struct MorningAction: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var instruction: String
    var mode: MorningActionMode = .prepare
}

enum MorningCardDisposition: String, Codable, CaseIterable {
    case unreviewed, ignored, mine, delegated, completed, resolved
    var label: String {
        switch self {
        case .unreviewed: return "To review"
        case .ignored: return "Filed away"
        case .mine: return "I’ll handle it"
        case .delegated: return "With Noteling"
        case .completed: return "Result ready"
        case .resolved: return "Resolved"
        }
    }
}

struct MorningCard: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var folderID: UUID
    var title: String
    var summary: String = ""
    var personIDs: [UUID] = []
    var sources: [MorningSource] = []
    var rationale: String = ""
    var action: MorningAction
    var contextAction: MorningAction? = nil
    var unknowns: String = ""
    var timing: String = ""
    var isSample: Bool = false
    var disposition: MorningCardDisposition = .unreviewed
    var updatedAt: Date = Date()
    var tracking: CardTracking? = nil
    var personalContext: String? = nil
    /// Options after the first (the first is `action`), best first. Optional so cards saved before it still load.
    var alternatives: [MorningAction]? = nil
    /// A card a script wrote into the cards inbox (`CardInbox`): its file says what it shows, and it never runs anything.
    /// Nil for every other card; the card step and the attention test never touch one that has it.
    var inbox: CardInboxLink? = nil
}

/// Where an inbox card came from, and what its file asked for besides its words.
struct CardInboxLink: Codable, Equatable {
    /// `<source>/<id>`: the folder in the inbox and the file's name without `.json`.
    var key: String
    /// high, normal or low.
    var severity: String
    /// Buttons that only open a page, ask Noteling a question in chat, or open a watch's page.
    var actions: [CardInboxAction]
    /// When its file was deleted: the script no longer reports it.
    var goneAt: Date? = nil
    /// Its file's deletion resolved it, rather than the person: the card opens again if the file comes back.
    var resolvedByInbox = false
    /// What its file says the matter is made of (`parts`), such as which items of a watch are wrong.
    var parts: [String]? = nil
    /// The parts it had when the person resolved it: a later file with another part opens it again.
    var resolvedParts: [String]? = nil
}

/// One button on an inbox card: open a web page, ask Noteling something about the card in chat, or open a watch's
/// page in Morning Files. Never anything else.
struct CardInboxAction: Codable, Equatable, Identifiable {
    var label: String
    var url: String? = nil
    var ask: String? = nil
    /// A watch's id: the button opens that watch's page, and only when there is such a watch.
    var watch: String? = nil
    var id: String { [label, url ?? "", ask ?? "", watch ?? ""].joined(separator: "\u{1F}") }
}

extension MorningCard {
    var isFromInbox: Bool { inbox != nil }
}

enum MorningWorkKind: String, Codable { case action, context }

enum MorningWorkStatus: String, Codable, CaseIterable {
    case queued, running, needsAttention, completed, failed, cancelled, interrupted
    var isPending: Bool { self == .queued || self == .running || self == .needsAttention }
    var label: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Working"
        case .needsAttention: return "Needs you"
        case .completed: return "Result ready"
        case .failed: return "Couldn’t finish"
        case .cancelled: return "Stopped"
        case .interrupted: return "Interrupted · check before retrying"
        }
    }
}

/// The accepted action and evidence are snapshots; editing a card cannot silently change queued work.
struct MorningWorkItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var cardID: UUID
    var card: MorningCard
    var people: [MorningPerson]
    var action: MorningAction
    var kind: MorningWorkKind = .action
    var status: MorningWorkStatus = .queued
    var result: String = ""
    var progress: String = ""
    var createdAt: Date = Date()
    var startedAt: Date? = nil
    var finishedAt: Date? = nil
}

struct MorningWorkspace: Codable, Equatable {
    var version: Int = 1
    var folders: [MorningFolder] = [
        MorningFolder(name: "Replies"), MorningFolder(name: "Unfinished"), MorningFolder(name: "Housekeeping")
    ]
    var people: [MorningPerson] = []
    var cards: [MorningCard] = []
    var workItems: [MorningWorkItem] = []
    var samplesLoaded = false
    var cardGenerations: [CardGenerationRecord]? = nil
    /// What the card step has judged, by observation id. Nil in workspaces saved before it was kept.
    var judgments: [String: CardJudgment]? = nil
    /// What the person taught about items they read, newest first. Nil until the first lesson.
    var lessons: [MorningLesson]? = nil
}
