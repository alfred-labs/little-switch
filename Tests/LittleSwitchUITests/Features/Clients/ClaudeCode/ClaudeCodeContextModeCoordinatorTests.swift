import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Claude Code Anthropic context coordinator")
struct ClaudeCodeContextModeCoordinatorTests {
    @Test("Combined default selection persists and stages route with Anthropic context")
    func combinedDefaultSelection() async throws {
        let disconnected = try await ClaudeCodeCoordinatorFixture.make()

        let persisted = try await disconnected.coordinator.setClaudeCodeDefaultModel(
            "claude-sonnet-5",
            contextMode: .extended1M
        )
        #expect(persisted.configuration.claudeCode.defaultModel == "claude-sonnet-5")
        #expect(persisted.configuration.claudeCode.contextMode == .extended1M)
        #expect(disconnected.store.configuration.claudeCode.defaultModel == "claude-sonnet-5")
        #expect(disconnected.store.configuration.claudeCode.contextMode == .extended1M)

        disconnected.store.failNextSave()
        await #expect(throws: RecordingConfigurationStore.Error.injected) {
            _ = try await disconnected.coordinator.setClaudeCodeDefaultModel(
                "claude-opus-5",
                contextMode: .standard
            )
        }
        let rolledBack = await disconnected.coordinator.snapshot()
        #expect(rolledBack.configuration.claudeCode.defaultModel == "claude-sonnet-5")
        #expect(rolledBack.configuration.claudeCode.contextMode == .extended1M)

        let connected = try await ClaudeCodeCoordinatorFixture.make()
        _ = try await connected.coordinator.connectClaudeCode()
        let pending = try await connected.coordinator.setClaudeCodeDefaultModel(
            "claude-sonnet-5",
            contextMode: .extended1M
        )
        #expect(pending.configuration.claudeCode.defaultModel == "claude-sonnet-5")
        #expect(pending.configuration.claudeCode.contextMode == .extended1M)
        #expect(!pending.hasPendingClaudeCodeChanges)

        let applied = try await connected.coordinator.applyClaudeCode()
        #expect(!applied.hasPendingClaudeCodeChanges)
        #expect(connected.profile.activations.last?.model == "sonnet")
        #expect(
            connected.profile.activations.last?.environment["ANTHROPIC_DEFAULT_SONNET_MODEL"] == "claude-sonnet-5[1m]")

        let changedRoute = try await connected.coordinator.setClaudeCodeDefaultModel(
            "claude-opus-5",
            contextMode: .extended1M
        )
        #expect(changedRoute.configuration.claudeCode.defaultModel == "claude-opus-5")
        #expect(changedRoute.configuration.claudeCode.contextMode == .standard)
        #expect(changedRoute.hasPendingClaudeCodeChanges)
    }
}
