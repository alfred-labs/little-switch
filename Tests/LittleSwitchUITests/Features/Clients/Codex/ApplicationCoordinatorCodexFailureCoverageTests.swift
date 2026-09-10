import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application coordinator Codex failure coverage")
struct CoordinatorCodexFailureCoverageTests {
    @Test("A stopped Codex connects without process control")
    func connectWhileStopped() async throws {
        let fixture = try await CodexCoverageFixture.make()

        let connected = try await fixture.coordinator.connectCodex()

        #expect(connected.configuration.codex.connected)
        #expect(fixture.controller.quitAttempts == 0)
        #expect(fixture.controller.openAttempts == 0)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A running Codex is relaunched on connect")
    func connectWhileRunning() async throws {
        let fixture = try await CodexCoverageFixture.make(codexRunning: true)

        let connected = try await fixture.coordinator.connectCodex()

        #expect(connected.configuration.codex.connected)
        #expect(fixture.profile.activations.count == 1)
        #expect(fixture.controller.quitAttempts == 1)
        #expect(fixture.controller.openAttempts == 1)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Connect rolls back profile and save failures", arguments: CodexApplyFailure.allCases)
    func connectFailures(failure: CodexApplyFailure) async throws {
        let fixture = try await CodexCoverageFixture.make()
        switch failure {
        case .profile:
            fixture.profile.failActivations(on: [1])
            await #expect(throws: ScriptedCodexProfileManager.Error.activateInjected) {
                _ = try await fixture.coordinator.connectCodex()
            }
        case .configuration:
            fixture.store.failFutureSaves(at: [1])
            await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
                _ = try await fixture.coordinator.connectCodex()
            }
        }

        #expect(!(await fixture.coordinator.snapshot()).configuration.codex.connected)
        #expect(fixture.profile.restoreCount == 1)
        #expect(fixture.controller.quitAttempts == 0)
        #expect(fixture.controller.openAttempts == 0)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Connect reports every failed rollback layer", arguments: CodexRollbackFailure.allCases)
    func connectRollbackFailures(failure: CodexRollbackFailure) async throws {
        let fixture = try await CodexCoverageFixture.make()
        switch failure {
        case .configuration:
            fixture.store.failFutureSaves(at: [1, 2])
        case .profile:
            fixture.profile.failActivations(on: [1])
            fixture.profile.failRestores(on: [1])
        }

        await #expect(throws: ApplicationCoordinator.Error.rollbackFailed) {
            _ = try await fixture.coordinator.connectCodex()
        }
        #expect(!(await fixture.coordinator.snapshot()).configuration.codex.connected)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Codex applies pending settings without controlling the client")
    func applyWithoutProcessControl() async throws {
        let fixture = try await CodexCoverageFixture.make(connected: true)
        _ = try await fixture.coordinator.setCodexDefaultModel(fixture.replacement)
        _ = try await fixture.coordinator.setCodexModelsExposure(
            [fixture.applied],
            exposed: false
        )

        let applied = try await fixture.coordinator.applyCodexSettings()

        #expect(!applied.hasPendingCodexChanges)
        #expect(applied.configuration.codex.defaultModel == fixture.replacement)
        #expect(fixture.controller.quitAttempts == 0)
        #expect(fixture.controller.openAttempts == 0)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Catalog drift without a draft still evaluates apply against current state")
    func applyWithoutDraft() async throws {
        let fixture = try await CodexCoverageFixture.make(connected: true)

        _ = try await fixture.coordinator.deleteProvider(id: fixture.providerID)

        let pending = await fixture.coordinator.snapshot()
        #expect(pending.hasPendingCodexChanges)
        await #expect(throws: ApplicationCoordinator.Error.noExposedCodexModel) {
            _ = try await fixture.coordinator.applyCodexSettings()
        }
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test(
        "Apply rolls back profile and save failures",
        arguments: CodexConnectedApplyFailure.allCases
    )
    func applyFailures(failure: CodexConnectedApplyFailure) async throws {
        let fixture = try await CodexCoverageFixture.make(connected: true)
        _ = try await fixture.coordinator.setCodexDefaultModel(fixture.replacement)
        _ = try await fixture.coordinator.setCodexModelsExposure(
            [fixture.applied],
            exposed: false
        )
        switch failure {
        case .profile:
            fixture.profile.failActivations(on: [1])
            await #expect(throws: ScriptedCodexProfileManager.Error.activateInjected) {
                _ = try await fixture.coordinator.applyCodexSettings()
            }
        case .configuration:
            fixture.store.failFutureSaves(at: [1])
            await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
                _ = try await fixture.coordinator.applyCodexSettings()
            }
        }

        #expect((await fixture.coordinator.snapshot()).hasPendingCodexChanges)
        #expect(fixture.profile.activations.last?.defaultModel == fixture.applied)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Apply rollback restores the immutable applied provider catalog")
    func applyRestoresAppliedProviderCatalog() async throws {
        let fixture = try await CodexCoverageFixture.make(connected: true)
        let appliedConfiguration = await fixture.coordinator.snapshot().configuration
        let appliedActivation = ScriptedCodexActivation(
            providers: appliedConfiguration.providers,
            configuration: appliedConfiguration.codex
        )
        _ = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "Drifted Local",
                baseURL: "http://127.0.0.1:11435",
                authMode: .none
            )
        )
        _ = try await fixture.coordinator.setCodexDefaultModel(fixture.replacement)
        fixture.store.failFutureSaves(at: [1])

        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await fixture.coordinator.applyCodexSettings()
        }

        let activations = fixture.profile.activationSnapshots
        #expect(activations.count == 2)
        #expect(activations.first?.providers != appliedActivation.providers)
        #expect(activations.last == appliedActivation)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test(
        "Apply reports every failed rollback layer",
        arguments: CodexConnectedRollbackFailure.allCases
    )
    func applyRollbackFailures(failure: CodexConnectedRollbackFailure) async throws {
        let fixture = try await CodexCoverageFixture.make(connected: true)
        _ = try await fixture.coordinator.setCodexDefaultModel(fixture.replacement)
        _ = try await fixture.coordinator.setCodexModelsExposure(
            [fixture.applied],
            exposed: false
        )
        switch failure {
        case .configuration:
            fixture.profile.failActivations(on: [1])
            fixture.store.failFutureSaves(at: [1])
        case .profile:
            fixture.profile.failActivations(on: [1, 2])
        }

        await #expect(throws: ApplicationCoordinator.Error.rollbackFailed) {
            _ = try await fixture.coordinator.applyCodexSettings()
        }
        #expect((await fixture.coordinator.snapshot()).hasPendingCodexChanges)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Disconnect rolls back restore and save failures", arguments: CodexDisconnectFailure.allCases)
    func disconnectFailures(failure: CodexDisconnectFailure) async throws {
        let fixture = try await CodexCoverageFixture.make(connected: true)
        switch failure {
        case .restore:
            fixture.profile.failRestores(on: [1])
            await #expect(throws: ScriptedCodexProfileManager.Error.restoreInjected) {
                _ = try await fixture.coordinator.disconnectCodex()
            }
        case .save:
            fixture.store.failFutureSaves(at: [1])
            await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
                _ = try await fixture.coordinator.disconnectCodex()
            }
        }

        #expect((await fixture.coordinator.snapshot()).configuration.codex.connected)
        #expect(fixture.profile.activations.last?.defaultModel == fixture.applied)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Disconnect reports every failed rollback layer", arguments: CodexRollbackFailure.allCases)
    func disconnectRollbackFailures(failure: CodexRollbackFailure) async throws {
        let fixture = try await CodexCoverageFixture.make(connected: true)
        fixture.profile.failRestores(on: [1])
        switch failure {
        case .configuration:
            fixture.store.failFutureSaves(at: [1])
        case .profile:
            fixture.profile.failActivations(on: [1])
        }

        await #expect(throws: ApplicationCoordinator.Error.rollbackFailed) {
            _ = try await fixture.coordinator.disconnectCodex()
        }
        #expect((await fixture.coordinator.snapshot()).configuration.codex.connected)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}

enum CodexApplyFailure: CaseIterable, Sendable {
    case profile
    case configuration
}

enum CodexConnectedApplyFailure: CaseIterable, Sendable {
    case profile
    case configuration
}

enum CodexRollbackFailure: CaseIterable, Sendable {
    case configuration
    case profile
}

enum CodexConnectedRollbackFailure: CaseIterable, Sendable {
    case configuration
    case profile
}

enum CodexDisconnectFailure: CaseIterable, Sendable {
    case restore
    case save
}
