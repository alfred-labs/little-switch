import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Image registry invalidation boundaries")
struct ModelImageInputRegistryInvalidationTests {
    @Test("Invalidating one provider removes its evidence and cooldown without clearing another provider")
    func providerIsolation() async throws {
        let one = imageProbeProvider(models: ["known", "retry"])
        let two = imageProbeProvider(models: ["known", "retry"])
        let instant = Date(timeIntervalSince1970: 1_000)
        let prober = RegistryTestProber(outcome: .inconclusive(.timeout))
        await prober.release.open()
        let registry = ModelImageInputRegistry(prober: prober, admission: RegistryTestAdmission()) { instant }
        let generation = UUID()
        var observations: [ModelImageInputObservation] = []
        for provider in [one, two] {
            try await registry.configure(provider: provider, generation: generation)
            let observation = ModelImageInputObservation(
                key: try ModelImageInputPolicyResolver.key(provider: provider, modelID: "known", wire: .responses),
                verdict: .verified,
                source: .visualProbe,
                observedAt: instant)
            observations.append(observation)
            await registry.record(observation, generation: generation)
            let result = try await registry.probeIfNeeded(
                provider: provider, model: provider.models[1], wire: .responses, secret: nil)
            #expect(result?.outcome == .inconclusive(.timeout))
            #expect(try await registry.candidates(provider: provider, preferredModelIDs: [], wire: .responses).isEmpty)
        }

        await registry.invalidate(providerID: one.id)
        #expect(await registry.observations(providerID: one.id, generation: generation).isEmpty)
        #expect(await registry.observations(providerID: two.id, generation: generation) == [observations[1]])
        #expect(try await registry.candidates(provider: two, preferredModelIDs: [], wire: .responses).isEmpty)

        try await registry.configure(provider: one, generation: UUID())
        #expect(try await registry.candidates(provider: one, preferredModelIDs: [], wire: .responses) == one.models)
        await registry.shutdown()
    }
}
