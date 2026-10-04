import Foundation
import Testing
@testable import Familiar

/// A price a script returns reaches the model as the script wrote it: 19.99, never 19.989999999999998. Apple's JSON
/// writer prints doubles with 17 significant digits, so Noteling writes the JSON it hands on itself.
@Suite @MainActor
struct ScriptNumbersTests {
    private func pack(_ script: String) async throws -> (ScriptRunner, ScriptTool, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("script-numbers-\(UUID())")
        let pack = root.appendingPathComponent("shop")
        try FileManager.default.createDirectory(at: pack.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try "---\nname: Shop\n---\nFixture.".write(to: pack.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try script.write(to: pack.appendingPathComponent("scripts/prices.py"), atomically: true, encoding: .utf8)
        let runner = ScriptRunner(config: Config())
        let registry = ToolRegistry(root: root, runner: runner)
        await registry.reload()
        return (runner, try #require(registry.script(named: "shop__prices")), root)
    }

    @Test func pricesAScriptReturnsReachTheModelAsWritten() async throws {
        let (runner, script, root) = try await pack("""
        def run() -> dict:
            \"\"\"Prices.\"\"\"
            return {"price": 19.99, "was": 247.89, "count": 3, "in_stock": True, "badge": None, "offers": [1.1, "Deal"]}
        """)
        defer { try? FileManager.default.removeItem(at: root) }

        let text = try await runner.run(script, args: [:], context: nil)
        #expect(text.contains("\"price\": 19.99") && text.contains("\"was\": 247.89"))
        #expect(text.contains("\"count\": 3") && text.contains("\"in_stock\": true") && text.contains("\"badge\": null"))
        #expect(text.contains("1.1") && text.contains("\"Deal\""))
        #expect(!text.contains("19.98999") && !text.contains("247.88999") && !text.contains("1.100000"))
    }

    @Test func aNumberGivenToAScriptArrivesAsGiven() async throws {
        let (runner, script, root) = try await pack("""
        def run(price: float = 0.0) -> str:
            \"\"\"Echoes the price it was given, as Python reads it.\"\"\"
            return repr(price)
        """)
        defer { try? FileManager.default.removeItem(at: root) }

        let text = try await runner.run(script, args: ["price": 19.99], context: nil)
        #expect(text.contains("\"19.99\""))
    }

    @Test func thePensBriefCarriesPricesAsWritten() {
        #expect(PageBriefs.result(of: "{\"result\": {\"was\": 19.99, \"price\": 247.89}}") == "{\"price\":247.89,\"was\":19.99}")
    }

    @Test func aChecksRawAnswerCarriesPricesAsWritten() {
        let result = NoteCheckResult.parse("{\"result\": {\"price\": 19.99}}", script: "shop__prices")
        #expect(result.raw == "{\"price\":19.99}")
    }
}
