import AppKit

/// One hint drawn on the screen, stuck to its control: a small tag at the control's corner (hints shown as you arrive),
/// a brief of its first lines (the pen is up), or the whole hint with who left it (the mouse came to it, or every
/// hint is shown open). One look for the pen and for hints that show by themselves.
@MainActor
final class StickerLayer {
    enum Mode: Equatable { case tag, brief, open }

    let note: StickyNote
    /// The control, in global coordinates.
    var frame: NSRect
    var mode: Mode = .brief
    let layer = CALayer()
    private let text = CATextLayer()
    private let byline = CATextLayer()
    private let writing = CAShapeLayer()
    private let glyph = CATextLayer()
    private let scale: CGFloat

    /// A tag's side: enough to see the paper, too small to cover what it is stuck to.
    static let tagSide: CGFloat = 18

    init(note: StickyNote, frame: NSRect, scale: CGFloat) {
        self.note = note
        self.frame = frame
        self.scale = scale
        layer.backgroundColor = note.isWarning ? StickerPaper.warning : StickerPaper.tip
        layer.cornerRadius = 2
        layer.borderWidth = 0.5
        layer.borderColor = StickerPaper.edge
        layer.shadowOpacity = 0.3; layer.shadowRadius = 3; layer.shadowOffset = CGSize(width: 0, height: -2)
        for t in [text, byline, glyph] { t.contentsScale = scale; t.isWrapped = true; t.truncationMode = .end }
        text.foregroundColor = StickerPaper.ink.cgColor      // the truncation token takes the layer's colour, not the string's
        byline.foregroundColor = StickerPaper.inkSoft.cgColor
        byline.font = NSFont.systemFont(ofSize: 10); byline.fontSize = 10
        glyph.foregroundColor = StickerPaper.ink.cgColor
        glyph.font = NSFont.systemFont(ofSize: 12, weight: .bold); glyph.fontSize = 12
        glyph.alignmentMode = .center
        glyph.string = "!"
        writing.strokeColor = StickerPaper.inkSoft.cgColor
        writing.lineWidth = 1.2
        writing.lineCap = .round
        writing.fillColor = nil
        layer.addSublayer(text); layer.addSublayer(byline); layer.addSublayer(writing); layer.addSublayer(glyph)
    }

    var isOpen: Bool { mode == .open }

    /// Where a tag sits: over the control's top-right corner, kept on the screen.
    static func tagFrame(control: NSRect, in bounds: NSRect) -> NSRect {
        let side = tagSide
        var x = control.maxX - side * 0.6
        var y = control.maxY - side * 0.55
        x = min(max(2, x), bounds.width - side - 2)
        y = min(max(2, y), bounds.height - side - 2)
        return NSRect(x: x, y: y, width: side, height: side)
    }

    /// Draws the sticker for its mode, `control` being the control in the view's own coordinates.
    func layout(control: NSRect, in bounds: NSRect) {
        let seed = CGFloat(abs(note.id.hashValue % 100)) / 100
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        layer.transform = CATransform3DIdentity
        switch mode {
        case .tag:
            let f = Self.tagFrame(control: control, in: bounds)
            layer.bounds = CGRect(x: 0, y: 0, width: f.width, height: f.height)
            layer.position = CGPoint(x: f.midX, y: f.midY)
            layer.transform = CATransform3DMakeRotation((seed - 0.5) * 0.3, 0, 0, 1)
            layer.zPosition = 1
            text.isHidden = true; byline.isHidden = true
            if note.isWarning {
                glyph.isHidden = false; writing.isHidden = true
                glyph.frame = CGRect(x: 0, y: 1, width: f.width, height: 15)
            } else {
                // Two short lines of writing: a note at a glance.
                glyph.isHidden = true; writing.isHidden = false
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 4, y: 11)); path.addLine(to: CGPoint(x: 14, y: 11))
                path.move(to: CGPoint(x: 4, y: 7)); path.addLine(to: CGPoint(x: 11, y: 7))
                writing.path = path
                writing.frame = CGRect(x: 0, y: 0, width: f.width, height: f.height)
            }
        case .brief, .open:
            glyph.isHidden = true; writing.isHidden = true
            text.isHidden = false
            let open = mode == .open
            let width: CGFloat = open ? 280 : 190
            let body = (note.isWarning ? "⚠︎ " : "") + (open ? note.text : String(note.text.prefix(100)))
            let font = StickerPaper.font(open ? 13.5 : 12.5, bold: true)
            let (attr, textH) = StickerPaper.measure(body, font: font, color: StickerPaper.ink, width: width - 20, maxLines: open ? 14 : 2)
            let height = textH + (open ? 34 : 14)
            let o = StickerPaper.origin(for: NSSize(width: width, height: height), control: control, in: bounds)
            layer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            layer.position = CGPoint(x: o.x + width / 2, y: o.y + height / 2)
            layer.transform = open ? CATransform3DIdentity : CATransform3DMakeRotation((seed - 0.5) * 0.06, 0, 0, 1)
            layer.zPosition = open ? 10 : 1
            text.string = attr
            text.frame = CGRect(x: 10, y: open ? 24 : 7, width: width - 20, height: textH)
            byline.string = "— " + note.byline
            byline.frame = CGRect(x: 10, y: 7, width: width - 20, height: 13)
            byline.isHidden = !open
        }
    }
}
