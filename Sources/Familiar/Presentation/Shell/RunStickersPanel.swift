import AppKit
import SwiftUI

/// The sticky notes beside the bubble: up to three, newest nearest the orb, and "and N more" above them when there
/// are more. Clicking one opens its job; the small x puts it away.
struct RunStickersView: View {
    @ObservedObject var model: RunStickers
    var open: (UUID) -> Void
    var more: () -> Void
    var putAway: (UUID) -> Void

    /// Room around the stack for the paper's shadow and its tilt.
    nonisolated static let margin: CGFloat = 8

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if model.more > 0 {
                // The tab style hangs under a sheet; turned round, it peeks out above the top sticker, its tucked
                // part under the paper. The words turn back so they read.
                Button(action: more) { Text(Self.moreWords(model.more)).rotationEffect(.degrees(180)) }
                    .buttonStyle(PaperTabStyle())
                    .rotationEffect(.degrees(180))
                    .padding(.trailing, 14).padding(.bottom, -13)
                    .zIndex(-1)
                    .help("Open Jobs")
                    .transition(.opacity)
            }
            ForEach(Array(model.shown.reversed().enumerated()), id: \.element.id) { index, sticker in
                RunStickerView(sticker: sticker, index: index, open: { open(sticker.id) }, putAway: { putAway(sticker.id) })
                    .zIndex(Double(index))
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .padding(Self.margin)
        .frame(width: RunStickersPanel.width, alignment: .bottomTrailing)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: model.stickers.map(\.id))
        .environment(\.colorScheme, .light)
    }

    /// "and 2 more", "and 1 more".
    nonisolated static func moreWords(_ count: Int) -> String { "and \(count) more" }
}

/// One sticker: the job's name, what it found, and who shared it with the time.
struct RunStickerView: View {
    let sticker: RunSticker
    let index: Int
    var open: () -> Void
    var putAway: () -> Void
    @State private var hovering = false

    nonisolated static let width: CGFloat = RunStickersPanel.width - 16
    /// Stickers lean a little either way down the stack, as stuck-on paper does.
    nonisolated static let tilts: [Double] = [-1.2, 0.8, -0.6]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(sticker.jobName)
                .font(HandFont.font(size: 13)).lineLimit(1).truncationMode(.tail)
                .padding(.trailing, 12)   // clear of the x
            Text(sticker.said)
                .font(Font(StickerPaper.font(13))).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.byline(sticker))
                .font(Font(StickerPaper.font(10.5))).foregroundStyle(Color(nsColor: StickerPaper.inkSoft))
                .padding(.top, 2)
        }
        .foregroundStyle(Color(nsColor: StickerPaper.ink))
        .padding(10)
        .frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: StickerPaper.tip)))
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color(cgColor: StickerPaper.edge), lineWidth: 0.7))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: putAway) {
                    Text("×").font(Font(StickerPaper.font(10.5, bold: true))).foregroundStyle(Color(nsColor: StickerPaper.inkSoft))
                        .frame(width: 16, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Put away")
                .padding(2)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
        .rotationEffect(.degrees(Self.tilt(index)))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .help("Open \(sticker.jobName)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sticker.jobName): \(sticker.said)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .accessibilityAction(named: "Put away") { putAway() }
    }

    /// "Yang · 3:12 PM", or just the time for your own jobs.
    nonisolated static func byline(_ sticker: RunSticker) -> String {
        let time = JobWords.clock(sticker.at)
        return sticker.byline.map { $0 + " · " + time } ?? time
    }

    /// The lean of the sticker at `index` down the stack.
    nonisolated static func tilt(_ index: Int) -> Double { tilts[((index % tilts.count) + tilts.count) % tilts.count] }
}

/// Takes the first click even though Noteling isn't the active app, so one click on a sticker acts.
final class RunStickersHost: NSHostingView<RunStickersView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The panel that holds them, beside the orb; the app places it and shows or hides it.
final class RunStickersPanel: NSPanel {
    nonisolated static let width: CGFloat = 216
    private let host: RunStickersHost

    init(model: RunStickers, hideFromScreenShare: Bool, open: @escaping (UUID) -> Void, more: @escaping () -> Void,
         putAway: @escaping (UUID) -> Void) {
        host = RunStickersHost(rootView: RunStickersView(model: model, open: open, more: more, putAway: putAway))
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 2 * RunStickersView.margin),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        sharingType = hideFromScreenShare ? .none : .readOnly
        contentView = host
    }

    /// Clicks must not take the focus from the person's app; a non-activating panel still gets the mouse.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Where the panel goes beside the orb: to its left, bottom edges level, growing upward; to its right when the left
    /// would leave the screen; always within the visible frame.
    nonisolated static func frame(contentHeight: CGFloat, orb: NSRect, visible: NSRect) -> NSRect {
        var x = orb.minX - width - 4
        if x < visible.minX { x = orb.maxX + 4 }
        x = min(max(x, visible.minX), visible.maxX - width)
        let y = min(max(orb.minY, visible.minY), visible.maxY - contentHeight)
        return NSRect(x: x, y: y, width: width, height: contentHeight)
    }

    /// Measures the stack, then puts the panel beside the orb on `screen` (or the orb's own, or the main one).
    func place(besideOrb orb: NSRect, on screen: NSScreen?) {
        host.layoutSubtreeIfNeeded()
        let height = max(host.fittingSize.height, 2 * RunStickersView.margin)
        let visible = (screen ?? NSScreen.screens.first { $0.frame.intersects(orb) } ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: orb.minX - Self.width - 4, y: orb.minY, width: Self.width + 4 + orb.width, height: max(height, orb.height))
        setFrame(Self.frame(contentHeight: height, orb: orb, visible: visible), display: true)
    }
}
