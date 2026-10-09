import Foundation
import FamiliarContracts

/// A streamed Messages API reply put back together, event by event, into the same message a request without streaming
/// returns: content blocks in order (text, thinking with its signature, tool calls with their input parsed), the stop
/// reason and the usage. `text` is what has been written so far, for showing the answer as it arrives.
package struct MessageStream {
    private var started: [String: Any]?
    private var blocks: [Int: [String: Any]] = [:]
    private var partialInput: [Int: String] = [:]
    private var stopReason: Any?
    private var stopDetails: Any?
    private var usage: [String: Any] = [:]
    private var stopped = false

    package init() {}

    /// The text blocks so far, joined the way the finished reply's text is.
    package var text: String {
        blocks.keys.sorted().compactMap { i in blocks[i]?["type"] as? String == "text" ? blocks[i]?["text"] as? String : nil }
            .joined(separator: "\n")
    }

    /// The whole message once the stream has said it's done; nil while it is still coming, or if it broke off.
    package var message: [String: Any]? {
        guard stopped, var message = started else { return nil }
        message["content"] = blocks.keys.sorted().compactMap { blocks[$0] }
        message["stop_reason"] = stopReason ?? NSNull()
        if let stopDetails { message["stop_details"] = stopDetails }
        message["usage"] = usage
        return message
    }

    /// One line of the event stream (`data: {…}`; `event:` lines and blank lines carry nothing more). True when the
    /// text changed.
    @discardableResult
    package mutating func apply(line: String) throws -> Bool {
        guard line.hasPrefix("data:") else { return false }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return try apply(event: event)
    }

    /// One event. True when the text changed.
    @discardableResult
    package mutating func apply(event: [String: Any]) throws -> Bool {
        let index = event["index"] as? Int ?? 0
        switch event["type"] as? String {
        case "message_start":
            started = event["message"] as? [String: Any] ?? [:]
            usage = started?["usage"] as? [String: Any] ?? [:]
            return false
        case "content_block_start":
            blocks[index] = event["content_block"] as? [String: Any] ?? [:]
            return blocks[index]?["type"] as? String == "text"
        case "content_block_delta":
            guard var block = blocks[index], let delta = event["delta"] as? [String: Any] else { return false }
            var textChanged = false
            switch delta["type"] as? String {
            case "text_delta":
                block["text"] = (block["text"] as? String ?? "") + (delta["text"] as? String ?? "")
                textChanged = true
            case "input_json_delta":
                partialInput[index, default: ""] += delta["partial_json"] as? String ?? ""
            case "thinking_delta":
                block["thinking"] = (block["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
            case "signature_delta":
                block["signature"] = (block["signature"] as? String ?? "") + (delta["signature"] as? String ?? "")
            case "citations_delta":
                if let citation = delta["citation"] { block["citations"] = (block["citations"] as? [Any] ?? []) + [citation] }
            default:
                break
            }
            blocks[index] = block
            return textChanged
        case "content_block_stop":
            // A tool call's input arrives as pieces of JSON; it is whole once its block stops.
            if let json = partialInput.removeValue(forKey: index), var block = blocks[index] {
                let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
                block["input"] = trimmed.isEmpty ? [String: Any]()
                    : ((try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any] ?? [:])
                blocks[index] = block
            }
            return false
        case "message_delta":
            if let delta = event["delta"] as? [String: Any] {
                if let reason = delta["stop_reason"], !(reason is NSNull) { stopReason = reason }
                if let details = delta["stop_details"], !(details is NSNull) { stopDetails = details }
            }
            for (key, value) in event["usage"] as? [String: Any] ?? [:] where !(value is NSNull) { usage[key] = value }
            return false
        case "message_stop":
            stopped = true
            return false
        case "error":
            let error = event["error"] as? [String: Any] ?? [:]
            let kind = error["type"] as? String ?? "error"
            let message = error["message"] as? String ?? "The answer stopped with an error."
            throw ClaudeError(message: "API error (\(kind)): \(message)")
        default:   // ping, and anything newer
            return false
        }
    }
}
