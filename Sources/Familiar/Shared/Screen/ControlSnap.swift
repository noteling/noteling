import AppKit
import ApplicationServices

/// The control at a point on the live page, for a hint placed by where its control should be rather than by the
/// control's name: the element there, or the nearest of its ancestors, with the hint's role, and one of the hint's
/// class names when the hint has them and the page gives them. Its frame is as the page has it now, in
/// Accessibility's top-left coordinates. One call to find the element, a few to climb; off the main thread.
enum ControlSnap {
    static func frame(bundleID: String, at point: CGPoint, role: String, classes: [String]?) -> CGRect? {
        guard Permissions.accessibilityGranted,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.2)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(axApp, Float(point.x), Float(point.y), &hit) == .success, var element = hit else { return nil }
        var byRole: AXUIElement?
        for _ in 0..<6 {
            if AX.string(element, kAXRoleAttribute) == role {
                if let classes, let have = AX.strings(element, "AXDOMClassList"), !Set(have).isDisjoint(with: classes) {
                    return AXPageNode(element: element).frame
                }
                if byRole == nil { byRole = element }
                if classes == nil { break }
            }
            guard let parent = AX.element(element, kAXParentAttribute) else { break }
            element = parent
        }
        return byRole.flatMap { AXPageNode(element: $0).frame }
    }
}
