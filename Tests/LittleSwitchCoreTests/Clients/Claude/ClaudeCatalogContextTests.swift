import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Claude catalog context choices")
struct ClaudeCatalogContextTests {
    @Test("Discovery exposes explicit standard and 1M choices for every eligible route")
    func explicitContextChoices() throws {
        let provider = Provider(
            name: "Gateway",
            baseURL: "https://example.com",
            authMode: .bearer,
            models: [DiscoveredModel(id: "flash", detectedContextWindow: 1_048_576)]
        )
        let snapshot = RoutingSnapshot(
            generation: 1,
            providers: [provider],
            mappings: Dictionary(
                uniqueKeysWithValues: ClaudeRoute.all.map {
                    ($0.id, ModelMapping(providerID: provider.id, modelID: "flash"))
                })
        )
        let catalog = ClaudeCatalog.make(from: snapshot, contextPresentation: .explicitChoices)
        #expect(
            catalog.data.map(\.id) == [
                "claude-fable-5-1", "claude-fable-5-1[1m]",
                "claude-opus-5", "claude-opus-5[1m]",
                "claude-sonnet-5", "claude-sonnet-5[1m]",
                "claude-haiku-4-5-20251001", "claude-haiku-4-5-20251001[1m]",
            ])
        #expect(catalog.firstID == "claude-fable-5-1")
        #expect(catalog.lastID == "claude-haiku-4-5-20251001[1m]")
        #expect(!catalog.hasMore)

        // Claude Code strips capability fields during discovery. Each option
        // must therefore exist as an ID, independently of the selected default.
        let discovery = try JSONDecoder().decode(
            DiscoveredCatalog.self, from: ClaudeCatalog.encode(catalog))
        #expect(discovery.data.map(\.id) == catalog.data.map(\.id))
        #expect(discovery.data.contains(DiscoveredOption(id: "claude-sonnet-5[1m]", displayName: "Sonnet ↦ [1m]")))
        for option in catalog.data {
            #expect(snapshot.resolve(model: option.id)?.modelID == "flash")
            #expect(snapshot.resolve(model: option.displayName)?.modelID == "flash")
        }
    }

    @Test(
        "Sonnet context choices follow the mapped capacity, including a manual declaration",
        arguments: [
            (DiscoveredModel(id: "flash", detectedContextWindow: 1_048_576), true),
            (DiscoveredModel(id: "flash", contextWindowOverride: 1_000_000), true),
            (DiscoveredModel(id: "flash", detectedContextWindow: 262_144, contextWindowOverride: 1_000_000), false),
            (DiscoveredModel(id: "flash"), false),
        ], ModelIndicator.allCases
    )
    func sonnetCapacity(fixture: (DiscoveredModel, Bool), indicator: ModelIndicator) throws {
        let (model, supports1M) = fixture
        let provider = Provider(
            name: "Gateway", baseURL: "https://example.com", authMode: .bearer, models: [model])
        let snapshot = RoutingSnapshot(
            generation: 1,
            providers: [provider],
            mappings: ["claude-sonnet-5": ModelMapping(providerID: provider.id, modelID: model.id)],
            modelIndicator: indicator
        )
        let route = try #require(ClaudeRoute.all.first { $0.id == "claude-sonnet-5" })
        let base = ClaudeCatalogModel(
            id: route.id,
            type: "model",
            displayName: route.catalogDisplayName(indicator: indicator),
            createdAt: route.createdAt,
            maxTokens: 64_000,
            maxInputTokens: 200_000,
            supports1M: supports1M,
            family: "sonnet",
            isFamilyDefault: true
        )
        var expected = [base]
        if supports1M {
            expected.append(
                ClaudeCatalogModel(
                    id: "claude-sonnet-5[1m]",
                    type: "model",
                    displayName: "\(base.displayName) [1m]",
                    createdAt: route.createdAt,
                    maxTokens: 64_000,
                    maxInputTokens: 1_000_000,
                    supports1M: false,
                    family: "sonnet",
                    isFamilyDefault: false
                ))
        }
        let catalog = ClaudeCatalog.make(from: snapshot, contextPresentation: .explicitChoices)
        #expect(catalog.data == expected)
        for option in catalog.data {
            #expect(snapshot.resolve(model: option.displayName) == snapshot.resolve(model: option.id))
        }
        #expect((snapshot.resolve(model: "claude-sonnet-5[1m]") != nil) == supports1M)
    }

    @Test("Fable 5 sessions retain their route after upgrading to Fable 5.1", arguments: [400_000, 1_000_000])
    func legacyFableRequests(contextWindow: Int) {
        let provider = Provider(
            name: "Gateway",
            baseURL: "https://example.com",
            authMode: .bearer,
            models: [DiscoveredModel(id: "large", detectedContextWindow: contextWindow)]
        )
        let snapshot = RoutingSnapshot(
            generation: 1,
            providers: [provider],
            mappings: ["claude-fable-5-1": ModelMapping(providerID: provider.id, modelID: "large")]
        )
        #expect(snapshot.resolve(model: "claude-fable-5-1")?.modelID == "large")
        #expect(snapshot.resolve(model: "claude-fable-5") == snapshot.resolve(model: "claude-fable-5-1"))
        #expect((snapshot.resolve(model: "claude-fable-5[1m]") != nil) == (contextWindow >= 1_000_000))
        #expect(snapshot.resolve(model: "claude-fable-5[1m][1m]") == nil)
        #expect(snapshot.resolve(model: "claude-fable-5-other") == nil)
    }

    private struct DiscoveredCatalog: Decodable {
        var data: [DiscoveredOption]
    }

    private struct DiscoveredOption: Decodable, Equatable {
        var id: String
        var displayName: String

        private enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }
}
