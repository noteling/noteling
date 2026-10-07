import AppKit
import QuartzCore

/// The moment Noteling takes the screen for a question.
struct CaptureMoment {
    let image: CGImage
    let screen: NSScreen
    /// What was picked, in AppKit screen coordinates: the circled area, or the spot pointed at. Nil for the whole screen.
    var region: NSRect? = nil
}

/// Shows the capture moment the way a phone shows a screenshot: a quick flash over the screen, then the picture
/// shrinking away toward the pad. It is how people learn that Noteling sees the screen, and when: after the flash, the
/// screen it has is fixed, so they can switch away. Not for the context checks every 2 s, which read only names, and
/// never in a capture (Noteling's own windows are left out of every screenshot). With Reduce Motion, a soft fade only.
@MainActor
enum CaptureFlash {
    private static var showing: [NSPanel] = []

    static let flashDuration: CFTimeInterval = 0.32
    static let flyDelay: CFTimeInterval = 0.1
    static let flyDuration: CFTimeInterval = 0.5

    /// `target` is the pad's frame, or nil when it isn't on screen: the picture then shrinks into the screen's corner.
    static func show(_ moment: CaptureMoment, toward target: NSRect?) {
        let screen = moment.screen
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        panel.contentView = view
        panel.setFrame(screen.frame, display: false)
        guard let root = view.layer else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let flash = CALayer()
        flash.frame = root.bounds
        flash.backgroundColor = NSColor.white.cgColor
        flash.opacity = 0
        root.addSublayer(flash)
        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = reduce ? [0, 0.16, 0] : [0, 0.5, 0]
        pulse.keyTimes = [0, 0.25, 1]
        pulse.duration = reduce ? 0.45 : flashDuration
        flash.add(pulse, forKey: "flash")
        var total = pulse.duration

        if !reduce {
            let start = (moment.region ?? screen.frame).intersection(screen.frame)
                .offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            let shot = CALayer()
            shot.contents = crop(moment.image, to: moment.region, screenFrame: screen.frame) ?? moment.image
            shot.contentsGravity = .resizeAspectFill
            shot.contentsScale = screen.backingScaleFactor
            shot.masksToBounds = true
            shot.borderColor = NSColor.white.cgColor
            shot.borderWidth = 3
            shot.cornerRadius = 4
            let local = target.map { $0.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY) }
            let end = destination(from: start, toward: local, in: root.bounds)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shot.bounds = CGRect(origin: .zero, size: end.size)
            shot.position = CGPoint(x: end.midX, y: end.midY)
            shot.opacity = 0
            root.addSublayer(shot)
            CATransaction.commit()

            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: CGPoint(x: start.midX, y: start.midY))
            move.toValue = NSValue(point: CGPoint(x: end.midX, y: end.midY))
            let size = CABasicAnimation(keyPath: "bounds.size")
            size.fromValue = NSValue(size: start.size)
            size.toValue = NSValue(size: end.size)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.75, 1]
            let fly = CAAnimationGroup()
            fly.animations = [move, size, fade]
            fly.duration = flyDuration
            fly.beginTime = CACurrentMediaTime() + flyDelay
            fly.fillMode = .backwards
            fly.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shot.add(fly, forKey: "fly")
            total = max(total, flyDelay + flyDuration)
        }

        panel.orderFrontRegardless()
        showing.append(panel)
        DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.05) {
            panel.orderOut(nil)
            showing.removeAll { $0 === panel }
        }
    }

    /// Where the picture ends: a thumbnail at the pad (or the screen's lower right), keeping the picture's shape.
    static func destination(from start: CGRect, toward target: CGRect?, in bounds: CGRect) -> CGRect {
        let aspect = start.height > 0 ? start.width / start.height : 1.6
        let width: CGFloat = min(120, max(40, (target?.width ?? 240) * 0.3))
        let size = CGSize(width: width, height: max(24, width / max(aspect, 0.2)))
        let onScreen = target.flatMap { $0.intersects(bounds) ? $0.intersection(bounds) : nil }
        let center = onScreen.map { CGPoint(x: $0.midX, y: $0.midY) }
            ?? CGPoint(x: bounds.maxX - 24 - size.width / 2, y: bounds.minY + 24 + size.height / 2)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    /// The picked part of a whole-screen picture; nil when there is no region or it falls outside.
    static func crop(_ image: CGImage, to region: NSRect?, screenFrame: CGRect) -> CGImage? {
        guard let region, screenFrame.width > 0 else { return nil }
        let scale = CGFloat(image.width) / screenFrame.width
        let r = CGRect(x: (region.minX - screenFrame.minX) * scale, y: (screenFrame.maxY - region.maxY) * scale,
                       width: region.width * scale, height: region.height * scale).integral
        let inside = r.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !inside.isEmpty else { return nil }
        return image.cropping(to: inside)
    }
}
