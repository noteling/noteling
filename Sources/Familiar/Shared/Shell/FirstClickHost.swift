import AppKit
import SwiftUI

/// A hosting view that takes the first click even though Noteling isn't the active app, so a button on a sticky note
/// beside someone's work acts on the first try instead of only bringing the note forward.
final class FirstClickHost<Root: View>: NSHostingView<Root> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
