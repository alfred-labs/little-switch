import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Codex coordinator")
struct CodexCoordinatorTests {
    @Test("Disconnected Codex settings persist without touching either desktop app")
    func disconnectedSettings() async throws {
        let fixture = try await CodexCoordinatorFixture.make()
        defer { fixture.remove() }

        let hidden = ModelMapping(providerID: fixture.providerID, modelID: "replacement")
        let snapshot = try await fixture.coordinator.setCodexModelsExposure(
            [hidden],
            exposed: false
        )

        #expect(snapshot.configuration.codex.excludedModels == [hidden])
        #expect(!snapshot.hasPendingCodexChanges)
        #expect(fixture.codexController.quitCount == 0)
        #expect(fixture.codexController.openCount == 0)
        #expect(fixture.claudeController.quitCount == 0)
        #expect(fixture.claudeController.openCount == 0)
        #expect(try fixture.store.load().codex == snapshot.configuration.codex)
    }

    @Test("Codex connects and relaunches the running app")
    func connect() async throws {
        let fixture = try await CodexCoordinatorFixture.make(codexRunning: true)
        defer { fixture.remove() }

        let connected = try await fixture.coordinator.connectCodex()

        #expect(connected.configuration.codex.connected)
        #expect(!connected.configuration.connected)
        #expect(fixture.codexProfile.activations.count == 1)
        #expect(fixture.codexController.quitCount == 1)
        #expect(fixture.codexController.openCount == 1)
        #expect(fixture.claudeController.quitCount == 0)
        #expect(fixture.claudeController.openCount == 0)
    }

    @Test("The Codex relaunch patches the desktop effort menu after quitting")
    func relaunchPatchesDesktopStateAfterQuit() async throws {
        let fixture = try await CodexCoordinatorFixture.make(codexRunning: true)
        defer { fixture.remove() }
        let log = SharedEventLog()
        fixture.codexController.eventLog = log
        fixture.codexProfile.eventLog = log

        _ = try await fixture.coordinator.connectCodex()

        #expect(log.recorded == ["codex-quit", "codex-desktop-patch", "codex-open"])
    }

    @Test("A failed Codex quit skips the desktop patch and relaunch")
    func failedQuitSkipsDesktopPatch() async throws {
        let fixture = try await CodexCoordinatorFixture.make(codexRunning: true)
        defer { fixture.remove() }
        let log = SharedEventLog()
        fixture.codexController.eventLog = log
        fixture.codexProfile.eventLog = log
        fixture.codexController.failNextQuit()

        _ = try await fixture.coordinator.connectCodex()

        #expect(log.recorded.isEmpty)
        #expect(fixture.codexController.openCount == 0)
    }

    @Test("Quitting remembers the connected products for the next launch")
    func quitRemembersConnectedProducts() async throws {
        let fixture = try await CodexCoordinatorFixture.make()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.connectCodex()

        await fixture.coordinator.shutdown(mode: .userQuit)

        let saved = try fixture.store.load()
        #expect(saved.relaunchTargets.codex)
        #expect(!saved.codex.connected)
    }

    @Test("The next launch puts the remembered switches back on")
    func launchRestoresRememberedSwitches() async throws {
        let fixture = try await CodexCoordinatorFixture.make()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.connectCodex()
        await fixture.coordinator.shutdown(mode: .userQuit)

        let restarted = try await fixture.coordinator.start()

        #expect(restarted.configuration.codex.connected)
        #expect(try fixture.store.load().relaunchTargets == .none)
    }

    @Test("A product that fails to reconnect stays remembered for the next launch")
    func failedReconnectStaysRemembered() async throws {
        let fixture = try await CodexCoordinatorFixture.make()
        defer { fixture.remove() }
        var stored = try fixture.store.load()
        stored.relaunchTargets = RelaunchTargets(claudeCode: true)
        try fixture.store.save(stored)

        _ = try await fixture.coordinator.start()

        #expect(try fixture.store.load().relaunchTargets.claudeCode)
    }

    @Test("Every remembered product is attempted, and a success clears its flag")
    func launchAttemptsEveryRememberedProduct() async throws {
        let fixture = try await CodexCoordinatorFixture.make()
        defer { fixture.remove() }
        var stored = try fixture.store.load()
        stored.relaunchTargets = RelaunchTargets(
            claude: true,
            codex: true,
            claudeCode: true,
            openCode: true
        )
        try fixture.store.save(stored)

        _ = try await fixture.coordinator.start()

        #expect(!(try fixture.store.load().relaunchTargets.codex))
    }

    @Test("A launch without remembered switches leaves everything off")
    func launchWithoutTargetsStaysOff() async throws {
        let fixture = try await CodexCoordinatorFixture.make()
        defer { fixture.remove() }

        let started = try await fixture.coordinator.start()

        #expect(!started.configuration.codex.connected)
        #expect(try fixture.store.load().relaunchTargets == .none)
    }

    @Test("A handoff shutdown leaves the remembered products untouched")
    func handoffKeepsTargetsUntouched() async throws {
        let fixture = try await CodexCoordinatorFixture.make()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.connectCodex()

        await fixture.coordinator.shutdown(mode: .handoff)

        let saved = try fixture.store.load()
        #expect(saved.relaunchTargets == .none)
        #expect(saved.codex.connected)
    }

    @Test("A failed relaunch leaves a successful Codex connection intact")
    func relaunchFailureKeepsConnection() async throws {
        let fixture = try await CodexCoordinatorFixture.make(codexRunning: true)
        defer { fixture.remove() }
        fixture.codexController.failNextQuit()

        let connected = try await fixture.coordinator.connectCodex()

        #expect(connected.configuration.codex.connected)
        #expect(fixture.codexProfile.activations.count == 1)
        #expect(fixture.codexController.openCount == 0)
    }

    @Test("Connected exposure changes apply without controlling Codex")
    func applyWithoutControllingCodex() async throws {
        let fixture = try await CodexCoordinatorFixture.make()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.connectCodex()
        let hidden = ModelMapping(providerID: fixture.providerID, modelID: "applied")
        _ = try await fixture.coordinator.setCodexDefaultModel(
            ModelMapping(providerID: fixture.providerID, modelID: "replacement")
        )

        let pending = try await fixture.coordinator.setCodexModelsExposure(
            [hidden],
            exposed: false
        )
        #expect(pending.hasPendingCodexChanges)
        #expect(pending.configuration.codex.excludedModels == [hidden])
        #expect(try fixture.store.load().codex.excludedModels.isEmpty)

        let applied = try await fixture.coordinator.applyCodexSettings()

        #expect(!applied.hasPendingCodexChanges)
        #expect(applied.configuration.codex.excludedModels == [hidden])
        #expect(applied.configuration.codex.defaultModel?.modelID == "replacement")
        #expect(fixture.codexProfile.activations.count == 2)
        #expect(fixture.codexController.quitCount == 0)
        #expect(fixture.codexController.openCount == 0)
    }

    @Test("A failed apply restores the applied Codex layers and keeps the draft")
    func applyRollback() async throws {
        let fixture = try await CodexCoordinatorFixture.make()
        defer { fixture.remove() }
        let connected = try await fixture.coordinator.connectCodex()
        _ = try await fixture.coordinator.setCodexDefaultModel(
            ModelMapping(providerID: fixture.providerID, modelID: "replacement")
        )
        _ = try await fixture.coordinator.setCodexModelsExposure(
            [ModelMapping(providerID: fixture.providerID, modelID: "applied")],
            exposed: false
        )
        fixture.codexProfile.failNextActivation()

        await #expect(throws: TestCodexProfileManager.Error.activateInjected) {
            _ = try await fixture.coordinator.applyCodexSettings()
        }

        let rolledBack = await fixture.coordinator.snapshot()
        #expect(rolledBack.hasPendingCodexChanges)
        #expect(try fixture.store.load() == connected.configuration)
        #expect(fixture.codexProfile.activations.last == connected.configuration.codex)
        #expect(!fixture.codexController.isRunning())
        #expect(fixture.codexController.quitCount == 0)
        #expect(fixture.codexController.openCount == 0)
    }

    @Test("Disconnect restores Codex without changing Claude")
    func disconnect() async throws {
        let fixture = try await CodexCoordinatorFixture.make()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.connectCodex()

        let disconnected = try await fixture.coordinator.disconnectCodex()

        #expect(!disconnected.configuration.codex.connected)
        #expect(fixture.codexProfile.restoreCount == 1)
        #expect(fixture.codexController.quitCount == 0)
        #expect(fixture.codexController.openCount == 0)
        #expect(!disconnected.configuration.connected)
        #expect(fixture.claudeController.quitCount == 0)
        #expect(fixture.claudeController.openCount == 0)
    }
}

extension CodexCoordinatorTests {
    @Test("Only selected-provider concurrency changes stay pending until Apply")
    func providerConcurrencyApplyLifecycle() async throws {
        let fixture = try await CodexCoordinatorFixture.make()
        defer { fixture.remove() }
        let connected = try await fixture.coordinator.connectCodex()
        #expect(fixture.codexProfile.signatures.count == 1)
        #expect(
            fixture.codexProfile.signatures.last?.maximumConcurrentThreadsPerSession == 7
        )

        let unrelated = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.unrelatedProviderID,
                name: "Unrelated",
                baseURL: "http://127.0.0.1:11435",
                authMode: .none,
                maximumParallelRequests: 23
            )
        )
        #expect(!unrelated.hasPendingCodexChanges)
        #expect(fixture.codexProfile.signatures.count == 1)

        let pending = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .none,
                maximumParallelRequests: 11
            )
        )
        #expect(pending.hasPendingCodexChanges)
        #expect(fixture.codexProfile.signatures.count == 1)
        #expect(try fixture.store.load().codex == connected.configuration.codex)

        let applied = try await fixture.coordinator.applyCodexSettings()

        #expect(!applied.hasPendingCodexChanges)
        #expect(fixture.codexProfile.signatures.count == 2)
        #expect(
            fixture.codexProfile.signatures.last?.maximumConcurrentThreadsPerSession == 11
        )
    }

    @Test("A legacy profile stays connected and pending without startup activation")
    func legacyStartupAndApply() async throws {
        let fixture = try await CodexCoordinatorFixture.make(
            connected: true,
            legacyProfile: true
        )
        defer { fixture.remove() }

        let startup = await fixture.coordinator.snapshot()
        #expect(startup.configuration.codex.connected)
        #expect(startup.hasPendingCodexChanges)
        #expect(fixture.codexProfile.activations.isEmpty)
        #expect(fixture.codexProfile.signatures.isEmpty)
        #expect(fixture.codexProfile.expectedStatuses.count == 1)
        #expect(
            fixture.codexProfile.expectedStatuses.first?
                .maximumConcurrentThreadsPerSession == 7
        )

        let applied = try await fixture.coordinator.applyCodexSettings()

        #expect(!applied.hasPendingCodexChanges)
        #expect(fixture.codexProfile.signatures.count == 1)
        #expect(
            fixture.codexProfile.signatures.first?
                .maximumConcurrentThreadsPerSession == 7
        )
    }

    @Test("A failed legacy upgrade rolls the exact applied signature back")
    func legacyApplyRollback() async throws {
        let fixture = try await CodexCoordinatorFixture.make(
            connected: true,
            legacyProfile: true
        )
        defer { fixture.remove() }
        fixture.store.failNextSave()

        await #expect(throws: RecordingConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.applyCodexSettings()
        }

        let rolledBack = await fixture.coordinator.snapshot()
        #expect(rolledBack.configuration.codex.connected)
        #expect(rolledBack.hasPendingCodexChanges)
        #expect(
            fixture.codexProfile.signatures.map(
                \.maximumConcurrentThreadsPerSession
            ) == [7, nil]
        )
    }
}

@MainActor
struct CodexCoordinatorFixture {
    let root: URL
    let providerID: UUID
    let unrelatedProviderID: UUID
    let store: RecordingConfigurationStore
    let claudeController: TestClaudeController
    let codexController: TestCodexController
    let codexProfile: TestCodexProfileManager
    let coordinator: ApplicationCoordinator

    static func make(
        codexRunning: Bool = false,
        connected: Bool = false,
        legacyProfile: Bool = false,
        legacyWebSearch: Bool = false
    ) async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-codex-coordinator-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let providerID = UUID()
        let unrelatedProviderID = UUID()
        let providers = [
            Provider(
                id: providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .none,
                models: [
                    DiscoveredModel(id: "applied"),
                    DiscoveredModel(id: "replacement"),
                ],
                status: .ready,
                maximumParallelRequests: 7
            ),
            Provider(
                id: unrelatedProviderID,
                name: "Unrelated",
                baseURL: "http://127.0.0.1:11435",
                authMode: .none,
                models: [
                    DiscoveredModel(id: "applied"),
                    DiscoveredModel(id: "replacement"),
                ],
                status: .ready
            ),
        ]
        let store = RecordingConfigurationStore(
            configuration: AppConfiguration(
                providers: providers,
                codex: CodexConfiguration(
                    connected: connected,
                    defaultModel: ModelMapping(providerID: providerID, modelID: "applied")
                )
            )
        )
        let claudeController = TestClaudeController()
        let codexController = TestCodexController(running: codexRunning)
        let codexProfile = TestCodexProfileManager(
            active: connected,
            legacyActiveWithoutConcurrency: legacyProfile,
            legacyWebSearch: legacyWebSearch
        )
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: ClaudeProfileManager(
                paths: ClaudeProfilePaths(applicationSupport: root)
            ),
            claudeController: claudeController,
            codexProfileManager: codexProfile,
            codexController: codexController,
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer()
        )
        _ = try await coordinator.start()
        store.clearSaves()
        return Self(
            root: root,
            providerID: providerID,
            unrelatedProviderID: unrelatedProviderID,
            store: store,
            claudeController: claudeController,
            codexController: codexController,
            codexProfile: codexProfile,
            coordinator: coordinator
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
