import AppKit
import SwiftUI

/// How big the stickers are drawn: one factor over the paper, the type and the x, moved through steps by Bigger and
/// Smaller on the right-click menu. 1 is the size they were designed at; the person's choice is remembered.
@MainActor
final class StickersLook: ObservableObject {
    @Published var scale: CGFloat

    nonisolated static let steps: [CGFloat] = [0.85, 1, 1.2, 1.4, 1.6]

    init(scale: CGFloat = 1) { self.scale = Self.clamped(scale) }

    /// A remembered factor brought back into the steps' range; anything that isn't a number is the design size.
    nonisolated static func clamped(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return 1 }
        return min(max(scale, steps[0]), steps[steps.count - 1])
    }

    /// The next step up from `scale`, or nil at the biggest.
    nonisolated static func bigger(than scale: CGFloat) -> CGFloat? { steps.first { $0 > scale + 0.001 } }
    /// The next step down from `scale`, or nil at the smallest.
    nonisolated static func smaller(than scale: CGFloat) -> CGFloat? { steps.last { $0 < scale - 0.001 } }
}

/// A sticker being dragged: the stack follows the mouse, then settles where it was let go.
enum StickerDrag { case moved, ended }

/// One line of the stickers' right-click menu; a nil in the list is a separator.
struct StickerMenuItem: Equatable {
    enum Choice: Equatable { case open(String), putAway(String), bigger, smaller, attach, hide }
    let title: String
    var enabled = true
    let choice: Choice
}

/// The sticky notes beside the bubble: the open matters with a sticker, urgent ones first, up to three, and "and N more"
/// above them when there are more. Clicking one opens its matter; the small x puts it away; dragging one moves the
/// stack; a right-click offers the rest.
struct StickersView: View {
    @ObservedObject var model: Matters
    @ObservedObject var look: StickersLook
    var open: (String) -> Void
    var more: () -> Void
    var putAway: (String) -> Void
    var drag: (StickerDrag) -> Void = { _ in }
    /// The pointer came onto a sticker (true) or left it, for the right-click menu to know which one it is over.
    var point: (String, Bool) -> Void = { _, _ in }

    /// Room around the stack for the paper's shadow and its tilt.
    nonisolated static let margin: CGFloat = 8

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if model.more > 0 {
                // A tab hanging from the top edge peeks out above the top sticker, its tucked part under the paper.
                Button(action: more) { Text(Self.moreWords(model.more)) }
                    .buttonStyle(PaperTabStyle(hangsFromTop: true))
                    .padding(.trailing, 14).padding(.bottom, -13)
                    .zIndex(-1)
                    .help("Open Jobs")
                    .transition(.opacity)
            }
            ForEach(Array(model.shown.reversed().enumerated()), id: \.element.id) { index, sticker in
                StickerView(sticker: sticker, index: index, scale: look.scale, open: { open(sticker.id) }, putAway: { putAway(sticker.id) },
                            drag: drag, point: { point(sticker.id, $0) })
                    .zIndex(Double(index))
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .padding(Self.margin)
        // Pinned to the bottom edge, so a panel held taller than the stack for a moment keeps the stickers beside the orb.
        .frame(width: StickersPanel.width(look.scale))
        .frame(maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: model.stickers.map(\.id))
        .environment(\.colorScheme, .light)
    }

    /// "and 2 more", "and 1 more".
    nonisolated static func moreWords(_ count: Int) -> String { "and \(count) more" }
}

/// One sticker: the job's name, the minister's words, and who shared it with the time. An urgent one is on the amber
/// paper the warnings use. Everything on it is drawn at `scale`.
struct StickerView: View {
    let sticker: Sticker
    let index: Int
    var scale: CGFloat = 1
    var open: () -> Void
    var putAway: () -> Void
    var drag: (StickerDrag) -> Void = { _ in }
    var point: (Bool) -> Void = { _ in }
    @State private var hovering = false

    /// The paper's width at `scale`: the panel's less the margin either side.
    nonisolated static func width(_ scale: CGFloat) -> CGFloat { StickersPanel.width(scale) - 16 }
    /// Stickers lean a little either way down the stack, as stuck-on paper does.
    nonisolated static let tilts: [Double] = [-1.2, 0.8, -0.6]
    /// A press that travels this far is a drag of the stack, not a click.
    nonisolated static let dragDistance: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            Text(sticker.title)
                .font(HandFont.font(size: 13 * scale)).lineLimit(1).truncationMode(.tail)
                .padding(.trailing, 12 * scale)   // clear of the x
            Text(sticker.text)
                .font(Font(StickerPaper.font(13 * scale))).lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.byline(sticker))
                .font(Font(StickerPaper.font(10.5 * scale))).foregroundStyle(Color(nsColor: StickerPaper.inkSoft))
                .padding(.top, 2 * scale)
        }
        .foregroundStyle(Color(nsColor: StickerPaper.ink))
        .padding(10 * scale)
        .frame(width: Self.width(scale), alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: sticker.urgent ? StickerPaper.warning : StickerPaper.tip)))
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color(cgColor: StickerPaper.edge), lineWidth: 0.7))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: putAway) {
                    Text("×").font(Font(StickerPaper.font(10.5 * scale, bold: true))).foregroundStyle(Color(nsColor: StickerPaper.inkSoft))
                        .frame(width: 16 * scale, height: 16 * scale).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Put away")
                .padding(2)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
        .rotationEffect(.degrees(Self.tilt(index)))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        // A press that moves carries the whole stack; the panel follows the mouse, so the window's own coordinates
        // aren't needed here.
        .gesture(DragGesture(minimumDistance: Self.dragDistance).onChanged { _ in drag(.moved) }.onEnded { _ in drag(.ended) })
        .onHover { inside in
            hovering = inside
            point(inside)
        }
        .help("Open \(sticker.title)  ·  Drag to move the stickers  ·  Right-click for more")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sticker.title): \(sticker.text)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .accessibilityAction(named: "Put away") { putAway() }
    }

    /// "Yang · 3:12 PM", or just the time for your own jobs.
    nonisolated static func byline(_ sticker: Sticker) -> String {
        let time = JobWords.clock(sticker.at)
        return sticker.byline.map { $0 + " · " + time } ?? time
    }

    /// The lean of the sticker at `index` down the stack.
    nonisolated static func tilt(_ index: Int) -> Double { tilts[((index % tilts.count) + tilts.count) % tilts.count] }
}

/// The panel that holds them. It sits beside the orb and goes where the orb goes until the person drags it somewhere;
/// from then on it is its own thing at that spot, whatever the bubble does, until Put back beside Noteling. The app
/// decides when it is on the screen (`shows`) and places it; the panel keeps the person's choices and its right-click menu.
final class StickersPanel: NSPanel {
    /// The panel's width at the design size, and at `scale`.
    nonisolated static let designWidth: CGFloat = 216
    nonisolated static func width(_ scale: CGFloat) -> CGFloat { round(designWidth * scale) }

    let look: StickersLook
    private let model: Matters
    private let host: FirstClickHost<StickersView>
    private let open: (String) -> Void
    private let putAway: (String) -> Void
    /// Where the orb was when the panel was last placed, for the shrink that waits for a leaving sticker.
    private var orb = NSRect.zero
    private weak var screenHint: NSScreen?
    private var shrink: DispatchWorkItem?
    /// The mouse's offset from the panel's corner while a sticker is being dragged.
    private var dragOffset: NSPoint?
    /// The sticker under the pointer, which the right-click menu is about.
    private var pointed: String?

    /// Where the person put the stack, its bottom-left corner on the screen; nil while it sits beside the orb.
    private(set) var home: NSPoint?
    var isDetached: Bool { home != nil }
    /// Hidden by Hide stickers (the right-click menu or the menu bar) until Show Stickers, in this run of the app.
    var hidden = false
    /// Out of the way while Noteling works in front of the person, as the bubble is.
    var hiddenForControl = false
    /// The person moved the stack, changed its size, reattached it or hid it: the app remembers and places it again.
    var onChange: (() -> Void)?
    /// The person hid the stickers from their own menu.
    var onHide: (() -> Void)?

    init(model: Matters, look: StickersLook, home: NSPoint?, hideFromScreenShare: Bool, open: @escaping (String) -> Void,
         more: @escaping () -> Void, putAway: @escaping (String) -> Void) {
        self.model = model
        self.look = look
        self.home = home
        self.open = open
        self.putAway = putAway
        let relay = Relay()
        host = FirstClickHost(rootView: StickersView(model: model, look: look, open: open, more: more, putAway: putAway,
                                                     drag: { relay.panel?.drag($0) }, point: { relay.panel?.point($0, inside: $1) }))
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width(look.scale), height: 2 * StickersView.margin),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        relay.panel = self
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        sharingType = hideFromScreenShare ? .none : .readOnly
        host.contextMenu = { [weak self] in self?.contextMenu() }
        contentView = host
    }

    /// The view's closures are made before the panel is, so they reach it through this.
    private final class Relay { weak var panel: StickersPanel? }

    /// Clicks must not take the focus from the person's app; a non-activating panel still gets the mouse.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Whether the stickers are on the screen. Never without a matter to show, while hidden, or while Noteling works in
    /// front of the person. Beside the orb, also only while the bubble is collapsed and fully there and no crane is
    /// flying; at the person's own spot, the bubble's state doesn't matter.
    nonisolated static func shows(count: Int, hidden: Bool, controlling: Bool, detached: Bool,
                                  bubbleVisible: Bool, alpha: CGFloat, expanded: Bool, flying: Bool) -> Bool {
        guard count > 0, !hidden, !controlling else { return false }
        return detached || (bubbleVisible && alpha == 1 && !expanded && !flying)
    }

    /// Where the panel goes beside the orb: to its left, bottom edges level, growing upward; to its right when the left
    /// would leave the screen; always within the visible frame.
    nonisolated static func frame(contentHeight: CGFloat, width: CGFloat, orb: NSRect, visible: NSRect) -> NSRect {
        var x = orb.minX - width - 4
        if x < visible.minX { x = orb.maxX + 4 }
        x = min(max(x, visible.minX), visible.maxX - width)
        let y = min(max(orb.minY, visible.minY), visible.maxY - contentHeight)
        return NSRect(x: x, y: y, width: width, height: contentHeight)
    }

    /// Where the panel goes once the person has put it somewhere: its bottom-left corner stays at `home` as the stack
    /// grows upward, and a stack that would leave the screen is brought back onto it.
    nonisolated static func frame(contentHeight: CGFloat, width: CGFloat, home: NSPoint, visible: NSRect) -> NSRect {
        let x = min(max(home.x, visible.minX), max(visible.minX, visible.maxX - width))
        let y = min(max(home.y, visible.minY), max(visible.minY, visible.maxY - contentHeight))
        return NSRect(x: x, y: y, width: width, height: contentHeight)
    }

    /// Measures the stack, then puts the panel beside the orb on `screen` (or the orb's own, or the main one), or at the
    /// person's spot. A panel that would shrink keeps its height for a moment first, so a sticker on its way out isn't
    /// cut off.
    func place(besideOrb orb: NSRect, on screen: NSScreen?, settled: Bool = false) {
        self.orb = orb
        screenHint = screen
        shrink?.cancel()
        shrink = nil
        host.layoutSubtreeIfNeeded()
        let height = max(host.fittingSize.height, 2 * StickersView.margin)
        var target = frame(height: height)
        if !settled, isVisible, dragOffset == nil, target.height < frame.height {
            target = frame(height: frame.height)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.place(besideOrb: self.orb, on: self.screenHint, settled: true)
            }
            shrink = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
        setFrame(target, display: true)
    }

    /// The frame for a stack `height` tall, beside the orb or at the person's spot.
    private func frame(height: CGFloat) -> NSRect {
        let width = Self.width(look.scale)
        if let home {
            let wanted = NSRect(x: home.x, y: home.y, width: width, height: height)
            let visible = FloatingWindowPlacement.screen(for: wanted, fallback: screenHint ?? NSScreen.main)?.visibleFrame ?? wanted
            return Self.frame(contentHeight: height, width: width, home: home, visible: visible)
        }
        let visible = (screenHint ?? NSScreen.screens.first { $0.frame.intersects(orb) } ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: orb.minX - width - 4, y: orb.minY, width: width + 4 + orb.width, height: max(height, orb.height))
        return Self.frame(contentHeight: height, width: width, orb: orb, visible: visible)
    }

    // MARK: the person's hands

    /// A sticker is being dragged: the stack follows the mouse and, let go, settles on the screen it is over. Its first
    /// move detaches it from the orb.
    func drag(_ phase: StickerDrag) {
        let mouse = NSEvent.mouseLocation
        switch phase {
        case .moved:
            shrink?.cancel()
            shrink = nil
            if dragOffset == nil { dragOffset = NSPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY) }
            guard let dragOffset else { return }
            setFrameOrigin(NSPoint(x: mouse.x - dragOffset.x, y: mouse.y - dragOffset.y))
            home = frame.origin
        case .ended:
            guard dragOffset != nil else { return }
            dragOffset = nil
            if let screen = FloatingWindowPlacement.screen(for: frame, fallback: screenHint ?? NSScreen.main) {
                setFrame(FloatingWindowPlacement.clamped(frame, to: screen.visibleFrame), display: true)
            }
            home = frame.origin
            onChange?()
        }
    }

    /// The pointer came onto `id` or left it. A sticker's leaving can come after its neighbour's arriving.
    func point(_ id: String, inside: Bool) {
        if inside { pointed = id } else if pointed == id { pointed = nil }
    }

    /// What a right-click offers: on a sticker, Open and Put away first; then the size; then the way back beside the orb,
    /// once the stack was moved, and Hide. A nil is a separator line.
    nonisolated static func menu(pointing sticker: String?, detached: Bool, scale: CGFloat) -> [StickerMenuItem?] {
        var items: [StickerMenuItem?] = []
        if let sticker {
            items += [StickerMenuItem(title: "Open", choice: .open(sticker)), StickerMenuItem(title: "Put away", choice: .putAway(sticker)), nil]
        }
        items += [StickerMenuItem(title: "Bigger", enabled: StickersLook.bigger(than: scale) != nil, choice: .bigger),
                  StickerMenuItem(title: "Smaller", enabled: StickersLook.smaller(than: scale) != nil, choice: .smaller), nil]
        if detached { items.append(StickerMenuItem(title: "Put back beside Noteling", choice: .attach)) }
        items.append(StickerMenuItem(title: "Hide stickers", choice: .hide))
        return items
    }

    /// The right-click menu for where the pointer is: a sticker still on the screen, or the stack itself.
    func contextMenu() -> NSMenu {
        let sticker = pointed.flatMap { id in model.shown.contains { $0.id == id } ? id : nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in Self.menu(pointing: sticker, detached: isDetached, scale: look.scale) {
            guard let item else { menu.addItem(.separator()); continue }
            let entry = WindowDragHandle.ClosureMenuItem(title: item.title) { [weak self] in self?.choose(item.choice) }
            entry.isEnabled = item.enabled
            menu.addItem(entry)
        }
        return menu
    }

    func choose(_ choice: StickerMenuItem.Choice) {
        switch choice {
        case .open(let id): open(id)
        case .putAway(let id): putAway(id)
        case .bigger: if let next = StickersLook.bigger(than: look.scale) { resize(to: next) }
        case .smaller: if let next = StickersLook.smaller(than: look.scale) { resize(to: next) }
        case .attach:
            home = nil
            onChange?()
        case .hide:
            hidden = true
            onChange?()
            onHide?()
        }
    }

    /// The stickers redraw at the new size, then the panel is placed around them.
    private func resize(to scale: CGFloat) {
        look.scale = scale
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }
}
