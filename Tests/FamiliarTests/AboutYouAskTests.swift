import Foundation
import Testing
@testable import Familiar

/// "Is this you?" and the deck's one question slot: a draft built from what Noteling already has, never kept or read by
/// a prompt until the person says Yes; Fix opens the page with it filled in; Fix and Not now hold it for a week; the
/// minister's lesson question goes before it. (docs/plans/p13n-about-you.md, delivery 3)
@Suite @MainActor struct AboutYouAskTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func fixture() -> (matters: Matters, log: MemoryLog, lessons: Lessons, profile: Profile, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("about-you-ask-\(UUID().uuidString)")
        let log = MemoryLog(directory: dir.appendingPathComponent(MemoryLog.folder))
        log.clock = { self.at }
        let matters = Matters(directory: nil)
        matters.clock = { self.at }
        matters.memory = log
        let lessons = Lessons(file: dir.appendingPathComponent("taught.json"))
        lessons.clock = { self.at }
        let profile = Profile(home: dir, memory: log)
        profile.clock = { self.at }
        return (matters, log, lessons, profile, dir)
    }

    private func deck(_ matters: Matters, profile: Profile?, lessons: Lessons? = nil, name: String? = "Sam Lee", tools: String? = "Shopify admin and Stripe") -> DeckModel {
        let model = DeckModel(matters: matters)
        model.clock = { self.at }
        model.stampSeconds = 0
        model.endSeconds = 0
        model.drafts = { (name, tools) }
        model.lessons = lessons
        model.profile = profile
        return model
    }

    private func matter(_ id: String, job: String, name: String) -> Matter {
        var matter = Matter(id: id, findings: [FindingRef(job: job, id: id)], state: .open, view: MatterView(headline: "Thing \(id)", text: "Words.", tone: .calm),
                            jobName: name, byline: nil, createdAt: at, updatedAt: at)
        matter.writtenAt = at
        return matter
    }

    // MARK: the draft

    @Test func theToolsLineIsTheMostUsedPacksFirstThenByNameAtMostThreeAndNoneUnused() {
        #expect(AboutYouDraft.tools([]) == nil)
        #expect(AboutYouDraft.tools([("Orders", 0), (" ", 4)]) == nil)
        #expect(AboutYouDraft.tools([("Stripe", 2)]) == "Stripe")
        #expect(AboutYouDraft.tools([("Stripe", 3), ("stripe", 2), ("Linear", 1)]) == "Stripe and Linear")   // one pack, two spellings
        #expect(AboutYouDraft.tools([("stripe", 1), ("Shopify admin", 5), ("Stripe", 2), ("Zendesk", 2), ("Linear", 2)])
                == "Shopify admin, Linear and Stripe")
        #expect(AboutYouDraft(name: "Sam Lee", tools: "Stripe").text == "You're Sam Lee, working in Stripe?")
        #expect(AboutYouDraft(name: "Sam Lee", tools: nil).text == "You're Sam Lee?")
        #expect(AboutYouDraft(name: nil, tools: "Stripe").text == "You work in Stripe?")
        #expect(AboutYouDraft(name: "Sam", tools: "Stripe")[.company] == nil && AboutYouDraft(name: "Sam", tools: "Stripe")[.tools] == "Stripe")
    }

    @Test func onlyFieldsWithNothingKeptAreDraftedAndADraftIsNeverKeptOrInAPromptBeforeYes() throws {
        let (_, _, _, profile, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(profile.draft(name: "  ", tools: nil) == nil)
        #expect(profile.draft(name: "Sam Lee", tools: "Stripe") == AboutYouDraft(name: "Sam Lee", tools: "Stripe"))
        try profile.keep(.name, "Samantha Lee", from: .typed)
        #expect(profile.draft(name: "Sam Lee", tools: "Stripe") == AboutYouDraft(name: nil, tools: "Stripe"))
        try profile.keep(.tools, "Excel", from: .typed)
        #expect(profile.draft(name: "Sam Lee", tools: "Stripe") == nil)

        // Drafting kept nothing: the file and the block hold only what was typed.
        let file = try String(contentsOf: Profile.file(home: dir), encoding: .utf8)
        #expect(!file.contains("Stripe") && !file.contains("Sam Lee\""))
        #expect(!profile.block().text.contains("Stripe"))
    }

    @Test func yesKeepsEachDraftedFactAsDraftedAndTheNameGoesToTheAuthor() throws {
        let (_, log, _, profile, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        var names: [(String?, String?)] = []
        profile.onName = { names.append(($0, $1)) }
        let draft = try #require(profile.draft(name: "Sam Lee", tools: "Shopify admin and Stripe"))
        try profile.confirm(draft)
        #expect(profile.me.name == Fact(text: "Sam Lee", from: .drafted, at: at))
        #expect(profile.me.tools == Fact(text: "Shopify admin and Stripe", from: .drafted, at: at))
        #expect(names.count == 1 && names[0].0 == nil && names[0].1 == "Sam Lee")
        #expect(profile.block().text.contains("name: Sam Lee") && profile.block().text.contains("tools: Shopify admin and Stripe"))
        #expect(profile.draft(name: "Sam Lee", tools: "Shopify admin and Stripe") == nil)   // asked once: nothing left to draft
        #expect(Profile(home: dir).me.name?.from == .drafted)
        let lines = log.lines(on: at).compactMap { $0["fact"] as? String }
        #expect(lines == ["me.name", "me.tools"])
    }

    @Test func notNowAndFixHoldTheQuestionForAWeekAndAreKeptAcrossARestart() throws {
        let (_, log, _, profile, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let draft = try #require(profile.draft(name: "Sam Lee", tools: nil))
        profile.decline(draft)
        #expect(profile.fixing == nil && profile.draft(name: "Sam Lee", tools: nil) == nil)
        let again = Profile(home: dir)
        again.clock = { self.at.addingTimeInterval(6 * 86_400) }
        #expect(again.draft(name: "Sam Lee", tools: nil) == nil)                      // within the week, after a restart too
        again.clock = { self.at.addingTimeInterval(8 * 86_400) }
        #expect(again.draft(name: "Sam Lee", tools: nil) == draft)                    // asked again a week on
        again.decline(draft, fixing: true)
        #expect(again.fixing == draft && again.draft(name: "Sam Lee", tools: nil) == nil)
        #expect(again.me.isEmpty && again.block().text.isEmpty)                       // Fix keeps nothing by itself
        #expect(log.lines(on: at).compactMap { $0["profile"] as? String } == ["not now"])
        #expect(!(try String(contentsOf: Profile.file(home: dir), encoding: .utf8)).contains("Sam Lee"))
    }

    @Test func closingThePageWithoutKeepingDropsTheFixDraft() throws {
        // Quill's #149 L2: the "Fix and keep" rows last while the page is open, not until quit.
        let (_, _, _, profile, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let draft = try #require(profile.draft(name: "Sam Lee", tools: nil))
        profile.decline(draft, fixing: true)
        #expect(profile.fixing == draft)
        profile.pageClosed()
        #expect(profile.fixing == nil && profile.me.isEmpty)
        #expect(profile.draft(name: "Sam Lee", tools: nil) == nil)                    // still put aside for the week
    }

    @Test func anUnreadableFileIsNeverAskedAboutOrWrittenOver() throws {
        let (_, _, _, _, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = Profile.file(home: dir)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ mended by hand".utf8).write(to: file)
        let profile = Profile(home: dir)
        #expect(profile.draft(name: "Sam Lee", tools: "Stripe") == nil)
        #expect(throws: MinisterError.self) { try profile.confirm(AboutYouDraft(name: "Sam Lee", tools: nil)) }
        profile.decline(AboutYouDraft(name: "Sam Lee", tools: nil))
        #expect(try String(contentsOf: file, encoding: .utf8) == "{ mended by hand")
    }

    // MARK: the deck's slot

    @Test func theLessonQuestionGoesFirstThenIsThisYouAndOnlyOneShowsAtATime() throws {
        let (matters, _, lessons, profile, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        for id in ["r-1", "r-2"] { matters.save(matter(id, job: "team/reviews", name: "Reviews")) }
        let model = deck(matters, profile: profile, lessons: lessons)
        #expect(model.card?.id == "r-1" && model.needs == 3)                               // two cards and one question
        guard case .aboutYou? = model.ask else { Issue.record("expected Is this you?"); return }
        model.stamp(.notNow, on: "r-1")
        model.stamp(.notNow, on: "r-2")
        #expect(model.card == nil && model.question?.job == "team/reviews" && model.asks == 1)   // the lesson goes first
        model.answer(false)
        #expect(model.ask == .aboutYou(AboutYouDraft(name: "Sam Lee", tools: "Shopify admin and Stripe")))   // then A takes the slot
        #expect(model.hasSomethingToShow && !model.ended)
        model.answer(.notNow)
        #expect(model.ask == nil && model.ended)
    }

    @Test func yesOnTheCardKeepsTheDraftAndTheDeckEnds() throws {
        let (matters, _, _, profile, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = deck(matters, profile: profile)
        #expect(model.needs == 1 && model.hasSomethingToShow)
        model.answer(.yes)
        #expect(profile.me.name?.text == "Sam Lee" && profile.me.tools?.from == .drafted)
        #expect(model.ask == nil && model.ended)
        model.refreshQuestion()
        #expect(model.ask == nil)
    }

    @Test func fixOpensThePageWithTheDraftFilledInAndKeepingItAsIsIsDrafted() throws {
        let (matters, _, _, profile, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = deck(matters, profile: profile, tools: nil)
        var opened = 0
        model.openAboutYou = { opened += 1 }
        model.answer(.fix)
        #expect(opened == 1 && model.ask == nil && profile.fixing == AboutYouDraft(name: "Sam Lee", tools: nil))
        #expect(profile.me.isEmpty)
        #expect(AboutYouList.drafted(.name, "Sam Lee") == "Your name: Sam Lee? Fix and keep")
        #expect(AboutYouList.from(.name, kept: " Sam Lee ", fixing: profile.fixing) == .drafted)
        #expect(AboutYouList.from(.name, kept: "Samantha Lee", fixing: profile.fixing) == .typed)
        #expect(AboutYouList.from(.company, kept: "Acme", fixing: profile.fixing) == .typed)
        #expect(AboutYouList.from(.name, kept: "Sam Lee", fixing: nil) == .typed)
    }

    @Test func withoutAProfileTheDeckAsksOnlyTheLessonQuestion() {
        let (matters, _, _, _, dir) = fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = deck(matters, profile: nil)
        #expect(model.ask == nil && model.needs == 0 && !model.hasSomethingToShow)
        model.answer(.yes)   // nothing to answer
        #expect(model.ask == nil)
    }

    @Test func settingsSaysTheAuthorNowComesFromAboutYou() {
        #expect(SettingsView.aboutYouWords.contains("signs the notes you leave with the pen"))
        #expect(SettingsView.aboutYouWords.contains("replaces the one notes were signed with"))
    }
}
