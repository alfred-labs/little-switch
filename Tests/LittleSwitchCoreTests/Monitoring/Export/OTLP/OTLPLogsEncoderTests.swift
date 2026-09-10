import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OTLP safe log encoding")
struct OTLPLogsEncoderTests {
    @Test("A test log has stable identity, numeric severity and no fabricated trace")
    func safeEnvelope() throws {
        let entry = MonitoringLogEntry.operation(.test, at: Date(timeIntervalSince1970: 1))
        let data = try OTLPLogsEncoder.encode(resource: .init(), entries: [entry])
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let resources = try #require(root["resourceLogs"] as? [[String: Any]])
        let scopes = try #require(resources[0]["scopeLogs"] as? [[String: Any]])
        let logs = try #require(scopes[0]["logRecords"] as? [[String: Any]])
        #expect(logs.count == 1)
        let actual = try JSONSerialization.data(withJSONObject: logs[0])
        let expected = """
            {"timeUnixNano":"1000000000","observedTimeUnixNano":"1000000000",
             "severityNumber":9,"severityText":"INFO","body":{"stringValue":"Monitoring export test."},
             "attributes":[{"key":"event.id","value":{"stringValue":"\(entry.eventID.uuidString.lowercased())"}},
                           {"key":"event.name","value":{"stringValue":"monitoring.test"}}]}
            """
        #expect(
            try JSONSerialization.jsonObject(with: actual) as? NSDictionary == JSONSerialization.jsonObject(
                with: Data(expected.utf8)) as? NSDictionary)
        let retry = try OTLPLogsEncoder.encode(resource: .init(), entries: [entry])
        #expect(try #require(String(data: retry, encoding: .utf8)).contains(entry.eventID.uuidString.lowercased()))
    }

    @Test("Every admitted log attribute is encoded with its actual OTLP type")
    func terminalAttributes() throws {
        let entry = MonitoringLogEntry(
            observation: .init(
                requestID: UUID(),
                finishedAt: Date(),
                durationSeconds: 0.25,
                client: .codex,
                route: .responses,
                outcome: .serverError,
                providerID: UUID(),
                resolvedModel: "猫\"model",
                statusCode: 503,
                usage: .init(
                    inputTokens: 2,
                    outputTokens: 3,
                    cacheReadTokens: 4,
                    cacheWriteTokens: 5),
                estimatedInputTokens: 9,
                webSearchCount: 1,
                errorKind: .providerHTTP))
        let text = try #require(
            String(data: OTLPLogsEncoder.encode(resource: .init(), entries: [entry]), encoding: .utf8))
        #expect(text.contains(#""severityNumber":17"#))
        #expect(text.contains(#""intValue":"503""#))
        #expect(text.contains(#""doubleValue":0.25"#))
        #expect(text.contains("usage.cache_read_tokens"))
        #expect(!text.contains("traceId"))
        #expect(!text.contains("spanId"))
        #expect(!text.contains("authorization"))
    }
}
