import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Claude Code settings draft")
struct ClaudeCodeSettingsDraftTests {
    @Test("A draft applies only Claude Code defaults and normalizes context eligibility")
    func applying() {
        let fixture = draftFixture()
        let original = AppConfiguration(
            providers: fixture.providers,
            mappings: fixture.mappings,
            autoMode: false,
            connected: true,
            claudeCode: ClaudeCodeConfiguration(
                connected: true,
                defaultModel: "claude-sonnet-5",
                contextMode: .extended1M
            ),
            codex: CodexConfiguration(connected: true)
        )

        let applied = ClaudeCodeSettingsDraft(
            defaultModel: "missing",
            contextMode: .extended1M
        )
        .applying(to: original)

        #expect(applied.claudeCode.defaultModel == "claude-sonnet-5")
        #expect(applied.claudeCode.contextMode == .standard)
        #expect(applied.claudeCode.connected)
        #expect(applied.connected == original.connected)
        #expect(applied.codex == original.codex)
        #expect(applied.autoMode == original.autoMode)
    }

    @Test("Reconciliation follows provider and mapping availability")
    func reconciliation() {
        let fixture = draftFixture()
        let configuration = AppConfiguration(
            providers: fixture.providers,
            mappings: fixture.mappings,
            claudeCode: ClaudeCodeConfiguration(defaultModel: "claude-sonnet-5")
        )

        #expect(
            ClaudeCodeSettingsDraft(defaultModel: "claude-opus-5")
                .reconciled(with: configuration)
                == ClaudeCodeSettingsDraft(defaultModel: "claude-opus-5")
        )

        var reduced = configuration
        reduced.providers.removeAll { $0.id == fixture.opusProviderID }
        #expect(
            ClaudeCodeSettingsDraft(defaultModel: "claude-opus-5")
                .reconciled(with: reduced)
                == ClaudeCodeSettingsDraft(defaultModel: "claude-sonnet-5")
        )

        reduced.providers = []
        #expect(
            ClaudeCodeSettingsDraft(defaultModel: "claude-opus-5")
                .reconciled(with: reduced)
                == ClaudeCodeSettingsDraft(defaultModel: nil)
        )
    }

    @Test("Initialization mirrors persisted Claude Code state")
    func initialization() {
        let configuration = AppConfiguration(
            claudeCode: ClaudeCodeConfiguration(defaultModel: "claude-sonnet-5")
        )
        #expect(
            ClaudeCodeSettingsDraft(configuration: configuration)
                == ClaudeCodeSettingsDraft(
                    defaultModel: "claude-sonnet-5",
                    contextMode: .standard
                )
        )
    }

}

private struct DraftFixture {
    var providers: [Provider]
    var mappings: [String: ModelMapping]
    var opusProviderID: UUID
}

private func draftFixture() -> DraftFixture {
    let sonnetProviderID = UUID()
    let opusProviderID = UUID()
    return DraftFixture(
        providers: [
            Provider(
                id: sonnetProviderID,
                name: "Sonnet",
                baseURL: "http://127.0.0.1:11434",
                authMode: .none,
                models: [DiscoveredModel(id: "sonnet")]
            ),
            Provider(
                id: opusProviderID,
                name: "Opus",
                baseURL: "http://127.0.0.1:11435",
                authMode: .none,
                models: [DiscoveredModel(id: "opus")]
            ),
        ],
        mappings: [
            "claude-sonnet-5": ModelMapping(
                providerID: sonnetProviderID,
                modelID: "sonnet"
            ),
            "claude-opus-5": ModelMapping(
                providerID: opusProviderID,
                modelID: "opus"
            ),
        ],
        opusProviderID: opusProviderID
    )
}
