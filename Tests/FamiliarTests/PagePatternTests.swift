import Foundation
import Testing
@testable import Familiar

/// Pages of a kind: the pattern an address suggests, the text on the paper read back, and which pages are of the kind.
@Suite struct PagePatternTests {
    private func key(_ url: String) -> PageKey { PageKey.of(url)! }
    private func kind(_ url: String) -> String { PagePattern.of(key(url)).description }

    @Test func whatNamesOneItemBecomesAStar() {
        #expect(kind("https://www.walmart.com/ip/Great-Value-Whole-Vitamin-D-Milk-Gallon-128-fl-oz/10450114") == "www.walmart.com/ip/*/*")
        #expect(kind("https://shop.example/item/red-shoes/12345?ref=mail") == "shop.example/item/*/*")
        #expect(kind("https://github.com/noteling/noteling/issues/123") == "github.com/noteling/noteling/issues/*")
        #expect(kind("https://orders.example/orders/ORD-4417-A") == "orders.example/orders/*")
        #expect(kind("https://stackoverflow.com/questions/123456/why-is-the-sky-blue") == "stackoverflow.com/questions/*/*")
        #expect(kind("https://api.example/users/123e4567-e89b-12d3-a456-426614174000/profile") == "api.example/users/*/profile")
        #expect(kind("https://files.example/d/5f3e9a7c2b1d4e6f/view") == "files.example/d/*/view")
        #expect(kind("https://blog.example/2026/11/10/hints-on-buttons") == "blog.example/*/*/*/*")
        #expect(kind("https://app.example/app#/orders/123") == "app.example/app#/orders/*")
    }

    @Test func aPageOfItsOwnKindStaysItself() {
        for url in ["https://shop.example/products/red-shoes", "https://portal.example/settings/profile", "http://127.0.0.1:4310/?page=library",
                    "https://docs.example/", "https://portal.example/sign-in", "https://portal.example/help/ipv6-settings"] {
            let page = key(url)
            #expect(PagePattern.of(page) == PagePattern.exact(page), "\(url)")
            #expect(!PagePattern.of(page).isWide, "\(url)")
        }
    }

    @Test func aRecordsParameterGoesAndThePagesStays() {
        #expect(kind("https://example.service-now.com/incident.do?sys_id=0123456789abcdef0123456789abcdef") == "example.service-now.com/incident.do")
        #expect(kind("https://example.service-now.com/sp?id=sc_cat_item&sys_id=0123456789abcdef0123456789abcdef") == "example.service-now.com/sp?id=sc_cat_item")
        #expect(kind("https://example.service-now.com/nav_to.do?uri=incident.do%3Fsys_id%3D0123456789abcdef0123456789abcdef") == "example.service-now.com/incident.do")
    }

    @Test func thePapersTextReadsBack() {
        #expect(PagePattern("/ip/*/*", host: "www.walmart.com")?.description == "www.walmart.com/ip/*/*")
        #expect(PagePattern("www.walmart.com/ip/*/*")?.description == "www.walmart.com/ip/*/*")
        #expect(PagePattern("https://www.walmart.com/ip/*/*/", host: "www.walmart.com")?.description == "www.walmart.com/ip/*/*")
        #expect(PagePattern("ip/*/*", host: "www.walmart.com")?.description == "www.walmart.com/ip/*/*")
        #expect(PagePattern("/sp?id=sc_cat_item", host: "example.service-now.com")?.query == ["id": "sc_cat_item"])
        #expect(PagePattern("", host: "www.walmart.com") == nil && PagePattern("   ") == nil && PagePattern("/ip/*") == nil)
        #expect(PagePattern("/", host: "shop.example")?.path == "/" && PagePattern("shop.example")?.path == "/")
        let typed = PagePattern("/products/*", host: "shop.example")!
        #expect(typed.isWide && typed.matches(key("https://shop.example/products/red-shoes")) && !typed.matches(key("https://shop.example/products")))
    }

    @Test func whichPagesAreOfTheKind() {
        let items = PagePattern.of(key("https://www.walmart.com/ip/Great-Value-Whole-Milk/10450114"))
        #expect(items.matches(key("https://www.walmart.com/ip/Bananas-each/44390948?athcpid=x&from=search")))
        #expect(!items.matches(key("https://www.walmart.com/ip/44390948")))
        #expect(!items.matches(key("https://www.walmart.com/ip/Bananas-each/44390948/reviews")))
        #expect(!items.matches(key("https://walmart.com/ip/Bananas-each/44390948")))
        #expect(!items.matches(key("https://www.walmart.com/cp/Bananas-each/44390948")))
        let portal = PagePattern.of(key("https://example.service-now.com/sp?id=sc_cat_item&sys_id=0123456789abcdef0123456789abcdef"))
        #expect(portal.matches(key("https://example.service-now.com/sp?id=sc_cat_item&sys_id=fedcba9876543210fedcba9876543210")))
        #expect(!portal.matches(key("https://example.service-now.com/sp?id=ticket&sys_id=fedcba9876543210fedcba9876543210")))
        let route = PagePattern.of(key("https://app.example/app#/orders/123"))
        #expect(route.matches(key("https://app.example/app?x=1#/orders/999")) && !route.matches(key("https://app.example/app#/orders/999/edit")))
        #expect(PagePattern.exact(key("https://shop.example/item/red-shoes/1")).matches(key("https://shop.example/item/red-shoes/1?a=b")))
        #expect(!PagePattern.exact(key("https://shop.example/item/red-shoes/1")).matches(key("https://shop.example/item/red-shoes/2")))
    }
}
