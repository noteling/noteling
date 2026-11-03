import Foundation

/// Secrets hidden in what the model or the log is shown, by one rule for rows, JSON lines and plain text alike: a
/// column or key named like a secret (`access_token`, `card_number`) loses its value, and a value that looks like a
/// key, a token or a card number is hidden wherever it is.
enum SecretText {
    static let hidden = "(hidden)"

    /// A row or JSON object with its secrets hidden; lists and objects inside it are looked through the same way.
    static func redacted(_ object: [String: Any]) -> [String: Any] {
        object.reduce(into: [:]) { out, pair in
            out[pair.key] = SecretWords.looksSecret(pair.key) ? hidden : redacted(value: pair.value)
        }
    }

    static func redacted(value: Any) -> Any {
        switch value {
        case let text as String: return PageWalk.looksLikeSecretValue(text) ? hidden : text
        case let object as [String: Any]: return redacted(object)
        case let list as [Any]: return list.map { redacted(value: $0) }
        default: return value
        }
    }

    /// A line of text with each key, token or card number in it replaced, and the rest left as it is.
    static func hiding(_ text: String) -> String { PageWalk.hidingSecrets(text) }
}
