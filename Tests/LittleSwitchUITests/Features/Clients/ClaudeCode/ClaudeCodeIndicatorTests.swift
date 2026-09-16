import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Claude Code model indicator")
struct ClaudeCodeIndicatorTests {
    @Test("Cosmetic changes never activate a drifted or externally edited profile", arguments: [true, false])
    func preservesDriftedProfile(driftedAtStartup: Bool) async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make(
            claudeCodeConnected: true,
            profileStatus: driftedAtStartup ? .drifted : .active
        )
        if !driftedAtStartup {
            fixture.profile.setStatus(.drifted)
        }
        let changed = try await fixture.coordinator.setModelIndicator(.swap)
        #expect(fixture.profile.activations.isEmpty)
        #expect(changed.claudeCodeStatus == .needsAttention)
        #expect(changed.configuration.modelIndicator == .swap)
    }

    @Test("Immediate indicator changes update only applied labels and preserve pending family selection")
    func preservesPendingSelection() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make()
        _ = try await fixture.coordinator.connectClaudeCode()
        let original = try #require(fixture.profile.activations.last)
        _ = try await fixture.coordinator.setClaudeCodeDefaultModel("claude-opus-5")

        let changed = try await fixture.coordinator.setModelIndicator(.swap)
        let applied = try #require(fixture.profile.activations.last)
        var expected = original
        expected.environment["ANTHROPIC_DEFAULT_FABLE_MODEL_NAME"] = "Fable 5.1 ⇄"
        expected.environment["ANTHROPIC_DEFAULT_OPUS_MODEL_NAME"] = "Opus 5 ⇄"
        expected.environment["ANTHROPIC_DEFAULT_SONNET_MODEL_NAME"] = "Sonnet 5 ⇄ (1M context)"
        expected.environment["ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME"] = "Haiku 4.5 ⇄"
        #expect(applied == expected)
        #expect(changed.hasPendingClaudeCodeChanges)
        #expect(changed.configuration.claudeCode.defaultModel == "claude-opus-5")
        #expect(changed.configuration.modelIndicator == .swap)

        _ = try await fixture.coordinator.setModelIndicator(.swap)
        #expect(fixture.profile.activations.count == 2)
        _ = try await fixture.coordinator.applyClaudeCode()
        #expect(fixture.profile.activations.last?.model == "opus")
    }

    @Test("A failed presentation update rolls back the indicator and keeps the applied family")
    func rollsBackOnProfileFailure() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make()
        _ = try await fixture.coordinator.connectClaudeCode()
        let original = try #require(fixture.profile.activations.last)
        fixture.profile.failNextActivation()

        await #expect(throws: TestClaudeCodeProfileManager.Error.activateInjected) {
            _ = try await fixture.coordinator.setModelIndicator(.none)
        }
        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.configuration.modelIndicator == .mapsTo)
        #expect(fixture.store.configuration.modelIndicator == .mapsTo)
        #expect(fixture.profile.activations.last == original)
        #expect(!snapshot.hasPendingClaudeCodeChanges)
    }

    @Test("Incomplete indicator rollbacks require attention", arguments: [true, false])
    func reportsIncompleteRollback(profileRollbackFails: Bool) async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make()
        _ = try await fixture.coordinator.connectClaudeCode()
        let original = try #require(fixture.profile.activations.last)
        fixture.profile.failNextActivation()
        if profileRollbackFails {
            fixture.profile.failActivation(onAttempt: 3)
        } else {
            fixture.store.failSave(afterSuccessfulSaves: 1)
        }

        await #expect(throws: ApplicationCoordinator.Error.rollbackFailed) {
            _ = try await fixture.coordinator.setModelIndicator(.none)
        }

        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.claudeCodeStatus == .needsAttention)
        #expect(snapshot.configuration.modelIndicator == .mapsTo)
        #expect(fixture.profile.activations.last == original)
        #expect(fixture.store.configuration.modelIndicator == (profileRollbackFails ? .mapsTo : .none))
    }

    @Test("A profile inspection failure preserves the applied presentation")
    func preservesProfileAfterInspectionFailure() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make()
        _ = try await fixture.coordinator.connectClaudeCode()
        let original = fixture.profile.activations
        fixture.profile.failStatus()

        await #expect(throws: TestClaudeCodeProfileManager.Error.statusInjected) {
            _ = try await fixture.coordinator.setModelIndicator(.none)
        }

        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.configuration.modelIndicator == .mapsTo)
        #expect(fixture.store.configuration.modelIndicator == .mapsTo)
        #expect(fixture.profile.activations == original)
    }

    @Test("Without a CLI profile, the indicator remains a catalog-only preference")
    func updatesCatalogWithoutProfile() async throws {
        let fixture = try await ClaudeCodeCoordinatorFixture.make(includeProfile: false)

        let snapshot = try await fixture.coordinator.setModelIndicator(.swap)

        #expect(snapshot.configuration.modelIndicator == .swap)
        #expect(fixture.store.configuration.modelIndicator == .swap)
        #expect(snapshot.claudeCodeStatus == .disconnected)
        #expect(fixture.profile.activations.isEmpty)
    }
}
