import Foundation

/// A's draft, "Is this you?": what Noteling can already say about the person without asking anyone, put to them on
/// one sticker. Drafts are deterministic and rebuilt each time, never stored, and no prompt reads one before the person
/// says Yes (docs/plans/p13n-about-you.md, Rule 1). Only fields with nothing kept are drafted.
struct AboutYouDraft: Equatable {
    /// The Settings author, else the Mac's full name.
    var name: String?
    /// The packs the person uses most, up to `toolsLimit`, as one line: "Shopify admin and Stripe".
    var tools: String?

    static let toolsLimit = 3

    var isEmpty: Bool { name == nil && tools == nil }

    /// The sticker's words: "You're Sam Lee, working in Shopify admin and Stripe?"
    var text: String {
        switch (name, tools) {
        case let (name?, tools?): return "You're \(name), working in \(tools)?"
        case let (name?, nil): return "You're \(name)?"
        case let (nil, tools?): return "You work in \(tools)?"
        case (nil, nil): return ""
        }
    }

    /// The drafted value for a field, for the page's Fix to fill in.
    subscript(_ field: AboutMe.Field) -> String? {
        switch field {
        case .name: return name
        case .tools: return tools
        case .company, .role: return nil   // left blank unless the person states them (Rule 5)
        }
    }

    /// The tools line from the packs in use: most used first (notes and shown paths on them), then by name; at most
    /// `toolsLimit`. Nil when there are none.
    static func tools(_ packs: [(name: String, uses: Int)]) -> String? {
        struct Used { let name: String; let uses: Int }
        let used: [Used] = packs.compactMap { pack in
            let name = pack.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty || pack.uses <= 0 ? nil : Used(name: name, uses: pack.uses)
        }
        let ranked = used.sorted { a, b in
            if a.uses != b.uses { return a.uses > b.uses }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        var seen: Set<String> = []
        var names: [String] = []
        for pack in ranked where names.count < toolsLimit && seen.insert(pack.name.lowercased()).inserted { names.append(pack.name) }
        switch names.count {
        case 0: return nil
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }
}

/// C, asked in the moment: the minister's triage said a verdict hinges on who someone named in a finding is, and code
/// checked the name (`MinisterPrompt.parseAsk`). One tap says how they stand to the person; nothing is kept before it.
struct PersonAsk: Equatable {
    /// As the finding has it, at most `MinisterPrompt.askNameLimit` characters.
    let name: String
    let finding: FindingRef
    /// The job whose finding named them, as the person knows it.
    let job: String
    /// The minister's reason, one sentence.
    let why: String?

    /// "Lena: your manager, a teammate, a customer, a vendor?"
    var text: String { "\(name): your manager, a teammate, a customer, a vendor?" }
    /// Under it: what prompted the question.
    var byline: String { "From \(job)" + (why.map { ": \($0)" } ?? "") }
}

/// The deck's one question card, after the matter cards. Only one shows at a time, in this order: a question about a
/// person (C, tied to a live verdict), then the minister's lesson question, then "Is this you?" (A).
enum DeckAsk: Equatable {
    case person(PersonAsk)
    case lesson(LessonQuestion)
    case aboutYou(AboutYouDraft)

    /// The card's identity, for its tilt and its animation.
    var key: String {
        switch self {
        case .person(let ask): return "person:" + ask.name.lowercased()
        case .lesson(let question): return "lesson:" + question.job
        case .aboutYou: return "about-you"
        }
    }
}
