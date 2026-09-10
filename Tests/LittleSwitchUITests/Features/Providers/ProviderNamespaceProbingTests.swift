import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Injected provider namespace diagnostic")
struct ProviderNamespaceProbingTests {
    private static func provider(
        baseURL: String = "https://provider.example/api",
        models: [DiscoveredModel] = [DiscoveredModel(id: "probe-model")],
        namespaceProbe: ProviderNamespaceProbe? = nil
    ) -> Provider {
        var provider = Provider(
            name: "Fixture", baseURL: baseURL, authMode: .bearer, models: models
        )
        provider.namespaceProbe = namespaceProbe
        return provider
    }

    private static func verdict(model: String?) -> ProviderNamespaceProbe {
        ProviderNamespaceProbe(
            verdict: .restored, model: model, date: Date(timeIntervalSince1970: 123)
        )
    }

    @Test("A changed endpoint probes the discovered first model after discovery")
    func freshProbe() async throws {
        let prober = RecordingNamespaceProber(result: Self.verdict(model: "probe-model"))
        let coordinator = makeCoordinator(prober)
        let provider = Self.provider()

        let probe = try await coordinator.namespaceProbeForSave(
            provider: provider,
            previous: nil,
            credentialChanged: true,
            secret: "synthetic-key",
            wireProbe: ProviderWireProbe(
                messages: .available, responses: .available, chatCompletions: .available
            )
        )

        #expect(probe == Self.verdict(model: "probe-model"))
        #expect(await prober.calls == [.init(model: "probe-model", secret: "synthetic-key")])
    }

    @Test("An unchanged endpoint, credential, and first model reuse the cached verdict")
    func reuse() async throws {
        let prober = RecordingNamespaceProber(result: Self.verdict(model: "probe-model"))
        let coordinator = makeCoordinator(prober)
        let previous = Self.provider(namespaceProbe: Self.verdict(model: "probe-model"))

        let probe = try await coordinator.namespaceProbeForSave(
            provider: previous,
            previous: previous,
            credentialChanged: false,
            secret: nil,
            wireProbe: nil
        )

        #expect(probe == Self.verdict(model: "probe-model"))
        #expect(await prober.calls.isEmpty)
    }

    @Test("A different first model must be measured again on the same endpoint")
    func changedModelReprobes() async throws {
        let prober = RecordingNamespaceProber(result: Self.verdict(model: "other-model"))
        let coordinator = makeCoordinator(prober)
        let previous = Self.provider(namespaceProbe: Self.verdict(model: "probe-model"))
        let provider = Self.provider(models: [DiscoveredModel(id: "other-model")])

        let probe = try await coordinator.namespaceProbeForSave(
            provider: provider,
            previous: previous,
            credentialChanged: false,
            secret: nil,
            wireProbe: nil
        )

        #expect(probe == Self.verdict(model: "other-model"))
        #expect(await prober.calls == [.init(model: "other-model", secret: nil)])
    }

    @Test("A route the wire probe proved absent skips the behavioral probe")
    func absentRouteSkipsProbe() async throws {
        let prober = RecordingNamespaceProber(result: Self.verdict(model: "probe-model"))
        let coordinator = makeCoordinator(prober)
        let provider = Self.provider()

        let probe = try await coordinator.namespaceProbeForSave(
            provider: provider,
            previous: nil,
            credentialChanged: true,
            secret: nil,
            wireProbe: ProviderWireProbe(
                messages: .available, responses: .absent, chatCompletions: .available
            )
        )

        #expect(probe == nil)
        #expect(await prober.calls.isEmpty)
    }

    @Test("A provider with no discovered model has nothing to probe")
    func noModelSkipsProbe() async throws {
        let prober = RecordingNamespaceProber(result: Self.verdict(model: nil))
        let coordinator = makeCoordinator(prober)
        let provider = Self.provider(models: [])

        let probe = try await coordinator.namespaceProbeForSave(
            provider: provider,
            previous: nil,
            credentialChanged: true,
            secret: nil,
            wireProbe: ProviderWireProbe(
                messages: .available, responses: .available, chatCompletions: .available
            )
        )

        #expect(probe == nil)
        #expect(await prober.calls.isEmpty)
    }

    @Test("An injected cancellation aborts the save-time diagnostic")
    func cancellation() async throws {
        let coordinator = makeCoordinator(CancelledNamespaceProber())
        let provider = Self.provider()
        await #expect(throws: CancellationError.self) {
            try await coordinator.namespaceProbeForSave(
                provider: provider,
                previous: nil,
                credentialChanged: true,
                secret: nil,
                wireProbe: ProviderWireProbe(
                    messages: .available, responses: .available, chatCompletions: .available
                )
            )
        }
    }

    private func makeCoordinator(
        _ namespaceProber: any ProviderNamespaceProbing
    ) -> ApplicationCoordinator {
        ApplicationCoordinator(
            configurationStore: RecordingConfigurationStore(configuration: AppConfiguration()),
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransportBuilder: InjectedGatewayTransportBuilder(transport: TestGatewayTransport()),
            gatewayFactory: LiveGatewayFactory(builder: LiveGatewayBuilder()),
            providerNamespaceProber: namespaceProber
        )
    }
}

private actor RecordingNamespaceProber: ProviderNamespaceProbing {
    struct Call: Equatable, Sendable {
        let model: String
        let secret: String?
    }

    let result: ProviderNamespaceProbe
    private(set) var calls: [Call] = []

    init(result: ProviderNamespaceProbe) {
        self.result = result
    }

    func probe(provider: Provider, secret: String?, model: String) async throws -> ProviderNamespaceProbe {
        calls.append(Call(model: model, secret: secret))
        return result
    }
}

private struct CancelledNamespaceProber: ProviderNamespaceProbing {
    func probe(provider: Provider, secret: String?, model: String) async throws -> ProviderNamespaceProbe {
        throw CancellationError()
    }
}
