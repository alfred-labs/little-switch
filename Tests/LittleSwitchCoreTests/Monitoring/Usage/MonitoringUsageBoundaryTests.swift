import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring usage parser boundaries")
struct MonitoringUsageBoundaryTests {
    @Test("The depth ceiling discards one oversized sample and recovers at the next frame")
    func depthCeiling() {
        for depth in [62, 63, 70] {
            var reader = MonitoringUsageAccumulator()
            let body =
                "{\"usage\":{\"padding\":" + String(repeating: "[", count: depth) + "0"
                + String(repeating: "]", count: depth) + ",\"input_tokens\":9}}"
            reader.append(Data(body.utf8))
            #expect(reader.totals == (depth == 62 ? .init(inputTokens: 9) : nil))
            #expect(reader.invalidSampleCount == (depth == 62 ? 0 : 1))
            reader.append(Data(#"{"usage":{"output_tokens":2}}"#.utf8))
            reader.finish()
            #expect(reader.totals == .init(inputTokens: depth == 62 ? 9 : 0, outputTokens: 2))
            #expect(reader.retainedByteCount == 0)
        }
    }

    @Test("Long keys and deep response content remain bounded and cannot impersonate usage")
    func discardedContent() {
        let longKey = String(repeating: "usage", count: 100)
        let nesting =
            String(repeating: "[", count: 80) + #"{"usage":{"input_tokens":99}}"#
            + String(repeating: "]", count: 80)
        let body =
            "{\"\(longKey)\":{\"usage\":{\"input_tokens\":99}},\"output\":\(nesting),"
            + "\"text\":\"" + String(repeating: "猫", count: 100_000)
            + "\",\"usage\":{\"input_tokens\":3}}"
        let bytes = Data(body.utf8)
        var reader = MonitoringUsageAccumulator()
        for offset in stride(from: 0, to: bytes.count, by: 127) {
            reader.append(Data(bytes.dropFirst(offset).prefix(127)))
            #expect(reader.retainedByteCount <= 256)
        }
        reader.finish()
        #expect(reader.totals == .init(inputTokens: 3))
        #expect(reader.invalidSampleCount == 0)
        #expect(reader.retainedByteCount == 0)
    }

    @Test("Mismatched containers and invalid UTF-8 do not poison a following valid frame")
    func malformedFrameRecovery() {
        var reader = MonitoringUsageAccumulator()
        reader.append(Data(#"]} {"usage":{"input_tokens":9]}"#.utf8))
        #expect(reader.invalidSampleCount == 1)
        reader.append(Data(#"{"usage":{"unknown":""#.utf8))
        reader.append(Data([0xFF]))
        reader.append(Data(#"","input_tokens":7}}"#.utf8))
        #expect(reader.invalidSampleCount == 2)
        reader.append(Data(#"{"usage":{"input_tokens":4}}"#.utf8))
        reader.finish()
        reader.finish()
        #expect(reader.totals == .init(inputTokens: 4))
        #expect(reader.invalidSampleCount == 2)
        #expect(reader.retainedByteCount == 0)
    }

    @Test("A usage object exactly at its byte limit is accepted; one byte less drops it once")
    func exactSampleSize() {
        let usage = #"{"input_tokens":1}"#
        for limit in [0, 1, usage.utf8.count - 1, usage.utf8.count] {
            var reader = MonitoringUsageAccumulator(maximumUsageBytes: limit)
            reader.append(Data("{\"usage\":\(usage)}".utf8))
            reader.finish()
            let fits = limit == usage.utf8.count
            #expect(reader.totals == (fits ? .init(inputTokens: 1) : nil))
            #expect(reader.invalidSampleCount == (fits ? 0 : 1))
            #expect(reader.retainedByteCount == 0)
        }
    }

    @Test("Array roots and invalid escaped keys cannot supply a protocol usage path")
    func unrecognizedRootsAndKeys() {
        var reader = MonitoringUsageAccumulator()
        reader.append(Data(#"[{"usage":{"input_tokens":99}}] {"us\qage":{"input_tokens":99}}"#.utf8))
        reader.append(Data(#"{"usage":[{"input_tokens":99}],"response":{"us\u0061ge":{"output_tokens":3}}}"#.utf8))
        reader.finish()
        #expect(reader.totals == .init(outputTokens: 3))
        #expect(reader.invalidSampleCount == 0)
    }
}
