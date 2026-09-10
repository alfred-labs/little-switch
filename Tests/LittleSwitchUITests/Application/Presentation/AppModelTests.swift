import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("App model")
struct AppModelTests {
    @Test("Settings destinations are grouped by responsibility")
    func settingsDestinationGroups() {
        #expect(
            AppModel.SidebarGroup.allCases.map(\.title) == [
                "Common", "Backends", "Apps",
            ])
        #expect(AppModel.SidebarGroup.common.sections == [.common])
        #expect(AppModel.SidebarGroup.backends.sections == [.providers, .webSearch, .monitoring])
        #expect(
            AppModel.SidebarGroup.apps.sections == [
                .claude, .codex, .openCode,
            ])
        #expect(AppModel().selectedSection == .claude)
        #expect(AppModel.Section.allCases.first == .common)
        #expect(AppModel.Section.common.systemImage == "slider.horizontal.3")
        #expect(AppModel.Section.webSearch.systemImage == "globe")
        #expect(AppModel.Section.codex.systemImage == "chevron.left.forwardslash.chevron.right")
    }

    @Test("Every settings destination and sidebar group has a stable identity")
    func settingsDestinationIdentities() {
        #expect(
            AppModel.Section.allCases.map(\.id) == [
                "General",
                "Providers",
                "Web Search",
                "Monitoring",
                "Claude",
                "Codex",
                "OpenCode",
            ]
        )
        #expect(
            AppModel.Section.allCases.map(\.systemImage) == [
                "slider.horizontal.3",
                "externaldrive.connected.to.line.below",
                "globe",
                "waveform.path.ecg",
                "sparkles",
                "chevron.left.forwardslash.chevron.right",
                "terminal",
            ]
        )
        #expect(
            AppModel.SidebarGroup.allCases.map(\.id) == [
                "Common", "Backends", "Apps",
            ]
        )
        #expect(
            AppModel.SidebarGroup.allCases.map(\.title) == [
                "Common", "Backends", "Apps",
            ]
        )
    }

    @Test("Codex exposes model selection and independent connect or apply policy")
    func codexPrimaryActionPolicy() {
        let providerID = UUID()
        let first = ModelMapping(providerID: providerID, modelID: "qwen")
        let second = ModelMapping(providerID: providerID, modelID: "deepseek")
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "qwen"), DiscoveredModel(id: "deepseek")]
        )
        let configuration = AppConfiguration(
            providers: [provider],
            codex: CodexConfiguration(defaultModel: first, excludedModels: [second])
        )
        let model = AppModel(snapshot: CoordinatorSnapshot(configuration: configuration))

        #expect(model.codexPrimaryAction == .connect)
        #expect(model.codexPrimaryActionTitle == "Apply")
        #expect(model.canPerformCodexPrimaryAction)
        #expect(model.codexDefaultOptionID == model.optionID(for: first))
        #expect(model.isCodexModelExposed(first))
        #expect(!model.isCodexModelExposed(second))
        #expect(model.codexExposedModelOptions.map(\.mapping) == [first])
        #expect(model.codexPrimaryActionAccessibilityValue == "Codex disconnected")

        model.configuration.codex.connected = true
        model.hasPendingCodexChanges = true
        #expect(model.codexPrimaryAction == .apply)
        #expect(model.canPerformCodexPrimaryAction)
        #expect(model.codexPrimaryActionAccessibilityValue == "Changes pending")

        model.hasPendingCodexChanges = false
        #expect(!model.canPerformCodexPrimaryAction)
        #expect(model.codexPrimaryActionAccessibilityHint == "No pending settings")

        model.configuration.codex.excludedModels = [first, second]
        model.hasPendingCodexChanges = true
        #expect(!model.canPerformCodexPrimaryAction)
        #expect(
            model.codexPrimaryActionAccessibilityHint
                == "Expose at least one available model before applying changes"
        )
    }

    @Test("Primary actions explain every unavailable, busy, pending, and ready state")
    func completePrimaryActionMessages() {
        let providerID = UUID()
        let mapping = ModelMapping(providerID: providerID, modelID: "qwen")
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "qwen")]
        )
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: AppConfiguration(
                    providers: [provider],
                    mappings: ["claude-sonnet-5": mapping],
                    codex: CodexConfiguration(defaultModel: mapping)
                )
            )
        )

        #expect(
            model.claudePrimaryActionAccessibilityHint
                == "Applies LittleSwitch settings to Claude Desktop"
        )
        #expect(model.codexPrimaryActionAccessibilityHint == "Connects Codex to LittleSwitch")

        model.isBusy = true
        #expect(!model.canPerformClaudePrimaryAction)
        #expect(!model.canPerformCodexPrimaryAction)
        #expect(model.claudePrimaryActionAccessibilityHint == "An operation is in progress")
        #expect(model.codexPrimaryActionAccessibilityHint == "An operation is in progress")

        model.isBusy = false
        model.configuration.connected = true
        model.configuration.codex.connected = true
        model.hasPendingCodexChanges = true
        #expect(model.claudePrimaryActionTitle == "Apply")
        #expect(model.codexPrimaryActionTitle == "Apply")
        #expect(
            model.claudePrimaryActionAccessibilityHint
                == "Model routing edits wait for Apply"
        )
        #expect(model.codexPrimaryActionAccessibilityHint == "Applies pending settings")

        model.hasPendingCodexChanges = false
        #expect(model.codexPrimaryActionAccessibilityValue == "No pending changes")

        model.configuration.mappings["claude-sonnet-5"] = ModelMapping(
            providerID: providerID,
            modelID: "missing"
        )
        #expect(
            model.claudePrimaryActionAccessibilityHint
                == "Choose at least one available model to restore live routing"
        )

        model.configuration.codex.connected = false
        model.configuration.codex.excludedModels = [mapping]
        #expect(
            model.codexPrimaryActionAccessibilityHint
                == "Expose at least one available model before connecting Codex"
        )
    }

    @Test("Claude action connects while disconnected and routes live once connected")
    func claudePrimaryActionPolicy() {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "qwen")]
        )
        let configuration = AppConfiguration(
            providers: [provider],
            mappings: [
                "claude-sonnet-5": ModelMapping(
                    providerID: providerID,
                    modelID: "qwen"
                )
            ],
            connected: true
        )
        let model = AppModel(
            snapshot: CoordinatorSnapshot(configuration: configuration)
        )

        model.configuration.connected = false
        #expect(model.claudePrimaryAction == .connect)
        #expect(model.canPerformClaudePrimaryAction)
        #expect(model.claudePrimaryActionTitle == "Apply")
        #expect(
            model.claudePrimaryActionAccessibilityHint
                == "Applies LittleSwitch settings to Claude Desktop"
        )
        #expect(model.claudePrimaryActionAccessibilityValue == "Claude disconnected")

        model.configuration.connected = true
        #expect(model.claudePrimaryAction == nil)
        #expect(!model.canPerformClaudePrimaryAction)
        #expect(model.claudePrimaryActionTitle == "Apply")
        #expect(
            model.claudePrimaryActionAccessibilityHint
                == "Model routing edits wait for Apply"
        )
        #expect(model.claudePrimaryActionAccessibilityValue == "No pending changes")

        model.hasPendingClaudeMappings = true
        #expect(model.claudePrimaryActionAccessibilityValue == "Changes pending")
        model.hasPendingClaudeMappings = false

        model.isBusy = true
        #expect(!model.canPerformClaudePrimaryAction)
        model.isBusy = false
        model.configuration.connected = false
        #expect(model.canPerformClaudePrimaryAction)

        model.configuration.connected = true
        model.configuration.mappings["claude-sonnet-5"] = ModelMapping(
            providerID: providerID,
            modelID: "missing"
        )
        #expect(!model.canPerformClaudePrimaryAction)
        model.configuration.connected = false
        #expect(!model.canPerformClaudePrimaryAction)
        #expect(
            model.claudePrimaryActionAccessibilityHint
                == "Assign at least one available model before applying settings"
        )
    }
}

@MainActor
@Suite("App model selections and context")
struct AppModelSelectionTests {
    @Test("Model options are stable provider/model references sorted for display")
    func optionsAndMappings() throws {
        let firstID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let secondID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let configuration = AppConfiguration(
            providers: [
                Provider(
                    id: firstID,
                    name: "z.ai",
                    baseURL: "https://api.z.ai/api/anthropic",
                    authMode: .bearer,
                    models: [DiscoveredModel(id: "glm")]
                ),
                Provider(
                    id: secondID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .none,
                    models: [DiscoveredModel(id: "qwen")]
                ),
            ],
            mappings: [
                "claude-opus-5": ModelMapping(providerID: firstID, modelID: "glm")
            ]
        )
        let model = AppModel(snapshot: CoordinatorSnapshot(configuration: configuration))

        #expect(model.modelOptions.map(\.label) == ["Local/qwen", "z.ai/glm"])
        let selection = try #require(model.optionID(for: "claude-opus-5"))
        #expect(model.mapping(for: selection) == configuration.mappings["claude-opus-5"])
        #expect(model.mapping(for: nil) == nil)
        #expect(model.mapping(for: "missing") == nil)
    }

    @Test("Missing routes, models, and selections have nil fallbacks")
    func missingSelectionFallbacks() {
        let providerID = UUID()
        let available = ModelMapping(providerID: providerID, modelID: "available")
        let unavailable = ModelMapping(providerID: providerID, modelID: "missing")
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: AppConfiguration(
                    providers: [
                        Provider(
                            id: providerID,
                            name: "Local",
                            baseURL: "http://127.0.0.1:11434",
                            authMode: .none,
                            models: [DiscoveredModel(id: "available")]
                        )
                    ],
                    mappings: [
                        "claude-opus-5": unavailable,
                        "not-a-claude-route": available,
                    ],
                    codex: CodexConfiguration(defaultModel: unavailable)
                )
            )
        )

        #expect(model.providers.count == 1)
        #expect(model.optionID(for: "missing-route") == nil)
        #expect(model.optionID(for: "claude-opus-5") == nil)
        #expect(model.optionID(for: Optional<ModelMapping>.none) == nil)
        #expect(model.optionID(for: unavailable) == nil)
        #expect(model.codexDefaultOptionID == nil)
        #expect(model.mapping(for: nil) == nil)
        #expect(model.claudeCustomModelCount == 0)
    }

    @Test("Menu model counts include distinct valid Claude targets and exposed Codex models")
    func customModelCounts() {
        let providerID = UUID()
        let qwen = ModelMapping(providerID: providerID, modelID: "qwen")
        let deepseek = ModelMapping(providerID: providerID, modelID: "deepseek")
        let configuration = AppConfiguration(
            providers: [
                Provider(
                    id: providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .none,
                    models: [
                        DiscoveredModel(id: "qwen"),
                        DiscoveredModel(id: "deepseek"),
                    ]
                )
            ],
            mappings: [
                "claude-opus-5": qwen,
                "claude-sonnet-5": qwen,
                "claude-haiku-4-5-20251001": ModelMapping(
                    providerID: providerID,
                    modelID: "missing"
                ),
            ],
            codex: CodexConfiguration(excludedModels: [deepseek])
        )
        let model = AppModel(snapshot: CoordinatorSnapshot(configuration: configuration))

        #expect(model.claudeCustomModelCount == 1)
        #expect(model.codexCustomModelCount == 1)
    }

    @Test("Model context drafts show exact capacity and Claude's 200K or 1M modes")
    func modelContextDrafts() throws {
        var draft = ModelContextDraft(
            model: DiscoveredModel(id: "large", detectedContextWindow: 400_000)
        )

        #expect(draft.detail == "Detected 400K · Effective 400K · Claude 200K")
        #expect(draft.isValid)
        #expect(try draft.parsedOverride() == nil)

        draft.overrideText = "1m"
        #expect(draft.detail == "Detected 400K · Effective 1M · Claude 200K or 1M")
        #expect(try draft.parsedOverride() == 1_000_000)

        draft.overrideText = "invalid"
        #expect(!draft.isValid)
        #expect(draft.detail == "Invalid context override")
    }

    @Test("Context formatting covers unknown, exact, thousands, and millions")
    func completeModelContextFormatting() throws {
        var unknown = ModelContextDraft(model: DiscoveredModel(id: "unknown"))
        #expect(unknown.detail == "Detected Unknown · Effective Unknown · Claude 200K")

        unknown.overrideText = "123"
        #expect(unknown.detail == "Detected Unknown · Effective 123 · Claude 200K")
        #expect(ModelContextDraft.format(123) == "123")
        #expect(ModelContextDraft.format(400_000) == "400K")
        #expect(ModelContextDraft.format(2_000_000) == "2M")

        let overridden = ModelContextDraft(
            model: DiscoveredModel(id: "manual", contextWindowOverride: 1_000_000)
        )
        #expect(overridden.overrideText == "1M")
        #expect(overridden.declares1MManually)

        unknown.overrideText = "invalid"
        #expect(throws: ContextWindowInput.Error.self) {
            try ModelContextDraft.contextOverrides(from: [unknown])
        }
    }

    @Test("Model context drafts serialize only explicit overrides")
    func modelContextOverrides() throws {
        var detected = ModelContextDraft(
            model: DiscoveredModel(id: "detected", detectedContextWindow: 262_144)
        )
        var manual = ModelContextDraft(model: DiscoveredModel(id: "manual"))
        detected.overrideText = ""
        manual.overrideText = "400k"

        #expect(
            try ModelContextDraft.contextOverrides(from: [detected, manual])
                == ["manual": 400_000]
        )
    }

    @Test("The 1M switch writes an exact override and restores Auto")
    func manual1MSwitch() throws {
        var draft = ModelContextDraft(model: DiscoveredModel(id: "unknown"))

        #expect(!draft.declares1MManually)
        #expect(try draft.parsedOverride() == nil)

        draft.declares1MManually = true
        #expect(draft.declares1MManually)
        #expect(try draft.parsedOverride() == 1_000_000)

        draft.declares1MManually = false
        #expect(!draft.declares1MManually)
        #expect(try draft.parsedOverride() == nil)
    }

    @Test("The 1M switch grays out and deactivates when the probe detected less than 1M")
    func manual1MSwitchAvailability() {
        let detected400K = ModelContextDraft(
            model: DiscoveredModel(id: "large", detectedContextWindow: 400_000)
        )
        #expect(!detected400K.allows1MOverride)

        let unknown = ModelContextDraft(model: DiscoveredModel(id: "unknown"))
        #expect(unknown.allows1MOverride)

        let detected1M = ModelContextDraft(
            model: DiscoveredModel(id: "big", detectedContextWindow: 1_000_000)
        )
        #expect(detected1M.allows1MOverride)

        // A 1M override saved while capacity was unknown returns to Auto
        // once a probe reports 400K.
        let stale = ModelContextDraft(
            model: DiscoveredModel(
                id: "stale",
                detectedContextWindow: 400_000,
                contextWindowOverride: 1_000_000
            )
        )
        #expect(!stale.allows1MOverride)
        #expect(!stale.declares1MManually)
        #expect(stale.overrideText.isEmpty)
        #expect(stale.detail == "Detected 400K · Effective 400K · Claude 200K")
    }

    @Test("Coordinator snapshots update menu and settings state atomically")
    func applySnapshot() {
        let model = AppModel()
        model.isBusy = true
        model.errorMessage = "old"

        model.apply(
            CoordinatorSnapshot(
                configuration: AppConfiguration(autoMode: false, connected: true),
                requestCount: 12,
                claudeRequestCount: 7,
                codexRequestCount: 5,
                proxyRunning: true,
                claudeCodeStatus: .needsAttention,
                hasPendingClaudeCodeChanges: true,
                claudeCodeMappedRouteIDs: ["claude-sonnet-5"]
            ))

        #expect(model.connected)
        #expect(!model.autoMode)
        #expect(model.requestCount == 12)
        #expect(model.claudeRequestCount == 7)
        #expect(model.codexRequestCount == 5)
        #expect(model.proxyRunning)
        #expect(model.claudeCodeStatus == .needsAttention)
        #expect(model.hasPendingClaudeCodeChanges)
        #expect(model.claudeCodeMappedRouteIDs == ["claude-sonnet-5"])
        #expect(!model.isBusy)
        #expect(model.errorMessage == nil)
    }
}
