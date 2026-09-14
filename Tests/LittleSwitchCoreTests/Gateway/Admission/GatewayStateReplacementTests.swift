import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Gateway state replacement")
struct GatewayStateReplacementTests {
    @Test("Advertised catalog names resolve to their routes")
    func catalogNameEchoResolves() throws {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "qwen")]
        )
        let snapshot = RoutingSnapshot(
            generation: 1,
            providers: [provider],
            mappings: [
                "claude-sonnet-5": ModelMapping(providerID: providerID, modelID: "qwen")
            ]
        )

        let advertised = try #require(
            ClaudeCatalog.make(from: snapshot).data.first?.displayName
        )
        #expect(snapshot.resolve(model: advertised)?.modelID == "qwen")
        #expect(snapshot.resolve(model: "Opus ⇌") == nil)
    }

    @Test("Routed targets report the mapped model's 1M eligibility")
    func routedTargetEligibility() {
        let provider = Provider(
            id: UUID(),
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [
                DiscoveredModel(id: "large", detectedContextWindow: 1_000_000),
                DiscoveredModel(id: "small"),
            ]
        )
        let route = ClaudeRoute.all[0]

        #expect(
            RoutedTarget(route: route, provider: provider, modelID: "large")
                .supports1MContext
        )
        #expect(
            !RoutedTarget(route: route, provider: provider, modelID: "small")
                .supports1MContext
        )
        #expect(
            !RoutedTarget(route: route, provider: provider, modelID: "gone")
                .supports1MContext
        )
    }
}
