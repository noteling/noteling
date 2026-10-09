import Foundation
import Testing
@testable import Familiar

/// Several files decided at once from a folder's page, with one Undo; the attention test doesn't read a batch as a
/// judgment of each file; and folders with nothing to show step aside on the home.
@Suite
@MainActor
struct MorningBatchTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("morning-batch-\(UUID().uuidString)")

    private func card(_ title: String, in folder: UUID, tracked: Bool = false) -> MorningCard {
        var card = MorningCard(folderID: folder, title: title, action: MorningAction(title: "Prepare reply", instruction: "Draft a reply."))
        if tracked {
            card.tracking = CardTracking(sourceID: UUID(), itemKey: title.lowercased(), sourceName: "Morning mail", identityEvidence: "Its id",
                                         firstSeenAt: Date(), lastSeenAt: Date(), lastRunID: UUID(), contentFingerprint: title)
        }
        return card
    }

    @Test
    func severalFilesAreDecidedInOneSaveAndOneUndoPutsThemBack() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MorningStore(directory: directory)
        let folder = store.folders[1].id
        let a = card("Reply to Alex", in: folder), b = card("Rent receipt", in: folder, tracked: true), busy = card("Book the room", in: folder)
        for c in [a, b, busy] { try store.saveCard(c) }
        _ = try store.enqueue(cardID: busy.id)   // work waiting: left as it is

        let (before, skipped) = try store.decide(cardIDs: [a.id, b.id, busy.id], .resolve)
        #expect(before.map(\.id) == [a.id, b.id])
        #expect(skipped == 1)
        #expect(store.cards.first { $0.id == a.id }?.isResolved == true)
        #expect(store.cards.first { $0.id == b.id }?.tracking?.resolvedByUser == true)
        #expect(store.cards.first { $0.id == busy.id }?.isResolved == false)
        #expect(MorningStore.BatchDecision.resolve.receipt(before.count) == "Resolved 2 files.")

        try store.restoreDecisions(before)
        let reopened = MorningStore(directory: directory)   // and it's saved
        #expect(reopened.cards.first { $0.id == a.id }?.isResolved == false)
        #expect(reopened.cards.first { $0.id == a.id }?.disposition == .unreviewed)
        #expect(reopened.cards.first { $0.id == b.id }?.tracking?.resolvedByUser == false)
        #expect(reopened.cards.first { $0.id == b.id }?.tracking?.changes.isEmpty == true)
    }

    @Test
    func fileAwayKeepAndBackToReviewChangeOnlyFilesThatDiffer() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MorningStore(directory: directory)
        let folder = store.folders[1].id
        let a = card("Reply to Alex", in: folder), b = card("Rent receipt", in: folder)
        for c in [a, b] { try store.saveCard(c) }
        try store.setDisposition(cardID: b.id, to: .ignored)

        let filed = try store.decide(cardIDs: [a.id, b.id], .fileAway)
        #expect(filed.before.map(\.id) == [a.id])   // b was filed away already
        #expect(store.cards.allSatisfy { $0.disposition == .ignored })

        let back = try store.decide(cardIDs: [a.id, b.id], .toReview)
        #expect(back.before.count == 2)
        #expect(store.cards.allSatisfy { $0.disposition == .unreviewed })

        _ = try store.decide(cardIDs: [a.id], .resolve)
        let reopened = try store.decide(cardIDs: [a.id, b.id], .reopen)
        #expect(reopened.before.map(\.id) == [a.id])
        #expect(store.cards.first { $0.id == a.id }?.isResolved == false)
    }

    @Test
    func eachViewOffersOnlyWhatChangesItsFiles() {
        #expect(MorningStore.BatchDecision.offered(for: .unreviewed) == [.resolve, .fileAway, .mine])
        #expect(MorningStore.BatchDecision.offered(for: .ignored) == [.resolve, .toReview])
        #expect(MorningStore.BatchDecision.offered(for: .resolved) == [.reopen])
        #expect(!MorningStore.BatchDecision.offered(for: .mine).contains(.mine))
    }

    @Test
    func aBatchIsNotAJudgmentOfEachFile() {
        let folder = UUID()
        let one = card("Reply to Alex", in: folder, tracked: true), two = card("Rent receipt", in: folder, tracked: true)
        var before = MorningWorkspace()
        before.cards = [one, two]
        var single = before
        single.cards[0].disposition = .ignored
        #expect(AttentionImplicit.signals(from: before, to: single).map(\.signal) == [.ignored])

        var batch = before
        batch.cards[0].disposition = .ignored
        batch.cards[1].disposition = .ignored
        #expect(AttentionImplicit.signals(from: before, to: batch).isEmpty)
        #expect(AttentionImplicit.signals(from: batch, to: before).isEmpty)   // nor its Undo
    }

    @Test
    func foldersWithNothingToShowStepAsideUntilAFileArrives() {
        let busy = MorningFolder(name: "Unfinished"), quiet = MorningFolder(name: "Holiday Oct · GM")
        var hidden = MorningFolder(name: "Replies")
        hidden.hidden = true
        let folders = [busy, quiet, hidden]
        let counts = [busy.id: 3]

        #expect(MorningFilesView.shownFolders(folders, counts: counts, showingQuiet: false, showingHidden: false).map(\.name) == ["Unfinished"])
        #expect(MorningFilesView.shownFolders(folders, counts: counts, showingQuiet: true, showingHidden: false).map(\.name) == ["Unfinished", "Holiday Oct · GM"])
        #expect(MorningFilesView.shownFolders(folders, counts: counts, showingQuiet: true, showingHidden: true).map(\.name) == ["Unfinished", "Holiday Oct · GM", "Replies"])
        #expect(MorningFilesView.quietFoldersLine(folders, counts: counts, showingQuiet: false) == "Quiet folders (1) · Show")
        #expect(MorningFilesView.quietFoldersLine(folders, counts: counts, showingQuiet: true) == "Hide quiet folders")
        #expect(MorningFilesView.quietFoldersLine(folders, counts: [busy.id: 1, quiet.id: 2], showingQuiet: false) == nil)
    }
}
