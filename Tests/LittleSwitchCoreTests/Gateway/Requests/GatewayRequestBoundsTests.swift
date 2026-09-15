import AsyncHTTPClient
import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Prepared gateway request bounds")
struct GatewayRequestBoundsTests {
    @Test("Checkpoint degradation cannot expand history beyond the ingress limit")
    func expandedHistoryLimit() async throws {
        let fixture = try GatewayTests().makeFixture()
        let body = Data(
            #"{"model":"z.ai/glm-5.2","input":[{"type":"compaction","encrypted_content":"foreign"}]}"#.utf8)
        let target = try #require(fixture.snapshot.resolveCodex(model: "z.ai/glm-5.2"))
        let prepared = try PreparedGatewayResponses(
            body: ResponsesProviderState.degradedBody(body), target: target, configuration: .init())
        #expect(prepared.body.count > body.count)
        let transport = RecordingGatewayTransport(responses: [])
        let application = GatewayTests().makeApplication(
            fixture: fixture, transport: transport, maximumRequestBytes: body.count)
        try await application.test(.router) { client in
            let result = try await client.execute(uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: body))
            #expect(result.status == .contentTooLarge)
            #expect(String(buffer: result.body).contains("Expanded history is too large"))
        }
        #expect(await transport.requests.isEmpty)
        #expect(await fixture.state.sessionRequestCount == 0)
    }

    @Test("The model exchange bounds projected bytes before transport")
    func modelExchangeBodyLimit() async throws {
        let fixture = try GatewayTests().makeFixture()
        let body = Data(#"{"model":"glm-5.2","input":"synthetic"}"#.utf8)
        let transport = RecordingGatewayTransport(responses: [])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            maximumRequestBytes: body.count - 1,
            requiredAuthorityPort: nil)
        let request = HTTPClientRequest(url: "https://provider.example/v1/responses")
        await #expect(throws: ProviderToolContract.Error.invalidRequest) {
            try await responder.executeModelRequest(
                request, body: body, wire: .responses, eventID: UUID(), attempt: 0)
        }
        #expect(await transport.requests.isEmpty)
    }
}
