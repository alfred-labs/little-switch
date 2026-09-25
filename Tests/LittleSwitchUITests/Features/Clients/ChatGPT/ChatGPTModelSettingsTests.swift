import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Dedicated Chat model settings")
struct ChatGPTModelSettingsTests {
    @Test("Apply rejects an empty Chat draft and keeps the saved selection")
    func emptyDraftCannotBeApplied() async throws {
        let fixture = try await ChatGPTFixture.make()
        let previous = fixture.store.configuration
        #expect(try await fixture.coordinator.applyChatGPTSettings().configuration == previous)
        _ = try await fixture.coordinator.setChatGPTModel(nil)
        await #expect(throws: ChatGPTConnectionError.noModels) {
            try await fixture.coordinator.applyChatGPTSettings()
        }
        #expect(fixture.store.configuration == previous)
        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.hasPendingChatGPTChanges)
        #expect(snapshot.configuration.chatgpt.model == nil)
        #expect(fixture.events.recorded.isEmpty)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Selecting a Chat model keeps an independent draft until Apply")
    func independentDraft() async throws {
        let fixture = try await ChatGPTFixture.make()
        let previous = fixture.store.configuration
        let provider = try #require(previous.providers.first)
        let choice = ModelMapping(providerID: provider.id, modelID: "replacement")
        _ = try await fixture.coordinator.setCodexModelsExposure([choice], exposed: false)
        let drafted = try await fixture.coordinator.setChatGPTModel(choice)
        #expect(drafted.configuration.chatgpt.model == choice)
        #expect(drafted.hasPendingChatGPTChanges)
        #expect(fixture.store.configuration.chatgpt == previous.chatgpt)
        #expect(fixture.events.recorded.isEmpty)
        let applied = try await fixture.coordinator.applyChatGPTSettings()
        #expect(applied.configuration.chatgpt.model == choice)
        #expect(!applied.hasPendingChatGPTChanges)
        #expect(applied.configuration.codex.defaultModel == previous.codex.defaultModel)
        #expect(applied.configuration.codex.excludedModels.contains(choice))
        #expect(!applied.configuration.chatgpt.connected)
        #expect(fixture.events.recorded.isEmpty)
        #expect(fixture.builder.states.isEmpty)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Apply failure preserves the selected draft and saved choice")
    func saveFailure() async throws {
        let fixture = try await ChatGPTFixture.make()
        let previous = fixture.store.configuration
        let provider = try #require(previous.providers.first)
        let choice = ModelMapping(providerID: provider.id, modelID: "replacement")
        _ = try await fixture.coordinator.setChatGPTModel(choice)
        fixture.store.failNextSave()
        await #expect(throws: (any Error).self) { try await fixture.coordinator.applyChatGPTSettings() }
        #expect(fixture.store.configuration == previous)
        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.configuration.chatgpt.model == choice)
        #expect(snapshot.hasPendingChatGPTChanges)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("The shared connection applies the chosen Chat draft without changing Codex's default")
    func connectWithDraft() async throws {
        let fixture = try await ChatGPTFixture.make(hasChatModel: false)
        let previous = fixture.store.configuration
        let provider = try #require(previous.providers.first)
        let choice = ModelMapping(providerID: provider.id, modelID: "replacement")
        _ = try await fixture.coordinator.setChatGPTModel(choice)
        let connected = try await fixture.coordinator.connectDesktopClients()
        #expect(connected.configuration.chatgpt.model == choice)
        #expect(!connected.hasPendingChatGPTChanges)
        #expect(connected.configuration.codex.defaultModel == previous.codex.defaultModel)
        let disconnected = try await fixture.coordinator.disconnectDesktopClients()
        #expect(disconnected.configuration.chatgpt.model == choice)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Unknown model selections are rejected without erasing the saved choice")
    func invalidSelection() async throws {
        let fixture = try await ChatGPTFixture.make()
        let previous = fixture.store.configuration
        let provider = try #require(previous.providers.first)
        await #expect(throws: (any Error).self) {
            try await fixture.coordinator.setChatGPTModel(.init(providerID: provider.id, modelID: "missing"))
        }
        #expect(await fixture.coordinator.snapshot().configuration == previous)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
