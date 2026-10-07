import Foundation
import Testing
import FamiliarContracts
import FamiliarRuntime

/// A streamed reply put back together is the same message a request without streaming returns, and its text is there
/// as it grows: from the API's events, and from the Claude Code CLI's partial-message lines.
@Suite
struct MessageStreamTests {
    private func line(_ event: [String: Any]) throws -> String {
        "data: " + String(decoding: try JSONSerialization.data(withJSONObject: event), as: UTF8.self)
    }

    @Test
    func textThinkingAndAToolCallComeBackWhole() throws {
        var stream = MessageStream()
        let events: [[String: Any]] = [
            ["type": "message_start", "message": ["id": "m1", "role": "assistant", "content": [Any](), "usage": ["input_tokens": 12, "cache_read_input_tokens": 3]]],
            ["type": "content_block_start", "index": 0, "content_block": ["type": "thinking", "thinking": "", "signature": ""]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "thinking_delta", "thinking": ""]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "signature_delta", "signature": "sig-abc"]],
            ["type": "content_block_stop", "index": 0],
            ["type": "content_block_start", "index": 1, "content_block": ["type": "text", "text": ""]],
            ["type": "content_block_delta", "index": 1, "delta": ["type": "text_delta", "text": "Checking "]],
            ["type": "content_block_delta", "index": 1, "delta": ["type": "text_delta", "text": "the price."]],
            ["type": "content_block_stop", "index": 1],
            ["type": "content_block_start", "index": 2, "content_block": ["type": "tool_use", "id": "t1", "name": "shop__price", "input": [String: Any](), "toolset_name": "fixture"]],
            ["type": "content_block_delta", "index": 2, "delta": ["type": "input_json_delta", "partial_json": "{\"offer\": \"o"]],
            ["type": "content_block_delta", "index": 2, "delta": ["type": "input_json_delta", "partial_json": "1\", \"zip\": 7960}"]],
            ["type": "content_block_stop", "index": 2],
            ["type": "message_delta", "delta": ["stop_reason": "tool_use", "stop_sequence": NSNull()], "usage": ["output_tokens": 41]],
        ]
        var texts: [String] = []
        for event in events where try stream.apply(line: try line(event)) { texts.append(stream.text) }
        #expect(stream.message == nil)   // not whole until the stream says it's done
        try stream.apply(line: "event: message_stop")
        try stream.apply(line: try line(["type": "message_stop"]))

        let message = try #require(stream.message)
        let content = try #require(message["content"] as? [[String: Any]])
        #expect(content.map { $0["type"] as? String } == ["thinking", "text", "tool_use"])
        #expect(content[0]["signature"] as? String == "sig-abc")
        #expect(content[1]["text"] as? String == "Checking the price.")
        let input = try #require(content[2]["input"] as? [String: Any])
        #expect(input["offer"] as? String == "o1" && input["zip"] as? Int == 7960)
        #expect(content[2]["toolset_name"] as? String == "fixture")
        #expect(message["stop_reason"] as? String == "tool_use")
        let usage = try #require(message["usage"] as? [String: Any])
        #expect(usage["input_tokens"] as? Int == 12 && usage["cache_read_input_tokens"] as? Int == 3 && usage["output_tokens"] as? Int == 41)
        #expect(texts == ["", "Checking ", "Checking the price."])
    }

    @Test
    func aToolCallWithNoInputHasAnEmptyOne() throws {
        var stream = MessageStream()
        try stream.apply(event: ["type": "message_start", "message": ["content": [Any]()]])
        try stream.apply(event: ["type": "content_block_start", "index": 0, "content_block": ["type": "tool_use", "id": "t", "name": "look_at_screen", "input": [String: Any]()]])
        try stream.apply(event: ["type": "content_block_delta", "index": 0, "delta": ["type": "input_json_delta", "partial_json": ""]])
        try stream.apply(event: ["type": "content_block_stop", "index": 0])
        try stream.apply(event: ["type": "message_stop"])
        let block = try #require((stream.message?["content"] as? [[String: Any]])?.first)
        #expect((block["input"] as? [String: Any])?.isEmpty == true)
    }

    @Test
    func anErrorInTheStreamIsSaidPlainly() {
        var stream = MessageStream()
        #expect(throws: ClaudeError.self) {
            try stream.apply(event: ["type": "error", "error": ["type": "overloaded_error", "message": "Overloaded"]])
        }
    }

    @Test
    func theCLIsPartialLinesShowTheAnswerAsItGrows() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cli-partials-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let writer = try FileHandle(forWritingTo: file)
        defer { try? writer.close() }
        func lines(_ objects: [[String: Any]]) throws -> String {
            try objects.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        }
        func write(_ objects: [[String: Any]]) throws { writer.write(Data(try lines(objects).utf8)) }
        func delta(_ text: String) -> [String: Any] {
            ["type": "stream_event", "event": ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": text]]]
        }
        let start: [String: Any] = ["type": "stream_event", "event": ["type": "message_start", "message": ["content": [Any]()]]]
        let block: [String: Any] = ["type": "stream_event", "event": ["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": ""]]]

        var partials = CLIPartials(output: file)
        #expect(partials.read() == nil)
        try write([["type": "system", "subtype": "init"], start, block, delta("It's ")])
        #expect(partials.read() == "It's ")
        let next = Data(try lines([delta("ADS Inc's offer.")]).utf8)
        writer.write(next.prefix(next.count / 2))   // half a line: read only once it's whole
        #expect(partials.read() == nil)
        writer.write(next.suffix(from: next.count / 2))
        #expect(partials.read() == "It's ADS Inc's offer.")
        // a new model turn (after a tool call) starts from nothing
        try write([start, block, delta("Done.")])
        #expect(partials.read() == "Done.")
    }
}
