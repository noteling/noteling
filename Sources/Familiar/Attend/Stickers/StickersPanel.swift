import AppKit
import Combine
import SwiftUI

// The deck beside the orb: the minister's cards, one at a time, each on the paper with three verbs under it. The
// decision is the gesture: Do it runs the action the minister picked, as you, after a few seconds you can take back;
// Mine turns the card into a note of your own; Not now puts it away. A click on the card opens its matter; "N more"
// says what waits behind it. Keys do the same once the deck has been clicked: ← Do it, → Mine, ↑ Not now, ⏎ Open.

/// How big the deck is drawn: one factor over the paper, the type and the verbs, moved through steps by Bigger and
/// Smaller on the right-click menu. 1 is the size it was designed at; the person's choice is remembered.
@MainActor
final class StickersLook: ObservableObject {
    @Published var scale: CGFloat

    nonisolated static let steps: [CGFloat] = PaperLook.steps

    init(scale: CGFloat = 1) { self.scale = Self.clamped(scale) }

    nonisolated static func clamped(_ scale: CGFloat) -> CGFloat { PaperLook.clamped(scale) }
    nonisolated static func bigger(than scale: CGFloat) -> CGFloat? { PaperLook.bigger(than: scale) }
    nonisolated static func smaller(than scale: CGFloat) -> CGFloat? { PaperLook.smaller(than: scale) }
}

/// The deck being dragged: it follows the mouse, then settles where it was let go.
enum StickerDrag { case moved, ended }

/// One line of the deck's right-click menu; a nil in the list is a separator.
struct StickerMenuItem: Equatable {
    enum Choice: Equatable { case open(String), doIt(String), mine(String), putAway(String), bigger, smaller, attach, hide, show, more, close }
    let title: String
    var enabled = true
    let choice: Choice
}

/// A press the person stamped Do it on, waiting a few seconds so they can take it back.
struct PendingPress: Equatable {
    let id: String
    let label: String
    let until: Date
}

/// The deck's own state: the card on top, what the person stamped and what came of it. The matters keep every
/// state; this keeps only the moments between a stamp and its effect.
@MainActor
final class DeckModel: ObservableObject {
    enum Verdict: String { case doIt = "do", mine, notNow = "not now" }

    let matters: Matters
    /// A Do it waiting for its few seconds to pass.
    @Published var pending: PendingPress?
    /// What the last press came to, for a moment: "Nudge warehouse · 9:31", or why it failed.
    @Published var said: String?
    /// The stamp on the card that is leaving, while it leaves.
    @Published var stamped: (id: String, verdict: Verdict)?
    var clock: () -> Date = Date.init
    /// How long a Do it can be taken back, and how long the stamp shows before the card goes.
    var undoSeconds: TimeInterval = 5
    var stampSeconds: TimeInterval = 0.5
    var saidSeconds: TimeInterval = 8
    /// Runs the card's action, as the person; nil when nothing can run it (a render).
    var press: ((Matter, MatterView.Action) async -> FindingPress?)?
    /// Turns the card into one of the person's notes.
    var mine: ((Matter) -> Void)?
    var open: (String) -> Void = { _ in }
    /// Opens Jobs, where every card waits.
    var openMore: () -> Void = {}
    /// Cards stamped Do it, off the deck while their press waits.
    private var held: Set<String> = []
    private var pressTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()

    init(matters: Matters) {
        self.matters = matters
        matters.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }

    /// The cards as they stand: urgent first, then newest, less any whose press is waiting.
    var cards: [Sticker] { matters.stickers.filter { !held.contains($0.id) } }
    /// The card on top, and how many wait behind it.
    var card: Sticker? { cards.first }
    var more: Int { max(0, cards.count - 1) }
    var count: Int { cards.count }

    /// The person's verdict on the card: the stamp shows, then the card goes and the verdict takes effect.
    func stamp(_ verdict: Verdict, on id: String) {
        guard let matter = matters.matter(id: id), matter.state == .open, stamped == nil else { return }
        if verdict == .doIt, matter.view?.action == nil { return }
        if stampSeconds <= 0 { apply(verdict, to: matter); return }
        stamped = (id, verdict)
        DispatchQueue.main.asyncAfter(deadline: .now() + stampSeconds) { [weak self] in
            guard let self else { return }
            self.stamped = nil
            if let current = self.matters.matter(id: id), current.state == .open { self.apply(verdict, to: current) }
        }
    }

    private func apply(_ verdict: Verdict, to matter: Matter) {
        switch verdict {
        case .notNow:
            matters.putAway(matter.id)
        case .mine:
            if matters.take(matter.id) != nil { mine?(matter) }
        case .doIt:
            guard let action = matter.view?.action else { return }
            held.insert(matter.id)
            pending = PendingPress(id: matter.id, label: action.label, until: clock().addingTimeInterval(undoSeconds))
            matters.memory?.append(["matter": matter.id, "stamp": "do", "waiting": action.label])
            pressTask?.cancel()
            pressTask = Task { [weak self] in
                let nanoseconds = UInt64(max(0, self?.undoSeconds ?? 0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                await self?.run(matter, action)
            }
        }
    }

    /// The person took a Do it back: the card is back on the deck, nothing ran.
    func undo() {
        guard let pending else { return }
        pressTask?.cancel()
        pressTask = nil
        held.remove(pending.id)
        self.pending = nil
        matters.memory?.append(["matter": pending.id, "stamp": "undo", "label": pending.label])
    }

    /// The seconds passed: the press runs, the matter goes quiet with what was done, and the result shows for a moment.
    private func run(_ matter: Matter, _ action: MatterView.Action) async {
        let result = await press?(matter, action)
        held.remove(matter.id)
        pending = nil
        matters.did(matter.id, action.label)
        if let result {
            said = (result.failed ? "Couldn't \(action.label.lowercased()): \(JobWords.clip(result.said, 80))" : "\(action.label) · \(JobWords.clock(result.at))")
        } else {
            said = "\(action.label) · \(JobWords.clock(clock()))"
        }
        let shown = said
        DispatchQueue.main.asyncAfter(deadline: .now() + saidSeconds) { [weak self] in if self?.said == shown { self?.said = nil } }
    }

    /// Runs a waiting press now, without waiting the seconds out (tests, quitting).
    func flush() async {
        guard let pending, let matter = matters.matter(id: pending.id), let action = matter.view?.action else { return }
        pressTask?.cancel()
        pressTask = nil
        await run(matter, action)
    }
}

/// The deck as the panel draws it: "N more" peeking above, the card, the verbs tucked under its bottom edge, and the
/// line of a press waiting to run or just run.
struct StickersView: View {
    @ObservedObject var model: DeckModel
    @ObservedObject var look: StickersLook
    var drag: (StickerDrag) -> Void = { _ in }
    /// The pointer came onto the card (true) or left it, for the right-click menu to know what it is over.
    var point: (String, Bool) -> Void = { _, _ in }
    @State private var hovering = false

    /// Room around the deck for the paper's shadow and its tilt.
    nonisolated static let margin: CGFloat = PaperLook.margin

    var body: some View {
        let scale = look.scale
        VStack(alignment: .leading, spacing: 0) {
            if model.more > 0 {
                // A tab hanging from the top edge peeks out above the card, its tucked part under the paper.
                Button(action: model.openMore) { Text(Self.moreWords(model.more)) }
                    .buttonStyle(PaperTabStyle(hangsFromTop: true))
                    .padding(.leading, 14 * scale).padding(.bottom, -13)
                    .zIndex(-1)
                    .help("Open Jobs")
                    .transition(.opacity)
            }
            if let card = model.card {
                CardView(card: card, scale: scale, now: model.clock(), stamp: model.stamped?.id == card.id ? model.stamped?.verdict : nil,
                         open: { model.open(card.id) }, putAway: { model.stamp(.notNow, on: card.id) }, drag: drag, point: { point(card.id, $0) })
                    .id(card.id)
                    .zIndex(1)
                    .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity),
                                            removal: .offset(x: 40 * scale, y: -30 * scale).combined(with: .opacity)))
                verbs(card, scale: scale)
                    .padding(.leading, 14 * scale).padding(.top, -5)
                    .zIndex(0)
            }
            if let pending = model.pending {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(pending.until.timeIntervalSince(context.date).rounded(.up)))
                    Button("\(pending.label) in \(left) s · undo") { model.undo() }
                        .buttonStyle(PaperTabStyle())
                        .help("Take it back: nothing runs")
                }
                .padding(.leading, 14 * scale).padding(.top, model.card == nil ? 0 : 6)
                .transition(.opacity)
            } else if let said = model.said {
                Text(said).font(.system(size: 12 * scale, weight: .medium)).foregroundStyle(Pad.ink).lineLimit(2)
                    .padding(.horizontal, 10 * scale).padding(.vertical, 6 * scale)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Pad.tabPaper).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Pad.tabEdge.opacity(0.9), lineWidth: 0.8)))
                    .padding(.leading, 14 * scale).padding(.top, 6)
                    .transition(.opacity)
            }
        }
        .padding(Self.margin)
        // Pinned to the bottom edge, so a panel held taller than the deck for a moment keeps the card beside the orb.
        .frame(width: StickersPanel.width(look.scale))
        .frame(maxHeight: .infinity, alignment: .bottomLeading)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: model.card?.id)
        .animation(.easeInOut(duration: 0.25), value: model.pending)
        .animation(.easeInOut(duration: 0.25), value: model.said)
        .environment(\.colorScheme, .light)
    }

    /// The verbs under the card: the action's own label, then Mine and Not now, as paper tabs tucked under the sheet.
    private func verbs(_ card: Sticker, scale: CGFloat) -> some View {
        TabRow(spacing: 6, rowSpacing: -5) {
            if let action = card.action {
                Button(action.label) { model.stamp(.doIt, on: card.id) }.buttonStyle(PaperTabStyle()).zIndex(2)
                    .help("Noteling does it, as you, in a few seconds you can take back  ·  ←")
            }
            Button("Mine") { model.stamp(.mine, on: card.id) }.buttonStyle(PaperTabStyle()).zIndex(1)
                .help("Becomes a note of your own  ·  →")
            Button("Not now") { model.stamp(.notNow, on: card.id) }.buttonStyle(PaperTabStyle()).zIndex(0)
                .help("Put away; back only if something about it changes  ·  ↑")
        }
        .frame(width: PaperLook.cardWidth * scale - 14 * scale, alignment: .leading)
        .disabled(model.stamped != nil)
    }

    /// "2 more", "1 more".
    nonisolated static func moreWords(_ count: Int) -> String { "\(count) more" }
}

/// One card: the minister's headline in the hand, its words typed, the page, and who it came from with the time, on
/// the paper; amber when it can't wait. The stamp lands on it as it goes.
struct CardView: View {
    let card: Sticker
    var scale: CGFloat = 1
    var now: Date = Date()
    var stamp: DeckModel.Verdict?
    var open: () -> Void = {}
    var putAway: () -> Void = {}
    var drag: (StickerDrag) -> Void = { _ in }
    var point: (Bool) -> Void = { _ in }
    @State private var hovering = false

    /// A press that travels this far is a drag of the deck, not a click.
    nonisolated static let dragDistance: CGFloat = 6

    var body: some View {
        PaperView(headline: card.headline, text: card.text, page: card.page, byline: card.line(now: now), hand: .typed,
                  colour: card.urgent ? .amber : .yellow, scale: scale, now: now, tilt: PaperLook.tilt(for: card.id))
            .overlay(alignment: .topTrailing) {
                if hovering, stamp == nil {
                    Button(action: putAway) {
                        Text("×").font(Font(StickerPaper.font(12 * scale, bold: true))).foregroundStyle(PaperType.inkSoft)
                            .frame(width: 18 * scale, height: 18 * scale).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("Not now").padding(2 * scale)
                }
            }
            .overlay {
                if let stamp { StampView(verdict: stamp, scale: scale).transition(.scale(scale: 1.6).combined(with: .opacity)) }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: stamp)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .gesture(DragGesture(minimumDistance: Self.dragDistance).onChanged { _ in drag(.moved) }.onEnded { _ in drag(.ended) })
            .onHover { inside in
                hovering = inside
                point(inside)
            }
            .help("Open \(card.headline ?? card.title)  ·  Drag to move the deck  ·  Right-click for more")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(card.headline ?? card.title): \(card.text)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open() }
            .accessibilityAction(named: "Not now") { putAway() }
    }
}

/// A rubber stamp across the card: DONE in red for Do it, MINE in the pen's ink, NOT NOW in grey.
struct StampView: View {
    let verdict: DeckModel.Verdict
    var scale: CGFloat = 1

    var words: String {
        switch verdict {
        case .doIt: return "DONE"
        case .mine: return "MINE"
        case .notNow: return "NOT NOW"
        }
    }
    var ink: Color {
        switch verdict {
        case .doIt: return Pad.redInk
        case .mine: return Pad.penInk
        case .notNow: return PaperType.inkSoft
        }
    }

    var body: some View {
        Text(words)
            .font(.system(size: 26 * scale, weight: .heavy, design: .rounded))
            .tracking(2 * scale)
            .padding(.horizontal, 10 * scale).padding(.vertical, 4 * scale)
            .overlay(RoundedRectangle(cornerRadius: 6 * scale).stroke(ink, lineWidth: 3.5 * scale))
            .foregroundStyle(ink)
            .opacity(0.85)
            .rotationEffect(.degrees(-12))
            .allowsHitTesting(false)
    }
}

/// The panel that holds the deck. It sits beside the orb and goes where the orb goes until the person drags it
/// somewhere; from then on it is its own thing at that spot, whatever the bubble does, until Put back beside Noteling.
/// The app decides when it is on the screen (`shows`) and places it; the panel keeps the person's choices, its
/// right-click menu, and the keys once it has been clicked.
final class StickersPanel: NSPanel {
    /// The panel's width at the design size, and at `scale`: the card and room for its shadow either side.
    nonisolated static let designWidth: CGFloat = PaperLook.cardWidth + 2 * PaperLook.margin
    nonisolated static func width(_ scale: CGFloat) -> CGFloat { round(PaperLook.cardWidth * scale + 2 * PaperLook.margin) }

    let look: StickersLook
    let model: DeckModel
    private let host: FirstClickHost<StickersView>
    /// Where the orb was when the panel was last placed, for the shrink that waits for a leaving card.
    private var orb = NSRect.zero
    private weak var screenHint: NSScreen?
    private var shrink: DispatchWorkItem?
    /// The mouse's offset from the panel's corner while the deck is being dragged.
    private var dragOffset: NSPoint?
    /// The card under the pointer, which the right-click menu is about.
    private var pointed: String?

    /// Where the person put the deck, its bottom-left corner on the screen; nil while it sits beside the orb.
    private(set) var home: NSPoint?
    var isDetached: Bool { home != nil }
    /// Hidden by Hide stickers (the right-click menu or the menu bar's Stickers) until Show Stickers there, in this run of the app.
    var hidden = false
    /// Out of the way while Noteling works in front of the person, as the bubble is.
    var hiddenForControl = false
    /// The person moved the deck, changed its size, reattached it or hid it: the app remembers and places it again.
    var onChange: (() -> Void)?
    /// The person hid the deck from their own menu.
    var onHide: (() -> Void)?
    /// The person closed the deck (Esc): it waits behind the lamp until the next click.
    var onClose: (() -> Void)?

    init(model: DeckModel, look: StickersLook, home: NSPoint?, hideFromScreenShare: Bool) {
        self.model = model
        self.look = look
        self.home = home
        let relay = Relay()
        host = FirstClickHost(rootView: StickersView(model: model, look: look, drag: { relay.panel?.drag($0) }, point: { relay.panel?.point($0, inside: $1) }))
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

    /// A click gives the deck the keys without taking the person's app from the front; never the app's main window.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The keys, once the deck has been clicked: ← Do it, → Mine, ↑ Not now, ⏎ Open, Esc closes the deck.
    override func keyDown(with event: NSEvent) {
        guard let choice = Self.key(event.keyCode, card: model.card) else { return super.keyDown(with: event) }
        choose(choice)
    }

    /// What a key means on the card on top; nil for a key the deck doesn't take.
    nonisolated static func key(_ code: UInt16, card: Sticker?) -> StickerMenuItem.Choice? {
        guard let card else { return code == 53 ? .close : nil }
        switch code {
        case 123: return card.action == nil ? nil : .doIt(card.id)   // ←
        case 124: return .mine(card.id)                              // →
        case 126: return .putAway(card.id)                           // ↑
        case 36, 76: return .open(card.id)                           // ⏎
        case 53: return .close                                       // Esc
        default: return nil
        }
    }

    /// Whether the deck is on the screen. Only while the person opened it from the lamp, with a card to show, not
    /// hidden, and not while Noteling works in front of them. Beside the orb, also only while the bubble is collapsed
    /// and fully there and no crane is flying; at the person's own spot, the bubble's state doesn't matter.
    nonisolated static func shows(count: Int, opened: Bool, hidden: Bool, controlling: Bool, detached: Bool,
                                  bubbleVisible: Bool, alpha: CGFloat, expanded: Bool, flying: Bool) -> Bool {
        guard count > 0, opened, !hidden, !controlling else { return false }
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

    /// Where the panel goes once the person has put it somewhere: its bottom-left corner stays at `home` as the deck
    /// grows upward, and a deck that would leave the screen is brought back onto it.
    nonisolated static func frame(contentHeight: CGFloat, width: CGFloat, home: NSPoint, visible: NSRect) -> NSRect {
        let x = min(max(home.x, visible.minX), max(visible.minX, visible.maxX - width))
        let y = min(max(home.y, visible.minY), max(visible.minY, visible.maxY - contentHeight))
        return NSRect(x: x, y: y, width: width, height: contentHeight)
    }

    /// Measures the deck, then puts the panel beside the orb on `screen` (or the orb's own, or the main one), or at the
    /// person's spot. A panel that would shrink keeps its height for a moment first, so a card on its way out isn't
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

    /// The frame for a deck `height` tall, beside the orb or at the person's spot.
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

    /// The card is being dragged: the deck follows the mouse and, let go, settles on the screen it is over. Its first
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

    /// The pointer came onto `id` or left it. A card's leaving can come after its neighbour's arriving.
    func point(_ id: String, inside: Bool) {
        if inside { pointed = id } else if pointed == id { pointed = nil }
    }

    /// What a right-click offers: on a card, Open, its action, Mine and Not now first; then the size; then the way back
    /// beside the orb, once the deck was moved, and Hide. A nil is a separator line.
    nonisolated static func menu(pointing card: Sticker?, detached: Bool, scale: CGFloat) -> [StickerMenuItem?] {
        var items: [StickerMenuItem?] = []
        if let card {
            items.append(StickerMenuItem(title: "Open", choice: .open(card.id)))
            if let action = card.action { items.append(StickerMenuItem(title: action.label, choice: .doIt(card.id))) }
            items += [StickerMenuItem(title: "Mine", choice: .mine(card.id)), StickerMenuItem(title: "Not now", choice: .putAway(card.id)), nil]
        }
        items += [StickerMenuItem(title: "Bigger", enabled: StickersLook.bigger(than: scale) != nil, choice: .bigger),
                  StickerMenuItem(title: "Smaller", enabled: StickersLook.smaller(than: scale) != nil, choice: .smaller), nil]
        if detached { items.append(StickerMenuItem(title: "Put back beside Noteling", choice: .attach)) }
        items.append(StickerMenuItem(title: "Hide stickers", choice: .hide))
        return items
    }

    /// The menu bar's Stickers submenu: each card waiting, to open it; then Hide Stickers, or while they're hidden, Show
    /// Stickers with how many wait; and the way back beside the orb once the deck was moved. A nil is a separator line.
    nonisolated static func menuBar(stickers: [Sticker], hidden: Bool, detached: Bool) -> [StickerMenuItem?] {
        var items: [StickerMenuItem?] = []
        if hidden {
            items.append(StickerMenuItem(title: stickers.count > 0 ? "Show Stickers (\(stickers.count))" : "Show Stickers", choice: .show))
        } else {
            if !stickers.isEmpty { items += [StickerMenuItem(title: "Open the Deck (\(stickers.count))", choice: .show), nil] }
            for sticker in stickers { items.append(StickerMenuItem(title: menuLine(sticker), choice: .open(sticker.id))) }
            if stickers.isEmpty { items.append(StickerMenuItem(title: "No stickers", enabled: false, choice: .more)) }
            items.append(nil)
            items.append(StickerMenuItem(title: "Hide Stickers", enabled: !stickers.isEmpty, choice: .hide))
        }
        if detached { items.append(StickerMenuItem(title: "Put back beside Noteling", choice: .attach)) }
        return items
    }

    /// The submenu's own title, with how many cards there are: "Stickers", "Stickers (2)", "Stickers (2, hidden)".
    nonisolated static func menuBarTitle(count: Int, hidden: Bool) -> String {
        switch (count, hidden) {
        case (0, false): return "Stickers"
        case (0, true): return "Stickers (hidden)"
        case (let n, false): return "Stickers (\(n))"
        case (let n, true): return "Stickers (\(n), hidden)"
        }
    }

    /// A card's words as one menu line: its headline, else its words.
    nonisolated static func menuLine(_ sticker: Sticker) -> String {
        JobWords.clip((sticker.headline ?? sticker.text).split(whereSeparator: \.isWhitespace).joined(separator: " "), menuTextLimit)
    }
    nonisolated static let menuTextLimit = 60

    /// The right-click menu for where the pointer is: the card still on top, or the deck itself.
    func contextMenu() -> NSMenu {
        let card = pointed.flatMap { id in model.card?.id == id ? model.card : nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in Self.menu(pointing: card, detached: isDetached, scale: look.scale) {
            guard let item else { menu.addItem(.separator()); continue }
            let entry = WindowDragHandle.ClosureMenuItem(title: item.title) { [weak self] in self?.choose(item.choice) }
            entry.isEnabled = item.enabled
            menu.addItem(entry)
        }
        return menu
    }

    func choose(_ choice: StickerMenuItem.Choice) {
        switch choice {
        case .open(let id): model.open(id)
        case .doIt(let id): model.stamp(.doIt, on: id)
        case .mine(let id): model.stamp(.mine, on: id)
        case .putAway(let id): model.stamp(.notNow, on: id)
        case .bigger: if let next = StickersLook.bigger(than: look.scale) { resize(to: next) }
        case .smaller: if let next = StickersLook.smaller(than: look.scale) { resize(to: next) }
        case .attach:
            home = nil
            onChange?()
        case .hide:
            hidden = true
            onChange?()
            onHide?()
        case .show:
            hidden = false
            onChange?()
        case .more: model.openMore()
        case .close:
            if isKeyWindow { resignKey() }
            onClose?()
        }
    }

    /// The deck redraws at the new size, then the panel is placed around it.
    private func resize(to scale: CGFloat) {
        look.scale = scale
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }
}
