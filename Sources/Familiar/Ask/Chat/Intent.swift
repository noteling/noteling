import Foundation

/// What a person wants from a message, named by what they would be unhappy without: understanding (explain), the
/// ability to do it next time (teach: they click, Noteling points), or the result (act: Noteling clicks). Which one is
/// never a matter of particular words. The person says it their own way, taps a verb under an answer, or pins one over
/// the input; the model judges only where the words leave no doubt.
enum Intent: String, CaseIterable, Codable, Sendable {
    case explain, teach, act
}

/// The words the three intents go by on the pad (the tabs under an answer, the line over the input) and in the prompt.
/// English by default; a team's noteling.json (`verbs`) renames them and adds examples of how its people put each one,
/// in their jargon or language. Examples illustrate the intents for the model; nothing matches on them.
struct IntentWords: Codable, Equatable, Sendable {
    var explain = "Explain"
    var teach = "Teach me"
    var act = "Do it for me"
    /// By `Intent.rawValue`: the team's own ways of saying each, for the prompt.
    var examples: [String: [String]] = [:]

    static let standard = IntentWords()
    static let wordLimit = 24
    static let examplesLimit = 8
    static let exampleLimit = 60

    func word(_ intent: Intent) -> String {
        switch intent {
        case .explain: return explain
        case .teach: return teach
        case .act: return act
        }
    }

    mutating func set(_ intent: Intent, _ word: String) {
        switch intent {
        case .explain: explain = word
        case .teach: teach = word
        case .act: act = word
        }
    }

    /// How people put each intent, for the prompt: the team's examples, else a few in English.
    func examples(for intent: Intent) -> [String] {
        if let own = examples[intent.rawValue], !own.isEmpty { return own }
        switch intent {
        case .explain: return ["what is this", "why is it greyed out", "what does this mean"]
        case .teach: return ["where do I find…", "how do I get to…", "walk me through it", "I don't know where…"]
        case .act: return ["do it for me", "fill this in", "send it", "type it in for me"]
        }
    }

    /// The intent a tab stands for, by its word: case, spaces and punctuation at the ends don't count, so a tab the
    /// model wrote as "teach me!" still does.
    func intent(ofTab tab: String) -> Intent? {
        let key = Self.norm(tab)
        guard !key.isEmpty else { return nil }
        return Intent.allCases.first { Self.norm(word($0)) == key }
    }

    static func norm(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The two tabs that offer the other ways to take a how-to, in the order the prompt asks for them.
    var verbTabs: [String] { [teach, act] }
}
