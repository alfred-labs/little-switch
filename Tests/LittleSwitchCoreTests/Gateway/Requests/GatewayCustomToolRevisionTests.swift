import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Custom bridge routing revisions")
struct GatewayCustomToolRevisionTests {
    @Test("A stale provider capture fails before probing or sending content", arguments: [false, true])
    func staleCapture(deleted: Bool) async throws {
        let provider = Provider(name: "Test", baseURL: "https://unit.example/v1", authMode: .none)
        let cache = CustomToolCapabilityCache()
        let state = GatewayState(
            snapshot: RoutingSnapshot(generation: 0, providers: [provider], mappings: [:]),
            customToolCapabilities: cache)
        let transport = RecordingGatewayTransport(responses: [])
        var responder = GatewayResponder(state: state, transport: transport, secretStore: MemorySecretStore())
        responder.customToolRoutingCapture = await state.routingCapture()
        _ = await state.replace(
            providers: deleted ? [] : [provider], mappings: [:], credentialChangedProviderIDs: [provider.id])
        let url = provider.baseURL + "/responses"
        let body = Data(#"{"tools":[{"type":"custom","name":"exec"}]}"#.utf8)
        let traffic = TrafficUpstreamRequest(
            attempt: 0,
            claudeRoute: "m",
            providerID: provider.id,
            providerName: provider.name,
            modelID: "m",
            url: url,
            headers: [],
            body: body,
            streaming: false)
        await #expect(throws: GatewayAdmissionError.invalidated) {
            try await responder.executeModelRequest(
                HTTPClientRequest(url: url),
                body: body,
                traffic: traffic,
                wire: .responses,
                eventID: UUID(),
                attempt: 0)
        }
        #expect(await transport.requests.isEmpty)
        #expect(await cache.activeProbeCount == 0)
    }
}
