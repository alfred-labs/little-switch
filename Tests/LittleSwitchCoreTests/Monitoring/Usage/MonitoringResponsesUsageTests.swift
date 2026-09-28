import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring successive Responses usage")
struct MonitoringResponsesUsageTests {
    @Test("Automatic successors sum distinct response IDs while repeated snapshots remain cumulative")
    func successiveResponses() {
        let stream = """
            data: {"type":"response.created","response":{"id":"resp_original","usage":null}}

            data: {"type":"response.incomplete","response":{"id":"resp_original","usage":{"input_tokens":10,"output_tokens":3}}}

            data: {"type":"response.created","response":{"id":"resp_successor","usage":null}}

            data: {"type":"response.completed","response":{"usage":{"input_tokens":12,"output_tokens":4},"id":"resp_successor"}}

            data: {"type":"response.completed","response":{"id":"resp_original","usage":{"input_tokens":10,"output_tokens":2}}}
            """
        let bytes = Data(stream.utf8)
        for split in 0...bytes.count {
            var reader = MonitoringUsageAccumulator()
            reader.append(Data(bytes.prefix(split)))
            reader.append(Data(bytes.dropFirst(split)))
            reader.finish()
            #expect(reader.totals == .init(inputTokens: 22, outputTokens: 7))
            #expect(reader.invalidSampleCount == 0)
        }
    }

    @Test("Only the response identity, not output content or chat IDs, segments usage")
    func responseIdentityScope() {
        var reader = MonitoringUsageAccumulator()
        let stream = """
            {"response":{"id":"resp_1","output":[{"id":"not_a_response"}],"usage":{"input_tokens":3}}}
            {"response":{"usage":{"input_tokens":4},"output":{"id":"not_a_response"},"id":"resp_1"}}
            {"id":"chat_a","usage":{"output_tokens":2}}
            {"id":"chat_b","usage":{"output_tokens":3}}
            {"response":{"id":"resp_2","usage":{"input_tokens":5}}}
            """
        for byte in stream.utf8 { reader.append(Data([byte])) }
        reader.finish()
        #expect(reader.totals == .init(inputTokens: 9, outputTokens: 3))
    }

    @Test("Complete usage in an interrupted response is retained at EOF")
    func interruptedResponse() {
        var reader = MonitoringUsageAccumulator()
        reader.append(Data(#"{"response":{"id":"resp_1","usage":{"input_tokens":3}}}"#.utf8))
        reader.append(Data(#"{"response":{"id":"resp_2","usage":{"input_tokens":5},"output":["#.utf8))
        reader.finish()
        reader.finish()
        #expect(reader.totals == .init(inputTokens: 8))
        #expect(reader.invalidSampleCount == 0)
    }

    @Test("Response identity storage is bounded without evicting known cumulative snapshots")
    func responseLimit() {
        var reader = MonitoringUsageAccumulator()
        for index in 0..<129 {
            reader.append(Data("{\"response\":{\"id\":\"resp_\(index)\",\"usage\":{\"input_tokens\":1}}}".utf8))
        }
        reader.append(Data(#"{"response":{"id":"resp_0","usage":{"input_tokens":3}}}"#.utf8))
        reader.finish()
        #expect(reader.totals == .init(inputTokens: 130))
        #expect(reader.oversizedSampleCount == 1)
        #expect(reader.invalidSampleCount == 0)
        #expect(reader.ledger.responses.count == 128)
        #expect(reader.retainedByteCount <= 128 * 256)
    }

    @Test("Oversized IDs cannot become anonymous usage or retain arbitrary response content")
    func responseIDLimit() {
        for length in [254, 255, 10_000] {
            var reader = MonitoringUsageAccumulator()
            let body =
                "{\"response\":{\"id\":\"\(String(repeating: "a", count: length))\",\"usage\":{\"input_tokens\":3}}}"
            for byte in body.utf8 {
                reader.append(Data([byte]))
                #expect(reader.retainedByteCount <= 512)
            }
            reader.finish()
            #expect(reader.totals == (length == 254 ? .init(inputTokens: 3) : nil))
            #expect(reader.oversizedSampleCount == (length == 254 ? 0 : 1))
        }
    }

    @Test("Escaped response IDs deduplicate and distinct response totals saturate safely")
    func escapedIDsAndSaturation() {
        var reader = MonitoringUsageAccumulator()
        reader.append(Data(#"{"response":{"id":"resp_1","usage":{"output_tokens":2}}}"#.utf8))
        reader.append(Data(#"{"response":{"id":"resp_\u0031","usage":{"output_tokens":3}}}"#.utf8))
        #expect(reader.totals == .init(outputTokens: 3))
        reader.append(Data("{\"response\":{\"id\":\"resp_2\",\"usage\":{\"output_tokens\":\(Int.max)}}}".utf8))
        reader.finish()
        #expect(reader.totals == .init(outputTokens: Int.max))
    }
}
