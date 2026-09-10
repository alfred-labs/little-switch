import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic initial usage normalizer")
// swiftlint:disable:next type_body_length
struct AnthropicInitialUsageNormalizerTests {
    @Test("Empty EOF and passthrough chunks remain empty")
    func emptyPassthrough() {
        var normalizer = AnthropicInitialUsageNormalizer()

        #expect(normalizer.finish().isEmpty)
        #expect(normalizer.append(Data()) == .output([]))
    }

    @Test("A positive Example start is byte-for-byte passthrough across irregular chunks")
    func nativePositiveStartIsExact() throws {
        let start = frame(
            event: "message_start",
            json:
                #"{"type":"message_start","message":{"id":"msg_example","usage":{"input_tokens":49800,"output_tokens":0},"content":[]}}"#
        )
        let content = frame(
            event: "content_block_delta",
            json: #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hello"}}"#
        )
        let terminal = frame(
            event: "message_delta",
            json: #"{"type":"message_delta","usage":{"output_tokens":13}}"#
        )
        let wire = start + content + terminal
        var normalizer = AnthropicInitialUsageNormalizer()
        var output = Data()
        var nativeCount: Int?

        for chunk in chunks(wire, sizes: [1, 2, 7, 3, 19, 5]) {
            switch normalizer.append(chunk) {
            case .buffering:
                break
            // swiftlint:disable:next pattern_matching_keywords
            case .native(let inputTokens, let emitted):
                nativeCount = inputTokens
                output.append(emitted)
            case .output(let emitted):
                output.append(emitted)
            case .estimateRequired:
                Issue.record("A positive start must not request an estimate")
            }
        }
        output.append(normalizer.finish())

        #expect(nativeCount == 49_800)
        #expect(output == wire)
    }

    @Test("A CRLF native start remains exact when every byte is a separate chunk")
    func nativeCRLFStartIsExact() {
        let start = frame(
            event: "message_start",
            json: #"{"type":"message_start","message":{"id":"msg","usage":{"input_tokens":8}}}"#,
            lineEnding: "\r\n"
        )
        let later = frame(
            event: "message_delta",
            json: #"{"type":"message_delta","usage":{"output_tokens":1}}"#,
            lineEnding: "\r\n"
        )
        let wire = start + later
        var normalizer = AnthropicInitialUsageNormalizer()
        var output = Data()

        for byte in wire {
            switch normalizer.append(Data([byte])) {
            case .buffering:
                break
            // swiftlint:disable:next pattern_matching_keywords
            case .native(let inputTokens, let emitted):
                #expect(inputTokens == 8)
                output.append(emitted)
            case .output(let emitted):
                output.append(emitted)
            case .estimateRequired:
                Issue.record("Native CRLF start requested an estimate")
            }
        }

        #expect(output == wire)
    }

    @Test("A zero z.ai start rewrites one field and leaves every later byte untouched")
    func zeroStartUsesProviderEstimate() throws {
        // Exact provider framing is clearer as one source line.
        // swiftlint:disable line_length
        let startText = """
            event: message_start\r
            id: provider-start\r
            data: {"input_tokens":0,"message" : {"id":"msg_zai","model":"glm","usage" : {"output_tokens":0,"input_tokens" : 0,"cache_creation_input_tokens":3,"cache_read_input_tokens":4},"content":[]},"type":"message_start"}\r
            \r

            """
        // swiftlint:enable line_length
        let start = Data(startText.utf8)
        let content = frame(
            event: "content_block_delta",
            json: #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"later"}}"#
        )
        let terminal = frame(
            event: "message_delta",
            json: #"{"type":"message_delta","usage":{"input_tokens":41,"output_tokens":7}}"#
        )
        var normalizer = AnthropicInitialUsageNormalizer()

        #expect(normalizer.append(start + content + terminal) == .estimateRequired)
        let output = joined(
            normalizer.resolve(
                .providerEstimate(tokens: 9, elapsedMilliseconds: 18)
            )
        )
        let expectedStart = Data(
            startText.replacingOccurrences(
                of: #""input_tokens" : 0"#,
                with: #""input_tokens" : 9"#
            ).utf8
        )

        let objects = try eventObjects(output)
        let rewrittenStart = try #require(objects.first)
        let message = try #require(rewrittenStart["message"] as? [String: Any])
        let usage = try #require(message["usage"] as? [String: Any])
        #expect(usage["input_tokens"] as? Int == 9)
        #expect(usage["cache_creation_input_tokens"] as? Int == 3)
        #expect(usage["cache_read_input_tokens"] as? Int == 4)
        #expect(usage["output_tokens"] as? Int == 0)
        #expect(output.prefix(expectedStart.count) == expectedStart)
        #expect(output.suffix(content.count + terminal.count) == content + terminal)
        #expect(output == expectedStart + content + terminal)
        #expect(normalizer.finish().isEmpty)
    }

    @Test("Cached terminal usage is never added to the rewritten start")
    func cachedTerminalUsageIsUntouched() throws {
        let start = frame(
            event: "message_start",
            json:
                #"{"type":"message_start","message":{"id":"msg_cache","usage":{"input_tokens":0,"output_tokens":0},"content":[]}}"#
        )
        let terminal = frame(
            event: "message_delta",
            json:
                #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":41,"cache_read_input_tokens":1472,"output_tokens":7}}"#
        )
        var normalizer = AnthropicInitialUsageNormalizer()

        #expect(normalizer.append(start + terminal) == .estimateRequired)
        let output = joined(
            normalizer.resolve(
                .localEstimate(
                    tokens: 1_506,
                    providerOutcome: .timeout,
                    elapsedMilliseconds: 1_000
                )
            )
        )
        let text = try #require(String(data: output, encoding: .utf8))

        #expect(text.contains(#""input_tokens":1506"#))
        #expect(!text.contains("1547"))
        #expect(occurrences(of: terminal, in: output) == 1)
    }

    @Test("Comments, pings, CRLF, and multiline data may precede one zero start")
    func validFramingMatrix() throws {
        let comment = Data(": keep-alive\r\n\r\n".utf8)
        let ping = frame(
            event: "ping",
            json: #"{"type":"ping"}"#,
            lineEnding: "\r\n"
        )
        let multiline = Data(
            ("event: message_start\r\n"
                + "data: {\"type\":\"message_start\",\r\n"
                + "data: \"message\":{\"id\":\"msg\",\"content\":[],\"usage\":{\"input_tokens\":0}}}\r\n\r\n")
                .utf8
        )
        let later = frame(event: "ping", json: #"{"type":"ping"}"#)
        let wire = comment + ping + multiline + later
        var normalizer = AnthropicInitialUsageNormalizer()
        var decision: AnthropicInitialUsageNormalizer.Decision = .buffering
        var consumedCount = 0

        for (index, byte) in wire.enumerated() {
            decision = normalizer.append(Data([byte]))
            if decision == .estimateRequired {
                consumedCount = index + 1
                break
            }
        }

        #expect(decision == .estimateRequired)
        let output = joined(normalizer.resolve(.providerEstimate(tokens: 12, elapsedMilliseconds: 2)))
        let expectedMultiline = Data(
            multilineText(inputTokens: 12).utf8
        )
        #expect(output == comment + ping + expectedMultiline)
        #expect(try startInputTokens(output) == 12)

        let remaining = Data(wire.dropFirst(consumedCount))
        if !remaining.isEmpty {
            guard case .output(let emitted) = normalizer.append(remaining) else {
                Issue.record("Expected permanent passthrough")
                return
            }
            #expect(joined(emitted) == remaining)
        }
    }

    @Test("Malformed, unknown, terminal, and invalid-count prefixes fail open exactly")
    func invalidPrefixesFailOpen() {
        let invalidWires = [
            frame(event: "unknown", json: #"{"type":"unknown"}"#),
            frame(event: "message_start", json: #"{"type":"ping"}"#),
            frame(event: "ping", json: #"{"type":"message_start"}"#),
            frame(event: "message_start", json: "{"),
            frame(event: "message_start", json: #"{"type":"message_start"}"#),
            frame(event: "message_start", json: #"{"type":"message_start","message":{}}"#),
            frame(event: "message_start", json: #"{"type":"message_start","message":{"usage":{}}}"#),
            frame(event: "message_start", json: #"{"type":"message_start","message":{"usage":{"input_tokens":true}}}"#),
            frame(event: "message_start", json: #"{"type":"message_start","message":{"usage":{"input_tokens":-1}}}"#),
            frame(event: "message_start", json: #"{"type":"message_start","message":{"usage":{"input_tokens":1.5}}}"#),
            frame(event: "message_start", json: #"{"type":"message_start","message":{"usage":{"input_tokens":"0"}}}"#),
            Data("data: [DONE]\n\n".utf8),
            Data("event: ping\n\n".utf8),
        ]

        for wire in invalidWires {
            var normalizer = AnthropicInitialUsageNormalizer()
            #expect(normalizer.append(wire) == .output([wire]))
            let suffix = Data("opaque".utf8)
            #expect(normalizer.append(suffix) == .output([suffix]))
            #expect(normalizer.finish().isEmpty)
        }
    }

    @Test("EOF mid-frame flushes the original prefix without throwing")
    func incompleteEOFFailsOpen() {
        let wire = Data("event: message_start\ndata: {\"type\":\"message_start\"".utf8)
        var normalizer = AnthropicInitialUsageNormalizer()

        #expect(normalizer.append(wire) == .buffering)
        #expect(normalizer.finish() == [wire])
    }

    @Test("The prefix limit accepts exactly 64 KiB and fails open at the next byte")
    func prefixBoundary() {
        let exact = Data(repeating: 0x61, count: 64 * 1_024)
        var accepted = AnthropicInitialUsageNormalizer()
        #expect(accepted.append(exact) == .buffering)
        #expect(accepted.finish() == [exact])

        var rejected = AnthropicInitialUsageNormalizer()
        #expect(rejected.append(exact + Data([0x62])) == .output([exact + Data([0x62])]))
    }

    @Test("A complete message start crossing the prefix limit also fails open exactly")
    func completeFrameBeyondPrefixBoundary() {
        let oversized = frame(
            event: "message_start",
            json:
                #"{"type":"message_start","message":{"usage":{"input_tokens":0}},"padding":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}"#
        )
        var normalizer = AnthropicInitialUsageNormalizer(
            maximumPrefixBytes: oversized.count - 1
        )

        #expect(normalizer.append(oversized) == .output([oversized]))
    }

    @Test("Comments that push a valid start past the prefix boundary fail open exactly")
    func commentsPushStartBeyondPrefixBoundary() {
        let comments =
            Data(":".utf8)
            + Data(repeating: 0x20, count: 80)
            + Data("\n\n".utf8)
        let start = frame(
            event: "message_start",
            json: #"{"type":"message_start","message":{"usage":{"input_tokens":0}}}"#
        )
        let wire = comments + start
        var normalizer = AnthropicInitialUsageNormalizer(maximumPrefixBytes: comments.count + 8)

        #expect(normalizer.append(wire) == .output([wire]))
        #expect(normalizer.append(Data("later".utf8)) == .output([Data("later".utf8)]))
    }

    @Test("Resolution after EOF restores the original zero start")
    func finishWhileWaitingFailsOpen() {
        let start = frame(
            event: "message_start",
            json: #"{"type":"message_start","message":{"usage":{"input_tokens":0}}}"#
        )
        var normalizer = AnthropicInitialUsageNormalizer()
        #expect(normalizer.append(start) == .estimateRequired)
        #expect(normalizer.finish() == [start])
        #expect(normalizer.resolve(.providerEstimate(tokens: 7, elapsedMilliseconds: 1)).isEmpty)
    }

    @Test("Bytes arriving while counting are retained and a negative resolution fails open")
    func bufferedSuffixAndNegativeResolution() {
        let start = frame(
            event: "message_start",
            json: #"{"type":"message_start","message":{"usage":{"input_tokens":0}}}"#
        )
        let suffix = frame(event: "ping", json: #"{"type":"ping"}"#)
        var normalizer = AnthropicInitialUsageNormalizer()

        #expect(normalizer.append(start) == .estimateRequired)
        #expect(normalizer.append(suffix) == .estimateRequired)
        #expect(joined(normalizer.resolve(.native(-1))) == start + suffix)
    }

    @Test("The earliest mixed line-ending boundary is classified first")
    func mixedBoundaryOrdering() throws {
        let ping = frame(event: "ping", json: #"{"type":"ping"}"#)
        let start = frame(
            event: "message_start",
            json: #"{"type":"message_start","message":{"usage":{"input_tokens":0}}}"#,
            lineEnding: "\r\n"
        )
        var normalizer = AnthropicInitialUsageNormalizer()

        #expect(normalizer.append(ping + start) == .estimateRequired)
        let startText = try #require(String(data: start, encoding: .utf8))
        let rewritten = Data(
            startText
                .replacingOccurrences(of: #""input_tokens":0"#, with: #""input_tokens":5"#)
                .utf8
        )
        #expect(joined(normalizer.resolve(.native(5))) == ping + rewritten)
    }

    @Test("An extension field without a colon is ignored before message start")
    func extensionFieldWithoutColon() {
        let extensionFrame = Data("opaque\n\n".utf8)
        let start = frame(
            event: "message_start",
            json: #"{"type":"message_start","message":{"usage":{"input_tokens":0}}}"#
        )
        var normalizer = AnthropicInitialUsageNormalizer()

        #expect(normalizer.append(extensionFrame + start) == .estimateRequired)
        let output = joined(normalizer.resolve(.native(3)))
        #expect(output.starts(with: extensionFrame))
    }

    @Test("Invalid UTF-8 SSE field names and event values fail open")
    func invalidUTF8FieldsFailOpen() {
        for wire in [
            Data([0xFF, 0x3A, 0x20, 0x78, 0x0A, 0x0A]),
            Data("event: ".utf8) + Data([0xFF, 0x0A, 0x0A]),
        ] {
            var normalizer = AnthropicInitialUsageNormalizer()
            #expect(normalizer.append(wire) == .output([wire]))
        }
    }

    @Test("Duplicate input-token members are rejected instead of patching ambiguously")
    func duplicateInputTokenMembersFailOpen() {
        let wire = frame(
            event: "message_start",
            json:
                #"{"type":"message_start","message":{"usage":{"input_tokens":0,"input_tokens":0}}}"#
        )
        var normalizer = AnthropicInitialUsageNormalizer()

        #expect(normalizer.append(wire) == .output([wire]))
    }

    private func frame(
        event: String,
        json: String,
        lineEnding: String = "\n"
    ) -> Data {
        Data(
            ("event: \(event)\(lineEnding)"
                + "data: \(json)\(lineEnding)\(lineEnding)").utf8
        )
    }

    private func multilineText(inputTokens: Int) -> String {
        "event: message_start\r\n"
            + "data: {\"type\":\"message_start\",\r\n"
            + "data: \"message\":{\"id\":\"msg\",\"content\":[],\"usage\":{\"input_tokens\":\(inputTokens)}}}\r\n\r\n"
    }

    private func chunks(_ data: Data, sizes: [Int]) -> [Data] {
        var chunks: [Data] = []
        var offset = 0
        var index = 0
        while offset < data.count {
            let size = sizes[index % sizes.count]
            let end = min(data.count, offset + size)
            chunks.append(Data(data[offset..<end]))
            offset = end
            index += 1
        }
        return chunks
    }

    private func joined(_ values: [Data]) -> Data {
        values.reduce(into: Data()) { $0.append($1) }
    }

    private func eventObjects(_ wire: Data) throws -> [[String: Any]] {
        let text = try #require(String(data: wire, encoding: .utf8))
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return
            try text
            .components(separatedBy: "\n\n")
            .compactMap { frame -> [String: Any]? in
                let dataLines = frame.split(separator: "\n").filter { $0.hasPrefix("data: ") }
                guard !dataLines.isEmpty else {
                    return nil
                }
                let payload = dataLines.map { String($0.dropFirst(6)) }.joined(separator: "\n")
                return try JSONSerialization.jsonObject(
                    with: Data(payload.utf8)
                ) as? [String: Any]
            }
    }

    private func startInputTokens(_ wire: Data) throws -> Int {
        let start = try #require(
            eventObjects(wire).first { $0["type"] as? String == "message_start" }
        )
        let message = try #require(start["message"] as? [String: Any])
        let usage = try #require(message["usage"] as? [String: Any])
        return try #require(usage["input_tokens"] as? Int)
    }

    private func occurrences(of needle: Data, in haystack: Data) -> Int {
        guard !needle.isEmpty, haystack.count >= needle.count else { return 0 }
        var count = 0
        var start = haystack.startIndex
        while start <= haystack.endIndex - needle.count {
            let end = start + needle.count
            if haystack[start..<end].elementsEqual(needle) {
                count += 1
                start = end
            } else {
                start += 1
            }
        }
        return count
    }
}

extension Data {
    fileprivate mutating func append(_ values: [Data]) {
        for value in values {
            append(value)
        }
    }
}
