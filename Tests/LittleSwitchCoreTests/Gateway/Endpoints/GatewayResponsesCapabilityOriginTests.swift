import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Responses capability evidence origin")
struct GatewayResponsesCapabilityOriginTests {
    @Test(
        "Synthetic replies neither change existing verdicts nor trigger an adapter retry",
        arguments: [UInt(200), 204, 404, 405, 429, 500], [nil, false, true] as [Bool?])
    func synthetic(status: UInt, initial: Bool?) async {
        let provider = Provider(name: "Example", baseURL: "https://provider.example", authMode: .none)
        let responder = responder(provider)
        if let initial {
            await responder.state.responsesCapabilities.record(providerID: provider.id, supportsNative: initial)
        }
        await responder.recordResponsesCapability(providerID: provider.id, status: status, origin: .synthetic)
        #expect(await responder.state.responsesCapabilities.verdict(for: provider.id) == initial)
        #expect(!responder.responsesAdapterFallbackApplies(status: status, provider: provider, origin: .synthetic))
    }

    @Test(
        "HTTP and real WebSocket success still learn native support",
        arguments: [GatewayModelExchange.Origin.http, .webSocket], [UInt(200), 204])
    func providerSuccess(origin: GatewayModelExchange.Origin, status: UInt) async {
        let provider = Provider(name: "Example", baseURL: "https://provider.example", authMode: .none)
        let responder = responder(provider)
        await responder.state.responsesCapabilities.record(providerID: provider.id, supportsNative: false)
        await responder.recordResponsesCapability(providerID: provider.id, status: status, origin: origin)
        #expect(await responder.state.responsesCapabilities.verdict(for: provider.id) == true)
        #expect(!responder.responsesAdapterFallbackApplies(status: status, provider: provider, origin: origin))
    }

    @Test("The default origin still treats HTTP 404 and 405 as missing routes", arguments: [UInt(404), 405])
    func defaultHTTPRejection(status: UInt) async {
        let provider = Provider(name: "Example", baseURL: "https://provider.example", authMode: .none)
        let responder = responder(provider)
        await responder.recordResponsesCapability(providerID: provider.id, status: status)
        #expect(await responder.state.responsesCapabilities.verdict(for: provider.id) == false)
        #expect(responder.responsesAdapterFallbackApplies(status: status, provider: provider))
    }

    private func responder(_ provider: Provider) -> GatewayResponder {
        GatewayResponder(
            state: GatewayState(snapshot: .init(generation: 0, providers: [provider], mappings: [:])),
            transport: RecordingGatewayTransport(responses: []),
            secretStore: MemorySecretStore())
    }
}
