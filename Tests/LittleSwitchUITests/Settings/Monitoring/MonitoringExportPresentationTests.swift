import AppKit
import LittleSwitchCommon
import LittleSwitchCore
import Observation
import SwiftUI
import Testing

@testable import LittleSwitchUI

@Suite("Monitoring export presentation")
struct MonitoringExportPresentationTests {
    @Test("Export titles describe the actual signal state and pending changes")
    func stateTitles() {
        let states: [(MonitoringSignalExportStatus, String)] = [
            (.init(), L10n.string("Disabled")),
            (.init(state: .idle), L10n.string("Waiting")),
            (.init(state: .idle, lastAccepted: Date(timeIntervalSince1970: 1)), L10n.string("Ready")),
            (.init(state: .sending), L10n.string("Sending…")),
            (.init(state: .retrying), L10n.string("Retry scheduled")),
            (.init(state: .failed), L10n.string("Export failed")),
        ]
        for (status, title) in states {
            #expect(MonitoringExportPresentation.title(for: status, pending: false) == title)
            #expect(MonitoringExportPresentation.title(for: status, pending: true) == L10n.string("Pending"))
        }
    }

    @Test("Pending belongs only to the signal whose destination, credential or options changed")
    func signalPending() {
        let applied = MonitoringConfiguration()
        let unchanged = MonitoringSettingsDraft(configuration: applied)
        #expect(!MonitoringExportPresentation.hasPendingChanges(for: .metrics, draft: unchanged, applied: applied))
        #expect(!MonitoringExportPresentation.hasPendingChanges(for: .logs, draft: unchanged, applied: applied))
        let changes: [(MonitoringSignal, WritableKeyPath<MonitoringSettingsDraft, Bool>)] = [
            (.metrics, \.configuration.metrics.enabled),
            (.logs, \.configuration.logs.enabled),
            (.metrics, \.removeMetricsToken),
            (.logs, \.removeLogsToken),
        ]
        for (signal, keyPath) in changes {
            var draft = unchanged
            draft[keyPath: keyPath] = true
            expectPending(signal, draft: draft, applied: applied)
        }
        var draft = unchanged
        draft.metricsToken = "synthetic-metrics-token"
        expectPending(.metrics, draft: draft, applied: applied)
        draft = unchanged
        draft.logsToken = "synthetic-logs-token"
        expectPending(.logs, draft: draft, applied: applied)
        draft = unchanged
        draft.configuration.metricIntervalSeconds = 60
        expectPending(.metrics, draft: draft, applied: applied)
        draft = unchanged
        draft.configuration.minimumLogLevel = .warn
        expectPending(.logs, draft: draft, applied: applied)
        draft = unchanged
        draft.configuration.exposeMetrics.toggle()
        draft.configuration.exposeLogs.toggle()
        #expect(!MonitoringExportPresentation.hasPendingChanges(for: .metrics, draft: draft, applied: applied))
        #expect(!MonitoringExportPresentation.hasPendingChanges(for: .logs, draft: draft, applied: applied))
    }

    @Test("Local URL copying follows applied access and offers HTTPS only when available")
    func localAccess() {
        let disabled = MonitoringLocalEndpointPresentation(
            path: "/metrics", enabled: false, appliedEnabled: false, httpsAvailable: false
        )
        #expect(!disabled.canCopy)
        #expect(!disabled.isPending)
        #expect(disabled.httpURL == "http://127.0.0.1:11436/metrics")
        #expect(disabled.httpsURL == nil)
        #expect(disabled.copyHelp == L10n.string("Enable this endpoint and apply changes to make it available."))
        let activation = MonitoringLocalEndpointPresentation(
            path: "/logs", enabled: true, appliedEnabled: false, httpsAvailable: true
        )
        #expect(!activation.canCopy)
        #expect(activation.isPending)
        #expect(activation.httpURL == "http://127.0.0.1:11436/logs")
        #expect(activation.httpsURL == "https://127.0.0.1:11436/logs")
        #expect(activation.copyHelp == L10n.string("Apply changes to make this endpoint available."))
        let deactivation = MonitoringLocalEndpointPresentation(
            path: "/metrics", enabled: false, appliedEnabled: true, httpsAvailable: false
        )
        #expect(deactivation.canCopy)
        #expect(deactivation.isPending)
        #expect(deactivation.copyHelp == L10n.string("Available until you apply this change."))
        let available = MonitoringLocalEndpointPresentation(
            path: "/logs", enabled: true, appliedEnabled: true, httpsAvailable: true
        )
        #expect(available.canCopy)
        #expect(!available.isPending)
        #expect(available.copyHelp == L10n.string("Copy a local endpoint URL."))
    }

    @MainActor
    @Test("Delivery details use the singular form for one queued byte")
    func singularQueuedByte() async throws {
        let host = MenuControlTestHost(
            MonitoringExportStatusView(
                title: L10n.string("Metrics"),
                status: MonitoringSignalExportStatus(
                    state: .sending,
                    queuedCount: 1,
                    queuedBytes: 1
                ),
                testResult: nil
            ),
            width: 688,
            height: 240
        )
        defer { host.close() }
        try await host.activateAccessibility()

        let disclosure = try host.element(label: L10n.string("Delivery details"))
        #expect(disclosure.accessibilityPerformPress())
        host.render()
        let expected = L10n.string("\(1) queued · \(1) byte · \(UInt64(0)) dropped")
        #expect(host.textContent.contains { $0.contains(expected) })
    }

    @MainActor
    @Test("The native interval menu preserves a custom value and publishes each preset in seconds")
    func nativeIntervalPresets() throws {
        let selection = MonitoringIntervalTestSelection()
        var changes: [Int] = []
        let binding = Binding(
            get: { selection.value },
            set: {
                selection.value = $0
                changes.append($0)
            }
        )
        let host = MenuControlTestHost(MonitoringMetricIntervalPicker(value: binding), width: 600)
        defer { host.close() }
        let picker = NativeMenuPickerTestControl(root: host.hosting, identifyingTitle: L10n.string("5 min"))
        let presets: [(title: String, seconds: Int)] = [
            (L10n.string("\(5) s"), 5), (L10n.string("\(10) s"), 10),
            (L10n.string("\(15) s"), 15), (L10n.string("\(30) s"), 30),
            (L10n.string("1 min"), 60), (L10n.string("2 min"), 120), (L10n.string("5 min"), 300),
        ]
        let currentTitle = L10n.string("\(17) s (current)")
        #expect(try picker.titles == presets.map(\.title) + [currentTitle])
        #expect(try picker.selectedTitle == currentTitle)
        #expect(selection.value == 17)
        #expect(changes.isEmpty)

        for preset in presets {
            try picker.select(preset.title)
            host.hosting.rootView = MonitoringMetricIntervalPicker(value: binding)
            host.render()

            #expect(selection.value == preset.seconds)
            #expect(try picker.selectedTitle == preset.title)
            #expect(try picker.titles == presets.map(\.title))
        }
        #expect(changes == presets.map(\.seconds))
    }

    private func expectPending(
        _ signal: MonitoringSignal, draft: MonitoringSettingsDraft, applied: MonitoringConfiguration
    ) {
        for candidate in MonitoringSignal.allCases {
            #expect(
                MonitoringExportPresentation.hasPendingChanges(for: candidate, draft: draft, applied: applied)
                    == (candidate == signal))
        }
    }
}

@MainActor
@Observable
private final class MonitoringIntervalTestSelection {
    var value = 17
}
