import AppKit
import SwiftUI

/// `Noteling --render-jobs <dir>`: the Jobs window from fictional files, as PNGs for eyeballing. The list, with a job
/// of yours whose last run failed and your team's: one on that found something, one off, one ended and one upcoming;
/// the upcoming and ended jobs shown; a team job's page, the failed job's, an ended and an upcoming one's; the search
/// over many team jobs; two folders that can't be jobs; and a matter's page, as its sticker opens it. Nothing runs a
/// script or reaches a provider.
@MainActor
enum JobsRender {
    static func render(to directory: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = manager.temporaryDirectory.appendingPathComponent("noteling-jobs-render-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: root) }
        func write(_ url: URL, _ text: String) throws {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let own = root.appendingPathComponent("jobs"), team = root.appendingPathComponent("team-tools/jobs")
        let ran = Date().addingTimeInterval(-12 * 60)
        let iso = ISO8601DateFormatter()
        let endedAt = iso.string(from: ran.addingTimeInterval(-3 * 86_400)), startsAt = iso.string(from: ran.addingTimeInterval(5 * 86_400))
        for (folder, json, items) in [
            (team.appendingPathComponent("holiday/oct/gm"),
             #"{"name": "Holiday Oct · GM (fictional)", "about": "Price, strikethrough, badge and seller on the GM event items, against what the team expects.", "every_minutes": 60, "contributor": "Yang", "map": {"id": "item", "where": "page", "what": "problem"}}"#,
             "item,price,strikethrough,badge,seller\nK-1,16.99,26.99,Reduced price,Acme\nK-2,16.99,26.99,,Acme\nK-3,14.99,26.99,,Acme\nK-4,119.97,179,,Example Store\n"),
            (team.appendingPathComponent("holiday/oct/fashion"), #"{"name": "Holiday Oct · Fashion (fictional)", "every_minutes": 120}"#, "item,price\nF-1,12.33\n"),
            (team.appendingPathComponent("autumn/sale"), #"{"name": "Autumn sale (fictional)", "every_minutes": 60, "ends": "\#(endedAt)"}"#, "item\nA-1\n"),
            (team.appendingPathComponent("winter/launch"), #"{"name": "Winter launch (fictional)", "about": "Badges on the winter launch items.", "every_minutes": 30, "starts": "\#(startsAt)"}"#, ""),
            (own.appendingPathComponent("stuck-orders"), #"{"name": "Stuck orders (fictional)", "about": "Orders waiting on me for more than a day.", "every_minutes": 240}"#, ""),
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

        // What the GM job's last run left: two of four items as findings, and every result to take away.
        let columns = ["item", "problem", "price", "expected", "page"]
        let rows = [
            FindingRow(id: "K-1", values: ["item": "K-1", "problem": "price shows 18.99", "price": "18.99", "expected": "16.99",
                                           "page": "https://shop.example.test/items/K-1"], columns: columns),
            FindingRow(id: "K-3", values: ["item": "K-3", "problem": "couldn't check: the page took longer than 60 seconds", "price": "",
                                           "expected": "14.99", "page": "https://shop.example.test/items/K-3"], columns: columns),
        ]
        let output = store.output(for: gm)
        try write(output.appendingPathComponent(FolderJobFiles.findings), """
            item,problem,price,expected,page
            K-1,price shows 18.99,18.99,16.99,https://shop.example.test/items/K-1
            K-3,couldn't check: the page took longer than 60 seconds,,14.99,https://shop.example.test/items/K-3
            """ + "\n")
        try write(output.appendingPathComponent("all.csv"), "item,price,checked_at\nK-1,18.99,9:47 AM\nK-2,16.99,9:47 AM\nK-3,,9:47 AM\nK-4,119.97,9:47 AM\n")
        var snapshot = FindingsSnapshot()
        snapshot.columns = columns
        snapshot.rows = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, FindingsSnapshot.Kept(row: $0, firstSeen: ran, changedAt: nil)) })
        try snapshot.write(to: store.findingsFile(for: gm))
        try store.record(gm.id, FolderJobState(lastRunAt: ran, lastSuccessAt: ran, source: "the event pages", read: 4, found: 2))
        let before = ran.addingTimeInterval(-4 * 86_400)
        try store.record(autumn.id, FolderJobState(lastRunAt: before, lastSuccessAt: before, source: "the event pages", read: 3, found: 1))
        try store.record(stuck.id, FolderJobState(lastRunAt: ran.addingTimeInterval(-3_600), error: "The orders service asked to sign in again."))

        // The minister's matter for the first finding, as its sticker opens it.
        let matters = Matters(directory: root.appendingPathComponent("matters"))
        let matter = Matter(id: "gm-k-1", findings: [FindingRef(job: "team/holiday/oct/gm", id: "K-1")], state: .open,
                            view: MatterView(text: "K-1 shows 18.99 on the event page; the team expects 16.99. The event price starts at 9 AM, so look again after that before raising it.", tone: .calm),
                            jobName: gm.name, byline: "Yang", createdAt: ran, updatedAt: ran)
        matters.save(matter)
        matters.save(Matter(id: "gm-k-3", findings: [FindingRef(job: "team/holiday/oct/gm", id: "K-3")], state: .quiet,
                            why: "The page timed out, which says nothing about the price; the next run checks it again.",
                            jobName: gm.name, byline: "Yang", createdAt: ran, updatedAt: ran))
        let buttons = FolderJobButtons(store: store, execute: { _ in NSNull() })
        buttons.hasSecret = { _ in true }
        var panel = FolderJobsPanel(store: store, runner: runner, notifier: JobNotifier(), buttons: buttons)
        panel.matters = matters

        let navigation = JobsNavigation()
        let setup = JobsSetup(openSettings: {})
        func save(_ name: String, _ route: JobsNavigation.Route, height: CGFloat? = nil) throws {
            navigation.route = route
            try image(JobsWindowView(navigation: navigation, folderJobs: panel, setup: setup, close: {}),
                      size: NSSize(width: JobsWindowController.width, height: height ?? JobsWindowController.preferredHeight(for: route)),
                      to: directory.appendingPathComponent(name))
        }
        try save("jobs.png", .jobs)
        try save("job-team.png", .folderJob(gm.id), height: 1_250)
        try save("job-failed.png", .folderJob(stuck.id))
        try save("job-ended.png", .folderJob(autumn.id))
        if let winter = store.jobs.first(where: { $0.path == "winter/launch" }) { try save("job-upcoming.png", .folderJob(winter.id)) }
        try save("matter.png", .matter(matter.id))
        try save("matter-quiet.png", .matter("gm-k-3"))
        func page(_ name: String, height: CGFloat, showingOutside: Bool = false) throws {
            try image(JobsPage(folderJobs: panel, setup: setup, navigation: navigation, showingOutside: showingOutside)
                .foregroundStyle(Pad.ink).background(Pad.fieldPaper),
                      size: NSSize(width: JobsWindowController.width, height: height), to: directory.appendingPathComponent(name))
        }
        try page("jobs-outside-shown.png", height: 900, showingOutside: true)

        // Your team's jobs past a handful, with a search kept from last time: only those that match, and the ones on.
        for (path, name) in [("spring/shoes", "Spring · Shoes"), ("spring/garden", "Spring · Garden"), ("home/kitchen", "Kitchen"),
                             ("home/bath", "Bath"), ("back-to-school/backpacks", "Backpacks"), ("holiday/oct/toys", "Holiday Oct · Toys")] {
            try write(team.appendingPathComponent(path).appendingPathComponent("job.json"), #"{"name": "\#(name) (fictional)", "every_minutes": 120}"#)
            try write(team.appendingPathComponent(path).appendingPathComponent("job.py"), "def run():\n    return None\n")
        }
        store.refresh()
        store.setSearch("holiday")
        try page("jobs-search.png", height: 900)
        store.setSearch("")

        // Folders that can't be jobs: one of yours without its job.py, and a team job.json that isn't JSON, each with
        // what it means.
        try write(own.appendingPathComponent("new-check/job.json"), #"{"name": "New check (fictional)"}"#)
        try write(team.appendingPathComponent("spring/hats/job.json"), #"{"name": "Spring · Hats" "every_minutes": 60}"#)
        try write(team.appendingPathComponent("spring/hats/job.py"), "def run():\n    return None\n")
        store.refresh()
        try page("jobs-problems.png", height: 900)
    }

    static func image<V: View>(_ view: V, size: NSSize, to url: URL) throws {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .light).frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw RenderError.bitmap }
        bitmap.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw RenderError.encoding }
        try data.write(to: url)
        print("wrote \(url.lastPathComponent) \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
    }
    private enum RenderError: Error { case bitmap, encoding }
}
