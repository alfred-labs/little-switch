import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Provider image probe races")
struct ProviderImageInputProbeRaceTests {
    @Test("An observation write failure preserves persisted configuration and runtime knowledge")
    func persistenceFailure() async throws {
        let fixture = await ImageProbingFixture.make()
        _ = try await fixture.coordinator.start()
        try await fixture.prober.waitForCall()
        fixture.store.failNextSave()
        await fixture.prober.release.open()
        let _: Bool = try await eventually(description: "observation write failure") {
            await fixture.coordinator.snapshot().imageInputPersistenceFailures.contains(fixture.provider.id)
                ? true : nil
        }
        #expect(fixture.store.configuration.providers[0].imageInputObservations.isEmpty)
        #expect(await fixture.coordinator.snapshot().configuration.providers[0].imageInputObservations.isEmpty)
        let generation = await fixture.coordinator.imageProbeGenerations[fixture.provider.id]
        #expect(
            await fixture.coordinator.imageInputRegistry.observations(
                providerID: fixture.provider.id, generation: generation
            ).count == 1)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Deleting a provider cancels its probe and rejects a delayed callback")
    func deletion() async throws {
        let fixture = await ImageProbingFixture.make()
        _ = try await fixture.coordinator.start()
        try await fixture.prober.waitForCall()
        let generation = try #require(
            await fixture.coordinator.imageInputRegistry.generation(providerID: fixture.provider.id))
        _ = try await fixture.coordinator.deleteProvider(id: fixture.provider.id)
        let key = try ModelImageInputPolicyResolver.key(provider: fixture.provider, modelID: "model", wire: .responses)
        await fixture.coordinator.acceptImageInputObservation(
            ModelImageInputObservation(key: key, verdict: .verified, source: .visualProbe, observedAt: Date()),
            generation: generation)
        #expect(fixture.store.configuration.providers.isEmpty)
        #expect(await fixture.coordinator.snapshot().imageProbeProgress.isEmpty)
        #expect(await fixture.coordinator.imageInputRegistry.generation(providerID: fixture.provider.id) == nil)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Changing the endpoint rejects the old epoch without overwriting the saved edit")
    func edit() async throws {
        let fixture = await ImageProbingFixture.make()
        _ = try await fixture.coordinator.start()
        try await fixture.prober.waitForCall()
        let old = try #require(await fixture.coordinator.imageInputRegistry.generation(providerID: fixture.provider.id))
        _ = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.provider.id, name: "Edited", baseURL: "https://other.example", authMode: .none))
        let key = try ModelImageInputPolicyResolver.key(provider: fixture.provider, modelID: "model", wire: .responses)
        await fixture.coordinator.acceptImageInputObservation(
            ModelImageInputObservation(key: key, verdict: .unsupported, source: .providerRejection, observedAt: Date()),
            generation: old)
        #expect(fixture.store.configuration.providers[0].baseURL == "https://other.example")
        #expect(fixture.store.configuration.providers[0].imageInputObservations.isEmpty)
        #expect(await fixture.coordinator.imageInputRegistry.generation(providerID: fixture.provider.id) != old)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
