import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Shared model catalog selection")
struct CodexCatalogBulkTests {
    @Test("A previously hidden catalog gets a default when a group is enabled")
    func restoresHiddenCatalog() async throws {
        let fixture = try await CodexCoverageFixture.make(allModelsHidden: true)
        let hidden = await fixture.coordinator.snapshot()
        #expect(hidden.configuration.codex.defaultModel == nil)

        let restored = try await fixture.coordinator.setCodexModelsExposure([fixture.replacement], exposed: true)
        #expect(
            restored.configuration.codex
                == CodexConfiguration(
                    defaultModel: fixture.replacement,
                    excludedModels: [fixture.applied]
                )
        )
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Group selection protects the default and only changes the requested models")
    func protectsDefault() async throws {
        let fixture = try await CodexCoverageFixture.make(excludedModels: [])
        let result = try await fixture.coordinator.setCodexModelsExposure(
            [fixture.applied, fixture.replacement, fixture.replacement], exposed: false
        )
        #expect(result.configuration.codex.defaultModel == fixture.applied)
        #expect(result.configuration.codex.excludedModels == [fixture.replacement])
        let restored = try await fixture.coordinator.setCodexModelsExposure([fixture.replacement], exposed: true)
        #expect(restored.configuration.codex.excludedModels.isEmpty)
        let unchanged = try await fixture.coordinator.setCodexModelsExposure([], exposed: false)
        #expect(unchanged.configuration == restored.configuration)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("An invalid member rejects the complete group without applying a partial selection")
    func rejectsInvalidGroup() async throws {
        let fixture = try await CodexCoverageFixture.make(excludedModels: [])
        let original = await fixture.coordinator.snapshot()
        await #expect(throws: ApplicationCoordinator.Error.invalidMapping) {
            _ = try await fixture.coordinator.setCodexModelsExposure(
                [fixture.replacement, ModelMapping(providerID: UUID(), modelID: "missing")], exposed: false
            )
        }
        #expect(await fixture.coordinator.snapshot().configuration == original.configuration)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Bulk persistence failure restores the complete prior configuration")
    func rollback() async throws {
        let fixture = try await CodexCoverageFixture.make(excludedModels: [])
        let original = await fixture.coordinator.snapshot()
        fixture.store.failFutureSaves(at: [1])
        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await fixture.coordinator.setCodexModelsExposure([fixture.replacement], exposed: false)
        }
        #expect(await fixture.coordinator.snapshot().configuration == original.configuration)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Connected group edits stay pending and returning to the original selection clears them")
    func connectedDraft() async throws {
        let fixture = try await CodexCoverageFixture.make(connected: true, excludedModels: [])
        let pending = try await fixture.coordinator.setCodexModelsExposure(
            [fixture.applied, fixture.replacement], exposed: false
        )
        #expect(pending.hasPendingCodexChanges)
        #expect(pending.configuration.codex.defaultModel == fixture.applied)
        #expect(pending.configuration.codex.excludedModels == [fixture.replacement])
        let restored = try await fixture.coordinator.setCodexModelsExposure([fixture.replacement], exposed: true)
        #expect(!restored.hasPendingCodexChanges)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}
