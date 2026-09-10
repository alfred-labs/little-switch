import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring log HTTP encoding")
struct MonitoringLogHTTPEncodingTests {
    @Test("The actual HTTP page preserves fractional dates and the shared escaping and byte budget")
    func sharedEncoding() async throws {
        let fixture = try GatewayTests().makeFixture()
        let store = MonitoringStore()
        let date = Date(timeIntervalSince1970: 1_800_000_000.125)
        for _ in 0..<600 {
            await store.finish(
                .init(
                    requestID: UUID(),
                    finishedAt: date,
                    durationSeconds: 1.25,
                    client: .codex,
                    route: .responses,
                    outcome: .success,
                    providerID: UUID(),
                    resolvedModel: String(repeating: "\u{0}", count: 240) + String(repeating: "/", count: 16),
                    statusCode: 200,
                    usage: .init(
                        inputTokens: Int.max,
                        outputTokens: Int.max,
                        cacheReadTokens: Int.max,
                        cacheWriteTokens: Int.max),
                    estimatedInputTokens: Int.max,
                    webSearchCount: Int.max))
        }
        let monitoring = GatewayMonitoring(store: store) { .init(exposeLogs: true) }
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: RecordingGatewayTransport(responses: []),
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                monitoring: monitoring))
        let query = try MonitoringLogQuery(parameters: [
            .init(name: "since", value: "2020-01-01T00:00:00Z"), .init(name: "limit", value: "500"),
        ])
        let expected = try await store.logs(query: query)
        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/logs?since=2020-01-01T00:00:00Z&limit=500", method: .get)
            let actual = Data(response.body.readableBytesView)
            #expect(response.status == .ok)
            #expect(response.headers[.cacheControl] == "no-store")
            #expect(actual == (try expected.encoded()))
            #expect(actual.count <= 1_024 * 1_024)
            let encodedPage = try #require(String(bytes: actual, encoding: .utf8))
            let preservesFractionalDate = encodedPage.contains(".125Z")
            #expect(preservesFractionalDate)
            let cursor = try #require(expected.nextCursor)
            let continuation = try MonitoringLogQuery(parameters: [.init(name: "cursor", value: cursor)])
            let nextExpected = try await store.logs(query: continuation)
            let next = try await client.execute(uri: "/logs?cursor=\(cursor)", method: .get)
            #expect(Data(next.body.readableBytesView) == (try nextExpected.encoded()))
            #expect(Set(expected.entries.map(\.eventID)).isDisjoint(with: nextExpected.entries.map(\.eventID)))
        }
    }
}
