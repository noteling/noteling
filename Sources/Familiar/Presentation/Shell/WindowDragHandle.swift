import AppKit
import SwiftUI

@MainActor protocol WindowDragHandling: AnyObject {
    func beganDragging(_ window: NSWindow)
    func finishedDragging(_ window: NSWindow)
}

/// A native drag surface; the optional click action lets a small launcher remain a button.
struct WindowDragHandle: NSViewRepresentable {
    var onClick: (() -> Void)? = nil
    var onFinished: (NSWindow) -> Void = { _ in }
    /// What a right-click on the handle offers. The handle takes every mouse event, so a SwiftUI menu on what it covers
    /// would never open; it shows this one itself.
    var menu: [(title: String, action: () -> Void)] = []

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? DragView else { return }
        view.onClick = onClick
        view.onFinished = onFinished
        view.items = menu
    }

    /// A right-click menu whose items run closures.
    static func menu(_ items: [(title: String, action: () -> Void)]) -> NSMenu? {
        guard !items.isEmpty else { return nil }
        let menu = NSMenu()
        for item in items { menu.addItem(ClosureMenuItem(title: item.title, action: item.action)) }
        return menu
    }

    final class ClosureMenuItem: NSMenuItem {
        private let run: () -> Void
        init(title: String, action: @escaping () -> Void) {
            run = action
            super.init(title: title, action: #selector(runAction), keyEquivalent: "")
            target = self
        }
        required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
        @objc func runAction() { run() }
    }

    private final class DragView: NSView {
        var onClick: (() -> Void)?
        var onFinished: (NSWindow) -> Void = { _ in }
        var items: [(title: String, action: () -> Void)] = []
        override func menu(for event: NSEvent) -> NSMenu? { WindowDragHandle.menu(items) }
        private var startPoint: NSPoint?
        private var startFrame: NSRect?
        private var didDrag = false
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            startPoint = window.convertPoint(toScreen: event.locationInWindow)
            startFrame = window.frame
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, let startPoint, let startFrame else { return }
            // Use this event's location, not the global cursor: nonactivating panels
            // also receive app-targeted input that does not move the physical cursor.
            let point = window.convertPoint(toScreen: event.locationInWindow)
            let delta = NSPoint(x: point.x - startPoint.x, y: point.y - startPoint.y)
            guard didDrag || hypot(delta.x, delta.y) >= 4 else { return }
            if !didDrag { (window.delegate as? WindowDragHandling)?.beganDragging(window) }
            didDrag = true
            NSCursor.closedHand.set()
            window.setFrameOrigin(NSPoint(x: startFrame.minX + delta.x, y: startFrame.minY + delta.y))
        }

        override func mouseUp(with event: NSEvent) {
            guard startPoint != nil, let window else { return }
            startPoint = nil
            startFrame = nil
            NSCursor.openHand.set()
            if didDrag {
                onFinished(window)
                (window.delegate as? WindowDragHandling)?.finishedDragging(window)
            } else {
                onClick?()
            }
            didDrag = false
        }
    }
}
