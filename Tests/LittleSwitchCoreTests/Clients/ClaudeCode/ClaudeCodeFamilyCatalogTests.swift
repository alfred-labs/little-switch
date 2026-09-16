import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Claude Code family catalog")
struct ClaudeCodeFamilyCatalogTests {
    @Test("Discovery keeps Claude-compatible canonical IDs instead of adding context duplicates")
    func uniqueFamilyAliases() throws {
        let snapshot = fixture()
        let catalog = ClaudeCatalog.make(from: snapshot, contextPresentation: .canonicalFamilyChoices)
        let decoded = try JSONDecoder().decode(Catalog.self, from: ClaudeCatalog.encode(catalog))

        #expect(
            decoded.data == [
                Choice(
                    id: "claude-fable-5-1",
                    name: "Fable 5.1 ↦",
                    description: "Via LittleSwitch",
                    family: "fable",
                    isDefault: true,
                    maxInput: 200_000),
                Choice(
                    id: "claude-opus-5",
                    name: "Opus 5 ↦ (1M context)",
                    description: "Via LittleSwitch",
                    family: "opus",
                    isDefault: true,
                    maxInput: 1_000_000),
                Choice(
                    id: "claude-sonnet-5",
                    name: "Sonnet 5 ↦ (1M context)",
                    description: "Via LittleSwitch",
                    family: "sonnet",
                    isDefault: true,
                    maxInput: 1_000_000),
                Choice(
                    id: "claude-haiku-4-5-20251001",
                    name: "Haiku 4.5 ↦",
                    description: "Via LittleSwitch",
                    family: "haiku",
                    isDefault: true,
                    maxInput: 200_000),
            ])
        #expect(catalog.firstID == "claude-fable-5-1")
        #expect(catalog.lastID == "claude-haiku-4-5-20251001")
    }

    @Test("Native aliases select the mapped capacity even when they are not the default")
    func managedFamilyAliases() throws {
        let snapshot = fixture()
        let managed = try ClaudeCodeManagedSettings.resolve(
            providers: snapshot.providers,
            mappings: snapshot.mappings,
            configuration: ClaudeCodeConfiguration(defaultModel: "claude-opus-5")
        )

        // The selected default must also be the native picker value: a full
        // model ID can otherwise be reinserted as an extra selected row.
        #expect(managed.model == "opus")
        #expect(managed.environment["ANTHROPIC_DEFAULT_MODEL"] == "opus")
        #expect(managed.environment["ANTHROPIC_DEFAULT_FABLE_MODEL"] == "claude-fable-5-1")
        #expect(managed.environment["ANTHROPIC_DEFAULT_OPUS_MODEL"] == "claude-opus-5[1m]")
        #expect(managed.environment["ANTHROPIC_DEFAULT_SONNET_MODEL"] == "claude-sonnet-5[1m]")
        #expect(managed.environment["ANTHROPIC_DEFAULT_HAIKU_MODEL"] == "claude-haiku-4-5-20251001")
        #expect(managed.environment["ANTHROPIC_DEFAULT_FABLE_MODEL_NAME"] == "Fable 5.1 ↦")
        #expect(managed.environment["ANTHROPIC_DEFAULT_OPUS_MODEL_NAME"] == "Opus 5 ↦ (1M context)")
        #expect(managed.environment["ANTHROPIC_DEFAULT_SONNET_MODEL_NAME"] == "Sonnet 5 ↦ (1M context)")
        #expect(managed.environment["ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME"] == "Haiku 4.5 ↦")
        for family in ["FABLE", "OPUS", "SONNET", "HAIKU"] {
            #expect(managed.environment["ANTHROPIC_DEFAULT_\(family)_MODEL_DESCRIPTION"] == "Via LittleSwitch")
        }
    }

    @Test("Family references and advertised names retain the physical mappings")
    func familyResolution() throws {
        let snapshot = fixture()
        let catalog = ClaudeCatalog.make(from: snapshot, contextPresentation: .canonicalFamilyChoices)

        #expect(snapshot.resolve(model: "fable")?.modelID == "medium")
        #expect(snapshot.resolve(model: "opus")?.modelID == "large")
        #expect(snapshot.resolve(model: "sonnet")?.modelID == "flash")
        #expect(snapshot.resolve(model: "haiku")?.modelID == "small")
        #expect(snapshot.resolve(model: "sonnet[1m]")?.modelID == "flash")
        #expect(snapshot.resolve(model: "fable[1m]") == nil)
        for entry in catalog.data {
            #expect(snapshot.resolve(model: entry.id) != nil)
            #expect(snapshot.resolve(model: entry.displayName) == snapshot.resolve(model: entry.id))
        }
        #expect(snapshot.resolve(model: "claude-fable-5")?.modelID == "medium")
        #expect(snapshot.resolve(model: "claude-opus-5[1m]")?.modelID == "large")
        #expect(snapshot.resolve(model: "Sonnet ↦ [1m]")?.modelID == "flash")
    }

    @Test("A saved standard preference normalizes to the single eligible family choice")
    func automaticContext() {
        let snapshot = fixture()
        let normalized = ClaudeCodeConfiguration(
            connected: true, defaultModel: "claude-sonnet-5", contextMode: .standard
        ).normalized(providers: snapshot.providers, mappings: snapshot.mappings)
        #expect(
            normalized
                == ClaudeCodeConfiguration(
                    connected: true, defaultModel: "claude-sonnet-5", contextMode: .extended1M
                ))
    }

    private func fixture() -> RoutingSnapshot {
        let provider = Provider(
            name: "Gateway",
            baseURL: "https://example.com",
            authMode: .none,
            models: [
                DiscoveredModel(id: "medium", detectedContextWindow: 262_144),
                DiscoveredModel(id: "large", detectedContextWindow: 1_000_000),
                DiscoveredModel(id: "flash", detectedContextWindow: 1_048_576),
                DiscoveredModel(id: "small"),
            ]
        )
        return RoutingSnapshot(
            generation: 1,
            providers: [provider],
            mappings: [
                "claude-fable-5-1": ModelMapping(providerID: provider.id, modelID: "medium"),
                "claude-opus-5": ModelMapping(providerID: provider.id, modelID: "large"),
                "claude-sonnet-5": ModelMapping(providerID: provider.id, modelID: "flash"),
                "claude-haiku-4-5-20251001": ModelMapping(providerID: provider.id, modelID: "small"),
            ]
        )
    }

    private struct Catalog: Decodable {
        var data: [Choice]
    }

    private struct Choice: Decodable, Equatable {
        var id: String
        var name: String
        var description: String?
        var family: String
        var isDefault: Bool
        var maxInput: Int?

        private enum CodingKeys: String, CodingKey {
            case id, description
            case name = "display_name"
            case family = "anthropic_family_tier"
            case isDefault = "is_family_default"
            case maxInput = "max_input_tokens"
        }
    }
}
