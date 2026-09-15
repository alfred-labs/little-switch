import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Provider image probing lifecycle")
struct ProviderImageInputProbingTests {
    @Test("Startup and refresh return while a background probe is suspended")
    func nonblocking() async throws {
        let fixture = await ImageProbingFixture.make()
        let started = try await fixture.coordinator.start()
        #expect(started.configuration.providers[0].status == .ready)
        try await fixture.prober.waitForCall()
        let refreshed = try await fixture.coordinator.refreshProvider(id: fixture.provider.id)
        #expect(
            refreshed.imageProbeProgress[fixture.provider.id]
                == ProviderImageProbeProgress(completed: 0, total: 1, running: true))
        #expect(await fixture.prober.calls == 1)
        await fixture.prober.release.open()
        let _: Bool = try await eventually(description: "completed and persisted image probe") {
            let snapshot = await fixture.coordinator.snapshot()
            return snapshot.imageProbeProgress[fixture.provider.id]?.running == false ? true : nil
        }
        #expect(fixture.store.configuration.providers[0].imageInputObservations.count == 1)
        #expect(await fixture.coordinator.snapshot().configuration.providers[0].status == .ready)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("An inconclusive probe is diagnostic, not a provider connection failure")
    func inconclusive() async throws {
        let fixture = await ImageProbingFixture.make(outcome: .inconclusive(.timeout))
        _ = try await fixture.coordinator.start()
        await fixture.prober.release.open()
        let _: Bool = try await eventually(description: "inconclusive image diagnostic") {
            await fixture.coordinator.snapshot().imageInputDiagnostics.count == 1 ? true : nil
        }
        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.configuration.providers[0].status == .ready)
        #expect(snapshot.configuration.providers[0].lastError == nil)
        #expect(snapshot.configuration.providers[0].imageInputObservations.isEmpty)
        #expect(snapshot.imageInputDiagnostics[0].result.outcome == .inconclusive(.timeout))
        _ = try await fixture.coordinator.refreshProvider(id: fixture.provider.id)
        #expect(await fixture.prober.calls == 1)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A successful save schedules a probe but a failed save never does")
    func saveOnlyAfterCommit() async throws {
        let fixture = await ImageProbingFixture.make(empty: true)
        _ = try await fixture.coordinator.start()
        fixture.store.failNextSave()
        let input = ProviderInput(name: "New", baseURL: "https://provider.example", authMode: .none)
        await #expect(throws: RecordingConfigurationStore.Error.injected) {
            try await fixture.coordinator.saveProvider(input)
        }
        #expect(await fixture.prober.calls == 0)
        let saved = try await fixture.coordinator.saveProvider(input)
        #expect(saved.configuration.providers.count == 1)
        try await fixture.prober.waitForCall()
        await fixture.coordinator.shutdown(mode: .handoff)
        #expect(await fixture.coordinator.imageInputRegistry.waiterCount == 0)
    }

    @Test("Before gateway admission is ready, refresh cannot spend a probe")
    func deferred() async throws {
        let fixture = await ImageProbingFixture.make()
        await fixture.coordinator.loadImageProbingFixture(fixture.provider)
        _ = try await fixture.coordinator.refreshProvider(id: fixture.provider.id)
        #expect(await fixture.prober.calls == 0)
        #expect(await fixture.coordinator.snapshot().imageProbeProgress[fixture.provider.id]?.running != true)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}

struct ImageProbingFixture: Sendable {
    let provider: Provider
    let prober: CoordinatorImageTestProber
    let store: RecordingConfigurationStore
    let coordinator: ApplicationCoordinator

    @MainActor static func make(
        outcome: ModelImageInputProbeOutcome = .verified,
        empty: Bool = false
    ) async -> ImageProbingFixture {
        let provider = Provider(
            name: "Example",
            baseURL: "https://provider.example",
            authMode: .none,
            models: [DiscoveredModel(id: "model")],
            status: .ready)
        let store = RecordingConfigurationStore(configuration: AppConfiguration(providers: empty ? [] : [provider]))
        let transport = StaticCatalogTransport()
        await transport.serveCatalog(#"{"data":[{"id":"model"}]}"#)
        let prober = CoordinatorImageTestProber(outcome: outcome)
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: transport,
            gatewayTransportBuilder: InjectedGatewayTransportBuilder(transport: TestGatewayTransport()),
            gatewayServerOverride: TestGatewayServer(),
            gatewayFactory: LiveGatewayFactory(builder: LiveGatewayBuilder()),
            imageInputProber: prober)
        return ImageProbingFixture(provider: provider, prober: prober, store: store, coordinator: coordinator)
    }
}

actor CoordinatorImageTestProber: ModelImageInputProbing {
    private(set) var calls = 0
    let release = AsyncTestGate()
    let outcome: ModelImageInputProbeOutcome

    init(outcome: ModelImageInputProbeOutcome) { self.outcome = outcome }

    func probe(
        provider: Provider,
        model: DiscoveredModel,
        wire: ModelImageInputWire,
        secret: String?
    ) async throws -> ModelImageInputProbeResult {
        calls += 1
        try await release.wait()
        return ModelImageInputProbeResult(outcome: outcome, usage: nil, startedAt: Date(), durationSeconds: 1)
    }

    func waitForCall() async throws {
        let _: Bool = try await eventually(description: "background image probe") { await self.calls > 0 ? true : nil }
    }
}

extension ApplicationCoordinator {
    fileprivate func loadImageProbingFixture(_ provider: Provider) { configuration.providers = [provider] }
}
