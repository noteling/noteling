import AppKit
import ApplicationServices

/// `Noteling --background-click <bundle-id> --label "<control text>" [--count N]`: clicks one control in that app's
/// window by coordinates through the SkyLight rung, the way the background lane does when precise clicks are on,
/// while another app stays in front. Prints the invariants the rung promises and whether the app reacted:
/// the frontmost app and the real cursor don't move, Noteling never activates, and the target doesn't stay active.
/// Needs Accessibility (and Screen Recording for the pixel check), so run the bundle binary
/// (build/Noteling.app/Contents/MacOS/Noteling). Exit 0 when every invariant held and the control reacted.
@MainActor
func runBackgroundClick() async -> Int32 {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--background-click"), i + 1 < args.count,
          let l = args.firstIndex(of: "--label"), l + 1 < args.count else {
        print("usage: --background-click <bundle-id> --label \"<control text>\" [--title <window title part>] [--count N] [--trust]")
        return 2
    }
    let bundleID = args[i + 1], label = args[l + 1].lowercased()
    func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
    let count = value("--count").flatMap(Int.init) ?? 1
    let titlePart = value("--title")?.lowercased()
    let trust = args.contains("--trust")   // skip the self-test: is the click path itself alive on a real target?

    let windows = TargetWindow.list().filter { d in
        d.bundleID == bundleID && (titlePart.map { d.title.lowercased().contains($0) } ?? true)
    }
    guard let descriptor = windows.sorted(by: { $0.isOnScreen && !$1.isOnScreen }).first else {
        let others = TargetWindow.list().filter { $0.bundleID == bundleID }.map { "“\($0.title.prefix(50))”" }
        print("no window of \(bundleID)\(titlePart.map { " titled like “\($0)”" } ?? ""); \(others.isEmpty ? "is the app running with a window?" : "its windows: \(others.joined(separator: ", "))")")
        return 1
    }
    guard case .success(var target) = await TargetWindow.resolve(windowID: CGWindowID(descriptor.id)) else {
        print("could not resolve window \(descriptor.id) “\(descriptor.title)”")
        return 1
    }
    print("target: \(target.appName) “\(target.title.prefix(60))” \(target.toolkit.rawValue) window \(target.cgWindowID) at \(Int(target.frameCG.minX)),\(Int(target.frameCG.minY)) \(Int(target.frameCG.width))x\(Int(target.frameCG.height))")
    var warm: TargetWindow.AXWarmUp?
    if target.toolkit == .chromium || target.toolkit == .electron {
        warm = await target.warmUpAccessibility()
        print("accessibility warmed up\(target.axDegraded ? " (no web tree: pixels only)" : "")")
    }
    defer { if let warm { target.restoreAccessibility(warm) } }

    guard let (element, frame) = BackgroundClickProbe.find(label: label, under: target.axWindow) else {
        print("no control whose name contains “\(label)” in that window")
        return 1
    }
    let center = CGPoint(x: frame.midX, y: frame.midY)
    let space = target.space(maxLongEdge: 1568)
    print("control: “\(AX.string(element, kAXTitleAttribute) ?? AX.string(element, kAXDescriptionAttribute) ?? label)” \(AX.string(element, kAXRoleAttribute) ?? "") at \(Int(center.x)),\(Int(center.y))")

    let ready: Bool
    if trust {
        SkyLightClick.shared.assumeReady()
        ready = true
    } else {
        ready = await SkyLightClick.shared.prepare(flagOn: true)
    }
    print("skylight: \(SkyLightClick.shared.state)\(trust ? " (self-test skipped)" : "")")
    guard ready else { return 1 }

    let front0 = NSWorkspace.shared.frontmostApplication
    let mouse0 = NSEvent.mouseLocation
    let before = await ActionVerifier.snapshot(target: target, element: element, cropAroundCG: center)
    let t0 = Date()
    let completed = await SkyLightClick.shared.click(target: target, globalCG: center, local: space.local(fromCG: center),
                                                     button: .left, count: count, flags: [])
    let clickMs = Int(Date().timeIntervalSince(t0) * 1000)
    let trustAX = target.toolkit != .electron && !target.axDegraded
    let verdict = await ActionVerifier.verify(before: before, expecting: .anyChange, trustAX: trustAX) {
        await ActionVerifier.snapshot(target: target, element: element, cropAroundCG: center)
    }
    try? await Task.sleep(nanoseconds: 150_000_000)
    let front1 = NSWorkspace.shared.frontmostApplication
    let mouse1 = NSEvent.mouseLocation
    let targetFront = BackgroundClickProbe.bool(target.axApp, kAXFrontmostAttribute) ?? false

    let checks = BackgroundClickProbe.checks(completed: completed, verdict: verdict,
                                             frontBefore: front0?.processIdentifier, frontAfter: front1?.processIdentifier,
                                             mouseBefore: mouse0, mouseAfter: mouse1,
                                             notelingActive: NSApplication.shared.isActive, targetFrontmostAfter: targetFront)
    print("click sequence \(completed ? "completed" : "did not complete") in \(clickMs) ms; app reaction: \(verdict)")
    for c in checks { print("  \(c.ok ? "PASS" : "FAIL") \(c.name)\(c.detail.isEmpty ? "" : ": \(c.detail)")") }
    print("front: \(front0?.localizedName ?? "?") → \(front1?.localizedName ?? "?"); cursor: \(Int(mouse0.x)),\(Int(mouse0.y)) → \(Int(mouse1.x)),\(Int(mouse1.y))")
    if let say = value("--say")?.lowercased() {
        // What the window says now: static texts and values containing the word, e.g. a page's own report of the click.
        let texts = BackgroundClickProbe.texts(containing: say, under: target.axWindow)
        print(texts.isEmpty ? "the window shows nothing containing “\(say)”" : "the window says: " + texts.joined(separator: " | "))
    }
    return checks.allSatisfy(\.ok) ? 0 : 1
}

enum BackgroundClickProbe {
    struct Check { let name: String; let ok: Bool; let detail: String }

    /// Pure. The promises of a background click, as pass/fail lines.
    nonisolated static func checks(completed: Bool, verdict: Verdict, frontBefore: pid_t?, frontAfter: pid_t?,
                                   mouseBefore: NSPoint, mouseAfter: NSPoint, notelingActive: Bool, targetFrontmostAfter: Bool) -> [Check] {
        let reacted: (Bool, String)
        switch verdict {
        case .confirmed(let evidence): reacted = (true, evidence)
        case .unverifiable(let why): reacted = (false, "unverifiable: \(why)")
        case .noEffect(let why): reacted = (false, "no effect: \(why)")
        }
        let moved = hypot(mouseAfter.x - mouseBefore.x, mouseAfter.y - mouseBefore.y)
        return [
            Check(name: "click sequence completed", ok: completed, detail: ""),
            Check(name: "the control reacted", ok: reacted.0, detail: reacted.1),
            Check(name: "frontmost app unchanged", ok: frontBefore == frontAfter, detail: frontBefore == frontAfter ? "" : "\(frontBefore ?? 0) → \(frontAfter ?? 0)"),
            Check(name: "real cursor unmoved", ok: moved < 1, detail: moved < 1 ? "" : "moved \(Int(moved)) pt"),
            Check(name: "Noteling never activated", ok: !notelingActive, detail: ""),
            Check(name: "target not left active", ok: !targetFrontmostAfter, detail: ""),
        ]
    }

    /// Breadth-first search of the window for a control whose title, description or value contains `label`
    /// (lowercased), with a frame. Groups and static text are skipped so a button wins over the text inside it.
    @MainActor static func find(label: String, under root: AXUIElement) -> (AXUIElement, CGRect)? {
        var queue: [AXUIElement] = [root]
        var visited = 0
        var fallback: (AXUIElement, CGRect)?
        while !queue.isEmpty, visited < 4000 {
            let el = queue.removeFirst()
            visited += 1
            let names = [AX.string(el, kAXTitleAttribute), AX.string(el, kAXDescriptionAttribute), AX.string(el, kAXValueAttribute)]
            if names.contains(where: { $0?.lowercased().contains(label) == true }), let frame = frameCG(el), frame.width > 0, frame.height > 0 {
                let role = AX.string(el, kAXRoleAttribute) ?? ""
                if role != "AXGroup" && role != "AXStaticText" && role != "AXWindow" { return (el, frame) }
                if fallback == nil { fallback = (el, frame) }
            }
            queue.append(contentsOf: AX.children(el))
        }
        return fallback
    }

    /// Static texts and values in the window containing `part` (lowercased), at most eight.
    @MainActor static func texts(containing part: String, under root: AXUIElement) -> [String] {
        var queue: [AXUIElement] = [root]
        var visited = 0
        var out: [String] = []
        while !queue.isEmpty, visited < 4000, out.count < 8 {
            let el = queue.removeFirst()
            visited += 1
            for s in [AX.string(el, kAXValueAttribute), AX.string(el, kAXTitleAttribute)] {
                if let s, s.lowercased().contains(part), !out.contains(s) { out.append(String(s.prefix(160))) }
            }
            queue.append(contentsOf: AX.children(el))
        }
        return out
    }

    static func frameCG(_ el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef, CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    static func bool(_ el: AXUIElement, _ attr: String) -> Bool? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let v else { return nil }
        return (v as? Bool) ?? (v as? NSNumber)?.boolValue
    }
}
