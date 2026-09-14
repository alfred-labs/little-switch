import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application coordinator mapping draft")
struct ApplicationCoordinatorMappingDraftTests {
    @Test("Connected remaps wait in the draft until apply, then persist and hot-swap")
    func connectedRemapsWaitForApply() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make()
        defer { fixture.removeFiles() }

        let replacement = ModelMapping(
            providerID: fixture.providerID,
            modelID: "replacement"
        )
        let drafted = try await fixture.coordinator.setMapping(
            routeID: "claude-opus-5",
            mapping: replacement
        )

        // Draft only: the snapshot shows it, disk and gateway do not.
        #expect(drafted.hasPendingClaudeMappings)
        #expect(drafted.configuration.mappings["claude-opus-5"] == replacement)
        #expect(
            try fixture.store.load().mappings["claude-opus-5"]
                == fixture.appliedConfiguration.mappings["claude-opus-5"]
        )
        #expect(
            await fixture.gatewayState.capture().mappings["claude-opus-5"]
                == fixture.appliedConfiguration.mappings["claude-opus-5"]
        )

        let applied = try await fixture.coordinator.applyClaudeMappings()
        let autoChanged = try await fixture.coordinator.setAutoMode(false)

        #expect(!applied.hasPendingClaudeMappings)
        #expect(applied.configuration.mappings["claude-opus-5"] == replacement)
        #expect(
            try fixture.store.load().mappings["claude-opus-5"] == replacement
        )
        #expect(
            await fixture.gatewayState.capture().mappings["claude-opus-5"]
                == replacement
        )
        #expect(!autoChanged.configuration.autoMode)
        // Remapping is routing-only: no Desktop relaunch, no profile rewrite.
        // The stopped controller records nothing even for the auto-mode
        // relaunch, mirroring connect-while-stopped semantics.
        #expect(fixture.controller.quitCount == 0)
        #expect(fixture.controller.openCount == 0)
    }

    @Test("Re-picking the applied mapping leaves nothing pending")
    func noOpDraftClearsPending() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make()
        defer { fixture.removeFiles() }

        let applied = try #require(
            fixture.appliedConfiguration.mappings["claude-opus-5"]
        )
        let drafted = try await fixture.coordinator.setMapping(
            routeID: "claude-opus-5",
            mapping: applied
        )

        #expect(!drafted.hasPendingClaudeMappings)
    }

    @Test("Applying with no mapping draft is a no-op")
    func applyWithoutDraftIsNoOp() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make()
        defer { fixture.removeFiles() }

        let unchanged = try await fixture.coordinator.applyClaudeMappings()

        #expect(!unchanged.hasPendingClaudeMappings)
        #expect(
            unchanged.configuration.mappings
                == fixture.appliedConfiguration.mappings
        )
    }

    @Test("Applying an all-routes-unassigned draft is refused while connected")
    func connectedUnmapLastRouteRefused() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make()
        defer { fixture.removeFiles() }

        let drafted = try await fixture.coordinator.setMapping(
            routeID: "claude-opus-5",
            mapping: nil
        )
        #expect(drafted.hasPendingClaudeMappings)

        await #expect(throws: ApplicationCoordinator.Error.noMappedModel) {
            _ = try await fixture.coordinator.applyClaudeMappings()
        }

        #expect(try fixture.store.load().mappings["claude-opus-5"] != nil)
        #expect(
            await fixture.gatewayState.capture().mappings["claude-opus-5"] != nil
        )
        // The refused draft stays drafted, so the user can adjust it
        // instead of retyping it.
        #expect((await fixture.coordinator.snapshot()).hasPendingClaudeMappings)
    }

    @Test("A failed apply save restores the applied mappings and keeps the draft")
    func applySaveFailureRollback() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(
            injectFailingStore: true
        )
        defer { fixture.removeFiles() }

        _ = try await fixture.coordinator.setMapping(
            routeID: "claude-opus-5",
            mapping: ModelMapping(
                providerID: fixture.providerID,
                modelID: "replacement"
            )
        )
        fixture.failingStore?.failNextSave()

        await #expect(throws: FailNextConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.applyClaudeMappings()
        }

        #expect(try fixture.store.load() == fixture.appliedConfiguration)
        #expect((await fixture.coordinator.snapshot()).hasPendingClaudeMappings)
    }

    @Test("A failed apply save keeps the mapping draft and commits nothing")
    func applySaveFailureKeepsStagedState() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(
            injectFailingStore: true,
            claudeCodeConnected: true,
            mapsSecondRoute: true
        )
        defer { fixture.removeFiles() }

        // A staged Claude Code default on Opus, plus a mapping draft that
        // unassigns Opus (Sonnet keeps the candidate mappings valid, so
        // the apply reaches the save).
        _ = try await fixture.coordinator.setClaudeCodeDefaultModel("claude-opus-5")
        #expect((await fixture.coordinator.snapshot()).hasPendingClaudeCodeChanges)

        let drafted = try await fixture.coordinator.setMapping(
            routeID: "claude-opus-5",
            mapping: nil
        )
        #expect(drafted.hasPendingClaudeMappings)
        // The route list the Claude Code pane shows follows the draft:
        // Opus is staged away, so only Sonnet remains.
        #expect(drafted.claudeCodeMappedRouteIDs == ["claude-sonnet-5"])

        fixture.failingStore?.failNextSave()
        await #expect(throws: FailNextConfigurationStore.Error.injected) {
            _ = try await fixture.coordinator.applyClaudeMappings()
        }

        let snapshot = await fixture.coordinator.snapshot()
        // The refused mapping draft stays drafted, and nothing half-commit:
        // disk and in-memory configuration keep the applied state.
        #expect(snapshot.hasPendingClaudeMappings)
        #expect(try fixture.store.load() == fixture.appliedConfiguration)
        // The staged default named a route the mapping draft removes, so
        // it reconciles to the post-Apply truth — nothing pending: both
        // drafts describe one Apply, and that Apply would normalize the
        // default off the removed route.
        #expect(!snapshot.hasPendingClaudeCodeChanges)
    }

    @Test("Claude Code defaults may target a route the mapping draft adds")
    func claudeCodeDefaultTargetsDraftedRoute() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make(
            claudeCodeConnected: true
        )
        defer { fixture.removeFiles() }

        _ = try await fixture.coordinator.setMapping(
            routeID: "claude-haiku-4-5-20251001",
            mapping: ModelMapping(
                providerID: fixture.providerID,
                modelID: "applied"
            )
        )
        let drafted = await fixture.coordinator.snapshot()
        #expect(drafted.claudeCodeMappedRouteIDs.contains("claude-haiku-4-5-20251001"))

        let staged = try await fixture.coordinator.setClaudeCodeDefaultModel(
            "claude-haiku-4-5-20251001"
        )

        #expect(staged.hasPendingClaudeMappings)
        #expect(staged.hasPendingClaudeCodeChanges)
    }

    @Test("Disconnecting discards the mapping draft")
    func disconnectDiscardsMappingDraft() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make()
        defer { fixture.removeFiles() }

        _ = try await fixture.coordinator.setMapping(
            routeID: "claude-opus-5",
            mapping: ModelMapping(
                providerID: fixture.providerID,
                modelID: "replacement"
            )
        )
        let disconnected = try await fixture.coordinator.disconnect()

        #expect(!disconnected.hasPendingClaudeMappings)
        #expect(
            try fixture.store.load().mappings["claude-opus-5"]
                == fixture.appliedConfiguration.mappings["claude-opus-5"]
        )
    }

    @Test("Deleting a provider reconciles its entries out of the mapping draft")
    func providerDeletionReconcilesDraft() async throws {
        let fixture = try await ConnectedCoordinatorFixture.make()
        defer { fixture.removeFiles() }

        _ = try await fixture.coordinator.setMapping(
            routeID: "claude-opus-5",
            mapping: ModelMapping(
                providerID: fixture.providerID,
                modelID: "replacement"
            )
        )
        #expect((await fixture.coordinator.snapshot()).hasPendingClaudeMappings)

        let deleted = try await fixture.coordinator.deleteProvider(
            id: fixture.providerID
        )

        #expect(!deleted.hasPendingClaudeMappings)
    }
}
