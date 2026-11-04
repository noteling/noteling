import AppKit
import QuartzCore

/// A click as the recording kept it, the way a way shown later would look for it: by its name, by the page's own id
/// for it, by where it was alone, or not at all. The caption shows each one as it is kept, so a miss shows at once.
struct CapturedStep: Equatable {
    enum Kind: Equatable {
        case named(String)
        case byID(String)      // the control's kind: "button"
        case place(String)     // the thing's kind: "group"
        case nothing
    }

    /// Its place among the recording's clicks, from 1.
    let number: Int
    /// The click's event, in `events.json`.
    let event: Int
    let kind: Kind
    /// The person pointed at it with the pen after it was kept.
    var fixed = false

    /// A step a way can't be sure to find again: kept by where it was, or not at all.
    var isMiss: Bool {
        switch kind {
        case .named, .byID: return false
        case .place, .nothing: return true
        }
    }

    static func of(_ e: WatchEvent, number: Int, fixed: Bool = false) -> CapturedStep {
        let role = e.axRole.map(WatchRecorder.prettyRole).map { $0 == "static text" ? "text" : $0 } ?? "control"
        let kind: Kind
        if e.axRole != nil, let label = e.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty { kind = .named(label) }
        else if e.axRole != nil, e.domID != nil { kind = .byID(role) }
        else if e.axRole != nil, let r = e.rect, r.count == 4, r[2] > 0, r[3] > 0 { kind = .place(role) }
        else { kind = .nothing }
        return CapturedStep(number: number, event: e.index, kind: kind, fixed: fixed)
    }

    /// How the caption says it: "Billing", "? a group with no name", "· missed".
    var words: String {
        switch kind {
        case .named(let name): return (name.count > 26 ? String(name.prefix(25)) + "…" : name) + (fixed ? " ✎" : "")
        case .byID(let role): return role + (fixed ? " ✎" : "")
        case .place(let role): return "? a \(role) with no name"
        case .nothing: return "· missed"
        }
    }

    /// What the flash beside it says: the caption's words, and for a miss what that means.
    var tag: String {
        switch kind {
        case .named, .byID: return words
        case .place: return "\(words): kept by where it is"
        case .nothing: return "· missed: nothing here to keep"
        }
    }
}

/// While Watch Me records: the shimmering border on every screen, the caption at the top with the steps kept so far,
/// and a flash on each step as it is kept, ringed with what a way shown later will look for. Nothing of it takes a
/// click, except the caption while its last step is a miss: a click there asks to point at what was meant.
@MainActor
final class WatchHUD {
    /// The caption was clicked while its last step was a miss.
    var onFix: (() -> Void)?

    private var borders: [NSPanel] = []
    private var captions: [CaptionPanel] = []
    private var flashGeneration = 0

    nonisolated static var purple: NSColor { .systemPurple }
    nonisolated static var amber: NSColor { .systemOrange }

    var isShowing: Bool { !borders.isEmpty }

    func show(hotkey: String) {
        guard !isShowing else { return }
        for s in NSScreen.screens {
            let p = Self.panel(s.frame, clickThrough: true)
            let v = NSView(frame: NSRect(origin: .zero, size: s.frame.size))
            v.wantsLayer = true
            if let layer = v.layer { ShimmerBorder.install(on: layer, bounds: v.bounds, dim: 0) }
            p.contentView = v
            p.orderFrontRegardless()
            borders.append(p)
            let caption = CaptionPanel(screen: s)
            caption.onClick = { [weak self] in self?.onFix?() }
            caption.orderFrontRegardless()
            captions.append(caption)
        }
        update(steps: [], hotkey: hotkey)
    }

    /// Out of the way for a moment, such as while the pen, with a border and a caption of its own, points at a step.
    func setHidden(_ hidden: Bool) {
        for p in borders + captions {
            if hidden { p.orderOut(nil) } else { p.orderFrontRegardless() }
        }
    }

    func hide() {
        for p in borders { p.orderOut(nil) }
        for p in captions { p.orderOut(nil) }
        borders.removeAll()
        captions.removeAll()
        flashGeneration += 1
    }

    func update(steps: [CapturedStep], hotkey: String) {
        let fixable = steps.last?.isMiss == true
        let status = Self.status(hotkey: hotkey)
        let line = Self.stepsLine(steps)
        for c in captions { c.show(status: status, line: line, fixable: fixable) }
    }

    /// The first line: "Noteling is watching · ⌃⌥Space to stop".
    nonisolated static func status(hotkey: String) -> String { "Noteling is watching  ·  \(hotkey) to stop" }

    /// The second line: the last few steps kept, numbered, the misses in amber, and what to do about the last one.
    nonisolated static func stepsLine(_ steps: [CapturedStep]) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let dim = NSColor(calibratedWhite: 1, alpha: 0.5), ink = NSColor(calibratedWhite: 1, alpha: 0.92)
        let out = NSMutableAttributedString()
        func add(_ s: String, _ color: NSColor) { out.append(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])) }
        guard !steps.isEmpty else {
            add("Click through it the way you always do", dim)
            return out
        }
        let shown = steps.suffix(3)
        if steps.count > shown.count { add("…   ", dim) }
        for (i, step) in shown.enumerated() {
            if i > 0 { add("     ", dim) }
            add("\(step.number)  ", dim)
            add(step.words, step.isMiss ? amber : ink)
        }
        if steps.last?.isMiss == true { add("   ·   click here, then point at it", amber) }
        return out
    }

    /// Rings what a step kept, with its words beside it, and fades: purple for a step a way will find, amber for a
    /// miss. `frame` is what was kept, in AppKit global coordinates; a step that kept nothing rings the spot clicked.
    func flash(_ step: CapturedStep, frame: NSRect?, at point: NSPoint) {
        let ring = frame.map { $0.insetBy(dx: -4, dy: -4) } ?? NSRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28)
        guard let panel = borders.first(where: { $0.frame.contains(NSPoint(x: ring.midX, y: ring.midY)) }) ?? borders.first(where: { $0.frame.contains(point) }),
              let root = panel.contentView?.layer else { return }
        flashGeneration += 1
        let generation = flashGeneration
        root.sublayers?.filter { $0.name == "flash" }.forEach { $0.removeFromSuperlayer() }
        let local = NSRect(x: ring.minX - panel.frame.minX, y: ring.minY - panel.frame.minY, width: ring.width, height: ring.height)
        let color = step.isMiss ? Self.amber : Self.purple
        let flash = CALayer()
        flash.name = "flash"
        flash.frame = root.bounds
        let shape = CAShapeLayer()
        let radius = frame == nil ? local.width / 2 : 7
        shape.path = CGPath(roundedRect: local, cornerWidth: radius, cornerHeight: radius, transform: nil)
        shape.fillColor = color.withAlphaComponent(0.10).cgColor
        shape.strokeColor = color.cgColor
        shape.lineWidth = 2.5
        if step.isMiss { shape.lineDashPattern = [6, 4] }
        flash.addSublayer(shape)
        let (pill, text) = Self.tag(step.tag, color: color, scale: panel.screen?.backingScaleFactor ?? 2)
        var x = local.minX, y = local.minY - pill.frame.height - 8
        if y < 8 { y = local.maxY + 8 }
        x = min(max(8, x), root.bounds.width - pill.frame.width - 8)
        pill.frame.origin = CGPoint(x: x, y: y)
        pill.addSublayer(text)
        flash.addSublayer(pill)
        root.addSublayer(flash)
        // A step that will be found goes quickly; a miss stays long enough to be read.
        let hold = step.isMiss ? 2.6 : 0.9
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            guard let self, self.flashGeneration == generation else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.6)
            CATransaction.setCompletionBlock { flash.removeFromSuperlayer() }
            flash.opacity = 0
            CATransaction.commit()
        }
    }

    private static func tag(_ words: String, color: NSColor, scale: CGFloat) -> (CALayer, CATextLayer) {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let width = min(ceil((words as NSString).size(withAttributes: [.font: font]).width) + 24, 420)
        let pill = CALayer()
        pill.frame = CGRect(x: 0, y: 0, width: width, height: 24)
        pill.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.92).cgColor
        pill.cornerRadius = 12
        pill.borderColor = color.withAlphaComponent(0.9).cgColor
        pill.borderWidth = 1
        let text = CATextLayer()
        text.string = NSAttributedString(string: words, attributes: [.font: font, .foregroundColor: NSColor.white])
        text.contentsScale = scale
        text.truncationMode = .end
        text.frame = CGRect(x: 12, y: 4, width: width - 24, height: 16)
        return (pill, text)
    }

    static func panel(_ frame: NSRect, clickThrough: Bool) -> NSPanel {
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = clickThrough
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        return p
    }
}

/// The caption at the top of a screen while Watch Me records: two lines on a dark pill. It lets clicks through to
/// what is under it, except while it offers to fix the last step.
@MainActor
final class CaptionPanel: NSPanel {
    var onClick: (() -> Void)?
    static let size = CGSize(width: 600, height: 52)
    private let statusText = CATextLayer()
    private let stepsText = CATextLayer()
    private let pill = CALayer()

    init(screen: NSScreen) {
        let frame = NSRect(x: screen.frame.midX - Self.size.width / 2, y: screen.frame.maxY - 30 - Self.size.height,
                           width: Self.size.width, height: Self.size.height)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        let view = ClickView(frame: NSRect(origin: .zero, size: Self.size))
        view.onClick = { [weak self] in self?.onClick?() }
        view.wantsLayer = true
        contentView = view
        let scale = screen.backingScaleFactor
        pill.frame = view.bounds
        pill.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.88).cgColor
        pill.cornerRadius = 16
        for (t, y) in [(statusText, CGFloat(28)), (stepsText, CGFloat(9))] {
            t.alignmentMode = .center
            t.truncationMode = .end
            t.contentsScale = scale
            t.frame = CGRect(x: 14, y: y, width: Self.size.width - 28, height: 17)
            pill.addSublayer(t)
        }
        view.layer?.addSublayer(pill)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(status: String, line: NSAttributedString, fixable: Bool) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        statusText.string = NSAttributedString(string: status, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white,
        ])
        stepsText.string = line
        pill.borderColor = WatchHUD.amber.withAlphaComponent(0.85).cgColor
        pill.borderWidth = fixable ? 1.5 : 0
        CATransaction.commit()
        ignoresMouseEvents = !fixable
    }

    private final class ClickView: NSView {
        var onClick: (() -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { onClick?() }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    }
}
