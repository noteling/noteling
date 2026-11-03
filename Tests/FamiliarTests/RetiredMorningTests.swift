import Foundation
import Testing
@testable import Familiar

/// What earlier versions kept and this one no longer reads: deleted once at launch, leaving the Morning folder's own
/// database for the person. Temp folders only.
@Suite struct RetiredMorningTests {
    @Test func whatEarlierVersionsKeptIsDeletedOnceAndTheMorningFolderIsLeft() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("retired-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        for folder in ["cards/inbox/pack-shop", "attention", "calendar", "runs/2026-09-29_09-00-00", "morning", "jobs"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try Data("{}".utf8).write(to: home.appendingPathComponent("cards/inbox/pack-shop/order-1.json"))
        try Data("x".utf8).write(to: home.appendingPathComponent("morning/morning.sqlite"))
        #expect(RetiredMorning.cleanUp(home: home) == ["cards", "attention", "calendar", "runs"])
        let left = try FileManager.default.contentsOfDirectory(atPath: home.path).sorted()
        #expect(left == ["jobs", "morning"])
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("morning/morning.sqlite").path))
        #expect(RetiredMorning.cleanUp(home: home).isEmpty)
    }
}
