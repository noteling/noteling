import AppKit
import SwiftUI

/// `Noteling --render-paper <dir>`: the paper as your notes and the minister's cards would wear it, as PNGs, to judge
/// against the bar: if these were a standalone product and a person had written and pinned them, would they be useful
/// and pretty enough? Your notes in your hand, with a when, a page and a checklist; cards typed with a handwritten
/// headline; alone, scattered on a light and a dark desk, and at the smallest and biggest sizes. Then exit.
@MainActor
func runRenderPaper() {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--render-paper"), i + 1 < args.count else { print("usage: --render-paper <dir>"); exit(2) }
    let dir = URL(fileURLWithPath: args[i + 1])
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // 2026-09-21, 10:13 AM in the Mac's time zone, as the other renders.
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let calendar = Calendar.current
    func today(_ hour: Int, _ minute: Int = 0) -> Date { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now }
    let thursday = calendar.date(byAdding: .day, value: 3, to: today(14)) ?? now

    // Your notes: what a person writes, or dictates and the scribe writes down.
    let dictated = Memo(id: "n-1", headline: "Lena · Q4 numbers", text: "Send Lena the Q4 numbers before the 4 o'clock call.",
                        when: today(15), page: "https://docs.example.com/finance/q4-numbers",
                        asked: "remind me to send Lena the Q4 numbers this afternoon", createdAt: now, updatedAt: now)
    let shopping = Memo(id: "n-2", headline: "Shopping", items: [PaperItem(text: "Milk"), PaperItem(text: "Eggs", done: true), PaperItem(text: "Coffee beans"), PaperItem(text: "Lemons")],
                        colour: .blue, createdAt: now, updatedAt: now)
    let dentist = Memo(id: "n-3", text: "Dentist Thu 2pm", colour: .pink, when: thursday, createdAt: now, updatedAt: now)
    let marco = Memo(id: "n-4", text: "Call Marco back about the warehouse lease. He wants an answer by Friday and the second floor is the sticking point; ask whether they'd split the term.",
                     colour: .green, createdAt: now, updatedAt: now)
    let soon = Memo(id: "n-5", headline: "Stand-up", text: "Bring the two open bugs.", when: now.addingTimeInterval(25 * 60), createdAt: now, updatedAt: now)
    let yours = [dictated, shopping, dentist, marco, soon]

    // The minister's cards: a headline it wrote, its words, who it came from, and the page.
    struct Card { var headline: String; var text: String; var byline: String; var page: String?; var urgent = false }
    let cards = [
        Card(headline: "Checkout is down", text: "The two checkout steps and the returns form are down; 38 other pages are fine.", byline: "Pages up · shared by Yang · 2 min ago", page: "https://shop.example.com/checkout", urgent: true),
        Card(headline: "September prices still up", text: "Two listings still show the September price, a day into the event.", byline: "Holiday Oct · GM · shared by Yang and Ana · 25 min ago", page: "https://seller.example.com/listings/4471"),
        Card(headline: "Four orders stuck", text: "Four orders have waited over an hour in “Paid”; the oldest is Acme's.", byline: "Orders stuck · 1 h ago", page: "https://ops.example.com/orders?state=paid"),
        Card(headline: "Blue kettle out of stock", text: "The blue kettle is out of stock on three of the five pages that sell it.", byline: "Stock-outs · shared by Ana · 2 h ago", page: nil),
        Card(headline: "A two-star review", text: "One new two-star review, about a late delivery.", byline: "Reviews under 3 stars · shared by Yang · 3 h ago", page: "https://reviews.example.com/r/88213"),
    ]

    func memoView(_ memo: Memo, scale: CGFloat = 1, collapsed: Bool = false, dark: Bool = false, tilt: Bool = true) -> PaperView {
        PaperView(headline: memo.headline, text: memo.text, items: memo.items, when: memo.when, page: memo.page, hand: .yours, colour: memo.colour,
                  scale: scale, collapsed: collapsed, now: now, dark: dark, tilt: tilt ? PaperLook.tilt(for: memo.id) : 0)
    }
    func cardView(_ card: Card, scale: CGFloat = 1, dark: Bool = false) -> PaperView {
        PaperView(headline: card.headline, text: card.text, page: card.page, byline: card.byline, hand: .typed, colour: card.urgent ? .amber : .yellow,
                  scale: scale, now: now, dark: dark, tilt: PaperLook.tilt(for: card.headline))
    }

    // The host is an off-screen window drawn into a 2x bitmap, as the stickers render is.
    func render<V: View>(_ view: V, _ name: String) {
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { print("rep failed: \(name)"); return }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { print("encode failed: \(name)"); return }
        do { try data.write(to: dir.appendingPathComponent(name)); print("wrote \(name) \(rep.pixelsWide)x\(rep.pixelsHigh)") }
        catch { print("write failed: \(name): \(error)") }
    }
    func onDesk<V: View>(_ view: V, dark: Bool = false) -> some View {
        view.padding(PaperLook.margin + 8).background(Pad.desk(dark))
    }

    print("hand font: \(HandFont.family ?? "system rounded")")
    for (memo, name) in zip(yours, ["memo-dictated", "memo-list", "memo-short", "memo-long", "memo-soon"]) {
        render(onDesk(memoView(memo, tilt: false)), "\(name).png")
    }
    render(onDesk(memoView(dictated, collapsed: true, tilt: false)), "memo-collapsed.png")
    for (card, name) in zip(cards, ["card-urgent", "card-prices", "card-orders", "card-stock", "card-review"]) {
        render(onDesk(cardView(card)), "\(name).png")
    }
    // Three of your notes and a card as they would sit on a desk, each leaning its own way.
    let desk = ZStack(alignment: .topLeading) {
        memoView(dictated).offset(x: 0, y: 24)
        memoView(shopping).offset(x: 250, y: 0)
        memoView(dentist, collapsed: true).offset(x: 20, y: 236)
        cardView(cards[1]).offset(x: 500, y: 40)
    }
    .frame(width: 800, height: 330, alignment: .topLeading)
    render(onDesk(desk), "desk-light.png")
    let darkDesk = ZStack(alignment: .topLeading) {
        memoView(dictated, dark: true).offset(x: 0, y: 24)
        memoView(shopping, dark: true).offset(x: 250, y: 0)
        memoView(dentist, dark: true, tilt: true).offset(x: 20, y: 236)
        cardView(cards[0], dark: true).offset(x: 500, y: 40)
    }
    .frame(width: 800, height: 330, alignment: .topLeading)
    render(onDesk(darkDesk, dark: true), "desk-dark.png")
    // The sizes Bigger and Smaller step through, side by side.
    let sizes = HStack(alignment: .top, spacing: 24) {
        memoView(dictated, scale: PaperLook.steps[0], tilt: false)
        memoView(dictated, scale: 1, tilt: false)
        memoView(dictated, scale: PaperLook.steps[PaperLook.steps.count - 1], tilt: false)
    }
    render(onDesk(sizes), "memo-sizes.png")
    exit(0)
}
