import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application coordinator shutdown")
struct ApplicationCoordinatorShutdownTests {
    @Test("Handoff preserves connected integrations and their profiles")
    func handoffShutdown() async throws {
        let fixture = try await ShutdownCoordinatorFixture.make()

        await fixture.coordinator.shutdown(mode: .handoff)

        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.configuration == fixture.configuration)
        #expect(!snapshot.proxyRunning)
        #expect(fixture.claudeController.isRunning())
        #expect(fixture.codexController.isRunning())
        #expect(fixture.claudeProfile.restoreCount == 0)
        #expect(fixture.codexProfile.restoreCount == 0)
        #expect(fixture.claudeCodeProfile.restoreCount == 0)
        #expect(fixture.openCodeProfile.restoreCount == 0)
        #expect(fixture.store.saves.isEmpty)
        #expect(await fixture.transport.didShutdown)
    }

    @Test("User quit restores every connected integration")
    func userQuitShutdown() async throws {
        let fixture = try await ShutdownCoordinatorFixture.make()

        await fixture.coordinator.shutdown(mode: .userQuit)

        let snapshot = await fixture.coordinator.snapshot()
        #expect(!snapshot.configuration.connected)
        #expect(!snapshot.configuration.codex.connected)
        #expect(!snapshot.configuration.claudeCode.connected)
        #expect(!snapshot.configuration.openCode.connected)
        #expect(!snapshot.proxyRunning)
        #expect(fixture.claudeController.isRunning())
        #expect(fixture.codexController.isRunning())
        #expect(fixture.claudeProfile.restoreCount == 1)
        #expect(fixture.codexProfile.restoreCount == 1)
        #expect(fixture.claudeCodeProfile.restoreCount == 1)
        #expect(fixture.openCodeProfile.restoreCount == 1)
        #expect(fixture.store.saves.last == snapshot.configuration)
        #expect(await fixture.transport.didShutdown)
    }
}

@MainActor
private struct ShutdownCoordinatorFixture {
    let configuration: AppConfiguration
    let store: RecordingConfigurationStore
    let claudeProfile: TestClaudeProfileManager
    let claudeController: TestClaudeController
    let codexProfile: TestCodexProfileManager
    let codexController: TestCodexController
    let claudeCodeProfile: TestClaudeCodeProfileManager
    let openCodeProfile: TestOpenCodeProfileManager
    let transport: StaticCatalogTransport
    let coordinator: ApplicationCoordinator

    static func make() async throws -> Self {
        let providerID = UUID()
        let mapping = ModelMapping(providerID: providerID, modelID: "applied")
        let configuration = AppConfiguration(
            providers: [
                Provider(
                    id: providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .none,
                    models: [DiscoveredModel(id: "applied")],
                    status: .ready
                )
            ],
            mappings: ["claude-sonnet-5": mapping],
            connected: true,
            claudeCode: ClaudeCodeConfiguration(
                connected: true,
                defaultModel: "claude-sonnet-5"
            ),
            codex: CodexConfiguration(connected: true, defaultModel: mapping),
            openCode: OpenCodeConfiguration(connected: true, defaultModel: mapping)
        )
        let store = RecordingConfigurationStore(configuration: configuration)
        let claudeProfile = TestClaudeProfileManager(active: true)
        let claudeController = TestClaudeController(running: true)
        let codexProfile = TestCodexProfileManager(active: true)
        let codexController = TestCodexController(running: true)
        let claudeCodeProfile = TestClaudeCodeProfileManager(status: .active)
        let openCodeProfile = TestOpenCodeProfileManager(status: .active)
        let transport = StaticCatalogTransport()
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
        store.clearSaves()
        return Self(
            configuration: store.configuration,
            store: store,
            claudeProfile: claudeProfile,
            claudeController: claudeController,
            codexProfile: codexProfile,
            codexController: codexController,
            claudeCodeProfile: claudeCodeProfile,
            openCodeProfile: openCodeProfile,
            transport: transport,
            coordinator: coordinator
        )
    }
}
