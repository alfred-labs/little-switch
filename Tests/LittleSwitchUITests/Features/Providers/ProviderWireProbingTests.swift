import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Injected provider wire diagnostic")
struct ProviderWireProbingTests {
    private let verdict = ProviderWireProbe(
        messages: .available, responses: .absent, chatCompletions: .unknown, date: Date(timeIntervalSince1970: 123))

    @Test("A save delegates the complete provider and credential to the injected diagnostic")
    func injectedDiagnostic() async throws {
        let prober = RecordingWireProber(result: verdict)
        let coordinator = makeCoordinator(prober)
        let provider = Provider(name: "Fixture", baseURL: "https://provider.example/api", authMode: .bearer)

        #expect(
            try await coordinator.wireProbeForSave(
                provider: provider, previous: nil, credentialChanged: true, secret: "synthetic-key") == verdict)
        #expect(await prober.calls == [.init(provider: provider, secret: "synthetic-key")])
    }

    @Test("A rename reuses the cached probe without calling the injected service")
    func reuse() async throws {
        let prober = RecordingWireProber(result: verdict)
        let coordinator = makeCoordinator(prober)
        let previous = Provider(
            name: "Before", baseURL: "https://provider.example/api", authMode: .none, wireProbe: verdict)
        var renamed = previous
        renamed.name = "After"

        #expect(
            try await coordinator.wireProbeForSave(
                provider: renamed, previous: previous, credentialChanged: false, secret: nil) == verdict)
        #expect(await prober.calls.isEmpty)
    }

    @Test("Changed endpoints, changed credentials and missing cache require a fresh diagnostic", arguments: [0, 1, 2])
    func refresh(reason: Int) async throws {
        let prober = RecordingWireProber(result: verdict)
        let coordinator = makeCoordinator(prober)
        let previous = Provider(
            name: "Fixture",
            baseURL: "https://provider.example/api",
            authMode: .none,
            wireProbe: reason == 2 ? nil : verdict)
        var provider = previous
        if reason == 0 { provider.baseURL = "https://other.example/api" }

        #expect(
            try await coordinator.wireProbeForSave(
                provider: provider, previous: previous, credentialChanged: reason == 1, secret: nil) == verdict)
        #expect(await prober.calls == [.init(provider: provider, secret: nil)])
    }

    @Test("An injected cancellation aborts the save-time diagnostic")
    func cancellation() async throws {
        let coordinator = makeCoordinator(CancelledWireProber())
        let provider = Provider(name: "Fixture", baseURL: "https://provider.example", authMode: .none)
        await #expect(throws: CancellationError.self) {
            try await coordinator.wireProbeForSave(
                provider: provider, previous: nil, credentialChanged: false, secret: nil)
        }
    }

    private func makeCoordinator(_ prober: any ProviderWireProbing) -> ApplicationCoordinator {
        ApplicationCoordinator(
            configurationStore: RecordingConfigurationStore(configuration: AppConfiguration()),
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransportBuilder: InjectedGatewayTransportBuilder(transport: TestGatewayTransport()),
            gatewayFactory: LiveGatewayFactory(builder: LiveGatewayBuilder()),
            providerWireProber: prober)
    }
}

private actor RecordingWireProber: ProviderWireProbing {
    struct Call: Equatable, Sendable {
        let provider: Provider
        let secret: String?
    }

    let result: ProviderWireProbe
    private(set) var calls: [Call] = []

    init(result: ProviderWireProbe) { self.result = result }

    func probe(provider: Provider, secret: String?) async throws -> ProviderWireProbe {
        calls.append(Call(provider: provider, secret: secret))
        return result
    }
}

private struct CancelledWireProber: ProviderWireProbing {
    func probe(provider: Provider, secret: String?) async throws -> ProviderWireProbe {
        throw CancellationError()
    }
}
