import AppKit
import SwiftUI

/// Jobs kept as folders, from fictional files: the Jobs list with a job of yours that ran and your team's (one on,
/// one off, one ended), a job's page with its input, its preview table and text and the files to take away, its card
/// in Morning Files with the same, and the job's folder there. Nothing runs a script.
extension MorningRender {
    @MainActor static func renderFolderJobs(fixtures: URL, directory: URL) throws {
        let root = fixtures.appendingPathComponent("folder-jobs")
        let manager = FileManager.default
        func write(_ url: URL, _ text: String) throws {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let own = root.appendingPathComponent("jobs"), team = root.appendingPathComponent("team-tools/jobs")
        let ran = Date().addingTimeInterval(-12 * 60)
        let iso = ISO8601DateFormatter()
        for (folder, json, items) in [
            (team.appendingPathComponent("holiday/oct/gm"),
             #"{"name": "Holiday Oct · GM (fictional)", "about": "Price, strikethrough, badge and seller on the GM event items, against what the team expects.", "every_minutes": 60, "contributor": "Yang"}"#,
             "item,price,strikethrough,badge,seller\nK-1,16.99,26.99,Reduced price,Acme\nK-2,16.99,26.99,,Acme\nK-3,14.99,26.99,,Acme\nK-4,119.97,179,,Example Store\n"),
            (team.appendingPathComponent("holiday/oct/fashion"), #"{"name": "Holiday Oct · Fashion (fictional)", "every_minutes": 120}"#, "item,price\nF-1,12.33\n"),
            (team.appendingPathComponent("autumn/sale"),
             #"{"name": "Autumn sale (fictional)", "every_minutes": 60, "ends": "\#(iso.string(from: ran.addingTimeInterval(-3 * 86_400)))"}"#, "item\nA-1\n"),
            (own.appendingPathComponent("stuck-orders"), #"{"name": "Stuck orders (fictional)", "about": "Orders waiting on me for more than a day."}"#, ""),
        ] {
            try write(folder.appendingPathComponent("job.json"), json)
            try write(folder.appendingPathComponent("job.py"), "def run():\n    return None\n")
            if !items.isEmpty { try write(folder.appendingPathComponent("input/items.csv"), items) }
        }
        let store = FolderJobStore(directory: own, results: root.appendingPathComponent("job-results"), teamDirectory: { team })
        let runner = FolderJobRunner(store: store, execute: { _ in NSNull() })
        guard let gm = store.jobs.first(where: { $0.path == "holiday/oct/gm" }), let autumn = store.jobs.first(where: { $0.path == "autumn/sale" }),
              let stuck = store.jobs.first(where: { $0.path == "stuck-orders" }) else { return }
        try store.setOn(gm.id, true)
        try store.setOn(autumn.id, true)

        // What the GM job's last run left: its preview, a table and a note, and every result to take away.
        let output = store.output(for: gm)
        try write(output.appendingPathComponent("preview/problems.csv"), """
            item,title,what's wrong,why
            K-1,"Plant pots, set of 5 – green (fictional)",price shows 18.99 – expected 16.99,The page shows the list price; the event price starts at 9 AM.
            K-3,"Plant pots, set of 5 – black (fictional)",couldn't check,The page took longer than 60 seconds.
            """ + "\n")
        try write(output.appendingPathComponent("preview/summary.txt"),
                  "2 of 4 items need a look. Prices were read from the live pages for zip 10001.\n")
        try write(output.appendingPathComponent("all.csv"), "item,price,checked_at\nK-1,18.99,9:47 AM\nK-2,16.99,9:47 AM\nK-3,,9:47 AM\nK-4,119.97,9:47 AM\n")
        try write(output.appendingPathComponent("raw/pages.json"), "{}\n")
        try store.record(gm.id, FolderJobState(lastRunAt: ran, lastSuccessAt: ran, said: "2 of 4 items need a look",
                                               preview: FolderJobFiles.previewDigest(output: output)))
        try store.record(autumn.id, FolderJobState(lastRunAt: ran.addingTimeInterval(-4 * 86_400), lastSuccessAt: ran.addingTimeInterval(-4 * 86_400),
                                                   said: "1 of 3 items need a look", preview: "fictional"))
        try store.record(stuck.id, FolderJobState(lastRunAt: ran.addingTimeInterval(-3_600), error: "The orders service asked to sign in again."))

        let morning = MorningStore(directory: root.appendingPathComponent("morning"))
        let inbox = root.appendingPathComponent("cards-inbox")
        let cards = FolderJobCards(root: inbox)
        cards.reconcile(store.jobs)
        let scan = CardInbox(store: morning, directory: inbox)
        scan.folderName = { source in store.jobs.first { FolderJobCards.source(for: $0) == source }?.name }
        scan.scan()

        let panel = FolderJobsPanel(store: store, runner: runner, notifier: JobNotifier())
        let navigation = MorningNavigation()
        func save(_ name: String, _ route: MorningNavigation.Route, height: CGFloat? = nil) throws {
            navigation.route = route
            try image(MorningFilesView(store: morning, navigation: navigation, close: {}, filed: {}, handoff: { _ in }, folderJobs: panel),
                      size: NSSize(width: MorningPanelController.preferredWidth(for: route),
                                   height: height ?? MorningPanelController.preferredHeight(for: route, isEmpty: false)),
                      to: directory.appendingPathComponent(name))
        }
        try save("folder-jobs-home.png", .folders)
        try save("folder-jobs.png", .jobs)
        try save("folder-job-page.png", .folderJob(gm.id), height: 1_250)
        try save("folder-job-failed.png", .folderJob(stuck.id))
        let card = CardInboxFormat.cardID(FolderJobCards.key(for: gm))
        if let folder = morning.cards.first(where: { $0.id == card })?.folderID { try save("folder-job-folder.png", .folder(folder)) }
        try save("folder-job-card.png", .card(card), height: 1_000)

        // Your team's jobs past a handful, with a search kept from last time: only those that match, and the ones on.
        for (path, name) in [("spring/shoes", "Spring · Shoes"), ("spring/garden", "Spring · Garden"), ("home/kitchen", "Kitchen"),
                             ("home/bath", "Bath"), ("back-to-school/backpacks", "Backpacks"), ("holiday/oct/toys", "Holiday Oct · Toys")] {
            try write(team.appendingPathComponent(path).appendingPathComponent("job.json"), #"{"name": "\#(name) (fictional)", "every_minutes": 120}"#)
            try write(team.appendingPathComponent(path).appendingPathComponent("job.py"), "def run():\n    return None\n")
        }
        store.refresh()
        store.setSearch("holiday")
        try image(JobsPage(morning: morning, sources: nil, runner: nil, navigation: navigation, folderJobs: panel)
            .foregroundStyle(Pad.ink).background(Pad.fieldPaper), size: NSSize(width: 650, height: 900),
            to: directory.appendingPathComponent("folder-jobs-search.png"))
        store.setSearch("")
        try image(JobsPage(morning: morning, sources: nil, runner: nil, navigation: navigation, showingOutside: true,
                           folderJobs: panel)
            .foregroundStyle(Pad.ink).background(Pad.fieldPaper), size: NSSize(width: 650, height: 760),
            to: directory.appendingPathComponent("folder-jobs-outside-shown.png"))
    }
}
