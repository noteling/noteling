import Combine
import Foundation
import Testing
@testable import Familiar

/// A job's latest finding is a sticky note beside the bubble: one per job whose latest output has a preview, newest
/// first, written as from whoever shared the job. Putting one away remembers what it was about, so it comes back only
/// when the job finds something else, even after a relaunch.
@Suite @MainActor
struct RunStickersTests {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func job(_ name: String, on: Bool = true, preview: String? = "d1", said: String? = "2 of 8 prices wrong",
                     ran: TimeInterval? = 0, starts: String? = nil, ends: String? = nil, by: [String] = []) -> FolderJob {
        var job = FolderJob(id: JobFiles.derivedID(name), source: by.isEmpty ? .own : .team, path: name.lowercased(), name: name)
        job.on = on
        job.contributors = by
        job.starts = starts.flatMap(JobMoment.parse)
        job.ends = ends.flatMap(JobMoment.parse)
        if let ran {
            job.state.lastRunAt = at.addingTimeInterval(ran)
            job.state.lastSuccessAt = at.addingTimeInterval(ran)
        }
        job.state.said = said
        job.state.preview = preview
        return job
    }

    private func folder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("run-stickers-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func aJobWithAPreviewHasAStickerAndOneWithoutDoesNot() throws {
        let shared = job("Holiday Oct · GM", by: ["Yang", "Ana"])
        let sticker = try #require(RunStickers.sticker(for: shared, at: at))
        #expect(sticker.id == shared.id && sticker.jobName == "Holiday Oct · GM" && sticker.byline == "Yang and Ana")
        #expect(sticker.said == "2 of 8 prices wrong" && sticker.at == at && sticker.digest == "d1")

        let own = try #require(RunStickers.sticker(for: job("Pages up", said: nil), at: at))
        #expect(own.byline == nil && own.said == "Its preview has something new.")   // the notification's words

        #expect(RunStickers.sticker(for: job("Quiet", preview: nil), at: at) == nil)
    }

    @Test func offEndedAndNotStartedJobsHaveNone() {
        #expect(RunStickers.sticker(for: job("Off", on: false), at: at) == nil)
        #expect(RunStickers.sticker(for: job("Ended", ends: "2026-01-01"), at: at) == nil)
        #expect(RunStickers.sticker(for: job("Later", starts: "2036-01-01"), at: at) == nil)
        #expect(RunStickers.sticker(for: job("Not run", ran: nil), at: at) == nil)
        #expect(RunStickers.sticker(for: job("Live", starts: "2026-01-01", ends: "2036-01-01"), at: at) != nil)
    }

    @Test func theNewestComesFirstAndTiesGoByName() {
        let model = RunStickers(file: nil)
        model.update([job("Older", ran: -600), job("Newest", ran: 60), job("Beta"), job("Alpha"), job("Quiet", preview: nil)], at: at)
        #expect(model.stickers.map(\.jobName) == ["Newest", "Alpha", "Beta", "Older"])
    }

    @Test func puttingOneAwayHidesItUntilTheJobFindsSomethingElse() {
        let model = RunStickers(file: nil)
        model.update([job("GM"), job("Pages up")], at: at)
        #expect(model.stickers.map(\.jobName) == ["GM", "Pages up"])

        model.putAway(job("GM").id)
        #expect(model.stickers.map(\.jobName) == ["Pages up"])
        model.update([job("GM"), job("Pages up")], at: at)
        #expect(model.stickers.map(\.jobName) == ["Pages up"])   // the same finding stays away

        model.update([job("GM", preview: "d2", ran: 120), job("Pages up")], at: at)
        #expect(model.stickers.map(\.jobName) == ["GM", "Pages up"])   // a new finding is back
        model.putAway(job("GM").id)
        model.update([job("GM", preview: "d2", ran: 120), job("Pages up")], at: at)
        #expect(model.stickers.map(\.jobName) == ["Pages up"])        // and the newer digest is the one remembered
        model.update([job("GM", preview: "d1"), job("Pages up")], at: at)
        #expect(model.stickers.map(\.jobName) == ["GM", "Pages up"])
    }

    @Test func aPutAwayStickerStaysAwayAfterARelaunch() throws {
        let file = folder().appendingPathComponent("job-results/stickers.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent()) }
        let jobs = [job("GM", by: ["Yang"]), job("Pages up")]

        let first = RunStickers(file: file)
        first.update(jobs, at: at)
        first.putAway(job("GM").id)
        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String]
        #expect(written == [job("GM").id.uuidString: "d1"])

        let again = RunStickers(file: file)
        again.update(jobs, at: at)
        #expect(again.stickers.map(\.jobName) == ["Pages up"])
        again.update([job("GM", preview: "d2", ran: 60), job("Pages up")], at: at)
        #expect(again.stickers.map(\.jobName) == ["GM", "Pages up"])

        // A put-away for a job that is gone is forgotten; a missing file is nothing put away.
        again.update([job("Pages up")], at: at)
        let left = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String]
        #expect(left == [:])
        let fresh = RunStickers(file: file.deletingLastPathComponent().appendingPathComponent("none.json"))
        fresh.update(jobs, at: at)
        #expect(fresh.stickers.count == 2)
    }

    @Test func threeSitBesideTheBubbleAndTheRestAreMore() {
        let model = RunStickers(file: nil)
        model.update((1...5).map { job("Job \($0)", ran: TimeInterval($0)) }, at: at)
        #expect(model.stickers.count == 5)
        #expect(model.shown.map(\.jobName) == ["Job 5", "Job 4", "Job 3"])
        #expect(model.more == 2)

        model.update((1...2).map { job("Job \($0)", ran: TimeInterval($0)) }, at: at)
        #expect(model.shown.count == 2 && model.more == 0)
    }

    @Test func theSameJobsTwicePublishOnce() {
        let model = RunStickers(file: nil)
        var published = 0
        let watching = model.objectWillChange.sink { published += 1 }
        defer { watching.cancel() }
        let jobs = [job("GM"), job("Pages up")]

        model.update(jobs, at: at)
        model.update(jobs, at: at)
        model.update(jobs, at: at.addingTimeInterval(30))
        #expect(published == 1)

        model.update([job("GM")], at: at)
        #expect(published == 2)
    }
}
