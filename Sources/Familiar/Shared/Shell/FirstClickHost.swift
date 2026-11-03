import AppKit
import SwiftUI

/// A hosting view that takes the first click even though Noteling isn't the active app, so a button on a sticky note
/// beside someone's work acts on the first try instead of only bringing the note forward.
final class FirstClickHost<Root: View>: NSHostingView<Root> {
    /// What a right-click opens, when set: an AppKit menu popped up here, which works in a panel that never takes the
    /// focus, where a SwiftUI menu would not open.
    var contextMenu: (() -> NSMenu?)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenu?() else { return super.rightMouseDown(with: event) }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
