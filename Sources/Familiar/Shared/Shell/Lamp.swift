import SwiftUI

/// The lamp beside the orb: one pixel of Attend in the periphery. Off when nothing needs you, with a barely-there tint
/// to say it is alive; warm when something does; hot when something can't wait. Brightness is the first signal and hue
/// the second, so the state reads without colour. A door type: Ask draws it on the bubble, Attend decides its state.
enum LampState: Equatable {
    case off, warm, hot

    /// What the deck comes to: hot with an urgent card, warm with any, off with none.
    static func of(count: Int, urgent: Bool) -> LampState { count == 0 ? .off : urgent ? .hot : .warm }

    /// "3 need you", "1 needs you, and can't wait", "Nothing needs you".
    static func words(count: Int, urgent: Bool) -> String {
        switch (count, urgent) {
        case (0, _): return "Nothing needs you"
        case (1, false): return "1 needs you"
        case (1, true): return "1 needs you, and can't wait"
        case (let n, false): return "\(n) need you"
        case (let n, true): return "\(n) need you, one can't wait"
        }
    }
}

/// A small desk lamp, drawn in ink: the shade, its stem, and the light it throws when it is on.
struct LampView: View {
    var state: LampState
    var size: CGFloat = 22

    private var glow: Color {
        switch state {
        case .off: return .clear
        case .warm: return Color(red: 1.0, green: 0.80, blue: 0.40)
        case .hot: return Color(red: 1.0, green: 0.55, blue: 0.30)
        }
    }
    private var ink: Color { Color(red: 0.24, green: 0.19, blue: 0.13) }

    var body: some View {
        ZStack {
            // The light on the desk, under the shade.
            if state != .off {
                Ellipse()
                    .fill(RadialGradient(colors: [glow.opacity(state == .hot ? 0.95 : 0.75), glow.opacity(0)], center: .center, startRadius: 0, endRadius: size * 0.55))
                    .frame(width: size * 1.1, height: size * 0.7)
                    .offset(y: size * 0.22)
                    .blur(radius: size * 0.04)
            }
            // The shade: a trapezoid, lit from inside when on.
            LampShade()
                .fill(state == .off ? ink.opacity(0.28) : glow.opacity(0.9))
                .overlay(LampShade().stroke(ink.opacity(state == .off ? 0.35 : 0.8), lineWidth: max(1, size * 0.05)))
                .frame(width: size * 0.62, height: size * 0.34)
                .offset(y: -size * 0.2)
            // The stem and the foot.
            RoundedRectangle(cornerRadius: size * 0.04)
                .fill(ink.opacity(state == .off ? 0.3 : 0.85))
                .frame(width: size * 0.07, height: size * 0.34)
                .offset(y: size * 0.12)
            Capsule()
                .fill(ink.opacity(state == .off ? 0.3 : 0.85))
                .frame(width: size * 0.36, height: size * 0.07)
                .offset(y: size * 0.3)
        }
        .frame(width: size, height: size)
        .opacity(state == .off ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.4), value: state)
        .accessibilityLabel(state == .off ? "Lamp off: nothing needs you" : state == .hot ? "Lamp hot: something can't wait" : "Lamp warm: something needs you")
    }
}

/// The shade of the little lamp: wider at the mouth than the crown.
struct LampShade: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.3, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.7, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
