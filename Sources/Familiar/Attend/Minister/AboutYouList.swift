import SwiftUI

/// The receipt's "About you & your people": everything the profile keeps, one line a fact with where it came from, Fix
/// and Forget on each; the people past the prompt's cap are marked; typing a fact here is the fallback, never the way in.
struct AboutYouList: View {
    @ObservedObject var profile: Profile
    var now: Date

    static let title = "About you & your people"
    /// Checked against what Noteling does: the block goes into the minister's turns and the pen, chat and headless ask.
    static let consentWords = "Kept on this Mac. Noteling includes it in what it asks the model, so answers and cards know who matters to you."
    static let consent = Text(consentWords).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)

    @State private var editing: String?
    @State private var draft = ""
    @State private var relation: Relation = .teammate
    @State private var words = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Self.consent.fixedSize(horizontal: false, vertical: true)
            ForEach(AboutMe.Field.allCases) { field in meRow(field) }
            let past = profile.pastCap
            ForEach(profile.ordered) { person in personRow(person, past: past.contains(person.id)) }
            if editing == "new" { personEditor(id: nil) } else {
                Button("Add a person") { start("new", name: "", relation: .teammate, words: "") }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
            }
            if let problem { Text(problem).font(.system(size: 12)).foregroundStyle(Pad.redInk).fixedSize(horizontal: false, vertical: true) }
        }
    }

    /// A field Fix brought from "Is this you?": "Your name: Sam Lee? Fix and keep".
    static func drafted(_ field: AboutMe.Field, _ text: String) -> String { "Your \(field.label.lowercased()): \(text)? Fix and keep" }

    /// Where a fact kept on the page came from: the draft as it was is `drafted`; anything changed is the person's own.
    static func from(_ field: AboutMe.Field, kept text: String, fixing: AboutYouDraft?) -> FactSource {
        guard let drafted = fixing?[field], let kept = try? Profile.line(text, what: "draft"), kept == drafted else { return .typed }
        return .drafted
    }

    static func source(_ from: FactSource, at: Date, now: Date) -> String {
        from.words.prefix(1).uppercased() + from.words.dropFirst() + ", " + JobWords.time(at, now: now)
    }

    @ViewBuilder private func meRow(_ field: AboutMe.Field) -> some View {
        let key = "me." + field.rawValue
        if editing == key {
            HStack(spacing: 8) {
                TextField(field.label, text: $draft).textFieldStyle(.roundedBorder).font(.system(size: 13)).onSubmit { keep(field) }
                Button("Keep") { keep(field) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
                Button("Cancel") { editing = nil }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
            }
        } else if let fact = profile.me[field] {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label + ": " + fact.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    Text(Self.source(fact.from, at: fact.at, now: now)).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                }
                Spacer(minLength: 8)
                Button("Fix") { start(key, name: fact.text) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
                Button("Forget") { profile.forget(field) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
                    .help("Gone from the next thing Noteling asks the model")
            }
        } else if let drafted = profile.fixing?[field] {
            // From "Is this you?" → Fix: the draft filled in, kept only once the person keeps it.
            Button(Self.drafted(field, drafted)) { start(key, name: drafted) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
        } else {
            Button("Add your " + field.label.lowercased()) { start(key, name: "") }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
        }
    }

    @ViewBuilder private func personRow(_ person: Person, past: Bool) -> some View {
        if editing == person.id { personEditor(id: person.id) } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Profile.line(person)).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    Text(Self.source(person.from, at: person.at, now: now) + (past ? " · on this page only, past what fits in a prompt" : ""))
                        .font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                }
                Spacer(minLength: 8)
                Button("Fix") { start(person.id, name: person.name, relation: person.relation, words: person.words ?? "") }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
                Button("Forget") { profile.forget(person: person.id) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
                    .help("Gone from the next thing Noteling asks the model")
            }
        }
    }

    private func personEditor(id: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name", text: $draft).textFieldStyle(.roundedBorder).font(.system(size: 13))
            Picker("", selection: $relation) { ForEach(Relation.allCases) { Text($0.label).tag($0) } }.labelsHidden().pickerStyle(.segmented)
            TextField("In your words (optional): runs the warehouse", text: $words).textFieldStyle(.roundedBorder).font(.system(size: 13))
            HStack(spacing: 10) {
                Button("Keep") { keepPerson(id: id) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
                Button("Cancel") { editing = nil }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
            }
        }
    }

    private func start(_ key: String, name: String, relation: Relation = .teammate, words: String = "") {
        editing = key
        draft = name
        self.relation = relation
        self.words = words
        problem = nil
    }

    private func keep(_ field: AboutMe.Field) {
        do {
            // The name also goes to the Settings author (Profile.onName).
            try profile.keep(field, draft, from: Self.from(field, kept: draft, fixing: profile.fixing))
            editing = nil
            problem = nil
        } catch { problem = error.localizedDescription }
    }

    private func keepPerson(id: String?) {
        do {
            // A fixed name is the same person; a name someone else goes by is refused, never merged.
            if let id {
                try profile.fix(person: id, name: draft, relation: relation, words: words, from: .typed)
            } else {
                try profile.keep(person: draft, relation: relation, words: words, from: .typed)
            }
            editing = nil
            problem = nil
        } catch { problem = error.localizedDescription }
    }
}
