import AppKit
import ApplicationServices

/// The control at a point on the live page, for a hint placed by where its control should be rather than by the
/// control's name: the element there, or one of its ancestors, with the hint's role and about the size of the hint's
/// control: one with the hint's class names when the hint has them and the page gives them, else the nearest in size.
/// A section of the page around the spot, whatever its role, is never taken for a control inside it: a page still
/// laying itself out has the spot over its wrappers for a moment, and a tag at a wrapper's corner is a tag at the
/// page's corner. Its frame is as the page has it now, in Accessibility's top-left coordinates. One call to find the
/// element, a few to climb; off the main thread.
enum ControlSnap {
    /// How many times as wide or as tall as the hint's control a control at the spot may be and still be it: a price
    /// block's words differ from item to item; a column or a page around the spot is not the block.
    static let give: CGFloat = 3

    /// A control of the hint's role at or around the spot, from the innermost out.
    struct Candidate: Equatable {
        var frame: CGRect
        /// It carries one of the hint's class names.
        var byClass: Bool = false
    }

    static func frame(bundleID: String, at point: CGPoint, role: String, classes: [String]?, like size: CGSize? = nil) -> CGRect? {
        guard Permissions.accessibilityGranted,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.2)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(axApp, Float(point.x), Float(point.y), &hit) == .success, var element = hit else { return nil }
        var candidates: [Candidate] = []
        for _ in 0..<8 {
            if AX.string(element, kAXRoleAttribute) == role, let frame = AXPageNode(element: element).frame {
                let byClass = classes.map { wanted in AX.strings(element, "AXDOMClassList").map { !Set($0).isDisjoint(with: wanted) } ?? false } ?? false
                candidates.append(Candidate(frame: frame, byClass: byClass))
                // One with the hint's class names that fits is it; with no names and no size to go by, the innermost is.
                if byClass && fits(frame, like: size) || classes == nil && size == nil { break }
            }
            guard let parent = AX.element(element, kAXParentAttribute) else { break }
            element = parent
        }
        return choose(candidates, like: size)
    }

    /// Of the controls of the hint's role at and around the spot, from the innermost out, the one the hint is about:
    /// one with the hint's class names first, else the nearest in size to the hint's control; nil when none fits.
    static func choose(_ candidates: [Candidate], like size: CGSize?) -> CGRect? {
        let fitting = candidates.filter { fits($0.frame, like: size) }
        if let named = fitting.first(where: \.byClass) { return named.frame }
        guard let size else { return fitting.first?.frame }
        return fitting.min { apart($0.frame.size, size) < apart($1.frame.size, size) }?.frame
    }

    /// Whether a control at the spot can be the hint's by its size: something to see, and no more than `give` times
    /// as wide or as tall as the hint's control, with a little room for the smallest.
    static func fits(_ frame: CGRect, like size: CGSize?) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        guard let size else { return true }
        return frame.width <= size.width * give + 24 && frame.height <= size.height * give + 24
    }

    /// How far apart two sizes are: the doublings of width and of height between them, added.
    static func apart(_ a: CGSize, _ b: CGSize) -> CGFloat {
        abs(log2(max(a.width, 1) / max(b.width, 1))) + abs(log2(max(a.height, 1) / max(b.height, 1)))
    }
}
