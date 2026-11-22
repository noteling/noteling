import Foundation

/// Names of one control that differ only in a count the page keeps: "Notifications (3)" and "Notifications (4)",
/// "Shopping cart 1 item" and "Shopping cart 2 items". A number is taken for a count only in a few shapes; any other
/// ("Size 10", "Go to page 2", "Step 1 of 3", "Choose 2 packs") may be what tells two controls apart, and a hint that
/// is missing is better than one on another control. So nothing here is for `alike`, and the lists are short on purpose.
enum ChangingCounts {
    /// What a page counts. The plural is the s after it; the noun is in the page's words, so English only.
    static let things: Set<String> = ["item", "notification", "message", "review", "comment", "alert", "request", "task",
                                      "update", "rating", "answer"]
    /// Counted too, but only as new or unread ones: "10 questions" is a quiz's size, "1,000 emails" a plan's.
    static let newThings: Set<String> = things.union(["question", "email", "order"])

    /// A word just before a number that makes it which one, or how many to have, rather than how many there are.
    static let labelWords: Set<String> = [
        "page", "step", "size", "item", "number", "no", "no.", "#", "level", "part", "chapter", "of", "version", "season",
        "episode", "room", "floor", "row",
        "show", "display", "load", "choose", "select", "pick", "buy", "get", "add", "take", "order", "last", "next",
        "first", "top", "past", "every", "to", "with", "for", "than", "unit", "copy", "quiz", "test", "plan",
    ]

    /// A name with one of its counts taken out: the name up to the number, the number, the bracket's end or what is
    /// counted (its singular), and the rest of the name.
    struct Reading: Equatable {
        var before: String
        var count: Int
        var what: String
        var after: String

        /// The same name with another count in the same place.
        func differsOnlyInCount(from other: Reading) -> Bool {
            before == other.before && what == other.what && after == other.after && count != other.count
        }

        /// Whether a normalized name can have such a reading: the same words, with a number there. A screen for a
        /// page's names, as reading one is slow; it passes some that have none ("2 item", a year).
        func isPossible(in name: String) -> Bool {
            guard name.hasPrefix(before) else { return false }
            let rest = name.dropFirst(before.count), digits = rest.prefix { "0123456789,".contains($0) }
            guard !digits.isEmpty, rest.dropFirst(digits.count).hasPrefix(what) else { return false }
            let end = rest.dropFirst(digits.count + what.count)
            return end == after || end == "s" + after
        }
    }

    /// The names are the same but for one count, in the same place in each, and the counts differ.
    static func differOnly(_ a: String?, _ b: String?) -> Bool { differOnly(readings(of: a), b) }

    /// The same, of a name already read: a hint's is read once for all the names on a page.
    static func differOnly(_ mine: [Reading], _ b: String?) -> Bool {
        guard !mine.isEmpty, let name = NoteAnchor.norm(b), mine.contains(where: { $0.isPossible(in: name) }) else { return false }
        let there = readings(of: name)
        return mine.contains { my in there.contains { my.differsOnlyInCount(from: $0) } }
    }

    /// Every way to read a count in a name, with at least ten characters of name besides it.
    static func readings(of name: String?) -> [Reading] {
        guard let name = NoteAnchor.norm(name), name.utf8.contains(where: { (48...57).contains($0) }) else { return [] }   // a digit
        return (bracketed(name) + counted(name)).filter { words(of: $0).count >= 10 }
    }

    /// The name less the count's place, brackets and the punctuation at its ends.
    private static func words(of reading: Reading) -> String {
        let bare = (reading.before + " " + reading.what + reading.after).map { "#()".contains($0) ? " " : $0 }
        return String(bare).split(separator: " ").joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
    }

    /// "(3)" or "(1,234)": a whole number and nothing else in brackets. Not a year, nor an area code.
    private static func bracketed(_ name: String) -> [Reading] {
        name.matches(of: #/\(([0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)\)/#).compactMap { match in
            let digits = match.output.1, before = name[..<match.range.lowerBound], after = name[match.range.upperBound...]
            guard let count = number(digits), !(digits.count == 4 && (1900...2099).contains(count)),
                  endsABracketWell(after), !isLabelled(before) else { return nil }
            return Reading(before: before + "(", count: count, what: ")", after: String(after))
        }
    }

    /// "2 items", "3 unread messages", "5 new": a number and what is counted, agreeing with it; at the end of the
    /// name or of a bracket, or at the start with nothing after it, or "in …" or "on …".
    private static func counted(_ name: String) -> [Reading] {
        name.matches(of: #/(?:^|(?<before>[ (]))(?<digits>[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+) (?:(?<new>new|unread)(?: (?<newThing>\p{L}+))?|(?<thing>\p{L}+))/#).compactMap { match in
            let out = match.output
            guard let count = number(out.digits) else { return nil }
            // The singular of what is counted, when it is on the list and agrees with the number.
            func noun(_ word: Substring, in list: Set<String>) -> String? {
                let plural = word.hasSuffix("s"), one = plural ? String(word.dropLast()) : String(word)
                return list.contains(one) && (plural || count == 1) ? one : nil
            }
            let what: String, end: String.Index
            if let new = out.new {
                if let thing = out.newThing {
                    guard let one = noun(thing, in: newThings) else { return nil }
                    (what, end) = (new + " " + one, thing.endIndex)
                } else {
                    (what, end) = (String(new), new.endIndex)
                }
            } else if let thing = out.thing, let one = noun(thing, in: things) {
                (what, end) = (one, thing.endIndex)
            } else {
                return nil
            }
            let before = name[..<out.digits.startIndex], after = name[end...]
            guard !isLabelled(before) else { return nil }
            if after.hasPrefix(")") {
                guard endsABracketWell(after.dropFirst()) else { return nil }
            } else if before.isEmpty {
                guard after.isEmpty || after.hasPrefix(" in ") || after.hasPrefix(" on ") else { return nil }
            } else {
                guard after.isEmpty else { return nil }
            }
            return Reading(before: String(before), count: count, what: " " + what, after: String(after))
        }
    }

    private static func number(_ digits: Substring) -> Int? { Int(digits.filter { $0 != "," }) }

    /// After a bracket: the end, or a space, a comma or a colon (not "report (1).pdf"), and no digit next
    /// ("(555) 123-4567").
    private static func endsABracketWell(_ after: Substring) -> Bool {
        guard let first = after.first else { return true }
        return " ,:".contains(first) && after.first { $0 != " " }?.isNumber != true
    }

    private static func isLabelled(_ before: Substring) -> Bool {
        guard let last = before.split(whereSeparator: { $0 == " " || $0 == "(" }).last else { return false }
        return labelWords.contains(last.trimmingCharacters(in: CharacterSet(charactersIn: ",:")))
    }
}

extension NoteAnchor {
    /// The hint's own control, its name changed only by a count: the hint's role, no steady id of its own that is not
    /// the hint's, and not the item's own name, whose numbers are the item's ("Set of 2 chairs").
    func isRecounted(role r: String?, label l: String?, domID id: String?) -> Bool {
        guard let label, let role, role == r, !Self.namesTheItem(label, page: page) else { return false }
        if let mine = domID, let id, Self.isSteadyID(mine), Self.isSteadyID(id), mine != id { return false }
        return ChangingCounts.differOnly(label, l)
    }
}
