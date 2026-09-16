import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Claude catalog context choices")
struct ClaudeCatalogContextTests {
    @Test("Discovery exposes one canonical family choice when every mapped model supports 1M")
    func familyContextChoices() throws {
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
        let catalog = ClaudeCatalog.make(from: snapshot, contextPresentation: .canonicalFamilyChoices)
        #expect(
            catalog.data.map(\.id) == [
                "claude-fable-5-1", "claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5-20251001",
            ])
        #expect(catalog.firstID == "claude-fable-5-1")
        #expect(catalog.lastID == "claude-haiku-4-5-20251001")
        #expect(!catalog.hasMore)

        // Discovery retains a Claude-compatible canonical ID even when it
        // discards capabilities. Managed defaults select the concrete context.
        let discovery = try JSONDecoder().decode(
            DiscoveredCatalog.self, from: ClaudeCatalog.encode(catalog))
        #expect(discovery.data.map(\.id) == catalog.data.map(\.id))
        #expect(
            discovery.data.contains(
                DiscoveredOption(id: "claude-sonnet-5", displayName: "Sonnet 5 ↦ (1M context)")))
        for option in catalog.data {
            #expect(option.maxInputTokens == 1_000_000)
            #expect(option.isFamilyDefault)
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
        #expect(ClaudeCatalog.make(from: snapshot).data == [base])
        var expected = base
        let name = indicator.symbol.map { "Sonnet 5 \($0)" } ?? "Sonnet 5"
        expected.displayName = supports1M ? "\(name) (1M context)" : name
        expected.description = "Via LittleSwitch"
        expected.maxInputTokens = supports1M ? 1_000_000 : 200_000
        let catalog = ClaudeCatalog.make(from: snapshot, contextPresentation: .canonicalFamilyChoices)
        #expect(catalog.data == [expected])
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
