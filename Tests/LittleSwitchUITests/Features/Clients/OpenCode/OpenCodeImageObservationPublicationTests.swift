import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("OpenCode image observation publication")
struct OpenCodeImageObservationPublicationTests {
    @Test("Evidence is pending until Apply, survives rollback, and never controls a client application")
    func publication() async throws {
        let fixture = try await OpenCodeCoordinatorFixture.make()
        _ = try await fixture.coordinator.connectOpenCode()
        let previous = try #require(fixture.profile.activations.last)
        let provider = try #require(await fixture.coordinator.snapshot().configuration.providers.first)
        await fixture.coordinator.responsesCapabilities.record(providerID: provider.id, supportsNative: false)
        let generation = try #require(await fixture.coordinator.imageProbeGenerations[provider.id])
        let observation = ModelImageInputObservation(
            key: try ModelImageInputPolicyResolver.key(provider: provider, modelID: "applied", wire: .chatCompletions),
            verdict: .unsupported,
            source: .providerRejection,
            observedAt: Date())
        await fixture.coordinator.acceptImageInputObservation(observation, generation: generation)
        #expect(await fixture.coordinator.snapshot().hasPendingOpenCodeChanges)
        #expect(fixture.profile.activations == [previous])
        fixture.store.failNextSave()
        await #expect(throws: RecordingConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.applyOpenCode()
        }
        #expect(await fixture.coordinator.snapshot().hasPendingOpenCodeChanges)
        #expect(fixture.store.configuration.providers[0].imageInputObservations == [observation])
        let applied = try await fixture.coordinator.applyOpenCode()
        #expect(!applied.hasPendingOpenCodeChanges)
        #expect(fixture.profile.activations.last?.provider.models["alpha:applied"]?.modalities?.input == ["text"])
        #expect(fixture.codexController.quitCount == 0)
        #expect(fixture.claudeController.quitCount == 0)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
