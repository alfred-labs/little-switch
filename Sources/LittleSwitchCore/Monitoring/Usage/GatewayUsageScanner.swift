import Foundation
import LittleSwitchCommon

/// Reads provider-reported token usage out of a recorded client response.
///
/// The gateway stays protocol-transparent, so usage is not parsed on the hot
/// path: it is recovered afterwards from the bytes the client already received.
/// Buffered JSON bodies are decoded whole. Streams are not: a `response.completed`
/// frame can carry the entire answer on one line, so the usage object is lifted
/// out by brace matching instead of parsing megabytes of transcript. Both ends
/// are read, because Anthropic reports input tokens in the opening `message_start`
/// frame and output tokens in the closing `message_delta`.
package enum GatewayUsageScanner {
    private static let marker = Data("\"usage\"".utf8)

    package static func totals(in body: Data) -> GatewayUsageTotals? {
        guard !body.isEmpty else { return nil }
        let document = try? JSONSerialization.jsonObject(with: body)
        if let document, let totals = totals(inDocument: document) {
            return totals
        }
        return streamTotals(in: body)
    }

    private static func streamTotals(in body: Data) -> GatewayUsageTotals? {
        let ranges = [
            body.range(of: marker),
            body.range(of: marker, options: .backwards),
        ]
        var merged: GatewayUsageTotals?
        for range in ranges.compactMap(\.self) {
            guard let sample = totals(after: range.upperBound, in: body) else { continue }
            merged = merged?.merging(sample) ?? sample
        }
        return merged
    }

    /// Parses the object that follows a `"usage"` key, and nothing else.
    /// ToolSearch calls in a recorded client response, counted by marker so
    /// neither buffered bodies nor streams need deserializing: the model's
    /// `tool_use` blocks carry the client tool's exact name, once per call,
    /// in JSON responses and in `content_block_start` frames alike. The
    /// request history is never scanned, so a call is counted when the model
    /// makes it, not again when the transcript replays it.
    package static func toolSearchCalls(in body: Data) -> Int {
        guard !body.isEmpty else { return 0 }
        let marker = Data("\"name\":\"ToolSearch\"".utf8)
        var count = 0
        var searchStart = body.startIndex
        while let range = body.range(of: marker, in: searchStart..<body.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    private static func totals(after index: Data.Index, in body: Data) -> GatewayUsageTotals? {
        guard let object = objectSlice(after: index, in: body),
            let document = try? JSONSerialization.jsonObject(with: object),
            let usage = document as? [String: Any]
        else {
            return nil
        }
        return totals(inUsage: usage)
    }

    /// The balanced `{…}` that follows `index`, quote-aware so a brace inside a
    /// string cannot end it early. Nil when the object is unterminated.
    private static func objectSlice(after index: Data.Index, in body: Data) -> Data? {
        var cursor = index
        while cursor < body.endIndex, body[cursor] != UInt8(ascii: "{") {
            guard isBlank(body[cursor]) || body[cursor] == UInt8(ascii: ":") else { return nil }
            cursor = body.index(after: cursor)
        }
        guard cursor < body.endIndex else { return nil }
        let start = cursor
        var depth = 0
        var inString = false
        var escaped = false
        while cursor < body.endIndex {
            let byte = body[cursor]
            if escaped {
                escaped = false
            } else if inString {
                escaped = byte == UInt8(ascii: "\\")
                inString = byte != UInt8(ascii: "\"")
            } else if byte == UInt8(ascii: "\"") {
                inString = true
            } else if byte == UInt8(ascii: "{") {
                depth += 1
            } else if byte == UInt8(ascii: "}") {
                depth -= 1
                if depth == 0 {
                    return Data(body[start...cursor])
                }
            }
            cursor = body.index(after: cursor)
        }
        return nil
    }

    private static func isBlank(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\t")
            || byte == UInt8(ascii: "\n")
    }

    private static func totals(inDocument document: Any) -> GatewayUsageTotals? {
        guard let object = document as? [String: Any] else { return nil }
        if let usage = object["usage"] as? [String: Any], let totals = totals(inUsage: usage) {
            return totals
        }
        for key in ["response", "message"] {
            guard let nested = object[key] as? [String: Any],
                let usage = nested["usage"] as? [String: Any],
                let totals = totals(inUsage: usage)
            else {
                continue
            }
            return totals
        }
        return nil
    }

    private static func totals(inUsage usage: [String: Any]) -> GatewayUsageTotals? {
        let details = detailCounts(in: usage)
        // Anthropic reports cache counters beside `input_tokens`; OpenAI and the
        // Responses API report them as a breakdown *of* the input count. Only the
        // breakdown is subtracted, so the four fields stay disjoint either way.
        let cacheRead = count(usage["cache_read_input_tokens"]) ?? details.read ?? 0
        let cacheWrite = count(usage["cache_creation_input_tokens"]) ?? details.write ?? 0
        let output = count(usage["output_tokens"]) ?? count(usage["completion_tokens"]) ?? 0
        let included = (details.read ?? 0) + (details.write ?? 0)
        guard let reportedInput = count(usage["input_tokens"]) ?? count(usage["prompt_tokens"]) else {
            guard output > 0 || cacheRead > 0 || cacheWrite > 0 else { return nil }
            return GatewayUsageTotals(
                outputTokens: output,
                cacheReadTokens: cacheRead,
                cacheWriteTokens: cacheWrite
            )
        }
        return GatewayUsageTotals(
            inputTokens: max(0, reportedInput - included),
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite
        )
    }

    private static func detailCounts(in usage: [String: Any]) -> (read: Int?, write: Int?) {
        for key in ["input_tokens_details", "prompt_tokens_details"] {
            guard let details = usage[key] as? [String: Any] else { continue }
            return (count(details["cached_tokens"]), count(details["cache_write_tokens"]))
        }
        return (nil, nil)
    }

    private static func count(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let reported = number.intValue
        return reported >= 0 ? reported : nil
    }
}
