import AppKit
import SwiftUI

/// Under a question on the pad: what Claude was shown from the screen, as a small photo clipped to the note with when
/// it was taken. While the answer is written it says the screen is held. A tap opens exactly what was sent.
struct SeenChip: View {
    let seen: SeenScreen
    let answering: Bool

    var body: some View {
        Button { SeenPreview.show(seen) } label: {
            HStack(spacing: 8) {
                if let picture = seen.thumbnail {
                    Image(decorative: picture, scale: 1)
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 46, height: 30).clipped()
                        .padding(2)
                        .background(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 1).stroke(Pad.tabEdge, lineWidth: 0.8))
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .rotationEffect(.degrees(-2))
                } else {
                    Image(systemName: seen.pageText != nil ? "doc.text" : "camera.viewfinder")
                        .font(.system(size: 12)).foregroundStyle(Pad.penInk)
                }
                Text(answering && seen.held ? SeenScreen.answeringCaption : seen.caption)
                    .font(.system(size: 11)).foregroundStyle(Pad.inkSoft)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(seen.isEmpty)
        .help(seen.isEmpty ? "" : "See exactly what Noteling was shown")
    }
}

/// A window with exactly what a question showed Claude: each picture as sent, and the page's text.
@MainActor
enum SeenPreview {
    private static var window: NSWindow?

    static func show(_ seen: SeenScreen) {
        guard !seen.isEmpty else { return }
        let view = SeenPreviewView(seen: seen)
        let w = window ?? {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.sharingType = .none
            w.center()
            window = w
            return w
        }()
        w.title = "What Noteling was shown"
        w.contentViewController = NSHostingController(rootView: view)
        w.setContentSize(NSSize(width: 680, height: 560))
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

private struct SeenPreviewView: View {
    let seen: SeenScreen

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(seen.caption).font(.headline)
                    Text(seen.place).font(.callout).foregroundStyle(.secondary)
                    Text("The pictures and page text that went with this question. It also carried the app, the window's title and address, and the apps you used recently.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(Array(seen.pictures.enumerated()), id: \.offset) { _, picture in
                    Image(decorative: picture, scale: 1)
                        .resizable().aspectRatio(contentMode: .fit)
                        .overlay(Rectangle().stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))
                }
                if let text = seen.pageText {
                    Text("The page, as text").font(.subheadline.weight(.semibold))
                    Text(text.count > 20_000 ? String(text.prefix(20_000)) + "\n…" : text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
