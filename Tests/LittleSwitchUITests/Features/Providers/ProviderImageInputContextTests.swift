import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Provider image context synchronization")
struct ProviderImageInputContextTests {
    @Test("Deleting a provider discards its completed diagnostic and late context synchronization")
    func deletedProvider() async throws {
        let fixture = await ImageProbingFixture.make(outcome: .inconclusive(.timeout))
        _ = try await fixture.coordinator.start()
        await fixture.prober.release.open()
        try await waitForCompletedProbe(fixture)
        #expect(await fixture.coordinator.snapshot().imageInputDiagnostics.count == 1)

        _ = try await fixture.coordinator.deleteProvider(id: fixture.provider.id)
        await fixture.coordinator.synchronizeImageInputContext(providerID: fixture.provider.id)
        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.configuration.providers.isEmpty)
        #expect(snapshot.imageInputDiagnostics.isEmpty)
        #expect(snapshot.imageProbeProgress.isEmpty)
        #expect(await fixture.coordinator.imageInputRegistry.generation(providerID: fixture.provider.id) == nil)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("An invalid replacement endpoint invalidates the old diagnostic and cannot spend another probe")
    func invalidEndpoint() async throws {
        let fixture = await ImageProbingFixture.make(outcome: .inconclusive(.timeout))
        _ = try await fixture.coordinator.start()
        await fixture.prober.release.open()
        try await waitForCompletedProbe(fixture)
        #expect(await fixture.coordinator.snapshot().imageInputDiagnostics.count == 1)

        var invalid = fixture.provider
        invalid.baseURL = "not a URL"
        await fixture.coordinator.installConfigurationForEdgeCoverage(AppConfiguration(providers: [invalid]))
        await fixture.coordinator.synchronizeImageInputContext(providerID: invalid.id)
        await fixture.coordinator.scheduleImageInputProbes(providerID: invalid.id)
        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.imageInputPersistenceFailures == [invalid.id])
        #expect(snapshot.imageInputDiagnostics.isEmpty)
        #expect(snapshot.imageProbeProgress.isEmpty)
        #expect(await fixture.prober.calls == 1)
        #expect(fixture.store.configuration.providers[0].baseURL == "https://provider.example")
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    private func waitForCompletedProbe(_ fixture: ImageProbingFixture) async throws {
        let _: Bool = try await eventually(description: "completed image context probe") {
            await fixture.coordinator.snapshot().imageProbeProgress[fixture.provider.id]?.running == false ? true : nil
        }
    }
}
