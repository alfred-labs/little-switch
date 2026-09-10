import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application coordinator startup coverage")
struct CoordinatorStartupCoverageTests {
    @Test("Live construction validates system paths without invoking integrations")
    func liveConstruction() async throws {
        let claudeController = ScriptedApplicationController()
        let codexController = ScriptedApplicationController()
        #expect(throws: ClaudeProfileManager.Error.applicationSupportUnavailable) {
            _ = try ApplicationCoordinator.live(
                applicationSupport: nil,
                homeDirectory: FileManager.default.temporaryDirectory,
                claudeController: claudeController,
                codexController: codexController
            )
        }

        let systemPaths = ApplicationCoordinatorLivePaths.system
        #expect(systemPaths.homeDirectory == FileManager.default.homeDirectoryForCurrentUser)

        let root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-live-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let paths = ApplicationCoordinatorLivePaths(
            applicationSupport: root.appending(path: "Application Support"),
            homeDirectory: root.appending(path: "Home")
        )
        let coordinator = try ApplicationCoordinatorLiveEnvironment.$paths.withValue(paths) {
            try ApplicationCoordinator.live(
                claudeController: claudeController,
                codexController: codexController
            )
        }
        await coordinator.shutdown(mode: .handoff)
    }

    @Test("Startup preserves load failures and maps gateway failures")
    func startupFailures() async {
        let loadStore = ScriptedConfigurationStore(configuration: AppConfiguration())
        loadStore.failLoad()
        let loadCoordinator = makeCoordinator(store: loadStore)

        await #expect(throws: ScriptedConfigurationStore.Error.loadInjected) {
            _ = try await loadCoordinator.start()
        }
        await loadCoordinator.shutdown(mode: .handoff)

        let gatewayCoordinator = makeCoordinator(
            store: ScriptedConfigurationStore(configuration: AppConfiguration()),
            gatewayServer: FailingStartupGatewayServer()
        )
        await #expect(throws: ApplicationCoordinator.Error.gatewayUnavailable) {
            _ = try await gatewayCoordinator.start()
        }
        await gatewayCoordinator.shutdown(mode: .handoff)
    }

    @Test("Startup clears invalid and inactive Claude connections")
    func claudeReconciliation() async throws {
        let invalid = startupFixture(
            configuration: AppConfiguration(connected: true),
            claudeActive: true
        )
        let invalidSnapshot = try await invalid.coordinator.start()
        #expect(!invalidSnapshot.configuration.connected)
        #expect(!invalid.store.configuration.connected)
        await invalid.coordinator.shutdown(mode: .handoff)

        let validConfiguration = connectedConfiguration(claude: true)
        let inactive = startupFixture(
            configuration: validConfiguration,
            claudeActive: false
        )
        let inactiveSnapshot = try await inactive.coordinator.start()
        #expect(!inactiveSnapshot.configuration.connected)
        #expect(!inactive.store.configuration.connected)
        await inactive.coordinator.shutdown(mode: .handoff)
    }

    @Test("Startup clears Codex connections without models or an active profile")
    func codexReconciliation() async throws {
        let invalid = startupFixture(
            configuration: AppConfiguration(codex: CodexConfiguration(connected: true)),
            codexActive: true
        )
        let invalidSnapshot = try await invalid.coordinator.start()
        #expect(!invalidSnapshot.configuration.codex.connected)
        #expect(!invalid.store.configuration.codex.connected)
        await invalid.coordinator.shutdown(mode: .handoff)

        let validConfiguration = connectedConfiguration(codex: true)
        let inactive = startupFixture(
            configuration: validConfiguration,
            codexActive: false
        )
        let inactiveSnapshot = try await inactive.coordinator.start()
        #expect(!inactiveSnapshot.configuration.codex.connected)
        #expect(!inactive.store.configuration.codex.connected)
        await inactive.coordinator.shutdown(mode: .handoff)
    }

    private func startupFixture(
        configuration: AppConfiguration,
        claudeActive: Bool = false,
        codexActive: Bool = false
    ) -> (store: ScriptedConfigurationStore, coordinator: ApplicationCoordinator) {
        let store = ScriptedConfigurationStore(configuration: configuration)
        return (
            store,
            makeCoordinator(
                store: store,
                claudeProfile: ScriptedClaudeProfileManager(active: claudeActive),
                codexProfile: ScriptedCodexProfileManager(active: codexActive)
            )
        )
    }

    private func makeCoordinator(
        store: ScriptedConfigurationStore,
        claudeProfile: ScriptedClaudeProfileManager = ScriptedClaudeProfileManager(),
        codexProfile: ScriptedCodexProfileManager = ScriptedCodexProfileManager(),
        gatewayServer: any GatewayServing = TestGatewayServer()
    ) -> ApplicationCoordinator {
        ApplicationCoordinator(
            configurationStore: store,
            secretStore: ScriptedSecretStore(),
            profileManager: claudeProfile,
            claudeController: ScriptedApplicationController(),
            codexProfileManager: codexProfile,
            codexController: ScriptedApplicationController(),
            discoveryTransport: ScriptedCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: gatewayServer
        )
    }

    private func connectedConfiguration(
        claude: Bool = false,
        codex: Bool = false
    ) -> AppConfiguration {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "applied")],
            status: .ready
        )
        return AppConfiguration(
            providers: [provider],
            mappings: [
                "claude-sonnet-5": ModelMapping(providerID: providerID, modelID: "applied")
            ],
            connected: claude,
            codex: CodexConfiguration(connected: codex)
        )
    }
}

private actor FailingStartupGatewayServer: GatewayServing {
    enum Error: Swift.Error {
        case startInjected
    }

    var isRunning: Bool { false }

    func start() async throws {
        throw Error.startInjected
    }

    func stop() async {}
}
