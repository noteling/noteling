import Foundation

/// Names that mean a value is a secret, whatever shows it: a form field's label, a column of a job's findings, a key in
/// a row. Watch Me, the page reader and the memory log all ask the same question, so the answer lives here.
enum SecretWords {
    nonisolated static let pattern = try! NSRegularExpression(
        pattern: #"(?i)\b(pass(word|code|phrase)?|pwd|pin|otp|mfa|2fa|secret|token|api[ _-]?key|key|cvv|cvc|ssn|credential|(security|verification|one[ -]?time|authenticat(ion|or)|recovery|backup) codes?|card ?numbers?|account ?numbers?|routing|iban|social security|(recovery|seed) phrases?)s?\b"#)

    /// Whether a name means a secret. `access_token`, `userPassword` and `card-number` count: the name is read as
    /// words first.
    nonisolated static func looksSecret(_ s: String?) -> Bool {
        guard let s, !s.isEmpty else { return false }
        let text = words(s)
        return pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// "user_password", "apiKey" or "access-token" as words.
    nonisolated static func words(_ name: String) -> String {
        name.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "[_\\-.]", with: " ", options: .regularExpression)
    }
}
