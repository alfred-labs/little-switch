import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("App model Claude Code")
struct AppModelClaudeCodeTests {
    @Test("Claude Code exposes mapped routes and complete connection policy")
    func primaryActionPolicy() {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "qwen"), DiscoveredModel(id: "glm")]
        )
        let sonnet = ModelMapping(providerID: providerID, modelID: "qwen")
        let opus = ModelMapping(providerID: providerID, modelID: "glm")
        let configuration = AppConfiguration(
            providers: [provider],
            mappings: [
                "claude-sonnet-5": sonnet,
                "claude-opus-5": opus,
            ],
            claudeCode: ClaudeCodeConfiguration(defaultModel: "claude-opus-5")
        )
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: configuration,
                claudeCodeStatus: .disconnected,
                claudeCodeMappedRouteIDs: ["claude-opus-5"]
            )
        )

        #expect(model.claudeCodePrimaryAction == .connect)
        #expect(model.claudeCodePrimaryActionTitle == "Apply")
        #expect(model.canPerformClaudeCodePrimaryAction)
        #expect(
            model.claudeCodePrimaryActionAccessibilityHint
                == "Configures new Claude Code terminal sessions"
        )
        #expect(model.claudeCodePrimaryActionAccessibilityValue == "Claude Code disconnected")
        #expect(model.claudeCodeMappedRouteOptions.map(\.id) == ["claude-opus-5"])
        #expect(model.claudeCodeDefaultRouteID == "claude-opus-5")

        model.claudeCodeStatus = .connected
        #expect(model.claudeCodeSwitchOn)
        #expect(model.claudeCodePrimaryAction == .apply)
        #expect(model.claudeCodePrimaryActionTitle == "Apply")
        #expect(!model.canPerformClaudeCodePrimaryAction)
        #expect(model.claudeCodePrimaryActionAccessibilityHint == "No pending settings")
        #expect(model.claudeCodePrimaryActionAccessibilityValue == "No pending changes")

        model.hasPendingClaudeCodeChanges = true
        #expect(model.canPerformClaudeCodePrimaryAction)
        #expect(
            model.claudeCodePrimaryActionAccessibilityHint
                == "Applies pending settings to new Claude Code terminal sessions"
        )
        #expect(model.claudeCodePrimaryActionAccessibilityValue == "Changes pending")

        model.hasPendingClaudeCodeChanges = false
        model.claudeCodeStatus = .needsAttention
        #expect(model.claudeCodeSwitchOn)
        #expect(model.claudeCodePrimaryAction == .apply)
        #expect(model.canPerformClaudeCodePrimaryAction)
        #expect(
            model.claudeCodePrimaryActionAccessibilityHint
                == "Reapplies LittleSwitch settings for new Claude Code sessions"
        )
        #expect(model.claudeCodePrimaryActionAccessibilityValue == "Needs attention")

        model.claudeCodeMappedRouteIDs = []
        #expect(!model.canPerformClaudeCodePrimaryAction)
        #expect(
            model.claudeCodePrimaryActionAccessibilityHint
                == "Map at least one Claude model before applying Claude Code"
        )
        model.claudeCodeMappedRouteIDs = ["claude-opus-5"]

        model.claudeCodeStatus = .recoveryAvailable
        #expect(model.claudeCodeSwitchOn)
        #expect(model.claudeCodePrimaryAction == .restore)
        #expect(model.claudeCodePrimaryActionTitle == "Restore settings")
        #expect(model.canPerformClaudeCodePrimaryAction)
        #expect(
            model.claudeCodePrimaryActionAccessibilityHint
                == "Restores the previous user-level Claude Code settings"
        )
        #expect(model.claudeCodePrimaryActionAccessibilityValue == "Recovery available")

        model.claudeCodeStatus = .recoveryUnavailable
        #expect(!model.claudeCodeSwitchOn)
        #expect(model.claudeCodePrimaryAction == .restore)
        #expect(!model.canPerformClaudeCodePrimaryAction)
        #expect(model.claudeCodePrimaryActionAccessibilityHint == "Recovery data is unavailable")
        #expect(model.claudeCodePrimaryActionAccessibilityValue == "Recovery unavailable")

        model.claudeCodeStatus = .disconnected
        #expect(!model.claudeCodeSwitchOn)
        model.claudeCodeMappedRouteIDs = []
        #expect(model.claudeCodeMappedRouteOptions.isEmpty)
        #expect(!model.canPerformClaudeCodePrimaryAction)
        #expect(
            model.claudeCodePrimaryActionAccessibilityHint
                == "Map at least one Claude model before connecting Claude Code"
        )

        model.claudeCodeMappedRouteIDs = ["claude-opus-5"]
        model.configuration.claudeCode.defaultModel = "missing"
        #expect(model.claudeCodeDefaultRouteID == "claude-opus-5")
        model.configuration.claudeCode.defaultModel = nil
        #expect(model.claudeCodeDefaultRouteID == "claude-opus-5")
        model.isBusy = true
        #expect(!model.canPerformClaudeCodePrimaryAction)
        #expect(model.claudeCodePrimaryActionAccessibilityHint == "An operation is in progress")
    }

    @Test("Unified Claude Apply follows pending state across both applications")
    func unifiedApplyAvailability() {
        let providerID = UUID()
        let mapping = ModelMapping(providerID: providerID, modelID: "glm")
        let configuration = AppConfiguration(
            providers: [
                Provider(
                    id: providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .none,
                    models: [DiscoveredModel(id: "glm")]
                )
            ],
            mappings: ["claude-opus-5": mapping],
            connected: true,
            claudeCode: ClaudeCodeConfiguration(
                connected: true,
                defaultModel: "claude-opus-5"
            )
        )
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: configuration,
                claudeCodeStatus: .connected,
                claudeCodeMappedRouteIDs: ["claude-opus-5"]
            )
        )

        #expect(!model.canApplyClaudeProducts)
        model.hasPendingClaudeMappings = true
        #expect(model.canApplyClaudeProducts)
        model.hasPendingClaudeMappings = false
        model.hasPendingClaudeCodeChanges = true
        #expect(model.canApplyClaudeProducts)
        model.hasPendingClaudeCodeChanges = false
        #expect(!model.canApplyClaudeProducts)
    }

    @Test("Claude Code default options expose route aliases and eligible 1M variants")
    func defaultModelOptions() {
        let providerID = UUID()
        let sonnetMapping = ModelMapping(providerID: providerID, modelID: "glm-5.3-flash")
        let haikuMapping = ModelMapping(providerID: providerID, modelID: "glm-4.7")
        let configuration = AppConfiguration(
            providers: [
                Provider(
                    id: providerID,
                    name: "z.ai",
                    baseURL: "https://api.z.ai/api/anthropic",
                    authMode: .bearer,
                    models: [
                        DiscoveredModel(
                            id: "glm-5.3-flash",
                            contextWindowOverride: 1_000_000
                        ),
                        DiscoveredModel(id: "glm-4.7"),
                    ]
                )
            ],
            mappings: [
                "claude-sonnet-5": sonnetMapping,
                "claude-haiku-4-5-20251001": haikuMapping,
            ],
            claudeCode: ClaudeCodeConfiguration(
                defaultModel: "claude-sonnet-5",
                contextMode: .extended1M
            )
        )
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: configuration,
                claudeCodeMappedRouteIDs: [
                    "claude-haiku-4-5-20251001",
                    "claude-sonnet-5",
                ]
            )
        )

        #expect(
            model.claudeCodeDefaultModelOptions.map(\.label) == [
                "Sonnet",
                "Sonnet [1m]",
                "Haiku",
            ]
        )
        #expect(
            model.claudeCodeDefaultModelOptions.map(\.routeID) == [
                "claude-sonnet-5",
                "claude-sonnet-5",
                "claude-haiku-4-5-20251001",
            ]
        )
        #expect(
            model.claudeCodeDefaultModelOptions.map(\.contextMode) == [
                .standard,
                .extended1M,
                .standard,
            ]
        )
        #expect(
            model.claudeCodeDefaultModelOptions.map(\.id) == [
                "claude-sonnet-5|standard",
                "claude-sonnet-5|1m",
                "claude-haiku-4-5-20251001|standard",
            ]
        )
        #expect(
            model.claudeCodeDefaultModelSelection?.label
                == "Sonnet [1m]"
        )

        model.configuration.claudeCode.contextMode = .standard
        #expect(
            model.claudeCodeDefaultModelSelection?.label
                == "Sonnet"
        )

        model.configuration.claudeCode.defaultModel = "claude-haiku-4-5-20251001"
        model.configuration.claudeCode.contextMode = .extended1M
        #expect(
            model.claudeCodeDefaultModelSelection?.label
                == "Haiku"
        )

        model.configuration.mappings.removeValue(forKey: "claude-haiku-4-5-20251001")
        model.claudeCodeMappedRouteIDs = ["claude-haiku-4-5-20251001"]
        #expect(model.claudeCodeDefaultModelSelection == nil)

        model.claudeCodeMappedRouteIDs = []
        #expect(model.claudeCodeDefaultModelSelection == nil)
    }

}
