import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring local failures")
struct MonitoringLocalFailureTests {
    @Test("Invalid filters and expired cursors produce distinct restart contracts")
    func queryFailures() async throws {
        let fixture = try GatewayTests().makeFixture()
        let store = MonitoringStore()
        let empty = try await store.logs()
        let payload = try #require(JSONSerialization.jsonObject(with: empty.encoded()) as? [String: Any])
        #expect(payload["schemaVersion"] as? Int == 1)
        let oldCursor = try #require(empty.nextCursor)
        for _ in 0..<1_001 { await store.recordOperation(.test) }
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: RecordingGatewayTransport(responses: []),
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                monitoring: GatewayMonitoring(store: store) { .init(exposeLogs: true) }
            )
        )
        try await app.test(.router) { client in
            let expired = try await client.execute(uri: "/logs?cursor=\(oldCursor)", method: .get)
            #expect(expired.status == .gone)
            #expect(expired.headers[.cacheControl] == "no-store")
            let expected = #"{"schemaVersion":1,"error":"cursor_expired","retentionLost":true,"restartRequired":true}"#
            #expect(String(buffer: expired.body) == expected)
            for query in ["limit=0", "unknown=1", "level=debug", "since=2026-99-99T99:99:99Z"] {
                let invalid = try await client.execute(uri: "/logs?\(query)", method: .get)
                #expect(invalid.status == .badRequest)
                #expect(String(buffer: invalid.body) == #"{"schemaVersion":1,"error":"invalid_query"}"#)
            }
        }
        #expect(await store.snapshot().family(.requests) == nil)
    }

    @Test("An interrupted internal response finishes its permit without changing its error")
    func internalBodyFailure() async throws {
        let fixture = try GatewayTests().makeFixture()
        let recorder = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            trafficRecorder: recorder
        )
        let eventID = UUID()
        let original = Response(status: .ok, body: .init { _ in throw GatewayTestError.privateFailure })
        let response = responder.finalizingResponse(
            original,
            eventID: eventID,
            permitCompletion: GatewayPermitCompletionGuard(state: fixture.state, eventID: eventID),
            recordsTraffic: false
        )
        await #expect(throws: GatewayTestError.privateFailure) { try await responseBodyData(response.body) }
        #expect(recorder.events.isEmpty)
    }
}
