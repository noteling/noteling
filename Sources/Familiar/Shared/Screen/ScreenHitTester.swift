import AppKit
import ApplicationServices

struct AXElementInfo {
    var role: String
    var title: String?
    var value: String?
    var description: String?
    var frame: NSRect?     // AppKit global coords
    var subrole: String? = nil       // AXSecureTextField marks a password field
    var placeholder: String? = nil
    var domID: String? = nil         // a web page's own id for it (AXDOMIdentifier)
    var classes: [String]? = nil     // a web page's class names for it (AXDOMClassList), the steady ones

    /// e.g. `button “Submit”` or `text field “Cost Center” = “”`
    var label: String {
        let r = role.replacingOccurrences(of: "AX", with: "")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).lowercased()
        let name = title?.isEmpty == false ? title : (description?.isEmpty == false ? description : nil)
        var s = name.map { "\(r) “\($0)”" } ?? r
        if let v = value, !v.isEmpty, v != name { s += " = “\(v.prefix(80))”" }
        return s
    }

    /// The name a hint is anchored by: a control's title, else its description, else its placeholder. Plain text goes
    /// by its own words when they can be a name, as the page reader lists it; else by where it is.
    var anchorLabel: String? {
        if role == "AXStaticText" { return PageWalk.nameOfText(value) }
        return [title, description, placeholder].compactMap { $0 }.first { !$0.isEmpty }
    }
    var isSecure: Bool { subrole == "AXSecureTextField" || role == "AXSecureTextField" }

    /// Of a page's class names for a control, the ones a page gives by hand rather than generates (`css-1x2y3z`,
    /// `sc-AbCdE`, `jsx-123`), at most six; nil when none.
    static func steadyClasses(_ names: [String]?) -> [String]? {
        guard let names else { return nil }
        let kept = names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && GeneratedID.isSteadyClass($0) }
        return kept.isEmpty ? nil : Array(kept.prefix(6))
    }
}

/// The native window and accessibility element under a screen point.
struct ScreenHit {
    var screenPoint: NSPoint
    var element: AXElementInfo?
    var windowOwner: String?
    var windowTitle: String?
    var ownerBundleID: String? = nil
    var windowFrame: NSRect? = nil     // AppKit global coordinates
    var ownerPID: pid_t? = nil
}

@MainActor
enum ScreenHitTester {
    /// The window and the element under the point. With `toControl`, the words or the picture under it stand for
    /// the control around them, named as the page reader names it: for the pen, whose hint on the text inside a
    /// button is the button's. Watch Me keeps the element itself and climbs on its own.
    static func hitTest(at point: NSPoint, toControl: Bool = false) -> ScreenHit {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let cgPoint = CGPoint(x: point.x, y: primaryMaxY - point.y)
        let myPID = ProcessInfo.processInfo.processIdentifier

        var ownerPID: pid_t?
        var owner: String?
        var title: String?
        var windowFrame: NSRect?
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in list {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != myPID else { continue }
            guard let layer = w[kCGWindowLayer as String] as? Int, layer < 20 else { continue }
            if let alpha = w[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
            guard let bdict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: bdict), bounds.contains(cgPoint) else { continue }
            ownerPID = pid
            owner = w[kCGWindowOwnerName as String] as? String
            title = w[kCGWindowName as String] as? String
            windowFrame = NSRect(x: bounds.minX, y: primaryMaxY - bounds.maxY, width: bounds.width, height: bounds.height)
            break
        }

        var info: AXElementInfo?
        if let pid = ownerPID, Permissions.accessibilityGranted {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.3)
            var hit: AXUIElement?
            if AXUIElementCopyElementAtPosition(app, Float(cgPoint.x), Float(cgPoint.y), &hit) == .success, let hit {
                let el = toControl ? control(holding: hit) : hit
                let role = AX.string(el, kAXRoleAttribute) ?? "AXUnknown"
                info = AXElementInfo(role: role,
                                     title: AX.string(el, kAXTitleAttribute),
                                     value: AX.string(el, kAXValueAttribute),
                                     description: AX.string(el, kAXDescriptionAttribute),
                                     frame: Self.axFrame(of: el, primaryMaxY: primaryMaxY),
                                     subrole: AX.string(el, kAXSubroleAttribute),
                                     placeholder: AX.string(el, kAXPlaceholderValueAttribute),
                                     domID: AX.string(el, "AXDOMIdentifier").flatMap { $0.isEmpty ? nil : $0 },
                                     classes: AXElementInfo.steadyClasses(AX.strings(el, "AXDOMClassList")))
                if (info?.title ?? "").isEmpty, (info?.description ?? "").isEmpty {
                    // A control named by nothing but the text inside it is called by that text, as the reader calls it.
                    if toControl, PageWalk.atomic.contains(role), let name = PageWalk.contentName(AXPageNode(element: el)) {
                        info?.description = name
                    } else if let parent = AX.element(el, kAXParentAttribute), let pt = AX.string(parent, kAXTitleAttribute), !pt.isEmpty {
                        info?.description = pt
                    }
                }
            }
        }
        let bundle = ownerPID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        return ScreenHit(screenPoint: point, element: info, windowOwner: owner, windowTitle: title, ownerBundleID: bundle, windowFrame: windowFrame,
                         ownerPID: ownerPID)
    }

    /// The control the element is part of: the chain from it up to its page or window, as far as the first control
    /// whose words are its name, and on it the one a hint is about (`PageWalk.control`); the element itself when it
    /// is a control of its own, or nothing around it is one.
    private static func control(holding el: AXUIElement) -> AXUIElement {
        var chain = [el], roles = [AX.string(el, kAXRoleAttribute) ?? "AXUnknown"]
        guard PageWalk.inside.contains(roles[0]) else { return el }
        var current = el
        for _ in 0..<8 {
            guard let parent = AX.element(current, kAXParentAttribute) else { break }
            let role = AX.string(parent, kAXRoleAttribute) ?? ""
            if role == kAXApplicationRole || role == kAXWindowRole || role == "AXWebArea" { break }
            chain.append(parent)
            roles.append(role)
            current = parent
            if PageWalk.atomic.contains(role) { break }
        }
        return PageWalk.control(holding: roles).map { chain[$0] } ?? el
    }

    /// An element's frame in AppKit global coordinates.
    nonisolated static func axFrame(of el: AXUIElement, primaryMaxY: CGFloat) -> NSRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return NSRect(x: pos.x, y: primaryMaxY - pos.y - size.height, width: size.width, height: size.height)
    }
}
