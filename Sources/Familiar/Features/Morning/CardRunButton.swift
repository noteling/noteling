import SwiftUI

/// The card and button whose question is showing, for a button that asks before it runs.
struct CardRunConfirm: Equatable {
    var card: UUID
    var action: String
}

/// A button on a job's card that runs a function of its job.py: it shows it's running while it does, and can't be
/// pressed while its job can't run it (why is said under the buttons). One whose job says it changes something asks
/// first.
struct CardRunButton: View {
    let card: MorningCard
    let action: CardInboxAction
    @ObservedObject var buttons: FolderJobButtons
    var primary = false
    /// Shows its question instead of running it.
    let confirm: () -> Void

    var body: some View {
        let running = buttons.pressing[card.id] == action.id
        Button {
            if action.confirm != nil { confirm() } else { Task { await buttons.press(card, action) } }
        } label: {
            if running {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(action.label) }
            } else {
                Text(action.label)
            }
        }
        .buttonStyle(MorningActionButton(primary: primary))
        .disabled(buttons.pressing[card.id] != nil || buttons.unavailable(card) != nil)
        .help(action.confirm ?? CardRunWords.help(action))
        .accessibilityHint(running ? "Running" : "Runs this job’s \(action.run ?? "") step")
    }
}

/// What a button asks before it runs: its job's words, then the button again to run it, or Cancel.
struct CardRunConfirmRow: View {
    let action: CardInboxAction
    let run: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(action.confirm ?? "", systemImage: "exclamationmark.circle").font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(action.label, action: run).buttonStyle(MorningActionButton(primary: true))
                Button("Cancel", action: cancel).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Pad.penInk)
            }
        }.padding(12).background(Pad.paperTop.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
    }
}

/// The words around a card's buttons that run its job's code.
enum CardRunWords {
    /// "Mark as fixed · 9:14 AM · Marked 4417 as fixed."
    static func line(_ press: CardPress, now: Date) -> String {
        "\(press.label) · \(JobWords.time(press.at, now: now)) · \(press.said)"
    }

    /// On hover, for a button that doesn't ask first.
    static func help(_ action: CardInboxAction) -> String {
        "Runs \(action.run ?? "")() in this job’s job.py, as you"
    }
}
