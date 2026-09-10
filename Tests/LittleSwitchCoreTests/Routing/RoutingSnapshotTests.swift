import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Routing snapshots")
struct RoutingSnapshotTests {
    @Test("A routing snapshot resolves both route IDs and exact display references")
    func resolvesMappings() throws {
        let providerID = try #require(
            UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        )
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "qwen/large")]
        )
        let snapshot = RoutingSnapshot(
            generation: 7,
            providers: [provider],
            mappings: ["claude-sonnet-5": ModelMapping(providerID: providerID, modelID: "qwen/large")]
        )

        let byRoute = try #require(snapshot.resolve(model: "claude-sonnet-5"))
        let byReference = try #require(snapshot.resolve(model: "Local/qwen/large"))
        #expect(byRoute == byReference)
        #expect(byRoute.provider == provider)
        #expect(byRoute.modelID == "qwen/large")
        #expect(snapshot.resolve(model: "claude-opus-5") == nil)
        #expect(snapshot.resolve(model: "local/qwen/large") == nil)
    }

    @Test("Only eligible models resolve the exact 1M suffix")
    func resolvesExtendedContextMappings() throws {
        let providerID = UUID()
        let eligible = Provider(
            id: providerID,
            name: "Gateway",
            baseURL: "https://example.com",
            authMode: .bearer,
            models: [DiscoveredModel(id: "large", detectedContextWindow: 1_000_000)]
        )
        let eligibleSnapshot = RoutingSnapshot(
            generation: 1,
            providers: [eligible],
            mappings: [
                "claude-opus-5": ModelMapping(providerID: providerID, modelID: "large")
            ]
        )

        #expect(eligibleSnapshot.resolve(model: "claude-opus-5[1m]")?.modelID == "large")
        #expect(eligibleSnapshot.resolve(model: "Gateway/large[1m]")?.modelID == "large")
        #expect(eligibleSnapshot.resolve(model: "claude-opus-5[1m][1m]") == nil)

        let standard = Provider(
            id: providerID,
            name: "Gateway",
            baseURL: "https://example.com",
            authMode: .bearer,
            models: [DiscoveredModel(id: "large", detectedContextWindow: 400_000)]
        )
        let standardSnapshot = RoutingSnapshot(
            generation: 1,
            providers: [standard],
            mappings: eligibleSnapshot.mappings
        )
        #expect(standardSnapshot.resolve(model: "claude-opus-5[1m]") == nil)
        #expect(standardSnapshot.resolve(model: "Gateway/large[1m]") == nil)
    }

    @Test("Invalid and disappeared mappings are omitted")
    func invalidMappings() {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "present")]
        )
        let snapshot = RoutingSnapshot(
            generation: 1,
            providers: [provider],
            mappings: [
                "claude-opus-5": ModelMapping(providerID: providerID, modelID: "missing"),
                "unknown": ModelMapping(providerID: providerID, modelID: "present"),
            ]
        )
        #expect(snapshot.validTargets.isEmpty)
        #expect(!snapshot.hasValidMapping)
    }
}
