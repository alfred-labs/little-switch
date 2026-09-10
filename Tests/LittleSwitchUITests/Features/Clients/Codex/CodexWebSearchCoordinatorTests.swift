import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Codex live web search coordinator")
struct CodexWebSearchCoordinatorTests {
    @Test("Startup leaves an old search profile connected and pending until Apply", arguments: [false, true])
    func legacyStartupAndApply(missingConcurrency: Bool) async throws {
        let fixture = try await CodexCoordinatorFixture.make(
            codexRunning: true,
            connected: true,
            legacyProfile: missingConcurrency,
            legacyWebSearch: true
        )
        defer { fixture.remove() }

        let startup = await fixture.coordinator.snapshot()
        #expect(startup.configuration.codex.connected)
        #expect(startup.hasPendingCodexChanges)
        #expect(fixture.codexProfile.activations.isEmpty)
        #expect(fixture.codexController.quitCount == 0)
        #expect(fixture.codexController.openCount == 0)
        let expected = try CodexManagedProfileSignature.resolve(
            providers: startup.configuration.providers, configuration: startup.configuration.codex
        )
        #expect(fixture.codexProfile.expectedStatuses == [expected])

        let applied = try await fixture.coordinator.applyCodexSettings()

        #expect(applied.configuration.codex.connected)
        #expect(!applied.hasPendingCodexChanges)
        #expect(fixture.codexProfile.signatures == [expected])
        #expect(fixture.codexProfile.signatures.first?.webSearchMode == "live")
        #expect(fixture.codexController.quitCount == 1)
        #expect(fixture.codexController.openCount == 1)
        #expect(fixture.claudeController.quitCount == 0)
        #expect(fixture.claudeController.openCount == 0)
    }

    @Test("A failed search-mode upgrade reapplies the original signature without a relaunch", arguments: [false, true])
    func legacyApplyRollback(missingConcurrency: Bool) async throws {
        let fixture = try await CodexCoordinatorFixture.make(
            codexRunning: true,
            connected: true,
            legacyProfile: missingConcurrency,
            legacyWebSearch: true
        )
        defer { fixture.remove() }
        let startup = await fixture.coordinator.snapshot()
        let expected = try CodexManagedProfileSignature.resolve(
            providers: startup.configuration.providers, configuration: startup.configuration.codex
        )
        var previous = expected.withoutManagedWebSearch()
        if missingConcurrency {
            previous = previous.withoutNativeConcurrency()
        }
        fixture.store.failNextSave()

        await #expect(throws: RecordingConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.applyCodexSettings()
        }

        let rolledBack = await fixture.coordinator.snapshot()
        #expect(rolledBack.configuration == startup.configuration)
        #expect(rolledBack.hasPendingCodexChanges)
        #expect(fixture.codexProfile.signatures == [expected, previous])
        #expect(fixture.codexController.quitCount == 0)
        #expect(fixture.codexController.openCount == 0)
    }
}
