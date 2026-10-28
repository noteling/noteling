import Foundation
import Testing
@testable import Familiar

/// Where a pack applies is a rule someone wrote, run on the Mac: a url rule is a host, its subdomains and the paths
/// under its path; an app rule is a bundle id; a title rule is words in a window title. A page rule with a path fits
/// better than one for the whole host, which fits better than an app, which fits better than a title.
@Suite struct MatchRulesTests {
    private func scene(_ url: String?, bundle: String = "com.google.Chrome", title: String = "Orders") -> ScreenContext {
        ScreenContext(appName: "Chrome", bundleID: bundle, windowTitle: title, url: url, focused: nil, timestamp: Date())
    }

    @Test func aHostRuleIsTheHostAndItsSubdomainsNotALookAlike() {
        let rules = MatchRules(urls: ["example.com"])
        #expect(rules.matches(scene("https://example.com/")))
        #expect(rules.matches(scene("https://shop.example.com/cart?ref=1#top")))
        #expect(rules.matches(scene("HTTPS://EXAMPLE.COM/Orders")))
        #expect(!rules.matches(scene("https://notexample.com/")))
        #expect(!rules.matches(scene("https://example.com.evil.test/")))
        #expect(!rules.matches(scene("https://other.test/?next=example.com")))   // the host in a query is not the host
        #expect(!rules.matches(scene("https://other.test/example.com/")))
        #expect(!rules.matches(scene(nil)))
    }

    @Test func aPathRuleIsThePathAndWhatIsUnderItNotASiblingThatStartsTheSame() {
        let rules = MatchRules(urls: ["orders.example.com/order/"])
        #expect(rules.matches(scene("https://orders.example.com/order/4417?tab=history#notes")))
        #expect(rules.matches(scene("https://orders.example.com/order")))
        #expect(rules.matches(scene("https://orders.example.com/Order/4417")))
        #expect(!rules.matches(scene("https://orders.example.com/orders")))
        #expect(!rules.matches(scene("https://orders.example.com/")))
        #expect(!rules.matches(scene("https://orders.example.com/search?q=order/4417")))
        #expect(MatchRules(urls: ["orders.example.com/order"]).matches(scene("https://orders.example.com/order/4417")))
        #expect(MatchRules(urls: ["https://orders.example.com/order/"]).matches(scene("https://orders.example.com/order/4417")))
        #expect(MatchRules(urls: ["*.example.com/order/"]).matches(scene("https://orders.example.com/order/4417")))
    }

    @Test func aRouteBehindTheHashCountsAsPathAndAStarStandsForAnything() {
        #expect(MatchRules(urls: ["app.example.com/#/incident/"]).matches(scene("https://app.example.com/#/incident/123")))
        #expect(!MatchRules(urls: ["app.example.com/#/incident/"]).matches(scene("https://app.example.com/#/change/123")))
        #expect(MatchRules(urls: ["shop.example.com/*/reviews"]).matches(scene("https://shop.example.com/item/9/reviews")))
        #expect(!MatchRules(urls: ["shop.example.com/*/reviews"]).matches(scene("https://shop.example.com/item/9/questions")))
        #expect(MatchRules(urls: ["shop.example.com/ip/*"]).matches(scene("https://shop.example.com/ip/Thing/123")))
    }

    @Test func aPortInTheRuleIsThatPortAndNoPortIsAnyPort() {
        #expect(MatchRules(urls: ["127.0.0.1:4310"]).matches(scene("http://127.0.0.1:4310/?page=abc")))
        #expect(!MatchRules(urls: ["127.0.0.1:4310"]).matches(scene("http://127.0.0.1:5000/")))
        #expect(!MatchRules(urls: ["127.0.0.1:4310"]).matches(scene("http://127.0.0.1/")))
        #expect(MatchRules(urls: ["localhost"]).matches(scene("http://localhost:4310/")))
        #expect(MatchRules(urls: ["example.com:443"]).matches(scene("https://example.com/")))   // https' own port
    }

    @Test func aRegexRuleStillRunsOverTheWholeAddress() {
        let rules = MatchRules(urls: ["/concur.*reports/"])
        #expect(rules.matches(scene("https://www.concursolutions.com/expense/reports/new")))
        #expect(!rules.matches(scene("https://www.concursolutions.com/home")))
    }

    @Test func anAppRuleIsTheWholeBundleIdAndATitleRuleIsWordsInTheTitle() {
        let app = MatchRules(bundles: ["com.example.OrdersApp"])
        #expect(app.matches(scene(nil, bundle: "com.example.ordersapp", title: "")))
        #expect(!app.matches(scene(nil, bundle: "com.example.OrdersApp.helper", title: "")))
        #expect(!app.matches(scene(nil, bundle: "example.OrdersApp", title: "")))
        #expect(MatchRules(bundles: ["/com\\.example\\..*/"]).matches(scene(nil, bundle: "com.example.Anything", title: "")))
        let title = MatchRules(titles: ["Orders Admin"])
        #expect(title.matches(scene(nil, bundle: "com.apple.Safari", title: "Order 4417 - Orders Admin")))
        #expect(!title.matches(scene(nil, bundle: "com.apple.Safari", title: "Mail")))
    }

    @Test func aPageRuleFitsBetterThanAHostAnAppOrATitle() throws {
        let page = scene("https://orders.example.com/order/4417", bundle: "com.google.Chrome", title: "Order 4417 - Orders Admin")
        let byPath = try #require(MatchRules(urls: ["orders.example.com/order/"]).hit(page))
        let byDeeperPath = try #require(MatchRules(urls: ["orders.example.com/order/4417"]).hit(page))
        let byHost = try #require(MatchRules(urls: ["example.com"]).hit(page))
        let byRegex = try #require(MatchRules(urls: ["/order/"]).hit(page))
        let byApp = try #require(MatchRules(bundles: ["com.google.Chrome"]).hit(page))
        let byTitle = try #require(MatchRules(titles: ["Orders Admin"]).hit(page))
        #expect(byDeeperPath.specificity > byPath.specificity)
        #expect(byPath.specificity > byHost.specificity && byHost.specificity == byRegex.specificity)
        #expect(byHost.specificity > byApp.specificity && byApp.specificity > byTitle.specificity)
        #expect(byPath.rule == "orders.example.com/order/" && byTitle.rule == "windows titled “Orders Admin”")
        // Several rules in one pack: the best fit is the pack's.
        let both = MatchRules(urls: ["example.com", "orders.example.com/order/"], titles: ["Orders Admin"])
        #expect(both.hit(page)?.rule == "orders.example.com/order/")
    }

    @Test func anywhereIsSaidAndNoRulesIsNoRules() {
        #expect(ToolRegistry.matchRules("anywhere").anywhere)
        #expect(ToolRegistry.matchRules(" Anywhere ").anywhere)
        #expect(ToolRegistry.matchRules(["anywhere": "true"]).anywhere)
        let rules = ToolRegistry.matchRules(["urls": ["a.example.com"], "titles": "Admin"])
        #expect(rules.urls == ["a.example.com"] && rules.titles == ["Admin"] && !rules.anywhere && !rules.isEmpty)
        #expect(ToolRegistry.matchRules(nil).isEmpty && !ToolRegistry.matchRules(nil).anywhere)
        #expect(ToolRegistry.matchRules("everywhere").isEmpty)
        #expect(MatchRules(anywhere: true).words == "anywhere")
        #expect(MatchRules(urls: ["a.example.com/x/"], bundles: ["com.a.b"], titles: ["T"]).words == "a.example.com/x/, the app com.a.b, windows titled “T”")
    }

    @Test func aPacksTextGainsMatchAnywhereOnlyWhenItHasFrontMatter() {
        let marked = ToolRegistry.markedAnywhere("---\nname: Shared\ndescription: Helpers.\n---\nBody.\n")
        #expect(marked == "---\nname: Shared\ndescription: Helpers.\nmatch: anywhere\n---\nBody.\n")
        #expect(ToolRegistry.matchRules(ToolRegistry.parseFrontmatter(marked ?? "").0["match"]).anywhere)
        #expect(ToolRegistry.markedAnywhere("No front matter here.") == nil)
        #expect(ToolRegistry.markedAnywhere("---\nname: Open\n") == nil)
    }
}
