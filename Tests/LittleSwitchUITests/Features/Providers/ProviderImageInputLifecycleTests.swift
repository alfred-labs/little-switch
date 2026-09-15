import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Provider image input lifecycle")
struct ProviderImageInputLifecycleTests {
    @Test("Refresh and a new coordinator reuse the persisted check without another inference")
    func restart() async throws {
        let first = await ImageProbingFixture.make(outcome: .unsupported)
        _ = try await first.coordinator.start()
        await first.prober.release.open()
        let _: Bool = try await eventually(description: "persisted capability") {
            let snapshot = await first.coordinator.snapshot()
            return snapshot.imageProbeProgress[first.provider.id]?.running == false ? true : nil
        }
        _ = try await first.coordinator.refreshProvider(id: first.provider.id)
        #expect(await first.prober.calls == 1)
        let observed = first.store.configuration.providers[0].imageInputObservations
        #expect(observed.count == 1)
        await first.coordinator.shutdown(mode: .handoff)
        let transport = StaticCatalogTransport()
        await transport.serveCatalog(#"{"data":[{"id":"model"}]}"#)
        let prober = CoordinatorImageTestProber(outcome: .verified)
        let restarted = ApplicationCoordinator(
            configurationStore: first.store,
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: transport,
            gatewayTransportBuilder: InjectedGatewayTransportBuilder(transport: TestGatewayTransport()),
            gatewayServerOverride: TestGatewayServer(),
            gatewayFactory: LiveGatewayFactory(builder: LiveGatewayBuilder()),
            imageInputProber: prober)
        _ = try await restarted.start()
        _ = try await restarted.refreshProvider(id: first.provider.id)
        #expect(await prober.calls == 0)
        #expect(first.store.configuration.providers[0].imageInputObservations == observed)
        #expect(
            try CodexCatalog.make(providers: first.store.configuration.providers, configuration: .disconnected)
                .models.allSatisfy { $0.inputModalities == ["text"] })
        await restarted.shutdown(mode: .handoff)
    }

    @Test("The selected default is checked before other exposed models")
    func defaultPriority() async throws {
        let fixture = try await CodexCoordinatorFixture.make()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.setCodexDefaultModel(
            ModelMapping(providerID: fixture.providerID, modelID: "replacement"))
        #expect(
            await fixture.coordinator.preferredImageProbeModelIDs(providerID: fixture.providerID).first == "replacement"
        )
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
