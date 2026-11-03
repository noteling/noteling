import AppKit
import SwiftUI

// The paper every product draws on: the pad's colours and type, the handwriting, the yellow sheet with its curl, the
// ruled lines, the ink line, the paper tabs and the row that wraps them. The chat's notes (`NotePad`, in Ask) are
// composed from these, and so are the stickers, the Jobs window and the task panel.

/// Palette and type of the pad. Paper stays yellow in both appearances; only the desk around it darkens.
enum Pad {
    static let ink = Color(red: 0.12, green: 0.165, blue: 0.267)                 // #1F2A44, body text
    static let inkSoft = ink.opacity(0.62)
    static let redInk = Color(red: 0.70, green: 0.14, blue: 0.12)
    static let penInk = Color(red: 0.45, green: 0.26, blue: 0.80)                // the quill's purple ink drop

    static let paperTop = Color(red: 1.0, green: 0.965, blue: 0.70)
    static let paperBottom = Color(red: 0.99, green: 0.905, blue: 0.53)
    static let paperEdge = Color(red: 0.84, green: 0.70, blue: 0.30)
    static let paperDeep = Color(red: 0.93, green: 0.80, blue: 0.40)             // a sheet tucked behind, or the crease

    static let tabPaper = Color(red: 1.0, green: 0.985, blue: 0.92)
    static let tabEdge = Color(red: 0.80, green: 0.70, blue: 0.45)
    static let fieldPaper = Color(red: 1.0, green: 0.99, blue: 0.955)

    static func desk(_ dark: Bool) -> LinearGradient {
        dark ? LinearGradient(colors: [Color(red: 0.21, green: 0.19, blue: 0.165), Color(red: 0.145, green: 0.13, blue: 0.11)], startPoint: .top, endPoint: .bottom)
             : LinearGradient(colors: [Color(red: 0.935, green: 0.90, blue: 0.84), Color(red: 0.89, green: 0.84, blue: 0.76)], startPoint: .top, endPoint: .bottom)
    }
    /// The pad's glued binding strip behind the header.
    static func binding(_ dark: Bool) -> Color { dark ? Color(red: 0.11, green: 0.095, blue: 0.08) : Color(red: 0.84, green: 0.78, blue: 0.675) }
    static func bindingEdge(_ dark: Bool) -> Color { dark ? .black.opacity(0.5) : Color(red: 0.62, green: 0.53, blue: 0.40).opacity(0.55) }
    /// Text and icons drawn directly on the desk (header, footer).
    static func deskInk(_ dark: Bool) -> Color { dark ? Color(red: 0.93, green: 0.90, blue: 0.84) : Color(red: 0.24, green: 0.19, blue: 0.13) }
    static func deskInkSoft(_ dark: Bool) -> Color { deskInk(dark).opacity(0.62) }

    /// Body type is sized for someone reading instructions off the note across a desk, not for density.
    static let bodySize: CGFloat = 15
    static let body = Font.system(size: bodySize)
    static let lineSpacing: CGFloat = 4
    /// Notes alternate this much either way down the pad; small enough that wrapped text still reads true.
    static let tilt: Double = 0.9
}

/// The handwriting used for note headings only. Picks the first installed family from a short list of the
/// handwriting faces macOS ships with; otherwise a rounded system font, which is the same spirit without the risk.
enum HandFont {
    static let family: String? = {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        return ["Noteworthy", "Bradley Hand", "Chalkboard SE", "Marker Felt"].first { installed.contains($0) }
    }()

    static func font(size: CGFloat) -> Font {
        if let family, let f = NSFontManager.shared.font(withFamily: family, traits: .boldFontMask, weight: 9, size: size) ?? NSFont(name: family, size: size) {
            return Font(f)
        }
        return .system(size: size, weight: .semibold, design: .rounded)
    }
}

/// Set on a static render (`--render-card`) so every answer is fully inked and nothing animates.
private struct PadStaticKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var padStatic: Bool { get { self[PadStaticKey.self] } set { self[PadStaticKey.self] = newValue } }
}


/// The yellow sheet: a warm gradient lit from the top, the adhesive strip along the top edge, a darker sheet from the
/// pad peeking out behind, and a curl at the bottom-right corner with the shadow it throws.
struct NoteSheetView: View {
    var curl: CGFloat
    var dark: Bool
    var ruled = false

    var body: some View {
        ZStack {
            NoteSheet(curl: curl * 0.7)
                .fill(Pad.paperDeep)
                .offset(x: 1.5, y: 2)
            NoteSheet(curl: curl)
                .fill(LinearGradient(colors: [Pad.paperTop, Pad.paperBottom], startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1)))
                .overlay {
                    // the glue strip: a hair paler and flatter, like the real thing
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.white.opacity(0.22)).frame(height: 15)
                        Rectangle().fill(Pad.paperEdge.opacity(0.10)).frame(height: 1)
                        Spacer(minLength: 0)
                    }
                    .clipShape(NoteSheet(curl: curl))
                }
                .overlay(NoteSheet(curl: curl).fill(RadialGradient(colors: [.white.opacity(0.14), .clear], center: UnitPoint(x: 0.2, y: 0.1), startRadius: 0, endRadius: 260)))
                .overlay { if ruled { RuledLines().clipShape(NoteSheet(curl: curl)) } }
                .overlay(NoteSheet(curl: curl).stroke(Pad.paperEdge.opacity(0.45), lineWidth: 0.8))
            CornerCurlView(curl: curl)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(dark ? 0.45 : 0.20), radius: 2, y: 2)
        .shadow(color: .black.opacity(dark ? 0.30 : 0.10), radius: 10, y: 8)
    }
}

/// Faint ruled lines, for the blank note.
struct RuledLines: View {
    var spacing: CGFloat = 23
    var top: CGFloat = 52
    var body: some View {
        GeometryReader { g in
            Path { p in
                var y = top
                while y < g.size.height - 12 { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y)); y += spacing }
            }
            .stroke(Pad.paperEdge.opacity(0.30), lineWidth: 0.8)
        }
    }
}

/// A rectangle with its bottom-right corner turned up (the curl area is cut away and drawn by `CornerCurlView`).
struct NoteSheet: Shape {
    var curl: CGFloat
    var animatableData: CGFloat { get { curl } set { curl = newValue } }
    func path(in r: CGRect) -> Path {
        let c = min(curl, r.width / 3, r.height / 3)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY), control: CGPoint(x: r.maxX - c * 0.45, y: r.maxY - c * 0.45))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// The turned-up corner: the flap's underside, bright at the crest and shading into the fold, over the shadow it casts.
struct CornerCurlView: View {
    var curl: CGFloat
    var body: some View {
        ZStack {
            CornerFlap(curl: curl).fill(Color.black.opacity(0.28)).blur(radius: 2.5).offset(x: -2, y: -1.5)
            CornerFlap(curl: curl)
                .fill(LinearGradient(stops: [.init(color: Color(red: 1.0, green: 0.99, blue: 0.90), location: 0),
                                             .init(color: Color(red: 1.0, green: 0.94, blue: 0.66), location: 0.55),
                                             .init(color: Color(red: 0.88, green: 0.72, blue: 0.32), location: 1)],
                                     startPoint: .bottomTrailing, endPoint: .topLeading))
            CornerFlap(curl: curl).stroke(Color.white.opacity(0.6), lineWidth: 0.6)
        }
    }
}

struct CornerFlap: Shape {
    var curl: CGFloat
    func path(in r: CGRect) -> Path {
        let c = min(curl, r.width / 3, r.height / 3)
        let a = CGPoint(x: r.maxX, y: r.maxY - c)          // where the fold meets the right edge
        let b = CGPoint(x: r.maxX - c, y: r.maxY)          // …and the bottom edge
        let tip = CGPoint(x: r.maxX - c * 0.92, y: r.maxY - c * 0.92)
        var p = Path()
        p.move(to: a)
        p.addQuadCurve(to: b, control: CGPoint(x: r.maxX - c * 0.45, y: r.maxY - c * 0.45))
        p.addQuadCurve(to: tip, control: CGPoint(x: r.maxX - c * 1.05, y: r.maxY - c * 0.35))
        p.addQuadCurve(to: a, control: CGPoint(x: r.maxX - c * 0.35, y: r.maxY - c * 1.05))
        p.closeSubpath()
        return p
    }
}

/// A pen stroke across the width: a hair wobbly so it reads as drawn rather than ruled.
struct InkLine: Shape {
    var wobble: CGFloat = 1
    func path(in r: CGRect) -> Path {
        var p = Path()
        let y = r.midY
        p.move(to: CGPoint(x: r.minX, y: y + wobble * 0.4))
        p.addCurve(to: CGPoint(x: r.midX, y: y - wobble * 0.3),
                   control1: CGPoint(x: r.minX + r.width * 0.2, y: y - wobble), control2: CGPoint(x: r.midX - r.width * 0.15, y: y + wobble * 0.6))
        p.addCurve(to: CGPoint(x: r.maxX, y: y + wobble * 0.2),
                   control1: CGPoint(x: r.midX + r.width * 0.2, y: y - wobble * 0.9), control2: CGPoint(x: r.maxX - r.width * 0.15, y: y + wobble * 0.8))
        return p
    }
}

/// A suggestion as a small paper tab stuck to the note's bottom edge: its top is tucked under the sheet. Hanging from
/// the top edge instead, its bottom is tucked under, for a tab that peeks out above a sticker.
struct PaperTabStyle: ButtonStyle {
    var hangsFromTop = false
    @Environment(\.isEnabled) private var enabled
    init(hangsFromTop: Bool = false) { self.hangsFromTop = hangsFromTop }
    func makeBody(configuration: Configuration) -> some View {
        let shape = hangsFromTop
            ? UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
            : UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Pad.ink)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.top, hangsFromTop ? 7 : 13).padding(.bottom, hangsFromTop ? 13 : 7)
            .background(
                shape
                    .fill(configuration.isPressed ? Pad.paperBottom : Pad.tabPaper)
                    .overlay(shape.strokeBorder(Pad.tabEdge.opacity(0.9), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.22), radius: 2.5, y: 2)
            )
            .opacity(enabled ? 1 : 0.55)
            .contentShape(Rectangle())
    }
}

/// Lays tabs out left to right and wraps onto another row when they do not fit, so a long suggestion never
/// truncates or scrolls; with a negative `rowSpacing` and descending zIndex the next row tucks under the one above.
struct TabRow: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + rowSpacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: width.isFinite ? width : maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += rowH + rowSpacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

/// Paper colours shared by the stickers on screen and the editor.
enum StickerPaper {
    static let tip = CGColor(red: 1.0, green: 0.94, blue: 0.58, alpha: 1)
    static let warning = CGColor(red: 1.0, green: 0.85, blue: 0.50, alpha: 1)
    static let edge = CGColor(red: 0.80, green: 0.66, blue: 0.28, alpha: 0.9)
    static let ink = NSColor(red: 0.12, green: 0.165, blue: 0.267, alpha: 1)
    static let inkSoft = NSColor(red: 0.12, green: 0.165, blue: 0.267, alpha: 0.6)

    static func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
        if let family = HandFont.family,
           let f = NSFontManager.shared.font(withFamily: family, traits: bold ? .boldFontMask : [], weight: bold ? 9 : 5, size: size) ?? NSFont(name: family, size: size) {
            return f
        }
        return NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }

    /// The text as CATextLayer should draw it, and the height it needs (measured with the same attributes, plus slack
    /// for the layer's own leading), capped at `maxLines`.
    static func measure(_ text: String, font: NSFont, color: NSColor, width: CGFloat, maxLines: Int) -> (NSAttributedString, CGFloat) {
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byWordWrapping
        let attr = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: para, .foregroundColor: color])
        let r = attr.boundingRect(with: NSSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let line = ceil(font.ascender - font.descender + font.leading) + 2
        let lines = max(1, min(CGFloat(maxLines), ceil(r.height / max(1, line - 2))))
        return (attr, lines * line + 4)
    }

    /// Stuck to the control's top-right corner; when there is no room above, hung under its bottom-right corner instead.
    static func origin(for size: NSSize, control: NSRect, in bounds: NSRect) -> NSPoint {
        var x = control.maxX - 26
        var y = control.maxY - 10
        if y + size.height > bounds.height - 6 { y = control.minY + 10 - size.height }
        x = min(max(6, x), bounds.width - size.width - 6)
        y = min(max(6, y), bounds.height - size.height - 6)
        return NSPoint(x: x, y: y)
    }
}

/// Shared overlay chrome: the rotating rainbow border and a caption pill at the top.
enum ShimmerBorder {
    static func install(on root: CALayer, bounds: CGRect, dim: CGFloat) {
        root.backgroundColor = CGColor(gray: 0, alpha: dim)
        for (width, opacity) in [(CGFloat(28), Float(0.28)), (CGFloat(8), Float(0.95))] {
            let container = CALayer()
            container.frame = bounds
            let mask = CAShapeLayer()
            mask.frame = bounds
            mask.path = CGPath(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2), cornerWidth: 18, cornerHeight: 18, transform: nil)
            mask.fillColor = nil
            mask.strokeColor = CGColor(gray: 0, alpha: 1)
            mask.lineWidth = width
            container.mask = mask
            let g = CAGradientLayer()
            g.type = .conic
            g.colors = [NSColor.systemBlue, NSColor.systemPurple, NSColor.systemPink, NSColor.systemOrange, NSColor.systemTeal, NSColor.systemBlue].map(\.cgColor)
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 0.5)
            let side = hypot(bounds.width, bounds.height) * 1.1
            g.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            g.opacity = opacity
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0; spin.toValue = 2 * Double.pi; spin.duration = 5; spin.repeatCount = .infinity
            g.add(spin, forKey: "spin")
            container.addSublayer(g)
            root.addSublayer(container)
        }
    }

    static func captionPill(bounds: CGRect, scale: CGFloat, width: CGFloat, text: String) -> (CALayer, CATextLayer) {
        let pill = CALayer()
        let t = CATextLayer()
        pill.frame = CGRect(x: bounds.midX - width / 2, y: bounds.height - 64, width: width, height: 34)
        pill.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.88).cgColor
        pill.cornerRadius = 17
        t.string = text
        t.fontSize = 13
        t.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        t.foregroundColor = NSColor.white.cgColor
        t.alignmentMode = .center
        t.truncationMode = .end
        t.contentsScale = scale
        t.frame = CGRect(x: 8, y: 8, width: width - 16, height: 20)
        pill.addSublayer(t)
        return (pill, t)
    }
}

/// A button on the paper: a small rounded label, filled with the pen's ink when it is the main one. A button that can't
/// be used now looks it.
struct PaperActionButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, primary: primary)
    }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label.font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .foregroundStyle(primary ? Color.white : Pad.ink)
                .background(primary ? Pad.penInk : Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(primary ? Color.clear : Pad.tabEdge.opacity(0.7)))
                .opacity(configuration.isPressed ? 0.7 : isEnabled ? 1 : 0.45)
        }
    }
}
