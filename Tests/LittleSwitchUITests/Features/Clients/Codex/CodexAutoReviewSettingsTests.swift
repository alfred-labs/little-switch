import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Codex approval review settings")
struct CodexAutoReviewSettingsTests {
    @Test("A separate reviewer persists independently of task exposure and default")
    func disconnectedSelection() async throws {
        let fixture = try await CodexCoverageFixture.make()
        _ = try await fixture.coordinator.setCodexModelsExposure([fixture.replacement], exposed: false)
        let selected = try await fixture.coordinator.setCodexAutoReviewModel(fixture.replacement)

        #expect(selected.configuration.codex.defaultModel == fixture.applied)
        #expect(selected.configuration.codex.autoReviewModel == fixture.replacement)
        #expect(selected.configuration.codex.excludedModels == [fixture.replacement])
        #expect(try fixture.store.load().codex == selected.configuration.codex)
        #expect(!selected.hasPendingCodexChanges)
        #expect(fixture.controller.quitAttempts == 0)
        #expect(fixture.controller.openAttempts == 0)

        let restored = try await fixture.coordinator.setCodexAutoReviewModel(nil)
        #expect(restored.configuration.codex.autoReviewModel == nil)
        #expect(restored.configuration.codex.defaultModel == fixture.applied)
        #expect(try fixture.store.load().codex == restored.configuration.codex)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Invalid reviewer selections and failed saves preserve the previous settings")
    func validationAndRollback() async throws {
        let fixture = try await CodexCoverageFixture.make()
        await #expect(throws: ApplicationCoordinator.Error.invalidMapping) {
            _ = try await fixture.coordinator.setCodexAutoReviewModel(
                ModelMapping(providerID: fixture.providerID, modelID: "missing"))
        }
        fixture.store.failFutureSaves(at: [1])
        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await fixture.coordinator.setCodexAutoReviewModel(fixture.replacement)
        }
        #expect((await fixture.coordinator.snapshot()).configuration.codex.autoReviewModel == nil)
        #expect(try fixture.store.load().codex.autoReviewModel == nil)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Connected reviewer changes wait for Apply before changing live routing")
    func connectedApply() async throws {
        let fixture = try await CodexCoverageFixture.make(connected: true)
        let gateway = try #require(await fixture.coordinator.gatewayState)
        let selected = try await fixture.coordinator.setCodexAutoReviewModel(fixture.replacement)

        #expect(selected.hasPendingCodexChanges)
        #expect(selected.configuration.codex.autoReviewModel == fixture.replacement)
        #expect(try fixture.store.load().codex.autoReviewModel == nil)
        #expect(
            await gateway.routingCapture().snapshot.resolveCodex(model: "little-switch-auto-review")?.mapping
                == fixture.applied
        )

        let applied = try await fixture.coordinator.applyCodexSettings()
        #expect(!applied.hasPendingCodexChanges)
        #expect(applied.configuration.codex.defaultModel == fixture.applied)
        #expect(applied.configuration.codex.autoReviewModel == fixture.replacement)
        #expect(try fixture.store.load().codex == applied.configuration.codex)
        #expect(
            await gateway.routingCapture().snapshot.resolveCodex(model: "little-switch-auto-review")?.mapping
                == fixture.replacement)
        #expect(fixture.profile.activations.last?.autoReviewModel == fixture.replacement)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Returning to the applied reviewer clears the draft and failed Apply preserves it")
    func draftCleanupAndFailedApply() async throws {
        let fixture = try await CodexCoverageFixture.make(connected: true)
        _ = try await fixture.coordinator.setCodexAutoReviewModel(fixture.replacement)
        let unchanged = try await fixture.coordinator.setCodexAutoReviewModel(nil)
        #expect(!unchanged.hasPendingCodexChanges)

        _ = try await fixture.coordinator.setCodexAutoReviewModel(fixture.replacement)
        fixture.store.failFutureSaves(at: [1])
        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await fixture.coordinator.applyCodexSettings()
        }
        let failed = await fixture.coordinator.snapshot()
        #expect(failed.hasPendingCodexChanges)
        #expect(failed.configuration.codex.autoReviewModel == fixture.replacement)
        #expect(try fixture.store.load().codex.autoReviewModel == nil)
        #expect(fixture.profile.activations.last?.autoReviewModel == nil)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Unavailable reviewers remain visible as unavailable and prevent Apply")
    func unavailablePresentation() async throws {
        let fixture = try await CodexCoverageFixture.make()
        var snapshot = await fixture.coordinator.snapshot()
        snapshot.configuration.codex.autoReviewModel = fixture.replacement
        let model = AppModel(snapshot: snapshot)
        #expect(!model.hasUnavailableCodexAutoReviewModel)
        #expect(model.canPerformCodexPrimaryAction)

        model.configuration.providers[0].models.removeAll { $0.id == fixture.replacement.modelID }
        #expect(model.hasUnavailableCodexAutoReviewModel)
        #expect(!model.canPerformCodexPrimaryAction)
        #expect(
            model.codexPrimaryActionAccessibilityHint
                == L10n.string("Choose an available approval review model before applying changes"))
        model.configuration.codex.autoReviewModel = nil
        #expect(!model.hasUnavailableCodexAutoReviewModel)
        #expect(model.canPerformCodexPrimaryAction)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Draft reconciliation retains the reviewer independently of an unavailable task default")
    func draftReconciliation() {
        let reviewer = ModelMapping(providerID: UUID(), modelID: "reviewer")
        let configuration = AppConfiguration(codex: CodexConfiguration(autoReviewModel: reviewer))
        let draft = CodexSettingsDraft(configuration: configuration)
        #expect(draft.reconciled(providers: []).autoReviewModel == reviewer)
        #expect(draft.applying(to: configuration) == configuration)
    }
}
