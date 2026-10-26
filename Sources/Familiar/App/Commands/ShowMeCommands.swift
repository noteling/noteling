import AppKit

/// `Noteling --show-me <path.json | pack/slug> [--bundle <id>] [--from N] [--until N]`: shows a kept path on the real
/// screen, as the chat's show_me does, and prints each step as it goes. Bring the app to the front first: the steps are
/// looked for in the frontmost app's window (or in `--bundle`'s while nothing else is in front). Needs Accessibility, so
/// run the bundle binary (build/Noteling.app/Contents/MacOS/Noteling).
@MainActor
func runShowMe() {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--show-me"), i + 1 < args.count else {
        print("usage: --show-me <path.json | pack/slug> [--bundle <id>] [--from N] [--until N]"); exit(2)
    }
    func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
    let name = args[i + 1]
    let config = Config.load()
    var path: ShowPath?
    if name.hasSuffix(".json") {
        path = try? JSONDecoder().decode(ShowPath.self, from: Data(contentsOf: URL(fileURLWithPath: name)))
    } else if let slash = name.firstIndex(of: "/") {
        let pack = config.resolvedToolsDir.appendingPathComponent(String(name[..<slash]))
        path = ShowPathStore.load(packDir: pack)[String(name[name.index(after: slash)...])]
    }
    guard let whole = path else { print("no path \(name)"); exit(1) }
    let shown = whole.slice(from: value("--from").flatMap(Int.init), until: value("--until").flatMap(Int.init))
    print("showing “\(shown.title)”: \(shown.route)")
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let tour = ShowTour(path: shown, bundleID: value("--bundle"), hideFromScreenShare: false)
    var last: TourProgress?
    tour.onProgress = { [weak tour] p in
        guard p != last else { return }
        last = p
        print("  \(p.count) \(p.state): \(p.step ?? p.title)")
        fflush(stdout)
        if p.state == .lost { tour?.stop() }   // no one to press Look again
    }
    tour.onFound = { index, rect in
        let top = (NSScreen.screens.first?.frame.maxY ?? 0) - rect.maxY
        print("  found step \(index + 1) at x=\(Int(rect.minX)) y=\(Int(top)) w=\(Int(rect.width)) h=\(Int(rect.height)) (top-left)")
        fflush(stdout)
    }
    tour.onEnd = { p in
        print("ended: \(p.state)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            BrowserAccessibility.settle()
            exit(p.state == .done ? 0 : 1)
        }
    }
    tour.start()
    // The app's own event loop, not the bare run loop: the tour hears clicks and Esc through event monitors, which
    // only NSApplication feeds. An accessory app doesn't come to the front by running it.
    NSApp.run()
}

/// `Noteling --find-step "label" [--role AXButton]`: looks for one control in the window in front, as a tour step
/// does, and says how long it took and how it matched.
@MainActor
func runFindStep() {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--find-step"), i + 1 < args.count else { print("usage: --find-step \"label\" [--role AXButton]"); exit(2) }
    let role = args.firstIndex(of: "--role").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    let step = ShowStep(say: "", role: role, label: args[i + 1])
    guard let (app, window) = ShowFinder.window(fallback: nil) else { print("no window"); exit(1) }
    BrowserAccessibility.hold(app)
    // A browser told just now builds its page in a few seconds: look until found, for up to five.
    for attempt in 1...10 {
        let started = Date()
        let found = ShowFinder.findOnScreen(step, app: app, window: window)
        let ms = Int(Date().timeIntervalSince(started) * 1_000)
        if let found {
            print("attempt \(attempt): \(found.how) visible=\(found.visible) frame=\(found.frame.map { "\($0)" } ?? "none") in \(ms) ms")
            BrowserAccessibility.settle()
            exit(0)
        }
        print("attempt \(attempt): not found in \(ms) ms")
        Thread.sleep(forTimeInterval: 0.5)
    }
    BrowserAccessibility.settle()
    exit(1)
}
