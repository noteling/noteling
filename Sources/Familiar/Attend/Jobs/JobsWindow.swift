import SwiftUI

/// Where the Jobs window is: the jobs, a job's page, a matter's page (from its sticker), Who's Who, a person, the editor.
@MainActor final class JobsNavigation: ObservableObject {
    enum Route: Equatable {
        /// Every job in one list (`JobsPage`).
        case jobs
        /// A job's page.
        case folderJob(UUID)
        /// A matter's page, from its sticker or its notification.
        case matter(String)
        /// Who's Who, one person, and the editor (nil: someone new).
        case people, person(UUID), editPerson(UUID?)
    }
    /// Where Back goes from a screen opened from somewhere other than its usual place.
    struct Return: Equatable {
        var from: Route
        var to: Route
    }
    /// Any other way off the screen forgets where Back would have gone.
    @Published var route: Route = .jobs {
        didSet { if let returning, route != returning.from { self.returning = nil } }
    }
    @Published private(set) var returning: Return?

    /// Opens `route` so that Back from it comes back to `origin`.
    func open(_ route: Route, returningTo origin: Route) {
        returning = Return(from: route, to: origin)
        self.route = route
    }

    /// Back: where the screen was opened from, when that was somewhere else than its usual place; otherwise one level
    /// up. A job's page and a matter's page are in Jobs; a person and the editor are in Who's Who, which is beside Jobs.
    func back() {
        if let returning, returning.from == route {
            route = returning.to
            return
        }
        switch route {
        case .person, .editPerson: route = .people
        case .jobs, .folderJob, .matter, .people: route = .jobs
        }
    }

    /// Each screen's heading.
    static func title(for route: Route, jobName: (UUID) -> String?) -> String {
        switch route {
        case .jobs: return "Jobs"
        case .folderJob(let id): return jobName(id) ?? "Job"
        case .matter: return "On your note"
        case .people, .person: return "Who’s Who"
        case .editPerson(let id): return id == nil ? "Someone you work with" : "Edit person"
        }
    }
}

/// The Jobs window's one view: a header with Back, the screen's heading, Who's Who and ×, then the screen: every job in
/// one list, a job's page, a matter's page, Who's Who, a person or the editor.
struct JobsWindowView: View {
    @ObservedObject var navigation: JobsNavigation
    let folderJobs: FolderJobsPanel
    @ObservedObject var people: PeopleStore
    var setup = JobsSetup()
    /// What a job's page does with a file its run left.
    var files = JobFileActions()
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Pad.tabEdge.opacity(0.35))
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [Pad.tabPaper, Pad.fieldPaper], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Pad.tabEdge.opacity(0.6)))
        .foregroundStyle(Pad.ink)
        .environment(\.colorScheme, .light)
        .onExitCommand { if navigation.route == .jobs { close() } else { navigation.back() } }
    }

    private var heading: String {
        JobsNavigation.title(for: navigation.route, jobName: { folderJobs.store.job(id: $0)?.name })
    }

    private var header: some View {
        HStack(spacing: 10) {
            if navigation.route != .jobs {
                Button { navigation.back() } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).accessibilityLabel("Back")
            }
            WindowDragHandle()
                .overlay {
                    HStack(spacing: 10) {
                        Image(systemName: Self.symbol(navigation.route)).foregroundStyle(Pad.inkSoft)
                        Text(heading).font(HandFont.font(size: 18)).lineLimit(1)
                        Spacer()
                    }.allowsHitTesting(false)
                }
                .frame(height: 24)
            if navigation.route == .jobs {
                Button("Who’s Who") { navigation.route = .people }.buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Pad.penInk).help("The people behind your work")
            }
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 12)) }.buttonStyle(.plain).accessibilityLabel("Close Jobs")
        }.padding(.horizontal, 18).padding(.vertical, 15)
    }

    /// The symbol beside the heading: a checklist for the jobs, a folder for a job, a note for a matter, people for Who's Who.
    static func symbol(_ route: JobsNavigation.Route) -> String {
        switch route {
        case .jobs: return "checklist"
        case .folderJob: return "folder"
        case .matter: return "note.text"
        case .people, .person, .editPerson: return "person.2"
        }
    }

    @ViewBuilder private var content: some View {
        switch navigation.route {
        case .jobs:
            JobsPage(folderJobs: folderJobs, setup: setup, navigation: navigation)
        case .folderJob(let id):
            FolderJobPage(store: folderJobs.store, runner: folderJobs.runner, id: id, files: files, setup: setup, notifier: folderJobs.notifier).id(id)
        case .matter(let id):
            if let matters = folderJobs.matters {
                MatterPage(matters: matters, store: folderJobs.store, buttons: folderJobs.buttons, id: id).id(id)
            } else { empty("Stickers are unavailable.") }
        case .people:
            PeopleView(store: people, open: { navigation.route = .person($0) }, edit: { navigation.route = .editPerson($0) })
        case .person(let id):
            if let person = people.person(id: id) { PersonView(person: person, edit: { navigation.route = .editPerson(id) }) }
            else { empty("This person is no longer here.") }
        case .editPerson(let id):
            PersonEditor(person: id.flatMap { people.person(id: $0) }, save: { person in
                try people.save(person); navigation.route = .person(person.id)
            }, remove: {
                if let id { try people.remove(id: id) }
                navigation.route = .people
            }, cancel: { navigation.route = id.map { .person($0) } ?? .people }).id(id)
        }
    }

    private func empty(_ title: String) -> some View { Text(title).font(.system(size: 14)).foregroundStyle(Pad.inkSoft).padding(24) }
}
