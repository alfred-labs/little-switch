import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Provider thinking drafts")
struct ProviderThinkingDraftTests {
    @Test("Editing or duplicating a provider resolves its saved thinking setting")
    func resolvesSavedThinking() throws {
        let base = Provider(name: "example", baseURL: "https://example.com", authMode: .none)
        var root = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any]
        )
        root["disabledThinkingOverride"] = "lowEffort"
        let provider = try JSONDecoder().decode(
            Provider.self, from: JSONSerialization.data(withJSONObject: root)
        )

        // Low effort is the product default, so a saved low effort round-trips
        // without counting as an advanced override.
        #expect(ProviderDraft(provider: provider).disabledThinkingOverride == .lowEffort)
        #expect(ProviderDraft(duplicating: provider, providers: [provider]).disabledThinkingOverride == .lowEffort)
        #expect(!ProviderDraft(provider: provider).hasAdvancedOverrides)
        #expect(!ProviderDraft(duplicating: provider, providers: [provider]).hasAdvancedOverrides)
    }

    @Test("Editing or duplicating a provider exposes a saved passthrough in Advanced")
    func revealsSavedPassthrough() throws {
        let base = Provider(name: "example", baseURL: "https://example.com", authMode: .none)
        var root = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any]
        )
        root["disabledThinkingOverride"] = "passthrough"
        let provider = try JSONDecoder().decode(
            Provider.self, from: JSONSerialization.data(withJSONObject: root)
        )

        #expect(ProviderDraft(provider: provider).hasAdvancedOverrides)
        #expect(ProviderDraft(duplicating: provider, providers: [provider]).hasAdvancedOverrides)
        #expect(ProviderDraft(provider: provider).disabledThinkingOverride == .passthrough)
        #expect(ProviderDraft(duplicating: provider, providers: [provider]).disabledThinkingOverride == .passthrough)
    }

    @Test("Thinking overrides remain draft edits until Save and reset when choosing a preset")
    func draftTransaction() {
        let provider = Provider(name: "example", baseURL: "https://example.com", authMode: .none)
        var draft = ProviderDraft(provider: provider)
        #expect(draft.disabledThinkingOverride == .default)
        #expect(draft.makeInput().disabledThinkingOverride == .default)

        draft.disabledThinkingOverride = .passthrough
        #expect(draft.makeInput().disabledThinkingOverride == .passthrough)
        #expect(draft.hasAdvancedOverrides)
        #expect(provider.disabledThinkingOverride == .default)
        #expect(ProviderDraft(provider: provider).disabledThinkingOverride == .default)

        draft.disabledThinkingOverride = .lowEffort
        #expect(draft.makeInput().disabledThinkingOverride == .lowEffort)
        #expect(!draft.hasAdvancedOverrides)

        draft.disabledThinkingOverride = .lowEffort
        draft.apply(.ollama)
        #expect(draft.disabledThinkingOverride == .default)
    }

    @Test("A duplicate's input preserves thinking independently of its source")
    func duplicateInput() throws {
        let source = Provider(
            name: "example",
            baseURL: "https://example.com",
            authMode: .none,
            disabledThinkingOverride: .lowEffort
        )
        var draft = ProviderDraft(duplicating: source, providers: [source])
        let input = draft.makeInput()

        #expect(input.disabledThinkingOverride == .lowEffort)
        #expect(input.intent == .duplicate(sourceID: source.id))
        #expect(try #require(input.id) != source.id)
        draft.disabledThinkingOverride = .passthrough
        #expect(source.disabledThinkingOverride == .lowEffort)
        #expect(draft.makeInput().disabledThinkingOverride == .passthrough)
    }
}

@MainActor
@Suite("Provider thinking coordinator")
struct ProviderThinkingCoordinatorTests {
    @Test("Save persists and can clear a provider's thinking override")
    func savesAndClearsOverride() async throws {
        let fixture = try await ProviderDuplicationFixture.make()
        var input = ProviderInput(
            id: fixture.source.id,
            name: fixture.source.name,
            baseURL: fixture.source.baseURL,
            authMode: fixture.source.authMode,
            disabledThinkingOverride: .lowEffort
        )
        let saved = try await fixture.coordinator.saveProvider(input)
        let provider = try #require(saved.configuration.providers.first)
        #expect(provider.disabledThinkingOverride == .lowEffort)
        #expect(fixture.store.configuration == saved.configuration)
        let decoded = try JSONDecoder().decode(
            AppConfiguration.self, from: JSONEncoder().encode(fixture.store.configuration)
        )
        #expect(decoded == saved.configuration)
        #expect(ProviderDraft(provider: provider).makeInput().disabledThinkingOverride == .lowEffort)

        input.disabledThinkingOverride = .passthrough
        let cleared = try await fixture.coordinator.saveProvider(input)
        #expect(cleared.configuration.providers.first?.disabledThinkingOverride == .passthrough)
        #expect(fixture.store.configuration == cleared.configuration)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Saving a duplicate retains its selected thinking setting")
    func savesDuplicateOverride() async throws {
        let fixture = try await ProviderDuplicationFixture.make()
        var input = fixture.input()
        input.disabledThinkingOverride = .lowEffort
        let before = fixture.store.configuration
        let snapshot = try await fixture.coordinator.saveProvider(input)
        let copy = try #require(snapshot.configuration.providers.first { $0.id == input.id })

        #expect(copy.disabledThinkingOverride == .lowEffort)
        #expect(snapshot.configuration.providers.first { $0.id == fixture.source.id } == before.providers.first)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
