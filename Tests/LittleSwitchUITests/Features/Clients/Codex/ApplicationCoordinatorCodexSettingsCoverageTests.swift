import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application coordinator Codex settings coverage")
struct CoordinatorCodexSettingsCoverageTests {
    @Test("Codex exposure validates mappings and rolls back disconnected saves")
    func exposureValidationAndRollback() async throws {
        let fixture = try await CodexCoverageFixture.make()
        await #expect(throws: ApplicationCoordinator.Error.invalidMapping) {
            _ = try await fixture.coordinator.setCodexModelsExposure(
                [ModelMapping(providerID: UUID(), modelID: "missing")],
                exposed: true
            )
        }

        fixture.store.failFutureSaves(at: [1])
        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await fixture.coordinator.setCodexModelsExposure(
                [fixture.replacement],
                exposed: false
            )
        }
        #expect(
            !(await fixture.coordinator.snapshot()).configuration.codex.excludedModels.contains(
                fixture.replacement
            )
        )
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Disconnected exposure and default changes persist immediately")
    func disconnectedSettings() async throws {
        let fixture = try await CodexCoverageFixture.make(
            excludedModels: []
        )

        let hidden = try await fixture.coordinator.setCodexModelsExposure(
            [fixture.replacement],
            exposed: false
        )
        #expect(hidden.configuration.codex.excludedModels == [fixture.replacement])

        let shown = try await fixture.coordinator.setCodexModelsExposure(
            [fixture.replacement],
            exposed: true
        )
        #expect(shown.configuration.codex.excludedModels.isEmpty)

        let replacement = try await fixture.coordinator.setCodexDefaultModel(
            fixture.replacement
        )
        #expect(replacement.configuration.codex.defaultModel == fixture.replacement)

        let fallback = try await fixture.coordinator.setCodexDefaultModel(nil)
        #expect(fallback.configuration.codex.defaultModel == fixture.applied)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Codex default validation and save failure preserve the applied value")
    func defaultValidationAndRollback() async throws {
        let fixture = try await CodexCoverageFixture.make()
        await #expect(throws: ApplicationCoordinator.Error.invalidMapping) {
            _ = try await fixture.coordinator.setCodexDefaultModel(
                ModelMapping(providerID: fixture.providerID, modelID: "missing")
            )
        }

        fixture.store.failFutureSaves(at: [1])
        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await fixture.coordinator.setCodexDefaultModel(fixture.replacement)
        }
        #expect(
            (await fixture.coordinator.snapshot()).configuration.codex.defaultModel
                == fixture.applied
        )
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Returning connected exposure and default drafts to applied values clears them")
    func connectedDraftCleanup() async throws {
        let fixture = try await CodexCoverageFixture.make(
            connected: true,
            excludedModels: [
                ModelMapping(providerID: UUID(), modelID: "stale")
            ]
        )

        _ = try await fixture.coordinator.setCodexModelsExposure(
            [fixture.replacement],
            exposed: false
        )
        let cleanExposure = try await fixture.coordinator.setCodexModelsExposure(
            [fixture.replacement],
            exposed: true
        )
        #expect(!cleanExposure.hasPendingCodexChanges)

        _ = try await fixture.coordinator.setCodexDefaultModel(fixture.replacement)
        let cleanDefault = try await fixture.coordinator.setCodexDefaultModel(fixture.applied)
        #expect(!cleanDefault.hasPendingCodexChanges)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Codex dependencies and model exposure are required before connecting")
    func connectRequirements() async throws {
        let unavailable = try await CodexCoverageFixture.make(includeDependencies: false)
        await #expect(throws: ApplicationCoordinator.Error.codexUnavailable) {
            _ = try await unavailable.coordinator.connectCodex()
        }
        await unavailable.coordinator.shutdown(mode: .handoff)

        let noModels = try await CodexCoverageFixture.make(allModelsHidden: true)
        await #expect(throws: ApplicationCoordinator.Error.noExposedCodexModel) {
            _ = try await noModels.coordinator.connectCodex()
        }
        await noModels.coordinator.shutdown(mode: .handoff)
    }

    @Test("Codex apply is a no-op without pending connected changes")
    func applyNoOp() async throws {
        let disconnected = try await CodexCoverageFixture.make()
        let unchanged = try await disconnected.coordinator.applyCodexSettings()
        #expect(!unchanged.configuration.codex.connected)
        await disconnected.coordinator.shutdown(mode: .handoff)

        let connected = try await CodexCoverageFixture.make(connected: true)
        let clean = try await connected.coordinator.applyCodexSettings()
        #expect(clean.configuration.codex.connected)
        #expect(connected.controller.quitAttempts == 0)
        await connected.coordinator.shutdown(mode: .handoff)
    }

    @Test("Codex apply rejects a draft with no exposed model")
    func applyWithoutExposedModel() async throws {
        let fixture = try await CodexCoverageFixture.make(connected: true)
        await fixture.stageLegacyAllHiddenDraft()

        await #expect(throws: ApplicationCoordinator.Error.noExposedCodexModel) {
            _ = try await fixture.coordinator.applyCodexSettings()
        }
        #expect((await fixture.coordinator.snapshot()).hasPendingCodexChanges)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A running Codex is relaunched on disconnect")
    func disconnectRunningCodex() async throws {
        let fixture = try await CodexCoverageFixture.make(
            connected: true,
            codexRunning: true
        )
        let disconnected = try await fixture.coordinator.disconnectCodex()
        #expect(!disconnected.configuration.codex.connected)
        #expect(fixture.controller.quitAttempts == 1)
        #expect(fixture.controller.openAttempts == 1)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
