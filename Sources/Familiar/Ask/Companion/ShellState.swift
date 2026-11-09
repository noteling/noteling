import Combine
import Foundation

/// Presentation state shared by the app shell and its views. Feature work does not
/// own the panel's geometry, visibility intent, or window actions.
@MainActor
final class ShellState: ObservableObject {
    @Published var expanded = false
    @Published var cardSize = NSSize(width: 400, height: 540)
    /// The lamp on the bubble: what the deck comes to, and the words for its hover.
    @Published var lamp = LampState.off
    @Published var lampWords = LampState.words(count: 0, urgent: false)
    @Published var lampHidden = false

    enum DragPhase { case moved, ended }
    var onHideBubble: (() -> Void)?
    var onDragBubble: ((DragPhase) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onPoke: (() -> Void)?
    var onResizeCard: ((NSSize, Bool) -> Void)?  // size, then whether the drag ended and should be persisted
    var onToggleLarge: (() -> Void)?
    /// A new note of your own, from the bubble's menu.
    var onNewNote: (() -> Void)?
    /// A click on the orb: every note of yours comes up where you are for a moment, or goes back if they are up.
    var onGlance: (() -> Void)?
    /// Noteling's menu: every note comes up (and back on the screen, if hidden), or every one goes off the screen until shown.
    var onShowNotes: (() -> Void)?
    var onHideNotes: (() -> Void)?
    @Published var noteCount = 0
    @Published var notesHidden = false
    /// The lamp was clicked: the deck opens, or the receipt when nothing needs you.
    var onLamp: (() -> Void)?
    var onOpenJobs: (() -> Void)?
    var onReceipt: (() -> Void)?
    var onHideLamp: (() -> Void)?

    private var quietExpandPending = false

    /// Show the pad while leaving keyboard focus with the user's current app.
    func expandQuietly() {
        quietExpandPending = true
        expanded = true
    }

    /// The native shell consumes this once when applying an expansion.
    func consumeQuietExpand() -> Bool {
        defer { quietExpandPending = false }
        return quietExpandPending
    }
}
