import AppKit
import Combine
import SwiftUI

/// What one note's panel shows and is doing: the note, whether it is being written on, how big it is drawn, a moment of
/// warmth when its when comes, and the clock the when words are read against.
@MainActor
final class MemoPanelState: ObservableObject {
    @Published var memo: Memo
    @Published var editing = false
    @Published var scale: CGFloat
    @Published var warm = false
    @Published var now = Date()
    /// What is being typed, until the writing ends and it becomes the note.
    @Published var headline = ""
    @Published var words = ""

    init(memo: Memo, scale: CGFloat) {
        self.memo = memo
        self.scale = scale
    }

    /// The note's words and checklist as one text to type on: a line each, items as `- [ ] …`.
    static func wordsToEdit(_ memo: Memo) -> String {
        var lines = memo.text.isEmpty ? [] : [memo.text]
        lines += memo.items.map { "- [\($0.done ? "x" : " ")] \($0.text)" }
        return lines.joined(separator: "\n")
    }

    /// Typed text back into words and a checklist.
    static func parse(words: String) -> (text: String, items: [PaperItem]) {
        var text: [String] = [], items: [PaperItem] = []
        for raw in words.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let item = MemoFile.item(line) { items.append(item) } else { text.append(line) }
        }
        return (text.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), items)
    }

    func beginEditing() {
        headline = memo.headline ?? ""
        words = Self.wordsToEdit(memo)
        editing = true
    }

    /// The note as typed; nil when nothing changed.
    func endEditing() -> Memo? {
        guard editing else { return nil }
        editing = false
        var changed = memo
        let head = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        changed.headline = head.isEmpty ? nil : head
        let parsed = Self.parse(words: words)
        changed.text = parsed.text
        changed.items = parsed.items
        guard changed != memo else { return nil }
        memo = changed
        return changed
    }
}

/// What the panel does for its view.
struct MemoPanelActions {
    var save: (Memo) -> Void = { _ in }
    var remove: () -> Void = {}
    var drag: (StickerDrag) -> Void = { _ in }
    var toggle: (Int) -> Void = { _ in }
    var openPage: () -> Void = {}
    var collapse: () -> Void = {}
    var endEditing: () -> Void = {}
    var hover: (Bool) -> Void = { _ in }
}

/// One of your notes on its paper: read, with its checklist to tick and its page to open; or written on, a headline
/// line and the words. A click on the words starts writing, Esc or a click elsewhere ends it; the glue strip drags it,
/// a double-click there folds it to its first line; the peel at its corner, on hover, takes it down.
struct MemoPanelView: View {
    @ObservedObject var state: MemoPanelState
    var actions: MemoPanelActions
    @State private var hovering = false
    @State private var peeling = false
    @FocusState private var wordsFocused: Bool

    var scale: CGFloat { state.scale }
    var paperWidth: CGFloat { PaperLook.memoWidth * scale }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if state.editing { editor } else { reading }
            }
            .overlay(alignment: .top) { strip }
            .overlay {
                if state.warm {
                    RoundedRectangle(cornerRadius: 1.5 * scale).stroke(PaperColour.amber.edge, lineWidth: 2.5 * scale)
                        .transition(.opacity)
                }
            }
            // Peeled: the sheet lifts from its corner and is gone.
            .rotationEffect(peeling ? .degrees(-5) : .zero, anchor: .bottomTrailing)
            .scaleEffect(peeling ? 0.94 : 1, anchor: .bottomTrailing)
            .offset(y: peeling ? -18 : 0)
            .opacity(peeling ? 0 : 1)
            if hovering, !state.editing, !peeling {
                PeelButton(help: "Take this note down") {
                    withAnimation(.easeIn(duration: PeelButton.peelSeconds)) { peeling = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + PeelButton.peelSeconds + 0.03) { actions.remove() }
                }
                .offset(x: PeelButton.offset, y: PeelButton.offset)
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .padding(PaperLook.margin)
        .onHover { inside in
            hovering = inside
            actions.hover(inside)
        }
        .animation(.easeInOut(duration: 0.35), value: state.warm)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .environment(\.colorScheme, .light)
    }

    private var reading: some View {
        PaperView(headline: state.memo.headline, text: state.memo.text, items: state.memo.items, when: state.memo.when, page: state.memo.page,
                  hand: .yours, colour: state.memo.colour, scale: scale, collapsed: state.memo.collapsed, now: state.now,
                  tilt: PaperLook.tilt(for: state.memo.id), onToggle: actions.toggle, onPage: actions.openPage)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !state.memo.collapsed else { actions.collapse(); return }
                state.beginEditing()
                wordsFocused = true
            }
            .gesture(DragGesture(minimumDistance: CardView.dragDistance).onChanged { _ in actions.drag(.moved) }.onEnded { _ in actions.drag(.ended) })
            .help(state.memo.collapsed ? "Click to open" : "Click to write  ·  Drag to move  ·  Right-click for more")
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Note: \(state.memo.firstLine)")
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            TextField("", text: $state.headline, prompt: Text("Headline").foregroundStyle(PaperType.inkSoft.opacity(0.5)))
                .textFieldStyle(.plain).font(PaperType.headline(.yours, scale))
                .onSubmit { wordsFocused = true }
            TextEditor(text: $state.words)
                .font(PaperType.body(.yours, scale)).lineSpacing(PaperType.lineSpacing(.yours, scale))
                .scrollContentBackground(.hidden).scrollDisabled(true)
                .frame(minHeight: 60 * scale)
                .focused($wordsFocused)
                .onExitCommand { actions.endEditing() }
        }
        .foregroundStyle(PaperType.ink)
        .padding(.horizontal, (PaperLook.padding - 5) * scale)
        .padding(.top, (PaperLook.strip + 9) * scale)
        .padding(.bottom, (PaperLook.padding - 4) * scale)
        .frame(width: paperWidth, alignment: .topLeading)
        .frame(minHeight: PaperLook.minHeight * scale, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(PaperSheet(colour: state.memo.colour, scale: scale))
        .onAppear { wordsFocused = true }
    }

    /// The glue strip: the drag handle, and a double-click folds the note or opens it again.
    private var strip: some View {
        Color.clear.frame(width: paperWidth, height: (PaperLook.strip + 2) * scale).contentShape(Rectangle())
            .onTapGesture(count: 2) { actions.collapse() }
            .gesture(DragGesture(minimumDistance: CardView.dragDistance).onChanged { _ in actions.drag(.moved) }.onEnded { _ in actions.drag(.ended) })
            .help("Drag to move  ·  Double-click to fold")
    }
}

/// One line of a note's right-click menu; nil in the list is a separator.
struct MemoMenuItem: Equatable {
    enum Choice: Equatable { case openPage, colour(PaperColour), collapse, onTop, bigger, smaller, remove }
    let title: String
    var enabled = true
    var checked = false
    let choice: Choice
}

/// The panel one of your notes lives in: borderless, pinned where you put it. It lives on the desktop, under your
/// windows and the same on every Space, like the desktop's widgets; it comes up on top of everything when it is new,
/// when its when comes and while you write on it, and settles back once you have had it; Keep on top holds one above
/// the windows of its own Space. It takes the keyboard while you write and gives it back when you click away.
final class MemoPanel: NSPanel {
    let state: MemoPanelState
    private let host: FirstClickHost<MemoPanelView>
    private var subscriptions = Set<AnyCancellable>()
    private var dragOffset: NSPoint?
    private var upWork: DispatchWorkItem?
    /// Clicked since it came up: once it is left again, it settles.
    private var touched = false
    /// Up on top of everything, everywhere: new, woken or being written on.
    private(set) var up = false
    /// The note changed as typed, moved, folded, recoloured or kept on top: the windows keep it.
    var onChange: ((Memo) -> Void)?
    var onRemove: (() -> Void)?
    var onResize: ((CGFloat?) -> Void)?
    var onToggle: ((Int) -> Void)?
    var onOpenPage: ((String) -> Void)?

    /// Where a note lives: on the desktop, just above its icons and under every window.
    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    init(memo: Memo, scale: CGFloat, hideFromScreenShare: Bool) {
        let state = MemoPanelState(memo: memo, scale: scale)
        self.state = state
        let relay = Relay()
        let actions = MemoPanelActions(save: { relay.panel?.changed($0) }, remove: { relay.panel?.onRemove?() },
                                       drag: { relay.panel?.drag($0) }, toggle: { relay.panel?.onToggle?($0) },
                                       openPage: { relay.panel?.openPage() }, collapse: { relay.panel?.collapse() },
                                       endEditing: { relay.panel?.endEditing() }, hover: { relay.panel?.hovered($0) })
        host = FirstClickHost(rootView: MemoPanelView(state: state, actions: actions))
        super.init(contentRect: NSRect(x: 0, y: 0, width: PaperLook.memoWidth * scale + 2 * PaperLook.margin, height: PaperLook.minHeight * scale + 2 * PaperLook.margin),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: false)
        relay.panel = self
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        sharingType = hideFromScreenShare ? .none : .readOnly
        applyLevel()
        host.contextMenu = { [weak self] in self?.contextMenu() }
        contentView = host
        state.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.fit() } }.store(in: &subscriptions)
        fit()
    }

    private final class Relay { weak var panel: MemoPanel? }

    /// Takes the keyboard while the person writes; never the app's main window.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// A click elsewhere ends the writing, and a note that came up and was clicked settles where it lives.
    override func resignKey() {
        super.resignKey()
        endEditing()
        if touched { settle() }
    }

    /// A click on the note counts as having had it: a note that came up settles once the mouse has left it again (a
    /// tick, a fold, a drag), or once the keyboard goes elsewhere when the click was to write.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown { touched = true }
        super.sendEvent(event)
    }

    func hovered(_ inside: Bool) {
        if !inside, touched, !state.editing, !isKeyWindow { settle() }
    }

    var memo: Memo { state.memo }

    /// The note as the store has it now, when it changed elsewhere (a file edit, the scribe's tidying).
    func show(_ memo: Memo) {
        guard !state.editing, memo != state.memo else { return }
        state.memo = memo
        applyLevel()
    }

    /// Up is on top of everything on every Space, full-screen apps too; Keep on top is above the windows of the Space
    /// the note is on; otherwise the note lives on the desktop, over the wallpaper and its icons, under every window,
    /// the same on every Space.
    static func level(onTop: Bool, up: Bool) -> (level: NSWindow.Level, behaviour: NSWindow.CollectionBehavior) {
        if up { return (.floating, [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]) }
        if onTop { return (.floating, [.stationary]) }
        return (desktopLevel, [.canJoinAllSpaces, .stationary])
    }

    func applyLevel() {
        let place = Self.level(onTop: state.memo.onTop, up: up)
        level = place.level
        collectionBehavior = place.behaviour
    }

    /// Comes up on top of everything, where the person is: for `seconds`, or until it has been clicked and left.
    func raise(for seconds: TimeInterval? = nil) {
        upWork?.cancel()
        upWork = nil
        up = true
        touched = false
        applyLevel()
        if let seconds {
            let work = DispatchWorkItem { [weak self] in self?.settle() }
            upWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
    }

    /// Back where it lives.
    func settle() {
        upWork?.cancel()
        upWork = nil
        touched = false
        guard up else { return }
        up = false
        state.warm = false
        applyLevel()
    }

    /// Sizes the panel to its paper, keeping the top-left corner where it is, so a note grows downward as it is written.
    func fit() {
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.width > 0, size.height > 0, size != frame.size else { return }
        let origin = NSPoint(x: frame.minX, y: frame.maxY - size.height)
        setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Where the paper's top-left corner is on the screen, which is what the note remembers.
    var paperTopLeft: NSPoint { NSPoint(x: frame.minX + PaperLook.margin, y: frame.maxY - PaperLook.margin) }

    func place(topLeft: NSPoint) {
        setFrameOrigin(NSPoint(x: topLeft.x - PaperLook.margin, y: topLeft.y + PaperLook.margin - frame.height))
    }

    // MARK: what the person does

    private func changed(_ memo: Memo) {
        state.memo = memo
        onChange?(memo)
    }

    /// Writing brings the note up, so what is typed is seen; a click elsewhere ends the writing and settles it.
    func beginEditing() {
        guard !state.editing else { return }
        raise()
        touched = true
        makeKeyAndOrderFront(nil)
        state.beginEditing()
    }

    /// The writing ended, by Esc or a click elsewhere: what was typed becomes the note; a note left blank goes away.
    func endEditing() {
        guard state.editing else { return }
        if let memo = state.endEditing() { onChange?(memo) } else if state.memo.isBlank { onChange?(state.memo) }
    }

    func drag(_ phase: StickerDrag) {
        let mouse = NSEvent.mouseLocation
        switch phase {
        case .moved:
            if dragOffset == nil { dragOffset = NSPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY) }
            guard let dragOffset else { return }
            setFrameOrigin(NSPoint(x: mouse.x - dragOffset.x, y: mouse.y - dragOffset.y))
        case .ended:
            guard dragOffset != nil else { return }
            dragOffset = nil
            if let screen = FloatingWindowPlacement.screen(for: frame, fallback: NSScreen.main) {
                setFrame(FloatingWindowPlacement.clamped(frame, to: screen.visibleFrame), display: true)
            }
            var memo = state.memo
            memo.at = paperTopLeft
            changed(memo)
        }
    }

    func collapse() {
        var memo = state.memo
        memo.collapsed.toggle()
        changed(memo)
    }

    func openPage() {
        if let page = state.memo.page { onOpenPage?(page) }
    }

    /// Its when came: the note comes up where the person is and glows until they have had it.
    func wake() {
        state.now = Date()
        raise()
        state.warm = true
        orderFrontRegardless()
    }

    // MARK: the menu

    nonisolated static func menu(for memo: Memo, scale: CGFloat) -> [MemoMenuItem?] {
        var items: [MemoMenuItem?] = []
        if memo.page != nil { items += [MemoMenuItem(title: "Open page", choice: .openPage), nil] }
        for colour in PaperColour.yours { items.append(MemoMenuItem(title: colour.name, checked: colour == memo.colour, choice: .colour(colour))) }
        items.append(nil)
        items.append(MemoMenuItem(title: memo.collapsed ? "Unfold" : "Fold", choice: .collapse))
        items.append(MemoMenuItem(title: "Keep on top", checked: memo.onTop, choice: .onTop))
        items.append(MemoMenuItem(title: "Bigger", enabled: PaperLook.bigger(than: scale) != nil, choice: .bigger))
        items.append(MemoMenuItem(title: "Smaller", enabled: PaperLook.smaller(than: scale) != nil, choice: .smaller))
        items.append(nil)
        items.append(MemoMenuItem(title: "Remove", choice: .remove))
        return items
    }

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in Self.menu(for: state.memo, scale: state.scale) {
            guard let item else { menu.addItem(.separator()); continue }
            let entry = WindowDragHandle.ClosureMenuItem(title: item.title) { [weak self] in self?.choose(item.choice) }
            entry.isEnabled = item.enabled
            entry.state = item.checked ? .on : .off
            menu.addItem(entry)
        }
        return menu
    }

    func choose(_ choice: MemoMenuItem.Choice) {
        switch choice {
        case .openPage: openPage()
        case .colour(let colour):
            var memo = state.memo
            memo.colour = colour
            changed(memo)
        case .collapse: collapse()
        case .onTop:
            var memo = state.memo
            memo.onTop.toggle()
            changed(memo)
            applyLevel()
        case .bigger: onResize?(PaperLook.bigger(than: state.scale))
        case .smaller: onResize?(PaperLook.smaller(than: state.scale))
        case .remove: onRemove?()
        }
    }
}
