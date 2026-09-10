import AppKit
import LittleSwitchCore
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Monitoring settings controls", .serialized)
struct MonitoringSettingsControlsTests {
    init() { _ = NSApplication.shared }

    @Test("Disabled destinations start folded without editable receiver or token fields")
    func disabledDestinationsStartFolded() {
        var configuration = MonitoringConfiguration()
        configuration.metrics.authentication = .bearer
        configuration.logs.authentication = .bearer
        let hosting = host(model(configuration))
        let editableFields = descendants(NSTextField.self, in: hosting).filter(\.isEditable)
        #expect(editableFields.isEmpty)
    }

    @Test("Each destination uses an independent empty native secure field")
    func secureFields() throws {
        var configuration = MonitoringConfiguration()
        configuration.metrics.enabled = true
        configuration.logs.enabled = true
        configuration.metrics.authentication = .bearer
        configuration.logs.authentication = .bearer
        configuration.metrics.credentialID = UUID()
        let model = model(configuration)
        let hosting = host(model)
        let fields = descendants(NSSecureTextField.self, in: hosting)
        #expect(fields.count == 2)
        let secretsEmpty = fields.allSatisfy(\.stringValue.isEmpty)
        #expect(secretsEmpty)
        #expect(
            Set(fields.compactMap(\.placeholderString)) == [
                "Leave blank to keep the saved token", "Bearer token",
            ])
    }

    @Test("Status polling preserves the native endpoint field, edited value and keyboard focus")
    func pollingDoesNotResetFields() throws {
        var configuration = MonitoringConfiguration()
        configuration.metrics.enabled = true
        configuration.metrics.endpoint = "http://localhost:19090/api/v1/otlp/v1/metrics"
        let model = model(configuration)
        let hosting = host(model)
        let window = window(hosting)
        defer { window.close() }
        let field = try #require(
            descendants(NSTextField.self, in: hosting).first { $0.stringValue == configuration.metrics.endpoint })
        let edited = "http://localhost:19090/edited/v1/metrics"
        let editor = try edit(field, value: edited, in: window)
        model.monitoringStatus.metrics = .init(state: .sending)
        hosting.layoutSubtreeIfNeeded()
        let updated = try #require(
            descendants(NSTextField.self, in: hosting).first { $0.stringValue == edited })
        #expect(updated === field)
        #expect(updated.isEditable)
        #expect(updated.currentEditor() === editor)
        #expect(window.firstResponder === editor)
    }

    @Test("Turning off an export folds its controls while preserving the typed token")
    func disablingPreservesToken() throws {
        let configuration = MonitoringConfiguration(
            metrics: .init(enabled: true, endpoint: "https://receiver.example/v1/metrics", authentication: .bearer)
        )
        let model = model(configuration)
        let hosting = host(model)
        let window = window(hosting)
        defer { window.close() }
        let field = try #require(descendants(NSSecureTextField.self, in: hosting).first)
        _ = try edit(field, value: "synthetic-token", in: window)
        let switches = descendants(NSSwitch.self, in: hosting)
        #expect(switches.count == 4)
        let metricsExport = try #require(switches.dropFirst(2).first)
        #expect(metricsExport.state == .on)
        _ = metricsExport.accessibilityPerformPress()
        hosting.layoutSubtreeIfNeeded()
        #expect(metricsExport.state == .off)
        #expect(descendants(NSSecureTextField.self, in: hosting).isEmpty)
        model.monitoringStatus.metrics = .init(state: .failed, configurationIssue: .missingCredential)
        hosting.layoutSubtreeIfNeeded()
        #expect(descendants(NSSecureTextField.self, in: hosting).isEmpty)
        let folded = try #require(descendants(NSSwitch.self, in: hosting).dropFirst(2).first)
        _ = folded.accessibilityPerformPress()
        hosting.layoutSubtreeIfNeeded()
        #expect(folded.state == .on)
        let restored = try #require(descendants(NSSecureTextField.self, in: hosting).first)
        #expect(restored.stringValue == "synthetic-token")
    }

    @Test("Native interval selection preserves a custom value and its pending draft during polling")
    func intervalSelectionSurvivesPolling() async throws {
        var configuration = MonitoringConfiguration(
            metrics: .init(enabled: true, endpoint: "https://receiver.example/v1/metrics")
        )
        configuration.metricIntervalSeconds = 17
        let model = model(configuration)
        let hosting = host(model) { model.monitoringDraft = $0 }
        let window = window(hosting)
        defer { window.close() }
        let picker = try #require(
            descendants(NSPopUpButton.self, in: hosting).first { $0.itemTitles.contains("17 s (current)") }
        )
        #expect(picker.titleOfSelectedItem == "17 s (current)")
        #expect(model.monitoringDraft == nil)
        model.monitoringStatus.metrics = .init(state: .sending)
        hosting.layoutSubtreeIfNeeded()
        #expect(picker.titleOfSelectedItem == "17 s (current)")
        #expect(model.configuration.monitoring.metricIntervalSeconds == 17)

        for (title, seconds) in [("1 min", 60), ("5 s", 5), ("5 min", 300)] {
            let menu = try #require(picker.menu)
            menu.performActionForItem(at: picker.indexOfItem(withTitle: title))
            hosting.layoutSubtreeIfNeeded()
            _ = try await eventually(description: "the selected monitoring interval") {
                await MainActor.run {
                    model.monitoringDraft?.configuration.metricIntervalSeconds == seconds ? true : nil
                }
            }
            model.monitoringStatus.metrics = .init(state: .idle, lastAccepted: Date())
            hosting.layoutSubtreeIfNeeded()
            let updated = try #require(
                descendants(NSPopUpButton.self, in: hosting).first { $0.itemTitles.contains("5 min") }
            )
            #expect(updated === picker)
            #expect(updated.titleOfSelectedItem == title)
            #expect(!updated.itemTitles.contains("17 s (current)"))
            let draft = MonitoringSettingsDraft(configuration: configuration, pending: model.monitoringDraft)
            #expect(draft.configuration.metricIntervalSeconds == seconds)
            #expect(draft.validationMessage == nil)
            #expect(model.configuration.monitoring == configuration)
        }
    }

    @Test("The native page renders both complete lab destinations and local access controls")
    func nativePage() {
        let configuration = MonitoringConfiguration(
            exposeLogs: true,
            metrics: .init(enabled: true, endpoint: "http://localhost:19090/api/v1/otlp/v1/metrics"),
            logs: .init(enabled: true, endpoint: "http://localhost:13100/otlp/v1/logs")
        )
        let model = model(configuration)
        model.monitoringStatus = .init(metrics: .init(state: .idle), logs: .init(state: .idle))
        model.selectedSection = .monitoring
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 1_060),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let controller = NSHostingController(rootView: settingsView(model))
        window.contentViewController = controller
        SettingsWindowChrome.apply(to: window)
        window.setContentSize(NSSize(width: 900, height: 1_060))
        controller.view.setFrameSize(NSSize(width: 900, height: 1_060))
        defer { window.close() }
        controller.view.layoutSubtreeIfNeeded()
        let fields = descendants(NSTextField.self, in: controller.view)
        #expect(fields.contains { $0.stringValue == configuration.metrics.endpoint })
        #expect(fields.contains { $0.stringValue == configuration.logs.endpoint })
    }

    private func model(_ monitoring: MonitoringConfiguration) -> AppModel {
        AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: AppConfiguration(monitoring: monitoring),
                monitoringHTTPSAvailable: true
            )
        )
    }

    private func host(
        _ model: AppModel,
        onDraft: @escaping @MainActor (MonitoringPendingSettings?) async -> Void = { _ in }
    ) -> NSHostingView<MonitoringSettingsView> {
        let onApply: @MainActor (MonitoringApplyInput) async -> Bool = { _ in false }
        let hosting = NSHostingView(
            rootView: MonitoringSettingsView(
                model: model,
                onApply: onApply,
                onDraft: onDraft
            ) {}
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 688, height: 1_400)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private func window(_ content: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: content.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        return window
    }

    private func edit(_ field: NSTextField, value: String, in window: NSWindow) throws -> NSTextView {
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText(value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        return editor
    }

    private func settingsView(_ model: AppModel) -> SettingsView {
        SettingsView(
            model: model,
            updater: DisabledSoftwareUpdateController(availability: .disabled(reason: "Preview")),
            onLaunchAtLoginEnabled: { _ in },
            onOpenLoginItems: {},
            onModelIndicator: { _ in },
            onSaveProvider: { _ in .failed("Preview") },
            onTestProvider: { _ in .authenticationFailed("Preview") },
            onSaveWebSearch: { _ in false },
            onWebSearchDraft: { _ in },
            onRefreshProvider: { _ in },
            onDeleteProvider: { _ in },
            onMapping: { _, _ in },
            onAutoMode: { _ in },
            onApplyClaudeProducts: { _, _ in },
            onClaudeCodeDefault: { _, _ in },
            onCodexExposure: { _, _ in },
            onCodexDefault: { _ in },
            onCodexAutoReview: { _ in },
            onConnectCodex: {},
            onApplyCodex: {},
            onOpenCodeDefault: { _ in },
            onConnectOpenCode: {},
            onApplyOpenCode: {},
            onRestoreOpenCode: {}
        )
    }

    private func descendants<NativeView: NSView>(_ type: NativeView.Type, in view: NSView) -> [NativeView] {
        let matches = (view as? NativeView).map { [$0] } ?? []
        return matches + view.subviews.flatMap { descendants(type, in: $0) }
    }
}
