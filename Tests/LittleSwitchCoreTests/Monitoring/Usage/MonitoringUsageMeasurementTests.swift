import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring provider usage normalization")
struct MonitoringUsageMeasurementTests {
    @Test("Provider token shapes retain separate uncached input, output and cache counts")
    func normalizedCounts() throws {
        let cases: [(String, GatewayUsageTotals)] = [
            (
                #"{"input_tokens":10,"output_tokens":6,"cache_read_input_tokens":4,"cache_creation_input_tokens":2}"#,
                .init(inputTokens: 10, outputTokens: 6, cacheReadTokens: 4, cacheWriteTokens: 2)
            ),
            (
                #"{"prompt_tokens":30,"completion_tokens":12,"prompt_tokens_details":{"cached_tokens":7,"cache_write_tokens":3}}"#,
                .init(inputTokens: 20, outputTokens: 12, cacheReadTokens: 7, cacheWriteTokens: 3)
            ),
            (
                #"{"input_tokens":20,"output_tokens":5,"input_tokens_details":{"cached_tokens":5,"cache_write_tokens":2}}"#,
                .init(inputTokens: 13, outputTokens: 5, cacheReadTokens: 5, cacheWriteTokens: 2)
            ),
            (
                #"{"input_tokens":2,"input_tokens_details":{"cached_tokens":5,"cache_write_tokens":3}}"#,
                .init(cacheReadTokens: 5, cacheWriteTokens: 3)
            ),
            (#"{"input_tokens_details":{"cached_tokens":0}}"#, .init()),
            (#"{"input_tokens_details":{"cache_write_tokens":2}}"#, .init(cacheWriteTokens: 2)),
            (
                #"{"input_tokens":10,"prompt_tokens":99,"output_tokens":3,"completion_tokens":99}"#,
                .init(inputTokens: 10, outputTokens: 3)
            ),
        ]
        for (document, expected) in cases {
            #expect(try MonitoringUsageMeasurement.decode(Data(document.utf8)) == expected)
        }
    }

    @Test("Absent recognized counts stay unknown and never fabricate a zero")
    func unknownCounts() throws {
        for document in [
            "{}", #"{"total_tokens":20}"#, #"{"input_tokens_details":{}}"#,
            #"{"prompt_tokens_details":null}"#, #"{"input_tokens_details":{"cached_tokens":null}}"#,
        ] {
            #expect(try MonitoringUsageMeasurement.decode(Data(document.utf8)) == nil)
        }
        #expect(try MonitoringUsageMeasurement.decode(Data(#"{"output_tokens":0}"#.utf8)) == .init())
    }

    @Test("Known malformed counts reject the whole sample, including malformed cache details")
    func invalidCounts() {
        let values = ["-1", "0.5", "true", "\"12\"", "9223372036854775808"]
        for value in values {
            for document in [
                "{\"input_tokens\":4,\"output_tokens\":\(value)}",
                "{\"input_tokens\":4,\"input_tokens_details\":{\"cached_tokens\":\(value)}}",
            ] {
                #expect(throws: DecodingError.self) {
                    try MonitoringUsageMeasurement.decode(Data(document.utf8))
                }
            }
        }
        for document in [
            "[]", "null", "true", #"{"input_tokens":null}"#,
            #"{"input_tokens_details":[]}"#, #"{"input_tokens":1"#,
        ] {
            #expect(throws: DecodingError.self) { try MonitoringUsageMeasurement.decode(Data(document.utf8)) }
        }
    }

    @Test("Maximum integer counts saturate cache addition without overflowing or becoming negative")
    func integerBoundary() throws {
        let document =
            "{\"input_tokens\":\(Int.max),\"output_tokens\":\(Int.max),"
            + "\"input_tokens_details\":{\"cached_tokens\":\(Int.max),\"cache_write_tokens\":\(Int.max)}}"
        #expect(
            try MonitoringUsageMeasurement.decode(Data(document.utf8))
                == .init(outputTokens: Int.max, cacheReadTokens: Int.max, cacheWriteTokens: Int.max))
    }

    @Test("Invalid UTF-8 in ignored values invalidates the sample instead of passing through lazy decoding")
    func invalidUTF8() {
        let encodings: [[UInt8]] = [[0xFF], [0xC0, 0xAF], [0xED, 0xA0, 0x80], [0xE2, 0x82]]
        for bytes in encodings {
            var document = Data(#"{"ignored":""#.utf8)
            document.append(contentsOf: bytes)
            document.append(Data(#"","input_tokens":7}"#.utf8))
            #expect(throws: DecodingError.self) { try MonitoringUsageMeasurement.decode(document) }
        }
    }
}
