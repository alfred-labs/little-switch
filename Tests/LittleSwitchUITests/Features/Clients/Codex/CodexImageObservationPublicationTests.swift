import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Codex image observation publication")
struct CodexImageObservationPublicationTests {
    @Test("A check completed during Apply cannot be erased by the captured client candidate")
    func concurrentCompletion() async throws {
        let fixture = try await CodexCoordinatorFixture.make(codexRunning: true)
        defer { fixture.remove() }
        _ = try await fixture.coordinator.connectCodex()
        _ = try await fixture.coordinator.setCodexDefaultModel(
            ModelMapping(providerID: fixture.providerID, modelID: "replacement"))
        let provider = try #require(await fixture.coordinator.snapshot().configuration.providers.first)
        let generation = try #require(await fixture.coordinator.imageProbeGenerations[provider.id])
        let observation = ModelImageInputObservation(
            key: try ModelImageInputPolicyResolver.key(provider: provider, modelID: "applied", wire: .responses),
            verdict: .unsupported,
            source: .providerRejection,
            observedAt: Date())
        fixture.codexController.onQuit = {
            await fixture.coordinator.acceptImageInputObservation(observation, generation: generation)
        }
        let applied = try await fixture.coordinator.applyCodexSettings()
        #expect(applied.configuration.providers[0].imageInputObservations == [observation])
        #expect(fixture.store.configuration.providers[0].imageInputObservations == [observation])
        #expect(applied.hasPendingCodexChanges)
        fixture.codexController.onQuit = nil
        let refreshed = try await fixture.coordinator.applyCodexSettings()
        #expect(!refreshed.hasPendingCodexChanges)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Learning waits for Apply and uses the selected route in the exact signature")
    func publication() async throws {
        let fixture = try await CodexCoordinatorFixture.make()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.connectCodex()
        let previous = try #require(fixture.codexProfile.signatures.last)
        let provider = try #require(await fixture.coordinator.snapshot().configuration.providers.first)
        await fixture.coordinator.responsesCapabilities.record(
            providerID: provider.id, supportsNative: false)
        let generation = try #require(await fixture.coordinator.imageProbeGenerations[provider.id])
        await fixture.coordinator.acceptImageInputObservation(
            ModelImageInputObservation(
                key: try ModelImageInputPolicyResolver.key(
                    provider: provider, modelID: "applied", wire: .chatCompletions),
                verdict: .unsupported,
                source: .providerRejection,
                observedAt: Date()),
            generation: generation)
        let pending = await fixture.coordinator.snapshot()
        #expect(pending.hasPendingCodexChanges)
        #expect(fixture.codexProfile.signatures == [previous])
        #expect(fixture.codexController.quitCount == 0)
        let applied = try await fixture.coordinator.applyCodexSettings()
        #expect(!applied.hasPendingCodexChanges)
        #expect(fixture.codexProfile.signatures.count == 2)
        #expect(fixture.codexProfile.signatures.last != previous)
        #expect(await fixture.coordinator.snapshot().hasPendingCodexChanges == false)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
