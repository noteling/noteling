import AppKit
import FamiliarContracts

/// What a question showed Claude from the screen, kept on the question's note as a chip, so seeing the screen is never
/// hidden: the pictures Claude was shown, the page's text, and when they were taken. Tapping the chip shows exactly that.
struct SeenScreen {
    enum Kind { case screen, pointed, circled }
    let kind: Kind
    let at: Date
    /// Where it was taken: the app, and the window's or page's title.
    let place: String
    /// The pictures Claude was shown, in order (for the pen: the whole screen, then the crop).
    var pictures: [CGImage] = []
    /// The page's text, when Claude was given that.
    var pageText: String? = nil
    /// The answer works from the screen as it was when asked (`FrozenScreen`), so the person can switch away.
    var held = false
    /// Taken at a pen pick, and not sent yet: nothing goes to Claude until the question comes.
    var pending = false

    var isEmpty: Bool { pictures.isEmpty && pageText == nil }

    /// The chip's picture: the pen's crop (what was picked), else the screen.
    var thumbnail: CGImage? { kind == .screen ? pictures.first : pictures.dropFirst().first ?? pictures.first }

    /// "Saw your screen · 10:31", "Read the page · 10:31", "Saw what you circled · 10:31".
    var caption: String {
        if pending {
            return (kind == .circled ? "Took what you circled" : "Took where you pointed") + " · sent only when you ask"
        }
        let what: String
        switch kind {
        case .pointed: what = "Saw where you pointed"
        case .circled: what = "Saw what you circled"
        case .screen: what = pictures.isEmpty ? "Read the page" : pageText == nil ? "Saw your screen" : "Read the page and saw your screen"
        }
        return what + " · " + at.formatted(date: .omitted, time: .shortened)
    }

    /// While the answer is being written: the screen is held, so moving on changes nothing.
    static let answeringCaption = "Got your screen · you can switch away"

    static func place(_ ctx: ScreenContext?) -> String {
        guard let ctx else { return "Your screen" }
        let title = ctx.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? ctx.appName : "\(ctx.appName) · “\(title)”"
    }
}

/// The screen as it was when the person asked, held for the whole answer: look_at_screen and read_screen answer from
/// it, so switching away while Noteling answers changes nothing. Held only for answers that can't act on the screen;
/// one that controls the computer has to see what its own actions did, so its looks stay live.
@MainActor
final class FrozenScreen {
    let scene: ScreenContext?
    let at: Date
    /// Downscaled to the size Claude is sent.
    private(set) var picture: CGImage?
    private(set) var pageText: String?

    init(scene: ScreenContext?, at: Date = Date(), picture: CGImage? = nil, pageText: String? = nil) {
        self.scene = scene
        self.at = at
        self.picture = picture
        self.pageText = pageText
    }

    func keep(picture: CGImage) { self.picture = picture }
    func keep(pageText: String) { self.pageText = pageText }

    private var time: String { at.formatted(date: .omitted, time: .standard) }

    /// Goes with a held picture, so Claude knows it isn't live.
    var pictureLine: String {
        "The screen as it was when they asked, at \(time). It may have changed since; this is what they asked about."
    }

    /// Goes before held page text.
    var pageLine: String { "The window in front when they asked, at \(time), read through Accessibility:\n" }

    /// read_screen when the person has moved on and no text was kept: say so rather than read the wrong window.
    static func movedOn(to now: ScreenContext) -> String {
        "They have moved on to \(SeenScreen.place(now)) since asking, so the window they asked about can't be read now. "
            + "Use look_at_screen for the screen as it was when they asked, or answer from what you have."
    }

    /// What read_screen returns during a held answer: the text kept when they asked; else a live read while the same
    /// window is still in front (kept for the rest of the answer); else that they've moved on. `now` is what is in front
    /// at the call, nil when that can't be told.
    func read(now: ScreenContext?, live: () async -> ToolResult) async -> (result: ToolResult, kept: String?) {
        if let pageText { return (.text(pageLine + pageText), nil) }
        if let scene, let now, !now.sameScene(as: scene) { return (.text(Self.movedOn(to: now)), nil) }
        let result = await live()
        guard !result.isError, let text = result.content as? String else { return (result, nil) }
        pageText = text
        return (result, text)
    }
}
