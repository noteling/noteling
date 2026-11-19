import AppKit
import Foundation
import Testing
@testable import Familiar

/// `--click` (Synthetics' approved, named click): made-up pages and stand-in hands, so no test presses anything.
@Suite @MainActor
struct HeadlessClickTests {
    static let key = String(repeating: "ab", count: 32)
    static let cart = HeadlessReadTests.element("AXButton", "Add to cart", CGRect(x: 10, y: 10, width: 80, height: 30))
    static func shop(_ elements: [PageElement] = [cart], url: String = "https://shop.example/ip/milk/1") -> PageSnapshot {
        HeadlessReadTests.page(url, elements)
    }

    static func prepare(_ page: PageSnapshot, name: String = "Add to cart", role: String? = nil) -> HeadlessClick.Report {
        HeadlessClick.decide(page, HeadlessClick.Ask(name: name, role: role, key: key), front: true).0
    }

    static func fire(_ page: PageSnapshot, expect: (String, String), name: String = "Add to cart", named: String? = nil,
                     front: Bool = true, requireFront: Bool = true) -> (HeadlessClick.Report, PageElement?) {
        HeadlessClick.decide(page, HeadlessClick.Ask(name: name, role: nil, key: key, fire: true, expect: expect,
                                                     namedApproval: named ?? name, requireFront: requireFront), front: front)
    }

    // MARK: - Prepare

    @Test func prepareGivesTokensHostAndNoPageWords() throws {
        let r = Self.prepare(Self.shop())
        #expect(r.ok && r.exit == 0 && r.guard == "safe" && r.host == "shop.example")
        #expect(HeadlessClick.isToken(r.page_token) && HeadlessClick.isToken(r.hit_token))
        let out = HeadlessClick.json(r)
        #expect(!out.contains("milk") && !out.contains("/ip/"))
        #expect(r.pressed == nil)
    }

    @Test func tokensAreStableAndKeyed() {
        let a = Self.prepare(Self.shop()), b = Self.prepare(Self.shop())
        #expect(a.page_token == b.page_token && a.hit_token == b.hit_token)
        let other = HeadlessClick.decide(Self.shop(), HeadlessClick.Ask(name: "Add to cart", role: nil,
                                                                        key: String(repeating: "cd", count: 32)), front: true).0
        #expect(other.page_token != a.page_token && other.hit_token != a.hit_token)
        #expect(Self.prepare(Self.shop(url: "https://shop.example/ip/eggs/2")).page_token != a.page_token)
    }

    @Test func onlyAnExactUniqueVisibleEnabledControl() {
        let alike = Self.shop([HeadlessReadTests.element("AXButton", "Add to cart – Bananas", CGRect(x: 0, y: 0, width: 9, height: 9))])
        let rAlike = Self.prepare(alike)
        #expect(rAlike.exit == 8 && rAlike.reason == "not_exact" && rAlike.find?.hits.isEmpty == true)
        #expect(!HeadlessClick.json(rAlike).contains("Bananas"))
        let two = Self.shop([Self.cart, HeadlessReadTests.element("AXButton", "Add to cart", CGRect(x: 0, y: 90, width: 9, height: 9))])
        #expect(Self.prepare(two).exit == 8 && Self.prepare(two).reason == "not_unique")
        let hidden = Self.shop([HeadlessReadTests.element("AXButton", "Add to cart", CGRect(x: 0, y: 0, width: 9, height: 9), visible: false)])
        #expect(Self.prepare(hidden).reason == "not_visible" && Self.prepare(hidden).exit == 8)
        let off = Self.shop([HeadlessReadTests.element("AXButton", "Add to cart", CGRect(x: 0, y: 0, width: 9, height: 9), enabled: false)])
        #expect(Self.prepare(off).reason == "disabled" && Self.prepare(off).exit == 8)
        #expect(Self.prepare(Self.shop(), name: "Checkout").exit == 1)
        #expect(Self.prepare(Self.shop(), role: "link").exit == 1)
    }

    @Test func guardWordsAreReported() {
        let order = Self.shop([HeadlessReadTests.element("AXButton", "Buy now", CGRect(x: 0, y: 0, width: 9, height: 9))])
        let r = Self.prepare(order, name: "Buy now")
        #expect(r.ok && r.guard == "confirm")
        let menu = Self.shop([HeadlessReadTests.element("AXMenuItem", "Help", CGRect(x: 0, y: 0, width: 9, height: 9), kind: "menu item")])
        #expect(Self.prepare(menu, name: "Help").exit == 7 && Self.prepare(menu, name: "Help").guard == "forbidden")
        var sheet = Self.shop()
        sheet.sheet = "Print"
        #expect(Self.prepare(sheet).exit == 7 && Self.prepare(sheet).reason == "sheet_open")
    }

    // MARK: - Fire

    func expect(_ page: PageSnapshot) -> (String, String) {
        let r = Self.prepare(page)
        return (r.page_token!, r.hit_token!)
    }

    @Test func fireOnTheSamePageAndControlMayPress() {
        let (r, hit) = Self.fire(Self.shop(), expect: expect(Self.shop()))
        #expect(r.ok && r.exit == 0 && hit?.label == "Add to cart")
    }

    @Test func fireRefusesAnotherPageOrAReplacedControl() {
        let tokens = expect(Self.shop())
        let other = Self.fire(Self.shop(url: "https://shop.example/ip/eggs/2"), expect: tokens)
        #expect(other.0.exit == 6 && other.0.reason == "page_changed" && other.1 == nil)
        var renamed = Self.cart
        renamed.domID = "add-to-cart-2"
        let replaced = Self.fire(Self.shop([renamed]), expect: tokens)
        #expect(replaced.0.exit == 6 && replaced.0.reason == "control_changed" && replaced.1 == nil)
        var sheet = Self.shop()
        sheet.sheet = "Sign in"
        #expect(Self.fire(sheet, expect: tokens).0.exit == 6)
    }

    @Test func fireNeedsTheBrowserInFront() {
        let tokens = expect(Self.shop())
        #expect(Self.fire(Self.shop(), expect: tokens, front: false).0.exit == 9)
        #expect(Self.fire(Self.shop(), expect: tokens, front: false, requireFront: false).0.exit == 0)
    }

    @Test func confirmClassNeedsTheNameInTheApproval() {
        let page = Self.shop([HeadlessReadTests.element("AXButton", "Buy now", CGRect(x: 0, y: 0, width: 9, height: 9))])
        let r = Self.prepare(page, name: "Buy now")
        let tokens = (r.page_token!, r.hit_token!)
        #expect(Self.fire(page, expect: tokens, name: "Buy now", named: "Add to cart").0.exit == 7)
        #expect(Self.fire(page, expect: tokens, name: "Buy now", named: "buy NOW").0.exit == 0)
    }

    // MARK: - Arguments and running

    static let prepareArgs = ["--click", "Add to cart", "--prepare", "--json", "--token", key]

    @Test(arguments: [
        ["--click", "Add to cart", "--json", "--token", key],                                  // neither form
        ["--click", "Add to cart", "--prepare", "--fire", "--json", "--token", key],           // both
        ["--click", "Add to cart", "--prepare", "--token", key],                               // no --json
        ["--click", "Add to cart", "--prepare", "--json", "--token", "ABC"],                   // bad token
        ["--click", "Add to cart", "--fire", "--json", "--token", key],                        // fire without --expect
        ["--click", "Add to cart", "--fire", "--json", "--token", key, "--expect", "x,y"],
        ["--click", "Add to cart", "--prepare", "--json", "--token", key, "--expect", key + "," + key],
        ["--click", "--prepare", "--json", "--token", key],
        ["--click", "Add to cart", "--prepare", "--json", "--token", key, "--app", "com.apple.finder"],
    ])
    func usageMistakesExitTwoAndLetTheBrowserGo(args: [String]) {
        let told = HeadlessReadTests.Told()
        var pressed = 0
        let hands = HeadlessClick.Hands(browser: HeadlessReadTests.browser(told, pages: [Self.shop()]),
                                        isFront: { _ in true }, spend: { _ in true }, press: { _, _ in pressed += 1; return true })
        var out: [String] = []
        #expect(HeadlessClick.run(args, hands: hands) { out.append($0) } == 2)
        #expect(told.settles == 1 && pressed == 0 && out.count == 1)
    }

    final class Pressed { var count = 0 }

    func runFire(spend: Bool = true, press: Bool = true, pages: [PageSnapshot?]) -> (Int32, HeadlessClick.Report, Int, Int) {
        let told = HeadlessReadTests.Told()
        let pressed = Pressed()
        let tokens = expect(Self.shop())
        let hands = HeadlessClick.Hands(browser: HeadlessReadTests.browser(told, fresh: false, pages: pages),
                                        isFront: { _ in true }, spend: { _ in spend },
                                        press: { _, _ in pressed.count += 1; return press })
        var out: [String] = []
        let code = HeadlessClick.run(["--click", "Add to cart", "--fire", "--json", "--token", Self.key,
                                      "--expect", tokens.0 + "," + tokens.1, "--named-approval", "Add to cart",
                                      "--require-front"], hands: hands) { out.append($0) }
        let report = try! JSONDecoder().decode(HeadlessClick.Report.self, from: Data(out[0].utf8))
        return (code, report, pressed.count, told.settles)
    }

    @Test func firePressesOnceAndSaysWhetherThePageChanged() {
        let gone = Self.shop([])
        let (code, report, pressed, settles) = runFire(pages: [Self.shop(), gone])
        #expect(code == 0 && report.pressed == true && report.changed == true && pressed == 1 && settles == 1)
        let same = runFire(pages: [Self.shop(), Self.shop()])
        #expect(same.0 == 0 && same.1.changed == false)
    }

    @Test func aUsedTokenNeverPressesAgain() {
        let (code, report, pressed, _) = runFire(spend: false, pages: [Self.shop()])
        #expect(code == 6 && report.reason == "token_used" && report.pressed == false && pressed == 0)
    }

    @Test func aControlThatMovedUnderThePressIsNotPressed() {
        let (code, report, pressed, _) = runFire(press: false, pages: [Self.shop()])
        #expect(code == 6 && report.reason == "control_changed" && report.pressed == false && pressed == 1)
    }

    @Test func prepareNeverPresses() {
        let told = HeadlessReadTests.Told()
        var pressed = 0, spent = 0
        let hands = HeadlessClick.Hands(browser: HeadlessReadTests.browser(told, pages: [Self.shop()]),
                                        isFront: { _ in true }, spend: { _ in spent += 1; return true },
                                        press: { _, _ in pressed += 1; return true })
        #expect(HeadlessClick.run(Self.prepareArgs, hands: hands) { _ in } == 0)
        #expect(pressed == 0 && spent == 0 && told.settles == 1)
    }

    @Test func usedTokensAreKeptOwnerOnlyAndOnce() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("click-used-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("click-used.json")
        #expect(UsedTokens.spend(Self.key, at: file))
        #expect(!UsedTokens.spend(Self.key, at: file))
        #expect(UsedTokens.spend(String(repeating: "cd", count: 32), at: file))
        #expect(UsedTokens.spend(Self.key, at: file, now: Date().addingTimeInterval(8 * 86_400)))
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(!(try String(contentsOf: file, encoding: .utf8)).contains(Self.key))
    }
}
