import AppKit
import QuartzCore
import SwiftUI

/// Where a tour is: what the card on screen and the list in chat both show.
struct TourProgress: Equatable {
    enum State: Equatable {
        case looking      // the step's control isn't found yet, such as while the next page loads
        case showing      // ringed on screen, waiting for the person's click
        case offscreen    // found, but scrolled out of view
        case lost         // not found in time
        case done
        case stopped
    }

    var title: String
    var steps: [String]
    /// The step being shown or looked for, from 0; `steps.count` once every step is done.
    var current: Int
    var state: State
    /// What the tour opened to get the person to where the way starts, as the card says it: the page's address, or
    /// the app's name. Nil when they were already there.
    var opened: String? = nil

    var isOver: Bool { state == .done || state == .stopped }
    var isLast: Bool { current == steps.count - 1 }
    var step: String? { steps.indices.contains(current) ? steps[current] : nil }
    /// "1 of 3"
    var count: String { "\(min(current + 1, steps.count)) of \(steps.count)" }
}

/// The way shown on screen: everything but the control dims, a breathing ring sits on it, Noteling's purple arrow glides
/// to it, and a sticky-note card beside it says what to do. Clicks go through to the app; only the card takes them.
@MainActor
final class ShowOverlay {
    static let purple = NSColor(red: 0.55, green: 0.30, blue: 0.95, alpha: 1)
    static let dimAlpha: CGFloat = 0.56
    /// Above the apps' windows and below Noteling's pad, so the pad isn't dimmed out of reach.
    static let dimLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
    static let marksLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)

    let card = ShowCardModel()
    private var screens: [(screen: NSScreen, dim: NSPanel, dimView: ShowDimView, marks: NSPanel, marksView: ShowMarksView)] = []
    private var cardPanel: NSPanel?
    private var cardHost: ShowCardHost?
    private let hideFromScreenShare: Bool
    private(set) var target: NSRect?

    init(hideFromScreenShare: Bool) {
        self.hideFromScreenShare = hideFromScreenShare
    }

    var isShown: Bool { !screens.isEmpty }

    /// Puts the dim and the marks on every screen, ready for a target. `from` is where the arrow starts: the pointer.
    func present(from point: NSPoint) {
        guard screens.isEmpty else { return }
        for screen in NSScreen.screens {
            let dimView = ShowDimView(frame: NSRect(origin: .zero, size: screen.frame.size))
            let marksView = ShowMarksView(frame: NSRect(origin: .zero, size: screen.frame.size), scale: screen.backingScaleFactor)
            let dim = Self.panel(screen.frame, level: Self.dimLevel, content: dimView, shareable: !hideFromScreenShare)
            let marks = Self.panel(screen.frame, level: Self.marksLevel, content: marksView, shareable: !hideFromScreenShare)
            dim.orderFrontRegardless()
            marks.orderFrontRegardless()
            dimView.fadeIn()
            if screen.frame.contains(point) { marksView.placeArrow(at: local(point, in: screen), animated: false) }
            screens.append((screen, dim, dimView, marks, marksView))
        }
        let host = ShowCardHost(rootView: ShowCardView(model: card))
        let panel = Self.panel(NSRect(x: 0, y: 0, width: ShowCardView.width + 2 * ShowCardView.margin, height: 160),
                               level: Self.marksLevel, content: host, shareable: !hideFromScreenShare, interactive: true)
        panel.alphaValue = 0
        cardHost = host
        cardPanel = panel
    }

    /// Rings `rect` (AppKit global coordinates): the cutout and the ring move there, the arrow glides to it.
    func ring(_ rect: NSRect) {
        let moved = target.map { !$0.equalTo(rect) } ?? true
        let first = target == nil
        target = rect
        for s in screens {
            let local = local(rect, in: s.screen)
            if s.screen.frame.intersects(rect) {
                s.dimView.cut(local, animated: true)
                s.marksView.ring(local, appear: first)
                if moved { s.marksView.glideArrow(to: Self.arrowTip(for: local)) }
            } else {
                s.dimView.cut(nil, animated: true)
                s.marksView.ring(nil, appear: false)
            }
        }
        placeCard()
    }

    /// Follows the control as the page moves it, without the arrow's flight.
    func follow(_ rect: NSRect) {
        guard let old = target, !old.equalTo(rect) else { return }
        target = rect
        for s in screens where s.screen.frame.intersects(rect) {
            let local = local(rect, in: s.screen)
            s.dimView.cut(local, animated: false)
            s.marksView.ring(local, appear: false, animated: false)
            s.marksView.placeArrow(at: Self.arrowTip(for: local), animated: false)
        }
        placeCard()
    }

    /// Nothing to ring right now: the dim lightens and the card waits where it was.
    func unring() {
        target = nil
        for s in screens {
            s.dimView.cut(nil, animated: true)
            s.marksView.ring(nil, appear: false)
        }
        placeCard()
    }

    /// The step was clicked: the ring turns green and lets go.
    func stepDone() {
        for s in screens { s.marksView.flashDone() }
    }

    func update(_ progress: TourProgress) {
        card.progress = progress
        placeCard()
    }

    func dismiss(after delay: TimeInterval = 0) {
        let panels = screens.flatMap { [$0.dim, $0.marks] } + [cardPanel].compactMap { $0 }
        screens = []
        cardPanel = nil
        cardHost = nil
        target = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.28
                for p in panels { p.animator().alphaValue = 0 }
            }, completionHandler: {
                MainActor.assumeIsolated { for p in panels { p.orderOut(nil) } }
            })
        }
    }

    // MARK: - Layout

    /// The arrow's tip just inside the control's lower right, so the arrow sits below and right of it, pointing in.
    nonisolated static func arrowTip(for rect: NSRect) -> NSPoint {
        NSPoint(x: rect.maxX - min(18, rect.width * 0.3), y: rect.minY + min(10, rect.height * 0.35))
    }

    /// Beside the ring when there is room (right, then left), else under or over it; where it was while looking.
    nonisolated static func cardOrigin(size: NSSize, ring: NSRect?, in visible: NSRect, last: NSPoint?) -> NSPoint {
        guard let ring = ring?.insetBy(dx: -ShowMarksView.pad, dy: -ShowMarksView.pad) else {
            if let last { return last }
            return NSPoint(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.18)
        }
        let gap: CGFloat = 26 - ShowCardView.margin
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, visible.minY + 8), visible.maxY - size.height - 8) }
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, visible.minX + 8), visible.maxX - size.width - 8) }
        let midY = clampY(ring.midY - size.height / 2 - 18)
        let below = NSPoint(x: clampX(ring.midX - size.width / 2), y: ring.minY - gap - size.height)
        let fitsBelow = below.y >= visible.minY + 8
        // A control in a header or toolbar: the card hangs under it rather than covering the rest of the bar.
        if fitsBelow, ring.maxY > visible.maxY - visible.height * 0.22 { return below }
        if ring.maxX + gap + size.width <= visible.maxX - 8 { return NSPoint(x: ring.maxX + gap, y: midY) }
        // Left of a button is usually the field it goes with, so under it comes first.
        if fitsBelow { return below }
        if ring.minX - gap - size.width >= visible.minX + 8 { return NSPoint(x: ring.minX - gap - size.width, y: midY) }
        return NSPoint(x: clampX(ring.midX - size.width / 2), y: clampY(ring.maxY + gap))
    }

    private func placeCard() {
        guard let panel = cardPanel, let host = cardHost else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let screen = target.flatMap { t in NSScreen.screens.first { $0.frame.intersects(t) } }
            ?? NSScreen.screens.first { $0.frame.contains(panel.frame.origin) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let shown = panel.alphaValue > 0
        let origin = Self.cardOrigin(size: size, ring: target, in: visible, last: shown ? panel.frame.origin : nil)
        let frame = NSRect(origin: origin, size: size)
        if !shown {
            panel.setFrame(frame.offsetBy(dx: 0, dy: -10), display: true)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(frame, display: true)
            }
        } else if !panel.frame.equalTo(frame) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.38
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    private func local(_ p: NSPoint, in screen: NSScreen) -> NSPoint {
        NSPoint(x: p.x - screen.frame.minX, y: p.y - screen.frame.minY)
    }

    private func local(_ r: NSRect, in screen: NSScreen) -> NSRect {
        r.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
    }

    private static func panel(_ frame: NSRect, level: NSWindow.Level, content: NSView, shareable: Bool, interactive: Bool = false) -> NSPanel {
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = level
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = !interactive
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.sharingType = shareable ? .readOnly : .none
        p.contentView = content
        return p
    }
}

// MARK: - The dim

/// The screen under a dark veil with a rounded hole where the control is.
final class ShowDimView: NSView {
    private let veil = CAShapeLayer()
    private var hole: NSRect?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        veil.fillRule = .evenOdd
        veil.fillColor = NSColor.black.withAlphaComponent(ShowOverlay.dimAlpha).cgColor
        veil.path = Self.path(bounds: bounds, hole: nil)
        veil.opacity = 0
        layer?.addSublayer(veil)
    }

    required init?(coder: NSCoder) { fatalError() }

    func fadeIn() {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 0; a.toValue = 1; a.duration = 0.35
        veil.add(a, forKey: "fade")
        veil.opacity = 1
    }

    /// Cuts the hole at `rect` (local), or closes it: an iris that opens from wide on the first cut.
    func cut(_ rect: NSRect?, animated: Bool) {
        let target = rect.map { $0.insetBy(dx: -ShowMarksView.pad, dy: -ShowMarksView.pad) }
        let from = veil.presentation()?.path ?? veil.path
        let start: CGPath? = (hole == nil && target != nil) ? Self.path(bounds: bounds, hole: target!.insetBy(dx: -90, dy: -90)) : from
        let to = Self.path(bounds: bounds, hole: target)
        hole = target
        veil.path = to
        // While looking for the next control the veil lightens, so the page underneath reads as "loading", not "blocked".
        veil.fillColor = NSColor.black.withAlphaComponent(target == nil ? ShowOverlay.dimAlpha * 0.5 : ShowOverlay.dimAlpha).cgColor
        guard animated, let start else { veil.removeAnimation(forKey: "cut"); return }
        let a = CABasicAnimation(keyPath: "path")
        a.fromValue = start; a.toValue = to
        a.duration = 0.5
        a.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
        veil.add(a, forKey: "cut")
    }

    /// The whole screen with a rounded hole; a hole too small to see when there is nothing to show, so the path keeps
    /// the same shape and animates between steps.
    static func path(bounds: NSRect, hole: NSRect?) -> CGPath {
        let p = CGMutablePath()
        p.addRect(bounds.insetBy(dx: -4, dy: -4))
        let r = hole ?? NSRect(x: bounds.midX, y: bounds.midY, width: 2, height: 2)
        let radius = min(12, r.height / 2, r.width / 2)
        p.addPath(CGPath(roundedRect: r, cornerWidth: max(radius, 0.5), cornerHeight: max(radius, 0.5), transform: nil))
        return p
    }
}

// MARK: - The ring and the arrow

/// The breathing ring around the control, and Noteling's purple arrow pointing at it.
final class ShowMarksView: NSView {
    nonisolated static let pad: CGFloat = 7
    nonisolated static let arrowHeight: CGFloat = 30

    private let glow = CAShapeLayer()
    private let rim = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let arrow = CALayer()
    private let tap = CAShapeLayer()
    private let arrowTipOffset: CGPoint   // from the image's lower-left corner to the tip, in points
    private var arrowAt: NSPoint?
    /// Bumped whenever the arrow flies or lets go, so an earlier landing stops tapping.
    private var flight = 0

    init(frame: NSRect, scale: CGFloat) {
        let extent = GhostCursorArt.extent(height: Self.arrowHeight).integral
        arrowTipOffset = CGPoint(x: -extent.minX, y: extent.height + extent.minY)
        super.init(frame: frame)
        wantsLayer = true
        guard let root = layer else { return }

        glow.fillColor = nil
        glow.strokeColor = ShowOverlay.purple.withAlphaComponent(0.55).cgColor
        glow.lineWidth = 10
        glow.shadowColor = ShowOverlay.purple.cgColor
        glow.shadowRadius = 14
        glow.shadowOpacity = 0.9
        glow.shadowOffset = .zero
        rim.fillColor = nil
        rim.strokeColor = NSColor.white.withAlphaComponent(0.95).cgColor
        rim.lineWidth = 6
        ring.fillColor = nil
        ring.strokeColor = ShowOverlay.purple.cgColor
        ring.lineWidth = 3
        for l in [glow, rim, ring] { l.opacity = 0; root.addSublayer(l) }

        tap.fillColor = nil
        tap.strokeColor = ShowOverlay.purple.cgColor
        tap.lineWidth = 2
        tap.opacity = 0
        root.addSublayer(tap)

        let image = GhostCursorArt.image(height: Self.arrowHeight, scale: scale)
        arrow.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        arrow.contentsScale = scale
        arrow.bounds = CGRect(origin: .zero, size: extent.size)
        arrow.anchorPoint = CGPoint(x: arrowTipOffset.x / extent.width, y: 1 - (extent.height - arrowTipOffset.y) / extent.height)
        arrow.opacity = 0
        root.addSublayer(arrow)
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func ringPath(_ rect: NSRect) -> CGPath {
        let r = rect.insetBy(dx: -pad, dy: -pad)
        let radius = min(12, r.height / 2, r.width / 2)
        return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// Rings `rect` (local), or lets the ring go. On the first ring of a tour it scales in; later it slides.
    func ring(_ rect: NSRect?, appear: Bool, animated: Bool = true) {
        guard let rect else {
            glow.removeAnimation(forKey: "breathe")
            for l in [glow, rim, ring] { fade(l, to: 0, duration: 0.2) }
            return
        }
        let path = Self.ringPath(rect)
        for l in [glow, rim, ring] {
            let from = l.presentation()?.path ?? l.path
            l.path = path
            l.strokeColor = l === glow ? ShowOverlay.purple.withAlphaComponent(0.55).cgColor
                : l === ring ? ShowOverlay.purple.cgColor : l.strokeColor
            if animated, let from, l.opacity > 0, !appear {
                let a = CABasicAnimation(keyPath: "path")
                a.fromValue = from; a.toValue = path; a.duration = 0.5
                a.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                l.add(a, forKey: "move")
            }
        }
        if appear || ring.opacity == 0 {
            for l in [rim, ring] { fade(l, to: 1, duration: 0.3) }
            fade(glow, to: 1, duration: 0.3)
            let grow = CABasicAnimation(keyPath: "lineWidth")
            grow.fromValue = 26; grow.toValue = 3; grow.duration = 0.45
            grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(grow, forKey: "appear")
        }
        breathe()
    }

    /// The halo swells and fades, over and over, so the eye finds the control without it shouting.
    private func breathe() {
        guard glow.animation(forKey: "breathe") == nil else { return }
        let width = CABasicAnimation(keyPath: "lineWidth")
        width.fromValue = 6; width.toValue = 22
        let alpha = CABasicAnimation(keyPath: "opacity")
        alpha.fromValue = 0.95; alpha.toValue = 0.15
        let group = CAAnimationGroup()
        group.animations = [width, alpha]
        group.duration = 1.25
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(group, forKey: "breathe")
    }

    func placeArrow(at tip: NSPoint, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        arrow.position = tip
        if arrow.opacity == 0 { arrow.opacity = 1 }
        CATransaction.commit()
        arrowAt = tip
    }

    /// The arrow flies to the control on a gentle arc, lands, and taps it.
    func glideArrow(to tip: NSPoint) {
        let start = arrow.presentation()?.position ?? arrowAt ?? tip
        arrowAt = tip
        if arrow.opacity == 0 {
            fade(arrow, to: 1, duration: 0.2)
        }
        flight += 1
        let landing = flight
        let distance = hypot(tip.x - start.x, tip.y - start.y)
        guard distance > 2 else { tap(landing); return }
        let path = CGMutablePath()
        path.move(to: start)
        // Arc toward the upper side of the straight line, like a hand swinging over.
        let mid = CGPoint(x: (start.x + tip.x) / 2, y: (start.y + tip.y) / 2)
        let normal = CGPoint(x: -(tip.y - start.y) / distance, y: (tip.x - start.x) / distance)
        let lift = min(140, distance * 0.22) * (normal.y >= 0 ? 1 : -1)
        path.addQuadCurve(to: tip, control: CGPoint(x: mid.x + normal.x * lift, y: mid.y + normal.y * lift))
        let fly = CAKeyframeAnimation(keyPath: "position")
        fly.path = path
        fly.duration = min(0.95, 0.45 + Double(distance) / 2_400)
        fly.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.0, 0.2, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arrow.position = tip
        CATransaction.commit()
        arrow.add(fly, forKey: "fly")
        DispatchQueue.main.asyncAfter(deadline: .now() + fly.duration) { [weak self] in self?.tap(landing) }
    }

    /// A press and a ripple at the tip, then again every few seconds while the person hasn't clicked.
    private func tap(_ landing: Int) {
        guard landing == flight, let tip = arrowAt else { return }
        let press = CAKeyframeAnimation(keyPath: "transform.scale")
        press.values = [1, 0.84, 1.06, 1]
        press.keyTimes = [0, 0.3, 0.7, 1]
        press.duration = 0.42
        arrow.add(press, forKey: "press")
        let r: CGFloat = 26
        tap.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tap.position = tip
        CATransaction.commit()
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.2; grow.toValue = 1.25
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 0.9; fadeOut.toValue = 0
        let ripple = CAAnimationGroup()
        ripple.animations = [grow, fadeOut]
        ripple.duration = 0.7
        ripple.timingFunction = CAMediaTimingFunction(name: .easeOut)
        tap.add(ripple, forKey: "ripple")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in self?.tap(landing) }
    }

    /// The click landed: a green flash on the ring, and the arrow steps back.
    func flashDone() {
        let green = NSColor(red: 0.20, green: 0.75, blue: 0.42, alpha: 1).cgColor
        let color = CABasicAnimation(keyPath: "strokeColor")
        color.toValue = green
        color.duration = 0.18
        color.autoreverses = false
        color.fillMode = .forwards
        color.isRemovedOnCompletion = false
        ring.add(color, forKey: "done")
        glow.add(color, forKey: "done")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.ring.removeAnimation(forKey: "done")
            self?.glow.removeAnimation(forKey: "done")
        }
        flight += 1   // stops the tapping until the next control is ringed
    }

    private func fade(_ l: CALayer, to value: Float, duration: CFTimeInterval) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = l.presentation()?.opacity ?? l.opacity
        a.toValue = value
        a.duration = duration
        l.opacity = value
        l.add(a, forKey: "fade")
    }
}

// MARK: - The card

@MainActor
final class ShowCardModel: ObservableObject {
    @Published var progress = TourProgress(title: "", steps: [], current: 0, state: .looking)
    var onStop: () -> Void = {}
    var onRetry: () -> Void = {}
    var onGotIt: () -> Void = {}
}

/// Takes the first click even though Noteling isn't the active app, so the card's buttons work on the first try.
final class ShowCardHost: NSHostingView<ShowCardView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The step on a small sticky note beside the control: where we are, what to do, and a way out.
struct ShowCardView: View {
    nonisolated static let width: CGFloat = 272
    nonisolated static let margin: CGFloat = 16   // room for the paper's shadow inside the panel
    @ObservedObject var model: ShowCardModel

    private var p: TourProgress { model.progress }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "hand.point.up.left.fill").font(.system(size: 10.5, weight: .semibold))
                Text(p.state == .done ? "YOU'RE THERE" : "STEP \(p.count.uppercased())")
                    .font(.system(size: 10, weight: .bold)).tracking(0.7)
                Spacer(minLength: 4)
                if !p.isOver {
                    Button(action: model.onStop) {
                        Image(systemName: "xmark").font(.system(size: 9.5, weight: .bold)).frame(width: 18, height: 18)
                            .background(Circle().fill(Pad.ink.opacity(0.07)))
                    }
                    .buttonStyle(.plain).help("Stop showing (Esc)")
                }
            }
            .foregroundStyle(Pad.penInk)

            Text(headline)
                .font(HandFont.font(size: 20)).foregroundStyle(Pad.ink)
                .fixedSize(horizontal: false, vertical: true)

            footer

            if p.steps.count > 1 { dots }
        }
        .padding(EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 14))
        .frame(width: Self.width, alignment: .leading)
        .background(NoteSheetView(curl: 16, dark: false))
        .rotationEffect(.degrees(-0.8))
        .padding(Self.margin)
        .environment(\.colorScheme, .light)
        .animation(.easeInOut(duration: 0.22), value: p)
    }

    private var headline: String {
        switch p.state {
        case .done: return "That's the way to “\(p.title)”."
        default: return p.step ?? p.title
        }
    }

    @ViewBuilder private var footer: some View {
        switch p.state {
        case .showing:
            if p.isLast {
                HStack(spacing: 10) {
                    Text("Click it, or").font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
                    Button("Got it", action: model.onGotIt).buttonStyle(CardButtonStyle(filled: true))
                }
            } else {
                Text("Click it when you're ready.").font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
            }
        case .offscreen:
            Label("It's further down the page. Bringing it into view…", systemImage: "arrow.down.circle")
                .font(.system(size: 12)).foregroundStyle(Pad.inkSoft)
        case .looking:
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                Text(p.opened.map { "Taking you to \($0)…" } ?? "Waiting for it to show…")
                    .font(.system(size: 12)).foregroundStyle(Pad.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
        case .lost:
            VStack(alignment: .leading, spacing: 8) {
                Text(p.opened.map { "I opened \($0), but can't see it there. If it asks you to sign in, do that, then look again." }
                     ?? "I can't see it on this screen. Is the right page open?")
                    .font(.system(size: 12)).foregroundStyle(Pad.redInk).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Look again", action: model.onRetry).buttonStyle(CardButtonStyle(filled: true))
                    Button("Stop", action: model.onStop).buttonStyle(CardButtonStyle(filled: false))
                }
            }
        case .done:
            Label("\(p.steps.count) step\(p.steps.count == 1 ? "" : "s"), all yours. Next time you'll know.", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12)).foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.30))
        case .stopped:
            EmptyView()
        }
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(p.steps.indices, id: \.self) { i in
                Capsule()
                    .fill(i < p.current ? Pad.penInk : i == p.current && !p.isOver ? Pad.penInk.opacity(0.55) : Pad.ink.opacity(0.14))
                    .frame(width: i == p.current && !p.isOver ? 18 : 7, height: 7)
            }
        }
        .padding(.top, 1)
    }
}

/// The card's buttons: ink on paper, or filled with the pen's purple for the one to press.
struct CardButtonStyle: ButtonStyle {
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(filled ? Color.white : Pad.ink)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(
                Capsule().fill(filled ? Pad.penInk : Pad.ink.opacity(0.07))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
