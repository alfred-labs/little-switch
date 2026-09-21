import AppKit
import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Provider advanced controls", .serialized)
struct ProviderEditorAdvancedControlsTests {
    @Test("Connection diagnostics start folded and can be inspected independently")
    func diagnosticsStartFolded() async throws {
        let state = ProviderAdvancedTestState()
        let host = MenuControlTestHost(ProviderAdvancedTestContent(state: state), width: 800, height: 1_400)
        defer { host.close() }
        try await host.activateAccessibility()

        #expect(host.textContent.contains(L10n.string("Compatibility")))
        #expect(!host.textContent.contains(L10n.string("Native /v1/responses · learned")))
        let disclosure = try host.element(label: L10n.string("Connection details"))
        #expect(disclosure.accessibilityPerformPress())
        host.render()
        #expect(host.textContent.contains(L10n.string("Native /v1/responses · learned")))
    }

    @Test("Folding advanced settings preserves a model's manual context declaration")
    func foldingPreservesContext() async throws {
        let state = ProviderAdvancedTestState()
        let host = MenuControlTestHost(ProviderAdvancedTestContent(state: state), width: 800, height: 1_400)
        defer { host.close() }
        try await host.activateAccessibility()

        let unavailable = try host.element(label: L10n.string("1M context for \("large")"))
        #expect(unavailable.accessibilityValue() as? String == L10n.string("Unavailable"))
        let automatic = try host.element(label: L10n.string("1M context for \("xlarge")"))
        #expect(automatic.accessibilityValue() as? String == L10n.string("Automatic"))
        let manual = try host.element(label: contextLabel("unknown"))
        #expect(manual.isAccessibilityEnabled())
        #expect(host.textContent.contains(L10n.string("Not reported")))
        // The Grid publishes an AX proxy; dispatch through its native switch.
        let switches = nativeSwitches(in: host.hosting)
        #expect(switches.count == 1)
        let native = try #require(switches.first)
        _ = native.accessibilityPerformPress()
        host.render()
        #expect(state.draft.contextOverrides == ["unknown": 1_000_000])
        #expect(host.textContent.contains(L10n.string("Not reported")))

        state.expanded = false
        host.render()
        #expect(!host.textContent.contains(L10n.string("Model context")))
        state.expanded = true
        host.render()
        #expect(state.draft.contextOverrides == ["unknown": 1_000_000])
        let restored = try host.element(label: contextLabel("unknown"))
        #expect((restored.accessibilityValue() as? NSNumber)?.boolValue == true)
    }

    private func contextLabel(_ modelID: String) -> String {
        L10n.string("Force 1M context in Claude for \(modelID)")
    }

    private func nativeSwitches(in view: NSView) -> [NSSwitch] {
        (view as? NSSwitch).map { [$0] } ?? view.subviews.flatMap { nativeSwitches(in: $0) }
    }
}

@MainActor
@Observable
private final class ProviderAdvancedTestState {
    var expanded = true
    var draft: ProviderDraft = {
        var draft = ProviderDraft()
        draft.modelContexts = [
            ModelContextDraft(model: DiscoveredModel(id: "large", detectedContextWindow: 400_000)),
            ModelContextDraft(
                model: DiscoveredModel(id: "xlarge", detectedContextWindow: 1_048_576, contextWindowOverride: 200_000)),
            ModelContextDraft(model: DiscoveredModel(id: "unknown")),
        ]
        return draft
    }()
}

private struct ProviderAdvancedTestContent: View {
    @Bindable var state: ProviderAdvancedTestState

    var body: some View {
        Form {
            ProviderEditorAdvanced(draft: $state.draft, isExpanded: $state.expanded, responsesWireVerdict: true)
        }
        .formStyle(.grouped)
    }
}
