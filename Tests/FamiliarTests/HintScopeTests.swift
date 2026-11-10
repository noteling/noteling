import AppKit
import Foundation
import Testing
@testable import Familiar

/// Where a hint on a page is met, as the paper offers it: this page, pages like it, the whole site.
@Suite @MainActor
struct HintScopeTests {
    private func anchor(_ url: String, role: String = "AXGroup") -> NoteAnchor {
        var a = NoteStore.sceneAnchor(bundleID: "com.google.Chrome", windowTitle: "Item", url: url)
        a.role = role
        a.rect = [0.5, 0.2, 0.1, 0.05]
        return a
    }

    @Test func thePaperOffersPagesLikeThisWhenTheAddressNamesOneItem() throws {
        let milk = anchor("https://www.walmart.com/ip/Great-Value-Whole-Milk/10450114?from=search")
        let choices = try #require(WandView.scopes(for: milk, existing: nil))
        #expect(choices == NoteEditor.ScopeChoices(host: "www.walmart.com", page: "/ip/Great-Value-Whole-Milk/10450114", pages: "/ip/*/*", initial: .pages("/ip/*/*")))
        // A page of its own kind starts from this page; a window in an app offers nothing.
        #expect(WandView.scopes(for: anchor("https://portal.example/settings/profile"), existing: nil)?.initial == .page)
        #expect(WandView.scopes(for: NoteStore.sceneAnchor(bundleID: "com.apple.TextEdit", windowTitle: "Untitled", url: nil), existing: nil) == nil)
        // A hint being changed starts from where it is.
        var site = milk
        site.page = nil
        site.path = nil
        let existing = StickyNote(id: "s", anchor: site, kind: "tip", text: "x", by: "y", at: "2026-11-10", confirmed: "2026-11-10")
        #expect(WandView.scopes(for: milk, existing: existing)?.initial == .site)
        var typed = milk
        typed.pattern = "www.walmart.com/ip/*"
        let kept = StickyNote(id: "k", anchor: typed, kind: "tip", text: "x", by: "y", at: "2026-11-10", confirmed: "2026-11-10")
        #expect(WandView.scopes(for: milk, existing: kept)?.initial == .pages("/ip/*"))
    }

    @Test func theMenuAndThePatternBesideItSayWhereTheHintIsMet() {
        let choices = NoteEditor.ScopeChoices(host: "www.walmart.com", page: "/ip/Great-Value-Whole-Milk/10450114", pages: "/ip/*/*", initial: .pages("/ip/*/*"))
        let editor = NoteEditor(existing: nil, place: "a circled spot", scope: choices)
        #expect(editor.frame.height == NoteEditor.height(withChecks: false, scope: true) && editor.chosenScope == .pages("/ip/*/*"))
        editor.typedPattern = "/ip/*"
        var kept: HintScope?
        editor.onCommit = { _, _, _, scope in kept = scope }
        editor.textView.string = "The per-unit price counts the whole pack"
        editor.commit()
        #expect(kept == .pages("/ip/*"))
        editor.selectScope(at: 2)
        #expect(editor.chosenScope == .site && editor.typedPattern == "www.walmart.com")
        editor.selectScope(at: 0)
        #expect(editor.chosenScope == .page && editor.typedPattern == "/ip/Great-Value-Whole-Milk/10450114")
        editor.selectScope(at: 1)
        #expect(editor.typedPattern == "/ip/*/*")
        #expect(NoteEditor(existing: nil, place: "x").chosenScope == nil)
        #expect(NoteEditor(existing: nil, place: "x", checks: [.init(script: "a__b", title: "b")], scope: choices).frame.height == NoteEditor.size.height + 52)
    }

    @Test func keepingTheHintWritesTheScopeIntoItsAnchor() throws {
        let controller = WandController()
        var kept: StickyNote?
        controller.onNoteSave = { kept = $0 }
        let view = WandView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), controller: controller, screen: NSScreen.main ?? NSScreen.screens[0])
        let milk = anchor("https://www.walmart.com/ip/Great-Value-Whole-Milk/10450114")
        view.present(anchor: milk, at: NSRect(x: 400, y: 400, width: 80, height: 30), existing: nil)
        var paper = try #require(view.openPaper)
        paper.textView.string = "The per-unit price counts the whole pack"
        paper.commit()
        #expect(kept?.anchor.pattern == "www.walmart.com/ip/*/*" && kept?.anchor.page?.description == "www.walmart.com/ip/Great-Value-Whole-Milk/10450114")
        #expect(kept?.anchor.scope == .pages("/ip/*/*") && kept?.anchor.role == "AXGroup")
        // Changed to the whole site: the page goes and the host stays, which is how a hint from before patterns says it.
        view.present(anchor: milk, at: NSRect(x: 400, y: 400, width: 80, height: 30), existing: kept)
        paper = try #require(view.openPaper)
        paper.selectScope(at: 2)
        paper.commit()
        #expect(kept?.anchor.scope == .site && kept?.anchor.page == nil && kept?.anchor.pattern == nil && kept?.anchor.host == "www.walmart.com")
        // A pattern typed wrong falls back to the one the address suggests; "this page" is the page.
        view.present(anchor: milk, at: NSRect(x: 400, y: 400, width: 80, height: 30), existing: kept)
        paper = try #require(view.openPaper)
        paper.selectScope(at: 1)
        paper.typedPattern = "   "
        paper.commit()
        #expect(kept?.anchor.pattern == "www.walmart.com/ip/*/*")
        view.present(anchor: milk, at: NSRect(x: 400, y: 400, width: 80, height: 30), existing: kept)
        paper = try #require(view.openPaper)
        paper.selectScope(at: 0)
        paper.commit()
        #expect(kept?.anchor.scope == .page && kept?.anchor.pattern == nil && kept?.anchor.page?.path == "/ip/Great-Value-Whole-Milk/10450114")
    }
}
