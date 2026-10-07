import CoreGraphics
import Foundation
import Testing
import FamiliarContracts
@testable import Familiar

@Suite
@MainActor
struct SeenScreenTests {
    private static func scene(_ title: String, url: String? = "https://shop.example.test/item/1") -> ScreenContext {
        ScreenContext(appName: "Fixture Browser", bundleID: "test.browser", windowTitle: title, url: url, focused: nil,
                      timestamp: Date(timeIntervalSince1970: 0))
    }

    private static func image(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // MARK: the held screen

    @Test
    func readDuringAHeldAnswerReturnsThePageAsAskedAboutWithoutReadingAgain() async {
        let held = FrozenScreen(scene: Self.scene("Item"), pageText: "Price $12.33")
        var liveReads = 0
        let (result, kept) = await held.read(now: Self.scene("Another tab")) { liveReads += 1; return .text("other page") }

        #expect(liveReads == 0)
        #expect(kept == nil)
        #expect((result.content as? String)?.hasSuffix("Price $12.33") == true)
        #expect((result.content as? String)?.contains("when they asked") == true)
    }

    @Test
    func readAfterThePersonMovedOnSaysSoInsteadOfReadingTheWrongWindow() async {
        let held = FrozenScreen(scene: Self.scene("Item"))
        var liveReads = 0
        let (result, kept) = await held.read(now: Self.scene("Inbox", url: "https://mail.example.test")) {
            liveReads += 1
            return .text("someone else's mail")
        }

        #expect(liveReads == 0)
        #expect(kept == nil)
        #expect(!result.isError)
        let text = result.content as? String ?? ""
        #expect(text.contains("moved on"))
        #expect(text.contains("“Inbox”"))
        #expect(text.contains("look_at_screen"))
    }

    @Test
    func readWhileTheSameWindowIsInFrontReadsItOnceAndKeepsIt() async {
        let held = FrozenScreen(scene: Self.scene("Item"))
        var liveReads = 0
        let first = await held.read(now: Self.scene("Item")) { liveReads += 1; return .text("Buy box: Seller A") }
        #expect(first.kept == "Buy box: Seller A")

        // The person switches away afterwards: the answer keeps reading what was kept.
        let second = await held.read(now: Self.scene("Inbox")) { liveReads += 1; return .text("mail") }
        #expect(liveReads == 1)
        #expect(second.kept == nil)
        #expect((second.result.content as? String)?.hasSuffix("Buy box: Seller A") == true)
    }

    @Test
    func aFailedLiveReadIsPassedOnAndNotKept() async {
        let held = FrozenScreen(scene: Self.scene("Item"))
        let (result, kept) = await held.read(now: nil) { .text("Nothing readable", isError: true) }
        #expect(result.isError)
        #expect(kept == nil)
        #expect(held.pageText == nil)
    }

    @Test
    func aHeldPictureSaysWhenItWasTaken() {
        let at = Date(timeIntervalSince1970: 1_000)
        let held = FrozenScreen(scene: nil, at: at, picture: Self.image(width: 8, height: 5))
        #expect(held.picture != nil)
        #expect(held.pictureLine.contains(at.formatted(date: .omitted, time: .standard)))
        #expect(held.pictureLine.contains("may have changed"))
    }

    // MARK: the chip

    @Test
    func theChipSaysWhatWasShown() {
        let at = Date(timeIntervalSince1970: 1_000)
        let time = at.formatted(date: .omitted, time: .shortened)
        let picture = Self.image(width: 8, height: 5)

        var screen = SeenScreen(kind: .screen, at: at, place: "Fixture Browser · “Item”")
        #expect(screen.isEmpty)
        screen.pageText = "Price"
        #expect(screen.caption == "Read the page · \(time)")
        screen.pictures = [picture]
        #expect(screen.caption == "Read the page and saw your screen · \(time)")
        screen.pageText = nil
        #expect(screen.caption == "Saw your screen · \(time)")

        #expect(SeenScreen(kind: .circled, at: at, place: "", pictures: [picture]).caption == "Saw what you circled · \(time)")
        #expect(SeenScreen(kind: .pointed, at: at, place: "", pictures: [picture]).caption == "Saw where you pointed · \(time)")
    }

    @Test
    func theChipShowsThePensCropAndOtherwiseTheScreen() {
        let whole = Self.image(width: 16, height: 10), crop = Self.image(width: 4, height: 3)
        #expect(SeenScreen(kind: .circled, at: Date(), place: "", pictures: [whole, crop]).thumbnail === crop)
        #expect(SeenScreen(kind: .pointed, at: Date(), place: "", pictures: [whole]).thumbnail === whole)
        #expect(SeenScreen(kind: .screen, at: Date(), place: "", pictures: [whole, crop]).thumbnail === whole)
        #expect(SeenScreen(kind: .screen, at: Date(), place: "").thumbnail == nil)
    }

    @Test
    func thePlaceNamesTheAppAndTheTitle() {
        #expect(SeenScreen.place(Self.scene("Item")) == "Fixture Browser · “Item”")
        #expect(SeenScreen.place(Self.scene("  ")) == "Fixture Browser")
        #expect(SeenScreen.place(nil) == "Your screen")
    }

    // MARK: the flash

    @Test
    func thePictureFliesToThePadKeepingItsShape() {
        let bounds = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let pad = CGRect(x: 1100, y: 100, width: 400, height: 540)
        let end = CaptureFlash.destination(from: bounds, toward: pad, in: bounds)
        #expect(abs(end.midX - pad.midX) < 0.5)
        #expect(abs(end.midY - pad.midY) < 0.5)
        #expect(end.width == 120)
        #expect(abs(end.width / end.height - 1.6) < 0.01)
    }

    @Test
    func withoutThePadOnThisScreenThePictureShrinksIntoTheCorner() {
        let bounds = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let elsewhere = CGRect(x: 2000, y: 100, width: 400, height: 540)
        for target in [nil, elsewhere] {
            let end = CaptureFlash.destination(from: bounds, toward: target, in: bounds)
            #expect(bounds.contains(end))
            #expect(end.maxX > bounds.width - 30)
            #expect(end.minY < 30)
        }
    }

    @Test
    func theFlashShowsJustThePickedPart() {
        let image = Self.image(width: 3200, height: 2000)   // a 2x picture of a 1600x1000 screen
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let part = CaptureFlash.crop(image, to: NSRect(x: 100, y: 800, width: 200, height: 100), screenFrame: screen)
        #expect(part?.width == 400)
        #expect(part?.height == 200)
        #expect(CaptureFlash.crop(image, to: nil, screenFrame: screen) == nil)
        #expect(CaptureFlash.crop(image, to: NSRect(x: 5000, y: 5000, width: 10, height: 10), screenFrame: screen) == nil)
    }
}
