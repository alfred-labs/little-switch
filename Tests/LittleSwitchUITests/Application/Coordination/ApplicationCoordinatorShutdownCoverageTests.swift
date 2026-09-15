import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application coordinator shutdown coverage")
struct CoordinatorShutdownCoverageTests {
    @Test("Shutdown cancels and joins an in-flight catalog refresh")
    func cancelsCatalogRefresh() async throws {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "applied")],
            status: .ready
        )
        let store = ScriptedConfigurationStore(
            configuration: AppConfiguration(providers: [provider])
        )
        let transport = ScriptedCatalogTransport(
            executions: [.catalog, .catalog, .suspended]
        )
        // Keep the catalog execution script independent of optional inference diagnostics.
        let imageProber = CoordinatorImageTestProber(outcome: .inconclusive(.invalidResponse))
        await imageProber.release.open()
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: ScriptedClaudeProfileManager(),
            claudeController: ScriptedApplicationController(),
            discoveryTransport: transport,
            gatewayTransportBuilder: InjectedGatewayTransportBuilder(transport: TestGatewayTransport()),
            gatewayServerOverride: TestGatewayServer(),
            gatewayFactory: LiveGatewayFactory(builder: LiveGatewayBuilder()),
            imageInputProber: imageProber
        )
        _ = try await coordinator.start()

        let refresh = Task {
            try await coordinator.refreshProvider(id: providerID)
        }
        try await transport.waitForExecuteCount(3)
        #expect(await transport.executeCount == 3)

        await coordinator.shutdown(mode: .handoff)

        await #expect(throws: CancellationError.self) {
            _ = try await refresh.value
        }
        #expect(await transport.cancellationCount == 1)
        #expect(await transport.shutdownCount == 1)
    }

    @Test("Transport execution waits fail within a bounded interval")
    func executionWaitTimeout() async {
        let transport = ScriptedCatalogTransport()

        await #expect(throws: ScriptedCatalogTransport.WaitError.executeTimedOut(1)) {
            try await transport.waitForExecuteCount(1, timeout: .milliseconds(10))
        }
    }

    @Test("User quit completes state cleanup when every external cleanup fails")
    func ignoresExternalCleanupFailures() async throws {
        let providerID = UUID()
        let mapping = ModelMapping(providerID: providerID, modelID: "applied")
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "applied")],
            status: .ready
        )
        let configuration = AppConfiguration(
            providers: [provider],
            mappings: ["claude-sonnet-5": mapping],
            connected: true,
            claudeCode: ClaudeCodeConfiguration(
                connected: true,
                defaultModel: "claude-sonnet-5"
            ),
            codex: CodexConfiguration(connected: true, defaultModel: mapping),
            openCode: OpenCodeConfiguration(connected: true, defaultModel: mapping)
        )
        let store = ScriptedConfigurationStore(configuration: configuration)
        let claudeProfile = ScriptedClaudeProfileManager(active: true)
        let claudeController = ScriptedApplicationController(running: true)
        let codexProfile = TestCodexProfileManager(active: true)
        let codexController = ScriptedApplicationController(running: true)
        let claudeCodeProfile = TestClaudeCodeProfileManager(status: .active)
        let openCodeProfile = TestOpenCodeProfileManager(status: .active)
        let transport = ScriptedCatalogTransport(shutdownShouldFail: true)
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: claudeProfile,
            claudeController: claudeController,
            codexProfileManager: codexProfile,
            codexController: codexController,
            claudeCodeProfileManager: claudeCodeProfile,
            openCodeProfileManager: openCodeProfile,
            discoveryTransport: transport,
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer()
        )
        _ = try await coordinator.start()

        claudeProfile.failRestores(on: [1])
        codexProfile.failNextRestore()
        claudeCodeProfile.failNextRestore()
        openCodeProfile.failNextRestore()
        store.failFutureSaves(at: [1, 2, 3, 4])

        await coordinator.shutdown()

        let stopped = await coordinator.snapshot()
        #expect(!stopped.configuration.connected)
        #expect(!stopped.configuration.codex.connected)
        #expect(!stopped.configuration.claudeCode.connected)
        #expect(!stopped.configuration.openCode.connected)
        #expect(!stopped.proxyRunning)
        #expect(claudeController.isRunning())
        #expect(codexController.isRunning())
        #expect(claudeController.quitAttempts == 0)
        #expect(codexController.quitAttempts == 0)
        #expect(claudeProfile.restoreCount == 1)
        #expect(await transport.shutdownCount == 1)
    }

    @Test("Handoff ignores discovery transport shutdown failure")
    func handoffTransportFailure() async throws {
        let transport = ScriptedCatalogTransport(shutdownShouldFail: true)
        let coordinator = ApplicationCoordinator(
            configurationStore: ScriptedConfigurationStore(configuration: .init()),
            secretStore: MemorySecretStore(),
            profileManager: ScriptedClaudeProfileManager(),
            claudeController: ScriptedApplicationController(),
            discoveryTransport: transport,
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer()
        )
        _ = try await coordinator.start()

        await coordinator.shutdown(mode: .handoff)

        #expect(await transport.shutdownCount == 1)
        #expect(!(await coordinator.snapshot()).proxyRunning)
    }
}
