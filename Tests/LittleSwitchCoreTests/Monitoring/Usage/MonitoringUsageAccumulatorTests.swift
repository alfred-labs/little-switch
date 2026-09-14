import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring incremental provider usage")
struct MonitoringUsageAccumulatorTests {
    @Test("Usage survives every byte boundary without retaining the response")
    func byteBoundaries() {
        let body = Data(
            #"{"response":{"output":[{"text":"private \\\"usage\\\": {ignored}"}],"usage":{"input_tokens":12,"output_tokens":7,"input_tokens_details":{"cached_tokens":4}}}}"#
                .utf8)
        for split in 0...body.count {
            var reader = MonitoringUsageAccumulator()
            reader.append(Data(body.prefix(split)))
            reader.append(Data(body.dropFirst(split)))
            reader.finish()
            #expect(reader.totals == GatewayUsageTotals(inputTokens: 8, outputTokens: 7, cacheReadTokens: 4))
            #expect(reader.retainedByteCount == 0)
            #expect(reader.invalidSampleCount == 0)
        }
    }

    @Test("Opening and terminal SSE usage are cumulative within one exchange")
    func cumulativeStream() {
        let body = """
            event: message_start
            data: {"type":"message_start","message":{"usage":{"input_tokens":9,"cache_read_input_tokens":3,"cache_creation_input_tokens":2,"output_tokens":0}}}

            event: message_delta
            data: {"usage":{"output_tokens":4}}

            data: {"usage":{"output_tokens":4}}

            data: [DONE]
            """
        var reader = MonitoringUsageAccumulator()
        for byte in body.utf8 { reader.append(Data([byte])) }
        reader.finish()
        #expect(
            reader.totals
                == GatewayUsageTotals(inputTokens: 9, outputTokens: 4, cacheReadTokens: 3, cacheWriteTokens: 2))
    }

    @Test("Text, tool content and nested arbitrary usage cannot become provider measurements")
    func falsePositives() {
        let bodies = [
            #"{"text":"\"usage\":{\"input_tokens\":99}"}"#,
            #"{"output":[{"usage":{"input_tokens":99}}]}"#,
            #"{"response":{"output":{"usage":{"input_tokens":99}}}}"#,
            #"{"arguments":{"message":{"usage":{"input_tokens":99}}}}"#,
            #"{"usage":{}}"#,
        ]
        for body in bodies {
            var reader = MonitoringUsageAccumulator()
            reader.append(Data(body.utf8))
            reader.finish()
            #expect(reader.totals == nil)
        }
    }

    @Test("An explicitly reported zero is distinct from missing usage")
    func reportedZero() {
        var reader = MonitoringUsageAccumulator()
        reader.append(Data(#"{"usage":{"input_tokens":0,"output_tokens":0}}"#.utf8))
        reader.finish()
        #expect(reader.totals == GatewayUsageTotals())
    }

    @Test("Invalid numeric measurements are never coerced into valid token counts")
    func invalidNumbers() {
        for value in ["-1", "1.5", "true", "\"12\"", "9223372036854775808", "null"] {
            var reader = MonitoringUsageAccumulator()
            reader.append(Data("{\"usage\":{\"input_tokens\":\(value)}}".utf8))
            reader.finish()
            #expect(reader.totals == nil)
            #expect(reader.invalidSampleCount == 1)
        }
    }

    @Test("Oversized and incomplete usage are bounded and do not poison the following frame")
    func limitsAndRecovery() {
        var reader = MonitoringUsageAccumulator(maximumUsageBytes: 128)
        let body =
            "data: {\"usage\":{\"padding\":\"" + String(repeating: "x", count: 4_096)
            + "\",\"input_tokens\":99}}\n\ndata: {\"usage\":{\"input_tokens\":3}}\n"
        for byte in body.utf8 {
            reader.append(Data([byte]))
            #expect(reader.retainedByteCount <= 384)
        }
        reader.append(Data("data: {\"usage\":{\"output_tokens\":".utf8))
        reader.finish()
        #expect(reader.totals == GatewayUsageTotals(inputTokens: 3))
        #expect(reader.invalidSampleCount == 2)
        #expect(reader.retainedByteCount == 0)
    }

    @Test("Escaped protocol keys and OpenAI cache breakdown remain recognizable")
    func escapedKeys() {
        var reader = MonitoringUsageAccumulator()
        reader.append(
            Data(
                #"{"us\u0061ge":{"prompt_tokens":20,"completion_tokens":6,"prompt_tokens_details":{"cached_tokens":5,"cache_write_tokens":2}}}"#
                    .utf8))
        reader.finish()
        #expect(
            reader.totals
                == GatewayUsageTotals(inputTokens: 13, outputTokens: 6, cacheReadTokens: 5, cacheWriteTokens: 2))
    }
}
