import AppKit
import ApplicationServices

/// Chromium browsers build a page's Accessibility tree only once an assistive app says one is listening, the way
/// VoiceOver does: by setting AXEnhancedUserInterface on the browser. Without it a page reads as an empty group, so a
/// control on it can be neither recorded nor shown. Noteling says so only while it needs the page's controls (a way
/// being shown, a Watch Me recording) and takes it back after, unless the browser already had it on.
@MainActor
enum BrowserAccessibility {
    private static let attribute = "AXEnhancedUserInterface" as CFString
    /// Who holds each browser on, by process; only the ones Noteling turned on itself are here.
    private static var holds: [pid_t: Int] = [:]
    /// Browsers let go of but not yet turned off. Chromium tears the tree down when told no one listens, and doesn't
    /// build it again for a while if told right after, so a quick check followed by a tour would find nothing.
    private static var goingOff: [pid_t: DispatchWorkItem] = [:]
    static let offDelay: TimeInterval = 8

    nonisolated static func needs(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier.map { PageReader.chromium.contains($0) } ?? false
    }

    /// Turns the page trees on for `app` if it is a Chromium browser; true when this call holds it (release it later).
    @discardableResult
    static func hold(_ app: NSRunningApplication) -> Bool {
        guard needs(app), Permissions.accessibilityGranted else { return false }
        let pid = app.processIdentifier
        if let count = holds[pid] {
            holds[pid] = count + 1
            return true
        }
        if let off = goingOff.removeValue(forKey: pid) {   // still on from a moment ago: keep it on
            off.cancel()
            holds[pid] = 1
            return true
        }
        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, attribute, &value) == .success, (value as? Bool) == true { return false }   // already on
        AXUIElementSetAttributeValue(element, attribute, kCFBooleanTrue)
        holds[pid] = 1
        Log.info("browser: page trees on for \(app.bundleIdentifier ?? "\(pid)")")
        return true
    }

    /// Says it again to a browser this holds whose page still reads empty: a page that loaded meanwhile, or a browser
    /// that missed it, then builds its tree.
    static func nudge(_ app: NSRunningApplication) {
        guard holds[app.processIdentifier] != nil else { return }
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier), attribute, kCFBooleanTrue)
    }

    /// Every Chromium browser that is running: for a recording, which may move between them. Returns those held.
    static func holdAll() -> [pid_t] {
        NSWorkspace.shared.runningApplications.filter { hold($0) }.map(\.processIdentifier)
    }

    /// Lets go of a browser; it goes back off a few seconds later unless something holds it again meanwhile.
    static func release(_ pid: pid_t) {
        guard let count = holds[pid] else { return }
        if count > 1 { holds[pid] = count - 1; return }
        holds[pid] = nil
        let off = DispatchWorkItem { MainActor.assumeIsolated { turnOff(pid) } }
        goingOff[pid] = off
        DispatchQueue.main.asyncAfter(deadline: .now() + offDelay, execute: off)
    }

    /// Turns off at once every browser Noteling turned on, held or waiting to go off: as Noteling quits, or as a
    /// command-line check ends, since nothing would be left to turn it off later.
    static func settle() {
        for pid in Array(goingOff.keys) + Array(holds.keys) { turnOff(pid) }
        holds = [:]
    }

    private static func turnOff(_ pid: pid_t) {
        goingOff.removeValue(forKey: pid)?.cancel()
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), attribute, kCFBooleanFalse)
        Log.info("browser: page trees back off for \(pid)")
    }
}
