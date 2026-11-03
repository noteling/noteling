import SwiftUI

/// Who's Who: the people behind the work, one row each, and a way to add one.
struct PeopleView: View {
    @ObservedObject var store: PeopleStore
    let open: (UUID) -> Void
    let edit: (UUID?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("The people behind your work.").font(HandFont.font(size: 23))
                Text("Roles, relationships, and the context you’d want a helpful colleague to know. You can correct these at any time.")
                    .font(.system(size: 13)).foregroundStyle(Pad.inkSoft)
                if let error = store.error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Pad.redInk).textSelection(.enabled)
                }
                Button { edit(nil) } label: { Label("Add a person", systemImage: "plus") }.buttonStyle(PaperActionButton(primary: true))
                ForEach(store.people) { person in
                    Button { open(person.id) } label: {
                        HStack(spacing: 12) {
                            Text(String(person.name.prefix(1)).uppercased()).font(HandFont.font(size: 21)).frame(width: 38, height: 38).background(Pad.paperTop, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.name + (person.isMe ? " · me" : "")).font(.system(size: 14, weight: .medium))
                                Text([person.role, person.relationship].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                            }
                            Spacer(); Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Pad.inkSoft)
                        }.padding(12).background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).contextMenu { Button("Edit person") { edit(person.id) } }
                }
                if store.people.isEmpty { Text("Start with yourself, then add someone you work with.").font(.system(size: 13)).foregroundStyle(Pad.inkSoft).padding(.top, 15) }
            }.padding(22)
        }
    }
}

/// One person: what Who's Who knows about them, and Edit.
struct PersonView: View {
    let person: Person
    let edit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(person.name).font(HandFont.font(size: 28))
                    if person.isMe { Text("YOU").font(.system(size: 10, weight: .semibold)).padding(5).background(Pad.paperTop, in: Capsule()) }
                    Spacer()
                    Button("Edit", action: edit).buttonStyle(PaperActionButton())
                }
                if !person.role.isEmpty { section("Role & team", icon: "building.2", text: person.role) }
                if !person.relationship.isEmpty { section("Relationship to you", icon: "person.2", text: person.relationship) }
                if !person.context.isEmpty { section("Working context", icon: "note.text", text: person.context) }
                if !person.identities.isEmpty { section("Names & identities across tools", icon: "at", text: person.identities.joined(separator: "\n")) }
            }.padding(23)
        }
    }

    private func section(_ title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(Pad.inkSoft)
            Text(text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
        }
    }
}

/// The editor for one person, new or existing; an existing one can be removed from here.
struct PersonEditor: View {
    private let existingID: UUID
    private let isNew: Bool
    let save: (Person) throws -> Void
    let remove: () throws -> Void
    let cancel: () -> Void
    @State private var name: String
    @State private var role: String
    @State private var relationship: String
    @State private var context: String
    @State private var identities: String
    @State private var isMe: Bool
    @State private var error: String?
    @State private var removing = false

    init(person: Person?, save: @escaping (Person) throws -> Void, remove: @escaping () throws -> Void = {}, cancel: @escaping () -> Void) {
        existingID = person?.id ?? UUID()
        isNew = person == nil
        self.save = save; self.remove = remove; self.cancel = cancel
        _name = State(initialValue: person?.name ?? "")
        _role = State(initialValue: person?.role ?? "")
        _relationship = State(initialValue: person?.relationship ?? "")
        _context = State(initialValue: person?.context ?? "")
        _identities = State(initialValue: person?.identities.joined(separator: "\n") ?? "")
        _isMe = State(initialValue: person?.isMe ?? false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                PaperField("Name", text: $name, placeholder: "Maya Chen")
                Toggle("This is me", isOn: $isMe).font(.system(size: 13))
                PaperField("Role & team", text: $role, placeholder: "Product lead · platform team")
                PaperField("Relationship to you", text: $relationship, placeholder: "My project partner")
                PaperTextField("Working context", text: $context, hint: "Shared projects, responsibilities, commitments, or anything Noteling should understand.", minHeight: 95)
                PaperTextField("Names & identities across tools", text: $identities, hint: "One per line, for example an email address, Jira username, or nickname.", minHeight: 72)
                Text("Kept on this Mac, in Noteling’s folder. You can correct it at any time.").font(.system(size: 11)).foregroundStyle(Pad.inkSoft)
                EditorFooter(error: error, saveTitle: "Save person", enabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, save: {
                    do {
                        try save(Person(id: existingID, name: name, role: role, relationship: relationship, context: context,
                                        identities: identities.components(separatedBy: .newlines), isMe: isMe))
                    } catch { self.error = error.localizedDescription }
                }, cancel: cancel)
                if !isNew {
                    if removing {
                        HStack(spacing: 10) {
                            Text("Remove \(name.isEmpty ? "this person" : name) from Who’s Who?").font(.system(size: 12))
                            Button("Remove") { do { try remove() } catch { self.error = error.localizedDescription } }.buttonStyle(PaperActionButton(primary: true))
                            Button("Keep") { removing = false }.buttonStyle(PaperActionButton())
                        }
                    } else {
                        Button("Remove person") { removing = true }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.redInk)
                    }
                }
            }.padding(23)
        }
    }
}

private struct PaperField: View {
    let title: String
    @Binding var text: String
    var placeholder: String
    init(_ title: String, text: Binding<String>, placeholder: String = "") { self.title = title; _text = text; self.placeholder = placeholder }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Pad.inkSoft)
            TextField(placeholder, text: $text).textFieldStyle(.roundedBorder).font(.system(size: 13)).accessibilityLabel(title)
        }
    }
}

private struct PaperTextField: View {
    let title: String
    @Binding var text: String
    var hint: String
    var minHeight: CGFloat
    init(_ title: String, text: Binding<String>, hint: String, minHeight: CGFloat) { self.title = title; _text = text; self.hint = hint; self.minHeight = minHeight }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Pad.inkSoft)
            TextEditor(text: $text).font(.system(size: 13)).frame(minHeight: minHeight).scrollContentBackground(.hidden)
                .padding(6).background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Pad.tabEdge.opacity(0.6))).accessibilityLabel(title)
            Text(hint).font(.system(size: 10)).foregroundStyle(Pad.inkSoft)
        }
    }
}

private struct EditorFooter: View {
    let error: String?
    let saveTitle: String
    let enabled: Bool
    let save: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error { Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Pad.redInk).textSelection(.enabled) }
            HStack {
                Button("Cancel", action: cancel).buttonStyle(PaperActionButton())
                Spacer()
                Button(saveTitle, action: save).buttonStyle(PaperActionButton(primary: true)).disabled(!enabled).opacity(enabled ? 1 : 0.5)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }.padding(.top, 5)
    }
}
