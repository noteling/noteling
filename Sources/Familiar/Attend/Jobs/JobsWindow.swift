import SwiftUI

/// Where the Jobs window is: the jobs, a job's page, or a matter's page (from its sticker).
@MainActor final class JobsNavigation: ObservableObject {
    enum Route: Equatable {
        /// Every job in one list (`JobsPage`).
        case jobs
        /// A job's page.
        case folderJob(UUID)
        /// A matter's page, from its sticker or its notification.
        case matter(String)
        /// The receipt: what came of the deck today.
        case receipt
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

    /// Back: where the screen was opened from, when that was somewhere else than its usual place; otherwise Jobs,
    /// which every page is one step from.
    func back() {
        if let returning, returning.from == route {
            route = returning.to
            return
        }
        route = .jobs
    }

    /// Each screen's heading; a matter's says whether it is on a sticker, kept quiet, or over.
    static func title(for route: Route, jobName: (UUID) -> String?, matterState: (String) -> Matter.State? = { _ in nil }) -> String {
        switch route {
        case .jobs: return "Jobs"
        case .receipt: return "What's been handled"
        case .folderJob(let id): return jobName(id) ?? "Job"
        case .matter(let id):
            switch matterState(id) {
            case .quiet: return "Kept quiet"
            case .yours: return "Yours"
            case .closed: return "Over"
            case .open, nil: return "On your note"
            }
        }
    }
}

/// The Jobs window's one view: a header with Back, the screen's heading and ×, then the screen: every job in one list,
/// a job's page, or a matter's page.
struct JobsWindowView: View {
    @ObservedObject var navigation: JobsNavigation
    let folderJobs: FolderJobsPanel
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
        JobsNavigation.title(for: navigation.route, jobName: { folderJobs.store.job(id: $0)?.name },
                             matterState: { folderJobs.matters?.matter(id: $0)?.state })
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
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 12)) }.buttonStyle(.plain).accessibilityLabel("Close Jobs")
        }.padding(.horizontal, 18).padding(.vertical, 15)
    }

    /// The symbol beside the heading: a checklist for the jobs, a folder for a job, a note for a matter.
    static func symbol(_ route: JobsNavigation.Route) -> String {
        switch route {
        case .jobs: return "checklist"
        case .receipt: return "checkmark.seal"
        case .folderJob: return "folder"
        case .matter: return "note.text"
        }
    }

    @ViewBuilder private var content: some View {
        switch navigation.route {
        case .jobs:
            JobsPage(folderJobs: folderJobs, setup: setup, navigation: navigation)
        case .folderJob(let id):
            FolderJobPage(store: folderJobs.store, runner: folderJobs.runner, id: id, files: files, setup: setup, notifier: folderJobs.notifier,
                          matters: folderJobs.matters, openMatter: { navigation.open(.matter($0), returningTo: .folderJob(id)) }).id(id)
        case .matter(let id):
            if let matters = folderJobs.matters {
                MatterPage(matters: matters, store: folderJobs.store, buttons: folderJobs.buttons, id: id, mine: folderJobs.mine).id(id)
            } else { Text("Stickers are unavailable.").font(.system(size: 14)).foregroundStyle(Pad.inkSoft).padding(24) }
        case .receipt:
            if let matters = folderJobs.matters {
                ReceiptPage(matters: matters, log: folderJobs.runner.memory, lessons: folderJobs.lessons, open: { navigation.open(.matter($0), returningTo: .receipt) })
            } else { Text("Stickers are unavailable.").font(.system(size: 14)).foregroundStyle(Pad.inkSoft).padding(24) }
        }
    }
}
