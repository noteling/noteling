import AppKit
import SwiftUI

// The paper a note is written on, drawn once here for your own notes and the minister's cards alike: the sheet in one
// of its colours with the glue strip along the top, a headline, the words, and the parts (a when, a page, a checklist),
// each drawn by code in the paper's own ink so a note is pretty on its own, with nothing of the system's on it. Your
// notes are in your hand; a card is typed, with a handwritten headline.

/// The colours a sheet comes in: four for your own notes, as Stickies had, and amber for a card that can't wait.
enum PaperColour: String, Codable, CaseIterable {
    case yellow, pink, blue, green, amber

    /// The ones your own notes come in, in menu order.
    static let yours: [PaperColour] = [.yellow, .pink, .blue, .green]

    var top: Color {
        switch self {
        case .yellow: return Pad.paperTop
        case .pink: return Color(red: 1.0, green: 0.905, blue: 0.90)
        case .blue: return Color(red: 0.87, green: 0.935, blue: 1.0)
        case .green: return Color(red: 0.90, green: 0.97, blue: 0.84)
        case .amber: return Color(red: 1.0, green: 0.885, blue: 0.60)
        }
    }
    var bottom: Color {
        switch self {
        case .yellow: return Pad.paperBottom
        case .pink: return Color(red: 0.985, green: 0.80, blue: 0.80)
        case .blue: return Color(red: 0.74, green: 0.85, blue: 0.985)
        case .green: return Color(red: 0.78, green: 0.915, blue: 0.67)
        case .amber: return Color(red: 0.985, green: 0.77, blue: 0.41)
        }
    }
    var edge: Color {
        switch self {
        case .yellow: return Pad.paperEdge
        case .pink: return Color(red: 0.82, green: 0.54, blue: 0.56)
        case .blue: return Color(red: 0.46, green: 0.61, blue: 0.80)
        case .green: return Color(red: 0.53, green: 0.70, blue: 0.40)
        case .amber: return Color(red: 0.80, green: 0.57, blue: 0.22)
        }
    }

    /// The word on a menu.
    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Whose hand a sheet is in: yours, in handwriting; or the minister's, typed, with a handwritten headline.
enum PaperHand { case yours, typed }

/// One line of a checklist on the paper.
struct PaperItem: Equatable, Codable {
    var text: String
    var done = false
}

/// The measures of the paper at the design size; everything on it scales from them.
enum PaperLook {
    /// Your own note: close to square, as a sticky is, growing downward with its words.
    static let memoWidth: CGFloat = 224
    /// A card from the minister: wide enough for the whole of what it may write, never cut.
    static let cardWidth: CGFloat = 280
    static let minHeight: CGFloat = 150
    static let collapsedHeight: CGFloat = 38
    static let padding: CGFloat = 14
    /// The glue strip along the top edge.
    static let strip: CGFloat = 13
    /// Room around a sheet for its shadow.
    static let margin: CGFloat = 16
    static let steps: [CGFloat] = [0.85, 1, 1.2, 1.4, 1.6]

    /// A sheet leans a hair either way, the same way every time for the same note, as stuck-on paper does.
    nonisolated static func tilt(for id: String) -> Double {
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return (Double(hash % 1_000) / 1_000 - 0.5) * 1.4
    }

    nonisolated static func clamped(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return 1 }
        return min(max(scale, steps[0]), steps[steps.count - 1])
    }
    nonisolated static func bigger(than scale: CGFloat) -> CGFloat? { steps.first { $0 > scale + 0.001 } }
    nonisolated static func smaller(than scale: CGFloat) -> CGFloat? { steps.last { $0 < scale - 0.001 } }
}

/// The type on the paper: the hand for your notes and for a card's headline, the pad's body face for a card's words.
enum PaperType {
    static let ink = Color(nsColor: StickerPaper.ink)
    static let inkSoft = Color(nsColor: StickerPaper.inkSoft)

    static func headline(_ hand: PaperHand, _ scale: CGFloat) -> Font { HandFont.font(size: (hand == .yours ? 17 : 15.5) * scale) }
    static func body(_ hand: PaperHand, _ scale: CGFloat) -> Font {
        hand == .yours ? Font(StickerPaper.font(15 * scale)) : .system(size: 14 * scale)
    }
    static func small(_ hand: PaperHand, _ scale: CGFloat) -> Font {
        hand == .yours ? Font(StickerPaper.font(12.5 * scale)) : .system(size: 11.5 * scale)
    }
    static func lineSpacing(_ hand: PaperHand, _ scale: CGFloat) -> CGFloat { (hand == .yours ? 1.5 : 3) * scale }
}

/// A time on the paper, in the words a person would write: the clock far off, a countdown within the hour, "now" at
/// the minute, and "was …" after.
enum PaperWhen {
    enum State { case later, near, due, past }
    static let nearSeconds: TimeInterval = 60 * 60

    nonisolated static func state(_ when: Date, now: Date) -> State {
        let left = when.timeIntervalSince(now)
        if left < -60 { return .past }
        if left <= 60 { return .due }
        if left <= nearSeconds { return .near }
        return .later
    }

    nonisolated static func words(_ when: Date, now: Date, calendar: Calendar = .current) -> String {
        switch state(when, now: now) {
        case .due: return "now"
        case .near: return "in \(Int((when.timeIntervalSince(now) / 60).rounded(.up))) min"
        case .past: return "was " + clock(when, now: now, calendar: calendar)
        case .later: return clock(when, now: now, calendar: calendar)
        }
    }

    /// "3:00 PM" today, "Thu 2:00 PM" within the week, "Nov 27, 2:00 PM" beyond it.
    nonisolated static func clock(_ when: Date, now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: when)).day ?? 0
        formatter.dateFormat = days == 0 ? "h:mm a" : (0..<7).contains(days) ? "EEE h:mm a" : "MMM d, h:mm a"
        return formatter.string(from: when)
    }
}

/// The sheet itself: a warm gradient lit from the top, the glue strip, a thin edge, and the shadow it throws on the desk.
struct PaperSheet: View {
    var colour: PaperColour
    var scale: CGFloat = 1
    var dark = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 1.5 * scale)
        shape.fill(LinearGradient(colors: [colour.top, colour.bottom], startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1)))
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().fill(Color.white.opacity(0.24)).frame(height: PaperLook.strip * scale)
                    Rectangle().fill(colour.edge.opacity(0.14)).frame(height: 1)
                }
                .clipShape(shape)
            }
            .overlay(shape.fill(RadialGradient(colors: [.white.opacity(0.14), .clear], center: UnitPoint(x: 0.2, y: 0.1), startRadius: 0, endRadius: 260 * scale)))
            .overlay(shape.stroke(colour.edge.opacity(0.45), lineWidth: 0.8))
            .compositingGroup()
            .shadow(color: .black.opacity(dark ? 0.45 : 0.20), radius: 2 * scale, y: 2 * scale)
            .shadow(color: .black.opacity(dark ? 0.30 : 0.10), radius: 10 * scale, y: 8 * scale)
    }
}

/// A note as it reads: the headline, the words, the checklist, the when and the page, and a card's byline, on its sheet.
/// Collapsed, only its first line shows under the glue strip.
struct PaperView: View {
    var headline: String?
    var text: String
    var items: [PaperItem] = []
    var when: Date?
    var page: String?
    var byline: String?
    var hand: PaperHand
    var colour: PaperColour
    var scale: CGFloat = 1
    var width: CGFloat?
    var collapsed = false
    var now: Date = Date()
    var dark = false
    var tilt: Double = 0
    /// The person ticked or unticked the checklist's line at this index.
    var onToggle: ((Int) -> Void)?
    var onPage: (() -> Void)?

    var paperWidth: CGFloat { (width ?? (hand == .yours ? PaperLook.memoWidth : PaperLook.cardWidth)) * scale }

    /// What a collapsed note shows: its headline, else its first line of words, else its first item.
    var firstLine: String {
        if let headline, !headline.isEmpty { return headline }
        if let line = text.split(whereSeparator: \.isNewline).first { return String(line) }
        return items.first?.text ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            if collapsed {
                Text(firstLine)
                    .font(headline?.isEmpty == false ? PaperType.headline(hand, scale) : PaperType.body(hand, scale))
                    .lineLimit(1).truncationMode(.tail)
            } else {
                if let headline, !headline.isEmpty {
                    Text(headline).font(PaperType.headline(hand, scale)).fixedSize(horizontal: false, vertical: true)
                }
                if !text.isEmpty {
                    Text(text).font(PaperType.body(hand, scale)).lineSpacing(PaperType.lineSpacing(hand, scale))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !items.isEmpty { checklist }
                if when != nil || page != nil { parts }
                if let byline, !byline.isEmpty {
                    Text(byline).font(PaperType.small(hand, scale)).foregroundStyle(PaperType.inkSoft).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 4 * scale)
                }
            }
        }
        // Sized by its words, never by the room it is given: a sheet in a tall window stays a sheet.
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(PaperType.ink)
        .padding(.horizontal, PaperLook.padding * scale)
        .padding(.top, (PaperLook.strip + (collapsed ? 6 : 9)) * scale)
        .padding(.bottom, (collapsed ? 7 : PaperLook.padding) * scale)
        .frame(width: paperWidth, alignment: .topLeading)
        .frame(minHeight: (collapsed ? PaperLook.collapsedHeight : PaperLook.minHeight) * scale, alignment: .topLeading)
        .background(PaperSheet(colour: colour, scale: scale, dark: dark))
        .rotationEffect(.degrees(tilt))
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 5 * scale) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                    PaperCheckBox(done: item.done, scale: scale)
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1.5 * scale }
                        .onTapGesture { onToggle?(index) }
                    Text(item.text).font(PaperType.body(hand, scale))
                        .strikethrough(item.done, color: PaperType.inkSoft)
                        .foregroundStyle(item.done ? PaperType.inkSoft : PaperType.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var parts: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            if let when {
                let state = PaperWhen.state(when, now: now)
                HStack(spacing: 6 * scale) {
                    PaperClock(scale: scale, at: when)
                    Text(PaperWhen.words(when, now: now)).font(PaperType.small(hand, scale))
                }
                .foregroundStyle(state == .due ? Pad.redInk : state == .past ? PaperType.inkSoft : PaperType.ink)
            }
            if let page, let host = Self.host(of: page) {
                Button(action: { onPage?() }) {
                    HStack(spacing: 4 * scale) {
                        Image(systemName: "arrow.up.right").font(.system(size: 9 * scale, weight: .semibold))
                        Text(host).font(PaperType.small(hand, scale)).underline(true, color: PaperType.inkSoft.opacity(0.6))
                    }
                    .foregroundStyle(PaperType.inkSoft)
                }
                .buttonStyle(.plain).help(page)
            }
        }
        .padding(.top, 1 * scale)
    }

    /// "docs.example.com", or the whole text when it isn't a web address.
    nonisolated static func host(of page: String) -> String? {
        let trimmed = page.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return JobWords.clip(trimmed, 40)
    }
}

/// The peel: a round button over the paper's top-left corner that fades in while the mouse is on the paper, big
/// enough to hit without aiming, unlike the × of an ad. On a note it takes the note down; on a card it is Not now.
struct PeelButton: View {
    var help: String
    var action: () -> Void
    @State private var over = false

    /// The circle, the hit area around it, where its centre sits in from the paper's corner, and how long a peel takes.
    nonisolated static let size: CGFloat = 28
    nonisolated static let hit: CGFloat = 36
    nonisolated static let centre: CGFloat = 8
    nonisolated static let peelSeconds: Double = 0.22
    /// Where the hit area's top-left corner goes from the paper's corner, for the centre to sit at `centre`.
    nonisolated static var offset: CGFloat { centre - hit / 2 }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color(white: 0.2).opacity(over ? 0.96 : 0.84))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: .black.opacity(0.28), radius: 2.5, y: 1)
                Image(systemName: "xmark").font(.system(size: 12.5, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: Self.size, height: Self.size)
            .scaleEffect(over ? 1.1 : 1)
            .frame(width: Self.hit, height: Self.hit)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { over = $0 }
        .animation(.easeOut(duration: 0.12), value: over)
    }
}

/// The pin at the paper's top-right corner, always there, so what holds a note up is in plain sight: pushed in and red
/// when the note is pinned over the windows of its Space; lying hollow and faint when the note is on the desktop,
/// under them. A click moves the note from the one to the other.
struct PinButton: View {
    var pinned: Bool
    var scale: CGFloat = 1
    var action: () -> Void
    @State private var over = false

    nonisolated static let hit: CGFloat = 24

    var body: some View {
        Button(action: action) {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 12 * scale, weight: pinned ? .semibold : .regular))
                .foregroundStyle(pinned ? Pad.redInk : PaperType.inkSoft.opacity(over ? 0.95 : 0.6))
                .rotationEffect(.degrees(pinned ? 28 : 60))
                .shadow(color: .black.opacity(pinned ? 0.25 : 0), radius: 0.8, x: 0.5, y: 1)
                .scaleEffect(over ? 1.2 : 1)
                .frame(width: Self.hit * scale, height: Self.hit * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pinned ? "Pinned over your windows, on this Space. Click to lay it on the desktop, under them."
                     : "On the desktop, under your windows. Click to pin it over them, on this Space.")
        .accessibilityLabel(pinned ? "Pinned. Lay it on the desktop" : "On the desktop. Pin it over your windows")
        .onHover { over = $0 }
        .animation(.easeOut(duration: 0.15), value: over)
        .animation(.spring(duration: 0.3), value: pinned)
    }
}

/// A checkbox a hand would draw: a square a hair off true, and a two-stroke tick when it is done.
struct PaperCheckBox: View {
    var done: Bool
    var scale: CGFloat = 1

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2 * scale)
                .stroke(PaperType.ink.opacity(0.7), lineWidth: 1.2 * scale)
                .rotationEffect(.degrees(-2.5))
            if done {
                PaperTick().stroke(PaperType.ink, style: StrokeStyle(lineWidth: 1.9 * scale, lineCap: .round, lineJoin: .round))
                    .padding(2.5 * scale)
                    .offset(x: 1.5 * scale, y: -2 * scale)
            }
        }
        .frame(width: 14 * scale, height: 14 * scale)
        .contentShape(Rectangle())
    }
}

struct PaperTick: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.05, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.minY + r.height * 0.9))
        p.addLine(to: CGPoint(x: r.minX + r.width * 1.05, y: r.minY + r.height * 0.05))
        return p
    }
}

/// A small clock face in ink, its hands at the time it stands for.
struct PaperClock: View {
    var scale: CGFloat = 1
    var at: Date

    var body: some View {
        let size = 12 * scale
        let parts = Calendar.current.dateComponents([.hour, .minute], from: at)
        let minute = Double(parts.minute ?? 0)
        let hour = Double((parts.hour ?? 0) % 12) + minute / 60
        ZStack {
            Circle().stroke(PaperType.ink.opacity(0.75), lineWidth: 1.2 * scale)
            // A short, heavy hour hand and a long, light minute hand, so that hands opposite each other (10:20, 12:30) still
            // read as a clock and not as a slash through a circle.
            PaperHand_(angle: hour / 12 * 360, length: 0.22).stroke(PaperType.ink, style: StrokeStyle(lineWidth: 1.7 * scale, lineCap: .round))
            PaperHand_(angle: minute / 60 * 360, length: 0.46).stroke(PaperType.ink, style: StrokeStyle(lineWidth: 0.95 * scale, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

/// One hand of the little clock, from the centre out, 0° at twelve.
struct PaperHand_: Shape {
    var angle: Double
    var length: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let centre = CGPoint(x: r.midX, y: r.midY)
        let radians = (angle - 90) * .pi / 180
        p.move(to: centre)
        p.addLine(to: CGPoint(x: centre.x + cos(radians) * r.width * length, y: centre.y + sin(radians) * r.height * length))
        return p
    }
}
