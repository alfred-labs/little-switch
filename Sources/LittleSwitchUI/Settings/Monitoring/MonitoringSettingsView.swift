import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI

struct MonitoringSettingsView: View {
    @Bindable var model: AppModel
    let onApply: @MainActor (MonitoringApplyInput) async -> Bool
    let onDraft: @MainActor (MonitoringPendingSettings?) async -> Void
    let onTest: @MainActor () async -> Void
    @State private var draft: MonitoringSettingsDraft

    init(
        model: AppModel,
        onApply: @escaping @MainActor (MonitoringApplyInput) async -> Bool,
        onDraft: @escaping @MainActor (MonitoringPendingSettings?) async -> Void,
        onTest: @escaping @MainActor () async -> Void
    ) {
        self.model = model
        self.onApply = onApply
        self.onDraft = onDraft
        self.onTest = onTest
        let initialDraft = MonitoringSettingsDraft(
            configuration: model.configuration.monitoring,
            pending: model.monitoringDraft
        )
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        SettingsPage {
            MonitoringLocalEndpointsView(
                configuration: $draft.configuration,
                applied: model.configuration.monitoring,
                httpsAvailable: model.monitoringHTTPSAvailable
            )
            exportSection
            if hasPendingChanges, let message = draft.validationMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.orange)
            }
        }
        .disabled(isBusy)
        .toolbar {
            SettingsToolbarActions {
                if hasPendingChanges { SettingsPendingNotice() }
                Button(model.monitoringStatus.isTesting ? "Testing…" : "Test export") {
                    Task { await onTest() }
                }
                .disabled(!canTest)
                .help("Send a synthetic event using the applied settings. Apply changes before testing.")
                Button(model.monitoringApplying ? "Applying…" : "Apply", systemImage: "checkmark") { applyDraft() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(isBusy || !hasPendingChanges || draft.validationMessage != nil)
                    .accessibilityHint("Apply monitoring settings")
            }
        }
        .onChange(of: draft) { _, value in
            let pending = value.pending
            Task { await onDraft(pending) }
        }
        .onChange(of: model.configuration.monitoring) { previous, applied in
            draft.rebase(on: applied, replacing: previous)
        }
        .onDisappear {
            draft.clearTypedTokens()
            let pending = draft.pending
            Task { await onDraft(pending) }
        }
    }

    private var exportSection: some View {
        SettingsSection("OTLP export") {
            MonitoringDestinationFields(
                title: "Metrics",
                placeholder: "https://collector.example/v1/metrics",
                destination: $draft.configuration.metrics,
                token: $draft.metricsToken,
                removeToken: $draft.removeMetricsToken,
                pending: MonitoringExportPresentation.hasPendingChanges(
                    for: .metrics, draft: draft, applied: model.configuration.monitoring),
                status: model.monitoringStatus.metrics,
                testResult: model.monitoringTestResult?.metrics
            ) {
                MonitoringMetricIntervalPicker(value: $draft.configuration.metricIntervalSeconds)
            }
            MonitoringDestinationFields(
                title: "Logs",
                placeholder: "https://collector.example/v1/logs",
                destination: $draft.configuration.logs,
                token: $draft.logsToken,
                removeToken: $draft.removeLogsToken,
                pending: MonitoringExportPresentation.hasPendingChanges(
                    for: .logs, draft: draft, applied: model.configuration.monitoring),
                status: model.monitoringStatus.logs,
                testResult: model.monitoringTestResult?.logs
            ) {
                LabeledContent("Minimum level") {
                    Picker("Minimum level", selection: $draft.configuration.minimumLogLevel) {
                        Text("Info").tag(MonitoringLevel.info)
                        Text("Warning").tag(MonitoringLevel.warn)
                        Text("Error").tag(MonitoringLevel.error)
                    }
                    .labelsHidden()
                    .settingsMenuPicker()
                    .monitoringControlColumn()
                }
                .frame(minHeight: SettingsLayout.disclosureRowMinimumHeight)
            }
            if let notice = model.monitoringNotice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.orange)
            }
            Text("Logs export structured events without prompts, response bodies or credentials.")
                .settingsSupportingText()
        }
    }

    private var isBusy: Bool {
        model.isBusy || model.monitoringAction != nil || model.monitoringApplying || model.monitoringStatus.isTesting
    }
    private var hasPendingChanges: Bool { draft.hasChanges(from: model.configuration.monitoring) }
    private var canTest: Bool {
        !isBusy && !hasPendingChanges
            && (model.configuration.monitoring.metrics.enabled || model.configuration.monitoring.logs.enabled)
    }

    private func applyDraft() {
        let input = draft.input
        Task {
            if await onApply(input) {
                draft.acknowledge(model.configuration.monitoring, submitted: input)
            }
        }
    }
}
