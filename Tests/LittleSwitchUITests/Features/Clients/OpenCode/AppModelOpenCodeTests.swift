import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("App model OpenCode")
struct AppModelOpenCodeTests {
    @Test("OpenCode exposes the complete connection and recovery policy")
    func primaryActionPolicy() {
        let fixture = modelFixture()
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: fixture.configuration,
                openCodeStatus: .disconnected
            )
        )

        #expect(!model.openCodeSwitchOn)
        #expect(model.openCodePrimaryAction == .connect)
        #expect(model.openCodePrimaryActionTitle == "Apply")
        #expect(model.canPerformOpenCodePrimaryAction)
        #expect(model.openCodePrimaryActionAccessibilityHint == "Configures OpenCode to use LittleSwitch")
        #expect(model.openCodePrimaryActionAccessibilityValue == "OpenCode disconnected")

        model.openCodeStatus = .connected
        #expect(model.openCodeSwitchOn)
        #expect(model.openCodePrimaryAction == .apply)
        #expect(!model.canPerformOpenCodePrimaryAction)
        #expect(model.openCodePrimaryActionAccessibilityHint == "No pending settings")
        #expect(model.openCodePrimaryActionAccessibilityValue == "No pending changes")

        model.hasPendingOpenCodeChanges = true
        #expect(model.canPerformOpenCodePrimaryAction)
        #expect(model.openCodePrimaryActionAccessibilityHint == "Applies pending settings to OpenCode")
        #expect(model.openCodePrimaryActionAccessibilityValue == "Changes pending")

        model.hasPendingOpenCodeChanges = false
        model.openCodeStatus = .needsAttention
        #expect(model.openCodeSwitchOn)
        #expect(model.openCodePrimaryAction == .apply)
        #expect(model.canPerformOpenCodePrimaryAction)
        #expect(model.openCodePrimaryActionAccessibilityHint == "Reapplies LittleSwitch settings to OpenCode")
        #expect(model.openCodePrimaryActionAccessibilityValue == "Needs attention")

        model.openCodeStatus = .recoveryAvailable
        #expect(model.openCodeSwitchOn)
        #expect(model.openCodePrimaryAction == .restore)
        #expect(model.openCodePrimaryActionTitle == "Restore settings")
        #expect(model.canPerformOpenCodePrimaryAction)
        #expect(
            model.openCodePrimaryActionAccessibilityHint
                == "Restores the previous user-level OpenCode settings"
        )
        #expect(model.openCodePrimaryActionAccessibilityValue == "Recovery available")

        model.openCodeStatus = .recoveryUnavailable
        #expect(!model.openCodeSwitchOn)
        #expect(model.openCodePrimaryAction == .restore)
        #expect(!model.canPerformOpenCodePrimaryAction)
        #expect(model.openCodePrimaryActionAccessibilityHint == "Recovery data is unavailable")
        #expect(model.openCodePrimaryActionAccessibilityValue == "Recovery unavailable")

        model.isBusy = true
        #expect(!model.canPerformOpenCodePrimaryAction)
        #expect(model.openCodePrimaryActionAccessibilityHint == "An operation is in progress")
    }

    @Test("Codex pending state gates OpenCode connect and apply")
    func codexGate() {
        let fixture = modelFixture()
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: fixture.configuration,
                hasPendingCodexChanges: true,
                openCodeStatus: .disconnected,
                hasPendingOpenCodeChanges: true
            )
        )

        #expect(!model.canPerformOpenCodePrimaryAction)
        #expect(model.openCodePrimaryActionAccessibilityHint == "Apply Codex changes first")

        model.openCodeStatus = .connected
        #expect(!model.canPerformOpenCodePrimaryAction)
        #expect(model.openCodePrimaryActionAccessibilityHint == "Apply Codex changes first")

        model.openCodeStatus = .recoveryAvailable
        #expect(model.canPerformOpenCodePrimaryAction)
        #expect(
            model.openCodePrimaryActionAccessibilityHint
                == "Restores the previous user-level OpenCode settings"
        )
    }

    @Test("Empty exposure disables connect and apply with specific guidance")
    func emptyExposure() {
        let fixture = modelFixture()
        var configuration = fixture.configuration
        configuration.codex.excludedModels = configuration.codex
            .availableModels(in: configuration.providers)
            .map(\.mapping)
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: configuration,
                openCodeStatus: .disconnected
            )
        )

        #expect(model.openCodeDefaultModelOptions.isEmpty)
        #expect(!model.canPerformOpenCodePrimaryAction)
        #expect(
            model.openCodePrimaryActionAccessibilityHint
                == "Expose at least one model in Codex before connecting OpenCode"
        )

        model.openCodeStatus = .connected
        model.hasPendingOpenCodeChanges = true
        #expect(!model.canPerformOpenCodePrimaryAction)
        #expect(
            model.openCodePrimaryActionAccessibilityHint
                == "Expose at least one model in Codex before applying OpenCode"
        )
    }

    @Test("Default options use only effective Codex exposure and preserve an independent default")
    func defaultOptions() {
        let fixture = modelFixture()
        let model = AppModel(snapshot: CoordinatorSnapshot(configuration: fixture.configuration))

        #expect(model.openCodeDefaultModelOptions.map(\.mapping) == [fixture.alpha, fixture.beta])
        #expect(model.openCodeDefaultOptionID == model.optionID(for: fixture.beta))

        model.configuration.openCode.defaultModel = fixture.hidden
        #expect(model.openCodeDefaultOptionID == model.optionID(for: fixture.alpha))

        model.configuration.openCode.defaultModel = nil
        #expect(model.openCodeDefaultOptionID == model.optionID(for: fixture.alpha))
    }

    @Test("Snapshot application updates every OpenCode field")
    func snapshotApplication() {
        let fixture = modelFixture()
        let model = AppModel()
        let snapshot = CoordinatorSnapshot(
            configuration: fixture.configuration,
            openCodeStatus: .needsAttention,
            hasPendingOpenCodeChanges: true
        )

        model.apply(snapshot)

        #expect(model.configuration == fixture.configuration)
        #expect(model.openCodeStatus == .needsAttention)
        #expect(model.hasPendingOpenCodeChanges)
    }
}

private struct ModelFixture {
    var configuration: AppConfiguration
    var alpha: ModelMapping
    var hidden: ModelMapping
    var beta: ModelMapping
}

private func modelFixture() -> ModelFixture {
    let alphaID = UUID()
    let betaID = UUID()
    let alpha = ModelMapping(providerID: alphaID, modelID: "alpha")
    let hidden = ModelMapping(providerID: alphaID, modelID: "hidden")
    let beta = ModelMapping(providerID: betaID, modelID: "beta")
    return ModelFixture(
        configuration: AppConfiguration(
            providers: [
                Provider(
                    id: alphaID,
                    name: "Alpha",
                    baseURL: "https://alpha.example.com",
                    authMode: .none,
                    models: [DiscoveredModel(id: "hidden"), DiscoveredModel(id: "alpha")]
                ),
                Provider(
                    id: betaID,
                    name: "Beta",
                    baseURL: "https://beta.example.com",
                    authMode: .none,
                    models: [DiscoveredModel(id: "beta")]
                ),
            ],
            codex: CodexConfiguration(defaultModel: alpha, excludedModels: [hidden]),
            openCode: OpenCodeConfiguration(defaultModel: beta)
        ),
        alpha: alpha,
        hidden: hidden,
        beta: beta
    )
}
