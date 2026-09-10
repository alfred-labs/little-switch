import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("OpenCode coordinator")
struct OpenCodeCoordinatorTests {
    @Test("Connect activates exact managed settings without controlling applications")
    func connect() async throws {
        let fixture = try await OpenCodeCoordinatorFixture.make()
        let before = await fixture.coordinator.snapshot()
        let expected = try OpenCodeManagedSettings.resolve(
            providers: before.configuration.providers,
            codex: before.configuration.codex,
            configuration: before.configuration.openCode
        )

        let connected = try await fixture.coordinator.connectOpenCode()

        #expect(connected.configuration.openCode.connected)
        #expect(connected.openCodeStatus == .connected)
        #expect(connected.proxyRunning)
        #expect(fixture.profile.activations == [expected])
        #expect(fixture.store.configuration.openCode.connected)
        #expect(fixture.claudeController.quitCount == 0)
        #expect(fixture.claudeController.openCount == 0)
        #expect(fixture.codexController.quitCount == 0)
        #expect(fixture.codexController.openCount == 0)
    }

    @Test("Disconnected defaults persist, normalize, validate, and roll back")
    func disconnectedDefault() async throws {
        let fixture = try await OpenCodeCoordinatorFixture.make()

        let changed = try await fixture.coordinator.setOpenCodeDefaultModel(fixture.beta)
        #expect(changed.configuration.openCode.defaultModel == fixture.beta)
        await #expect(throws: ApplicationCoordinator.Error.invalidMapping) {
            _ = try await fixture.coordinator.setOpenCodeDefaultModel(
                ModelMapping(providerID: UUID(), modelID: "missing")
            )
        }

        let normalized = try await fixture.coordinator.setOpenCodeDefaultModel(nil)
        #expect(normalized.configuration.openCode.defaultModel == fixture.alpha)
        fixture.store.failNextSave()
        await #expect(throws: RecordingConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.setOpenCodeDefaultModel(fixture.beta)
        }
        #expect((await fixture.coordinator.snapshot()).configuration.openCode.defaultModel == fixture.alpha)
    }

    @Test("Startup distinguishes normal, recovery, unavailable, drift, and empty states")
    func startupStatuses() async throws {
        let disconnected = try await OpenCodeCoordinatorFixture.make()
        #expect((await disconnected.coordinator.snapshot()).openCodeStatus == .disconnected)

        let orphan = try await OpenCodeCoordinatorFixture.make(profileStatus: .active)
        #expect((await orphan.coordinator.snapshot()).openCodeStatus == .recoveryAvailable)

        let active = try await OpenCodeCoordinatorFixture.make(
            openCodeConnected: true,
            profileStatus: .active
        )
        #expect((await active.coordinator.snapshot()).openCodeStatus == .connected)

        let drifted = try await OpenCodeCoordinatorFixture.make(
            openCodeConnected: true,
            profileStatus: .drifted
        )
        #expect((await drifted.coordinator.snapshot()).openCodeStatus == .needsAttention)

        let inactive = try await OpenCodeCoordinatorFixture.make(
            openCodeConnected: true,
            profileStatus: .inactive
        )
        #expect((await inactive.coordinator.snapshot()).openCodeStatus == .recoveryUnavailable)
        #expect(!inactive.store.configuration.openCode.connected)

        let missing = try await OpenCodeCoordinatorFixture.make(
            openCodeConnected: true,
            includeProfile: false
        )
        #expect((await missing.coordinator.snapshot()).openCodeStatus == .recoveryUnavailable)
        #expect(!missing.store.configuration.openCode.connected)

        let empty = try await OpenCodeCoordinatorFixture.make(
            openCodeConnected: true,
            profileStatus: .active,
            excludeAllModels: true
        )
        #expect((await empty.coordinator.snapshot()).openCodeStatus == .needsAttention)
        #expect(empty.store.configuration.openCode.connected)

        let failedStatusProfile = TestOpenCodeProfileManager(status: .active)
        failedStatusProfile.failStatus()
        let failedStatus = try await OpenCodeCoordinatorFixture.make(
            openCodeConnected: true,
            profile: failedStatusProfile
        )
        #expect((await failedStatus.coordinator.snapshot()).openCodeStatus == .recoveryUnavailable)
    }

    @Test("Connect reports recovery, dependency, catalog, and rollback failures")
    func connectFailures() async throws {
        let recovery = try await OpenCodeCoordinatorFixture.make(profileStatus: .active)
        await #expect(throws: ApplicationCoordinator.Error.openCodeRecoveryRequired) {
            _ = try await recovery.coordinator.connectOpenCode()
        }

        let unavailable = try await OpenCodeCoordinatorFixture.make(includeProfile: false)
        await #expect(throws: ApplicationCoordinator.Error.openCodeUnavailable) {
            _ = try await unavailable.coordinator.connectOpenCode()
        }

        let empty = try await OpenCodeCoordinatorFixture.make(excludeAllModels: true)
        await #expect(throws: ApplicationCoordinator.Error.noExposedOpenCodeModel) {
            _ = try await empty.coordinator.connectOpenCode()
        }

        let activation = try await OpenCodeCoordinatorFixture.make()
        activation.profile.failNextActivation()
        await #expect(throws: TestOpenCodeProfileManager.Error.activateInjected) {
            _ = try await activation.coordinator.connectOpenCode()
        }
        #expect(activation.profile.restoreCount == 1)
        #expect((await activation.coordinator.snapshot()).openCodeStatus == .disconnected)

        let rollback = try await OpenCodeCoordinatorFixture.make()
        rollback.profile.failNextActivation()
        rollback.profile.failNextRestore()
        await #expect(throws: ApplicationCoordinator.Error.rollbackFailed) {
            _ = try await rollback.coordinator.connectOpenCode()
        }
    }

    @Test("Connected default stays pending until Apply")
    func pendingDefault() async throws {
        let fixture = try await OpenCodeCoordinatorFixture.make()
        _ = try await fixture.coordinator.connectOpenCode()

        let pending = try await fixture.coordinator.setOpenCodeDefaultModel(fixture.beta)

        #expect(pending.configuration.openCode.defaultModel == fixture.beta)
        #expect(pending.hasPendingOpenCodeChanges)
        #expect(fixture.profile.activations.count == 1)
        #expect(fixture.store.configuration.openCode.defaultModel == fixture.alpha)
    }

    @Test("Apply succeeds and restores the prior profile transaction after save failure")
    func applyAndRollback() async throws {
        let success = try await OpenCodeCoordinatorFixture.make()
        _ = try await success.coordinator.connectOpenCode()
        _ = try await success.coordinator.setOpenCodeDefaultModel(success.beta)

        let applied = try await success.coordinator.applyOpenCode()

        #expect(applied.configuration.openCode.defaultModel == success.beta)
        #expect(!applied.hasPendingOpenCodeChanges)
        #expect(success.profile.activations.count == 2)

        let rollback = try await OpenCodeCoordinatorFixture.make()
        _ = try await rollback.coordinator.connectOpenCode()
        let prior = try #require(rollback.profile.activations.last)
        _ = try await rollback.coordinator.setOpenCodeDefaultModel(rollback.beta)
        rollback.store.failNextSave()

        await #expect(throws: RecordingConfigurationStore.Error.injected) {
            _ = try await rollback.coordinator.applyOpenCode()
        }
        #expect(rollback.profile.activations.last == prior)
        #expect((await rollback.coordinator.snapshot()).hasPendingOpenCodeChanges)

        let failedRollback = try await OpenCodeCoordinatorFixture.make()
        _ = try await failedRollback.coordinator.connectOpenCode()
        _ = try await failedRollback.coordinator.setOpenCodeDefaultModel(failedRollback.beta)
        failedRollback.store.failNextSave()
        failedRollback.profile.failNextRollback()
        await #expect(throws: ApplicationCoordinator.Error.rollbackFailed) {
            _ = try await failedRollback.coordinator.applyOpenCode()
        }
    }

    @Test("Apply is a no-op while disconnected and disconnect completes when connected")
    func applyNoOpAndDisconnectSuccess() async throws {
        let fixture = try await OpenCodeCoordinatorFixture.make()

        let unchanged = try await fixture.coordinator.applyOpenCode()
        #expect(!unchanged.configuration.openCode.connected)
        #expect(fixture.profile.activations.isEmpty)

        _ = try await fixture.coordinator.connectOpenCode()
        let disconnected = try await fixture.coordinator.disconnectOpenCode()

        #expect(!disconnected.configuration.openCode.connected)
        #expect(disconnected.openCodeStatus == .disconnected)
        #expect(fixture.profile.restoreCount == 1)
    }

    @Test("Apply preserves a persistence failure without needing a previous managed signature")
    func applyWithoutPreviousManagedProfile() async throws {
        let fixture = try await OpenCodeCoordinatorFixture.make(
            openCodeConnected: true,
            profileStatus: .active,
            excludeAllModels: true,
            codexConnected: true
        )

        await #expect(throws: ApplicationCoordinator.Error.noExposedOpenCodeModel) {
            _ = try await fixture.coordinator.applyOpenCode()
        }

        _ = try await fixture.coordinator.setCodexModelsExposure([fixture.alpha], exposed: true)
        _ = try await fixture.coordinator.applyCodexSettings()
        fixture.store.failNextSave()

        await #expect(throws: RecordingConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.applyOpenCode()
        }
        #expect((await fixture.coordinator.snapshot()).hasPendingOpenCodeChanges)
    }

    @Test("Disconnect saves false before restore and recovers true after failure")
    func disconnectRollback() async throws {
        let fixture = try await OpenCodeCoordinatorFixture.make()
        _ = try await fixture.coordinator.connectOpenCode()
        fixture.store.clearSaves()
        fixture.profile.failNextRestore()

        await #expect(throws: TestOpenCodeProfileManager.Error.restoreInjected) {
            _ = try await fixture.coordinator.disconnectOpenCode()
        }

        #expect(fixture.store.saves.map(\.openCode.connected) == [false, true])
        #expect(fixture.store.configuration.openCode.connected)
        #expect((await fixture.coordinator.snapshot()).openCodeStatus == .connected)
    }

    @Test("Orphan recovery restores without controlling applications")
    func restoreRecovery() async throws {
        let fixture = try await OpenCodeCoordinatorFixture.make(profileStatus: .active)

        let restored = try await fixture.coordinator.restoreOpenCodeSettings()

        #expect(restored.openCodeStatus == .disconnected)
        #expect(fixture.profile.restoreCount == 1)
        #expect(fixture.claudeController.quitCount == 0)
        #expect(fixture.codexController.quitCount == 0)
    }

    @Test("Recovery failure keeps orphan state and failed rollback save is explicit")
    func recoveryFailures() async throws {
        let orphan = try await OpenCodeCoordinatorFixture.make(profileStatus: .active)
        orphan.profile.failNextRestore()
        await #expect(throws: TestOpenCodeProfileManager.Error.restoreInjected) {
            _ = try await orphan.coordinator.restoreOpenCodeSettings()
        }
        #expect((await orphan.coordinator.snapshot()).openCodeStatus == .recoveryAvailable)

        let connected = try await OpenCodeCoordinatorFixture.make()
        _ = try await connected.coordinator.connectOpenCode()
        connected.profile.failNextRestore()
        connected.store.failSave(afterSuccessfulSaves: 1)
        await #expect(throws: ApplicationCoordinator.Error.rollbackFailed) {
            _ = try await connected.coordinator.disconnectOpenCode()
        }
    }

    @Test("Pending Codex exposure blocks OpenCode without consuming either draft")
    func codexApplyGate() async throws {
        let fixture = try await OpenCodeCoordinatorFixture.make(
            openCodeConnected: true,
            profileStatus: .active,
            codexConnected: true
        )

        _ = try await fixture.coordinator.setCodexDefaultModel(fixture.beta)
        let codexPending = try await fixture.coordinator.setCodexModelsExposure(
            [fixture.alpha],
            exposed: false
        )
        #expect(codexPending.hasPendingCodexChanges)
        #expect(codexPending.hasPendingOpenCodeChanges)

        await #expect(throws: ApplicationCoordinator.Error.codexApplyRequiredForOpenCode) {
            _ = try await fixture.coordinator.applyOpenCode()
        }
        #expect((await fixture.coordinator.snapshot()).hasPendingCodexChanges)

        let codexApplied = try await fixture.coordinator.applyCodexSettings()
        #expect(!codexApplied.hasPendingCodexChanges)
        #expect(codexApplied.hasPendingOpenCodeChanges)
        #expect(fixture.profile.activations.isEmpty)

        let openCodeApplied = try await fixture.coordinator.applyOpenCode()
        #expect(!openCodeApplied.hasPendingOpenCodeChanges)
        #expect(fixture.profile.activations.count == 1)
    }

    @Test("Pending Codex exposure also blocks OpenCode connect")
    func codexConnectGate() async throws {
        let fixture = try await OpenCodeCoordinatorFixture.make(codexConnected: true)
        _ = try await fixture.coordinator.setCodexModelsExposure([fixture.beta], exposed: false)

        await #expect(throws: ApplicationCoordinator.Error.codexApplyRequiredForOpenCode) {
            _ = try await fixture.coordinator.connectOpenCode()
        }
        #expect((await fixture.coordinator.snapshot()).hasPendingCodexChanges)
        #expect(fixture.profile.activations.isEmpty)
    }

    @Test("Provider deletion and committed Codex exposure create pending profile settings")
    func catalogChanges() async throws {
        let deletion = try await OpenCodeCoordinatorFixture.make(
            openCodeConnected: true,
            profileStatus: .active
        )
        let deleted = try await deletion.coordinator.deleteProvider(id: deletion.alpha.providerID)
        #expect(
            deleted.configuration.openCode.defaultModel
                == deleted.configuration.codex.resolvedDefaultModel(
                    in: deleted.configuration.providers
                )
        )
        #expect(deleted.hasPendingOpenCodeChanges)
        #expect(deletion.profile.activations.isEmpty)

        let exposure = try await OpenCodeCoordinatorFixture.make(
            openCodeConnected: true,
            profileStatus: .active
        )
        _ = try await exposure.coordinator.setCodexDefaultModel(exposure.beta)
        exposure.store.clearSaves()
        let hidden = try await exposure.coordinator.setCodexModelsExposure(
            [exposure.alpha],
            exposed: false
        )
        #expect(
            hidden.configuration.openCode.defaultModel
                == hidden.configuration.codex.resolvedDefaultModel(
                    in: hidden.configuration.providers
                )
        )
        #expect(hidden.hasPendingOpenCodeChanges)
        #expect(exposure.profile.activations.isEmpty)
    }
}

@MainActor
private struct OpenCodeCoordinatorFixture {
    let alpha: ModelMapping
    let beta: ModelMapping
    let store: RecordingConfigurationStore
    let profile: TestOpenCodeProfileManager
    let claudeController: TestClaudeController
    let codexController: TestCodexController
    let coordinator: ApplicationCoordinator

    static func make(
        openCodeConnected: Bool = false,
        profileStatus: OpenCodeProfileStatus = .inactive,
        profile: TestOpenCodeProfileManager? = nil,
        includeProfile: Bool = true,
        excludeAllModels: Bool = false,
        codexConnected: Bool = false
    ) async throws -> Self {
        let alphaID = UUID()
        let betaID = UUID()
        let alpha = ModelMapping(providerID: alphaID, modelID: "applied")
        let beta = ModelMapping(providerID: betaID, modelID: "replacement")
        let providers = [
            Provider(
                id: alphaID,
                name: "Alpha",
                baseURL: "http://127.0.0.1:11434",
                authMode: .none,
                models: [
                    DiscoveredModel(id: "applied", maxTokens: 8_192),
                    DiscoveredModel(id: "replacement", maxTokens: 4_096),
                ],
                status: .ready
            ),
            Provider(
                id: betaID,
                name: "Beta",
                baseURL: "http://127.0.0.1:11435",
                authMode: .none,
                models: [
                    DiscoveredModel(id: "applied", maxTokens: 8_192),
                    DiscoveredModel(id: "replacement", maxTokens: 4_096),
                ],
                status: .ready
            ),
        ]
        let allMappings = providers.flatMap { provider in
            provider.models.map { model in
                ModelMapping(providerID: provider.id, modelID: model.id)
            }
        }
        let configuration = AppConfiguration(
            providers: providers,
            codex: CodexConfiguration(
                connected: codexConnected,
                defaultModel: alpha,
                excludedModels: excludeAllModels ? allMappings : []
            ),
            openCode: OpenCodeConfiguration(
                connected: openCodeConnected,
                defaultModel: excludeAllModels ? nil : alpha
            )
        )
        let store = RecordingConfigurationStore(configuration: configuration)
        let profile = profile ?? TestOpenCodeProfileManager(status: profileStatus)
        let claudeController = TestClaudeController()
        let codexController = TestCodexController()
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: claudeController,
            codexProfileManager: TestCodexProfileManager(active: codexConnected),
            codexController: codexController,
            claudeCodeProfileManager: TestClaudeCodeProfileManager(),
            openCodeProfileManager: includeProfile ? profile : nil,
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer()
        )
        _ = try await coordinator.start()
        store.clearSaves()
        return Self(
            alpha: alpha,
            beta: beta,
            store: store,
            profile: profile,
            claudeController: claudeController,
            codexController: codexController,
            coordinator: coordinator
        )
    }
}
