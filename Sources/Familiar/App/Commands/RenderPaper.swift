import AppKit
import SwiftUI

/// `Noteling --render-paper <dir>`: the paper as your notes and the minister's cards would wear it, as PNGs, to judge
/// against the bar: if these were a standalone product and a person had written them and put them on their screen, would they be useful
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
    // Hands opposite each other on the little clock: the case that must not read as a slash.
    let lunch = Memo(id: "n-6", text: "Lunch with Ana", colour: .green, when: today(12, 30), createdAt: now, updatedAt: now)
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
    render(onDesk(memoView(lunch, tilt: false)), "memo-lunch.png")
    // The peel, as it shows when the mouse is on the paper.
    render(onDesk(ZStack(alignment: .topLeading) {
        memoView(dictated, tilt: false)
        PeelButton(help: "Take this note down", action: {}).offset(x: PeelButton.offset, y: PeelButton.offset)
    }), "memo-peel.png")
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
    // The deck as the panel draws it: "2 more" above the card on top, the verbs under it; then a card being stamped,
    // and the line of a press waiting to run.
    func deckModel(_ count: Int) -> DeckModel {
        let matters = Matters(directory: nil)
        matters.clock = { now }
        let findings = [("pages", "1", "nudge", "Nudge warehouse"), ("gm", "K-1", "fix", "Fix the price"), ("orders", "4417", nil, nil), ("stock", "S-1", "reorder", "Reorder"), ("reviews", "R-1", nil, nil)]
        for (index, card) in cards.prefix(count).enumerated() {
            let (job, id, run, label) = findings[index]
            let ref = FindingRef(job: "team/" + job, id: id)
            let at = now.addingTimeInterval(-Double(index * 20 + 2) * 60)
            let action = run.map { MatterView.Action(finding: ref, run: $0, label: label ?? $0) }
            let byline = card.byline.components(separatedBy: " · ")
            let shared = byline.first { $0.hasPrefix("shared by ") }.map { String($0.dropFirst(10)) }
            var matter = Matter(id: "m-\(index + 1)", findings: [ref], state: .open,
                                view: MatterView(headline: card.headline, text: card.text, action: action, page: card.page, tone: card.urgent ? .urgent : .calm),
                                jobName: byline[0], byline: shared, createdAt: at, updatedAt: at)
            matter.writtenAt = at
            matters.save(matter)
        }
        let model = DeckModel(matters: matters)
        model.clock = { now }
        return model
    }
    func deckView(_ model: DeckModel, scale: CGFloat = 1) -> some View {
        StickersView(model: model, look: StickersLook(scale: scale)).padding(8).background(Color(white: 0.96))
    }
    render(deckView(deckModel(3)), "deck.png")
    render(deckView(deckModel(1)), "deck-one.png")
    let stamping = deckModel(2)
    stamping.stamped = (stamping.card?.id ?? "", .doIt)
    render(deckView(stamping), "deck-stamped.png")
    let waiting = deckModel(2)
    waiting.pending = PendingPress(id: "m-1", label: "Nudge warehouse", until: Date().addingTimeInterval(4.4))   // counted against the clock on the wall
    render(deckView(waiting), "deck-undo.png")
    let done = deckModel(1)
    done.said = "Nudge warehouse · 10:13 AM"
    render(deckView(done), "deck-said.png")
    let over = deckModel(0)
    over.ended = true
    render(deckView(over), "deck-end.png")
    let good = deckModel(0)
    var payment = Matter(id: "m-good", findings: [FindingRef(job: "team/payments", id: "P-1")], state: .open,
                         view: MatterView(headline: "Acme paid", text: "Acme's invoice 2210 was paid in full this morning, three days early.", page: "https://books.example.com/invoices/2210", tone: .good),
                         jobName: "Payments", byline: "Ana", createdAt: now, updatedAt: now)
    payment.writtenAt = now
    good.matters.save(payment)
    render(deckView(good), "deck-good.png")
    // No button fits: the minister's next step is the first tab, into the chat.
    let stepping = deckModel(0)
    var lena = Matter(id: "m-next", findings: [FindingRef(job: "own/mail", id: "M-1")], state: .open,
                      view: MatterView(headline: "Lena wants the deck by 3", text: "Lena asked for the Q4 deck before her 3 o'clock, and nothing has gone back to her yet.",
                                       next: "Reply to Lena", page: "https://mail.example.com/inbox/M-1", tone: .calm),
                      jobName: "Mail", byline: nil, createdAt: now, updatedAt: now)
    lena.writtenAt = now
    stepping.matters.save(lena)
    render(deckView(stepping), "deck-next.png")
    let asking = deckModel(0)
    asking.question = LessonQuestion(job: "team/reviews", name: "Reviews under 3 stars", putAway: 3)
    render(deckView(asking), "deck-question.png")
    render(deckView(deckModel(3), scale: PaperLook.steps[0]), "deck-smallest.png")
    render(deckView(deckModel(3), scale: PaperLook.steps[PaperLook.steps.count - 1]), "deck-biggest.png")
    // The lamp off, warm and hot, at the bubble's size and larger, on a light and a dark desk.
    let lamps = HStack(spacing: 28) {
        ForEach([LampState.off, .warm, .hot], id: \.self) { state in
            VStack(spacing: 14) {
                LampView(state: state, size: 22)
                LampView(state: state, size: 66)
            }
        }
    }
    render(onDesk(lamps), "lamps-light.png")
    render(onDesk(lamps, dark: true), "lamps-dark.png")
    // The sizes Bigger and Smaller step through, side by side.
    let sizes = HStack(alignment: .top, spacing: 24) {
        memoView(dictated, scale: PaperLook.steps[0], tilt: false)
        memoView(dictated, scale: 1, tilt: false)
        memoView(dictated, scale: PaperLook.steps[PaperLook.steps.count - 1], tilt: false)
    }
    render(onDesk(sizes), "memo-sizes.png")
    exit(0)
}
