import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Claude Code coordinator")
struct ClaudeCodeCoordinatorTests {
    @Test("Connect configures the CLI and never controls a desktop application")
    func connect() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make()

        let connected = try await fixture.coordinator.connectClaudeCode()

        #expect(connected.configuration.claudeCode.connected)
        #expect(connected.claudeCodeStatus == .connected)
        #expect(connected.proxyRunning)
        #expect(fixture.profile.activations.count == 1)
        #expect(fixture.profile.activations.last?.model == "claude-sonnet-5")
        #expect(fixture.claudeController.quitCount == 0)
        #expect(fixture.claudeController.openCount == 0)
        #expect(fixture.codexController.quitCount == 0)
        #expect(fixture.codexController.openCount == 0)
        #expect(fixture.store.configuration.claudeCode.connected)
    }

    @Test("Disconnected defaults persist, normalize, validate, and roll back on failure")
    func disconnectedDefault() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make()

        let changed = try await fixture.coordinator.setClaudeCodeDefaultModel(
            "claude-opus-5"
        )
        #expect(changed.configuration.claudeCode.defaultModel == "claude-opus-5")
        await #expect(throws: ApplicationCoordinator.Error.invalidMapping) {
            _ = try await fixture.coordinator.setClaudeCodeDefaultModel("missing")
        }

        let normalized = try await fixture.coordinator.setClaudeCodeDefaultModel(nil)
        #expect(normalized.configuration.claudeCode.defaultModel == "claude-sonnet-5")
        fixture.store.failNextSave()
        await #expect(throws: RecordingConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.setClaudeCodeDefaultModel("claude-opus-5")
        }
        #expect(
            (await fixture.coordinator.snapshot()).configuration.claudeCode.defaultModel
                == "claude-sonnet-5"
        )
    }

    @Test("Connect requires recovery first and rolls back activation failures")
    func connectFailures() async throws {
        let recovery = try await ClaudeCodeCoordinatorFixture.make(profileStatus: .active)
        await #expect(throws: ApplicationCoordinator.Error.claudeCodeRecoveryRequired) {
            _ = try await recovery.coordinator.connectClaudeCode()
        }

        let activation = try await ClaudeCodeCoordinatorFixture.make()
        activation.profile.failNextActivation()
        await #expect(throws: TestClaudeCodeProfileManager.Error.activateInjected) {
            _ = try await activation.coordinator.connectClaudeCode()
        }
        #expect(activation.profile.restoreCount == 1)
        #expect((await activation.coordinator.snapshot()).claudeCodeStatus == .disconnected)

        let rollback = try await ClaudeCodeCoordinatorFixture.make()
        rollback.profile.failNextActivation()
        rollback.profile.failNextRestore()
        await #expect(throws: ApplicationCoordinator.Error.rollbackFailed) {
            _ = try await rollback.coordinator.connectClaudeCode()
        }
    }

    @Test("Apply restores the prior managed signature after a save failure")
    func applyRollback() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make()
        _ = try await fixture.coordinator.connectClaudeCode()
        let applied = try #require(fixture.profile.activations.last)
        let pending = try await fixture.coordinator.setClaudeCodeDefaultModel(
            "claude-opus-5"
        )
        #expect(pending.hasPendingClaudeCodeChanges)
        fixture.store.failNextSave()

        await #expect(throws: RecordingConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.applyClaudeCode()
        }

        #expect(fixture.profile.activations.count == 3)
        #expect(fixture.profile.activations.last == applied)
        #expect(fixture.store.configuration.claudeCode.defaultModel == "claude-sonnet-5")
        #expect((await fixture.coordinator.snapshot()).hasPendingClaudeCodeChanges)
        #expect(fixture.claudeController.quitCount == 0)
        #expect(fixture.codexController.quitCount == 0)
    }

    @Test("Apply persists a pending default and reports rollback failures")
    func applySuccessAndRollbackFailures() async throws {
        let success = try await ClaudeCodeCoordinatorFixture.make()
        _ = try await success.coordinator.connectClaudeCode()
        _ = try await success.coordinator.setClaudeCodeDefaultModel("claude-opus-5")

        let applied = try await success.coordinator.applyClaudeCode()

        #expect(applied.configuration.claudeCode.defaultModel == "claude-opus-5")
        #expect(!applied.hasPendingClaudeCodeChanges)
        #expect(success.profile.activations.count == 2)

        let failedRollback = try await ClaudeCodeCoordinatorFixture.make()
        _ = try await failedRollback.coordinator.connectClaudeCode()
        _ = try await failedRollback.coordinator.setClaudeCodeDefaultModel("claude-opus-5")
        failedRollback.store.failNextSave()
        failedRollback.profile.failActivation(onAttempt: 3)
        await #expect(throws: ApplicationCoordinator.Error.rollbackFailed) {
            _ = try await failedRollback.coordinator.applyClaudeCode()
        }

        let missingPrevious = try await ClaudeCodeCoordinatorFixture.make(
            claudeCodeConnected: true,
            profileStatus: .active,
            includeMappings: false
        )
        _ = try await missingPrevious.coordinator.setMapping(
            routeID: "claude-sonnet-5",
            mapping: ModelMapping(
                providerID: missingPrevious.sonnetProviderID,
                modelID: "applied"
            )
        )
        missingPrevious.store.failNextSave()
        await #expect(throws: ApplicationCoordinator.Error.rollbackFailed) {
            _ = try await missingPrevious.coordinator.applyClaudeCode()
        }
    }

    @Test("Disconnect saves false before restore and recovers true after restore failure")
    func disconnectRollback() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make()
        _ = try await fixture.coordinator.connectClaudeCode()
        fixture.store.clearSaves()
        fixture.profile.failNextRestore()

        await #expect(throws: TestClaudeCodeProfileManager.Error.restoreInjected) {
            _ = try await fixture.coordinator.disconnectClaudeCode()
        }

        #expect(fixture.store.saves.map(\.claudeCode.connected) == [false, true])
        #expect(fixture.store.configuration.claudeCode.connected)
        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.configuration.claudeCode.connected)
        #expect(snapshot.claudeCodeStatus == .connected)
    }

    @Test("Startup exposes orphan recovery without marking the CLI connected")
    func orphanRecovery() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make(profileStatus: .active)

        let snapshot = await fixture.coordinator.snapshot()

        #expect(!snapshot.configuration.claudeCode.connected)
        #expect(snapshot.claudeCodeStatus == .recoveryAvailable)
        #expect(!snapshot.hasPendingClaudeCodeChanges)
    }

    @Test("Startup keeps drifted connected settings visible for attention")
    func connectedDrift() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make(
            claudeCodeConnected: true,
            profileStatus: .drifted
        )

        let snapshot = await fixture.coordinator.snapshot()

        #expect(snapshot.configuration.claudeCode.connected)
        #expect(snapshot.claudeCodeStatus == .needsAttention)
        #expect(fixture.store.configuration.claudeCode.connected)
    }

    @Test("Apply reapplies drifted settings without rewriting unchanged configuration")
    func reapplyConnectedDrift() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make(
            claudeCodeConnected: true,
            profileStatus: .drifted
        )
        fixture.store.clearSaves()

        let reapplied = try await fixture.coordinator.applyClaudeCode()

        #expect(fixture.profile.activations.count == 1)
        #expect(fixture.profile.activations.last?.model == "claude-sonnet-5")
        #expect(reapplied.claudeCodeStatus == .connected)
        #expect(!reapplied.hasPendingClaudeCodeChanges)
        #expect(fixture.store.saves.isEmpty)
    }

    @Test("Apply is a no-op while Claude Code is disconnected")
    func applyWhileDisconnected() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make()
        fixture.store.clearSaves()

        let unchanged = try await fixture.coordinator.applyClaudeCode()

        #expect(unchanged.claudeCodeStatus == .disconnected)
        #expect(fixture.profile.activations.isEmpty)
        #expect(fixture.store.saves.isEmpty)
    }

    @Test("Invalid recovery clears an unsafe saved flag and reports unavailable")
    func invalidRecovery() async throws {
        let profile = TestClaudeCodeProfileManager(status: .active)
        profile.failStatus()
        let fixture = try await ClaudeCodeCoordinatorFixture.make(
            claudeCodeConnected: true,
            profile: profile
        )

        let snapshot = await fixture.coordinator.snapshot()

        #expect(!snapshot.configuration.claudeCode.connected)
        #expect(snapshot.claudeCodeStatus == .recoveryUnavailable)
        #expect(!fixture.store.configuration.claudeCode.connected)
    }

    @Test("Startup reconciles active, inactive, missing, and unmapped connected states")
    func startupStatusMatrix() async throws {
        let active = try await ClaudeCodeCoordinatorFixture.make(
            claudeCodeConnected: true,
            profileStatus: .active
        )
        #expect((await active.coordinator.snapshot()).claudeCodeStatus == .connected)

        let inactive = try await ClaudeCodeCoordinatorFixture.make(
            claudeCodeConnected: true,
            profileStatus: .inactive
        )
        #expect((await inactive.coordinator.snapshot()).claudeCodeStatus == .recoveryUnavailable)
        #expect(!inactive.store.configuration.claudeCode.connected)

        let missing = try await ClaudeCodeCoordinatorFixture.make(
            claudeCodeConnected: true,
            includeProfile: false
        )
        #expect((await missing.coordinator.snapshot()).claudeCodeStatus == .recoveryUnavailable)
        #expect(!missing.store.configuration.claudeCode.connected)

        let unmapped = try await ClaudeCodeCoordinatorFixture.make(
            claudeCodeConnected: true,
            profileStatus: .active,
            includeMappings: false
        )
        #expect((await unmapped.coordinator.snapshot()).claudeCodeStatus == .needsAttention)
        #expect(unmapped.store.configuration.claudeCode.connected)
    }

    @Test("Recovery restores an orphan profile without touching desktop apps")
    func restoreRecovery() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make(profileStatus: .active)

        let restored = try await fixture.coordinator.restoreClaudeCodeSettings()

        #expect(restored.claudeCodeStatus == .disconnected)
        #expect(fixture.profile.restoreCount == 1)
        #expect(fixture.claudeController.quitCount == 0)
        #expect(fixture.codexController.quitCount == 0)
    }

    @Test("Recovery failure keeps orphan state and failed rollback save is explicit")
    func recoveryFailures() async throws {
        let orphan = try await ClaudeCodeCoordinatorFixture.make(profileStatus: .active)
        orphan.profile.failNextRestore()
        await #expect(throws: TestClaudeCodeProfileManager.Error.restoreInjected) {
            _ = try await orphan.coordinator.restoreClaudeCodeSettings()
        }
        #expect((await orphan.coordinator.snapshot()).claudeCodeStatus == .recoveryAvailable)

        let connected = try await ClaudeCodeCoordinatorFixture.make()
        _ = try await connected.coordinator.connectClaudeCode()
        connected.profile.failNextRestore()
        connected.store.failSave(afterSuccessfulSaves: 1)
        await #expect(throws: ApplicationCoordinator.Error.rollbackFailed) {
            _ = try await connected.coordinator.disconnectClaudeCode()
        }
    }

    @Test("Provider deletion normalizes the CLI default and creates pending settings")
    func providerDeletion() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make()
        _ = try await fixture.coordinator.connectClaudeCode()

        let pending = try await fixture.coordinator.deleteProvider(id: fixture.sonnetProviderID)

        #expect(pending.configuration.claudeCode.defaultModel == "claude-opus-5")
        #expect(pending.hasPendingClaudeCodeChanges)
        #expect(fixture.profile.activations.count == 1)
    }

    @Test("Changing a physical provider target keeps the route-based profile stable")
    func changingPhysicalProviderTargetKeepsProfileStable() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make()
        _ = try await fixture.coordinator.connectClaudeCode()

        let unchanged = try await fixture.coordinator.applyClaudeCode()
        #expect(!unchanged.hasPendingClaudeCodeChanges)
        #expect(fixture.profile.activations.count == 1)

        let changed = try await fixture.coordinator.setMapping(
            routeID: "claude-sonnet-5",
            mapping: ModelMapping(
                providerID: fixture.sonnetProviderID,
                modelID: "replacement"
            )
        )
        #expect(!changed.hasPendingClaudeCodeChanges)
        #expect(fixture.profile.activations.count == 1)

        let applied = try await fixture.coordinator.applyClaudeCode()
        #expect(!applied.hasPendingClaudeCodeChanges)
        #expect(fixture.profile.activations.count == 1)
        #expect(fixture.profile.activations.last?.model == "claude-sonnet-5")
    }

    @Test("Returning or reconciling a CLI draft to applied values clears the draft")
    func draftReconciliation() async throws {
        let returned = try await ClaudeCodeCoordinatorFixture.make()
        _ = try await returned.coordinator.connectClaudeCode()
        _ = try await returned.coordinator.setClaudeCodeDefaultModel("claude-opus-5")

        let unchanged = try await returned.coordinator.setClaudeCodeDefaultModel(
            "claude-sonnet-5"
        )

        #expect(!unchanged.hasPendingClaudeCodeChanges)
        let returnedDraft = await returned.coordinator.pendingClaudeCodeSettings
        #expect(returnedDraft == nil)

        let reconciled = try await ClaudeCodeCoordinatorFixture.make()
        _ = try await reconciled.coordinator.connectClaudeCode()
        _ = try await reconciled.coordinator.setClaudeCodeDefaultModel("claude-opus-5")

        _ = try await reconciled.coordinator.deleteProvider(id: reconciled.sonnetProviderID)

        let reconciledDraft = await reconciled.coordinator.pendingClaudeCodeSettings
        #expect(reconciledDraft == nil)
    }

    @Test("Unavailable integration and empty routing fail with product errors")
    func unavailableAndEmpty() async throws {
        let unavailable = try await ClaudeCodeCoordinatorFixture.make(includeProfile: false)
        await #expect(throws: ApplicationCoordinator.Error.claudeCodeUnavailable) {
            _ = try await unavailable.coordinator.connectClaudeCode()
        }

        let empty = try await ClaudeCodeCoordinatorFixture.make(includeMappings: false)
        await #expect(throws: ApplicationCoordinator.Error.noMappedClaudeCodeModel) {
            _ = try await empty.coordinator.connectClaudeCode()
        }
    }
}

extension ClaudeCodeCoordinatorTests {
    @Test("Provider concurrency edits never create pending Claude Code settings")
    func providerConcurrencyHintsApplyLifecycle() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make()
        _ = try await fixture.coordinator.connectClaudeCode()
        let unrelated = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.opusProviderID,
                name: "Opus",
                baseURL: "http://127.0.0.1:11435",
                authMode: .none,
                maximumParallelRequests: 23
            )
        )
        #expect(!unrelated.hasPendingClaudeCodeChanges)
        #expect(fixture.profile.activations.count == 1)
        let selected = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.sonnetProviderID,
                name: "Sonnet",
                baseURL: "http://127.0.0.1:11434",
                authMode: .none,
                maximumParallelRequests: 11
            )
        )
        #expect(!selected.hasPendingClaudeCodeChanges)
        #expect(fixture.profile.activations.count == 1)
        #expect(
            fixture.profile.activations.last?
                .environment["CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"] == "4"
        )
        #expect(
            fixture.profile.activations.last?
                .environment["CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY"] == "4"
        )
    }
}

@MainActor
struct ClaudeCodeCoordinatorFixture {
    let sonnetProviderID: UUID
    let opusProviderID: UUID
    let store: RecordingConfigurationStore
    let profile: TestClaudeCodeProfileManager
    let claudeController: TestClaudeController
    let codexController: TestCodexController
    let coordinator: ApplicationCoordinator

    static func make(
        claudeCodeConnected: Bool = false,
        profileStatus: ClaudeCodeProfileStatus = .inactive,
        profile: TestClaudeCodeProfileManager? = nil,
        includeProfile: Bool = true,
        includeMappings: Bool = true,
        tlsProvisioner: (any GatewayTLSProvisioning)? = nil
    ) async throws -> Self {
        let sonnetProviderID = UUID()
        let opusProviderID = UUID()
        let providers = [
            Provider(
                id: sonnetProviderID,
                name: "Sonnet",
                baseURL: "http://127.0.0.1:11434",
                authMode: .none,
                models: [
                    DiscoveredModel(id: "applied", contextWindowOverride: 1_000_000),
                    DiscoveredModel(id: "replacement"),
                ],
                status: .ready,
                maximumParallelRequests: 7
            ),
            Provider(
                id: opusProviderID,
                name: "Opus",
                baseURL: "http://127.0.0.1:11435",
                authMode: .none,
                models: [
                    DiscoveredModel(id: "applied"),
                    DiscoveredModel(id: "replacement"),
                ],
                status: .ready
            ),
        ]
        let mappings: [String: ModelMapping] =
            includeMappings
            ? [
                "claude-sonnet-5": ModelMapping(
                    providerID: sonnetProviderID,
                    modelID: "applied"
                ),
                "claude-opus-5": ModelMapping(
                    providerID: opusProviderID,
                    modelID: "replacement"
                ),
            ]
            : [:]
        let configuration = AppConfiguration(
            providers: providers,
            mappings: mappings,
            claudeCode: ClaudeCodeConfiguration(
                connected: claudeCodeConnected,
                defaultModel: includeMappings ? "claude-sonnet-5" : nil
            )
        )
        let store = RecordingConfigurationStore(configuration: configuration)
        let profile = profile ?? TestClaudeCodeProfileManager(status: profileStatus)
        let claudeController = TestClaudeController()
        let codexController = TestCodexController()
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: ClaudeProfileManager(
                paths: ClaudeProfilePaths(
                    applicationSupport: FileManager.default.temporaryDirectory
                )
            ),
            claudeController: claudeController,
            codexProfileManager: TestCodexProfileManager(),
            codexController: codexController,
            claudeCodeProfileManager: includeProfile ? profile : nil,
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer(),
            tlsProvisioner: tlsProvisioner
        )
        _ = try await coordinator.start()
        store.clearSaves()
        return Self(
            sonnetProviderID: sonnetProviderID,
            opusProviderID: opusProviderID,
            store: store,
            profile: profile,
            claudeController: claudeController,
            codexController: codexController,
            coordinator: coordinator
        )
    }
}
