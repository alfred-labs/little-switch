import AppKit
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
            (.init(), "Disabled"),
            (.init(state: .idle), "Waiting"),
            (.init(state: .idle, lastAccepted: Date(timeIntervalSince1970: 1)), "Ready"),
            (.init(state: .sending), "Sending…"),
            (.init(state: .retrying), "Retry scheduled"),
            (.init(state: .failed), "Export failed"),
        ]
        for (status, title) in states {
            #expect(MonitoringExportPresentation.title(for: status, pending: false) == title)
            #expect(MonitoringExportPresentation.title(for: status, pending: true) == "Pending")
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
        #expect(disabled.copyHelp == "Enable this endpoint and apply changes to make it available.")
        let activation = MonitoringLocalEndpointPresentation(
            path: "/logs", enabled: true, appliedEnabled: false, httpsAvailable: true
        )
        #expect(!activation.canCopy)
        #expect(activation.isPending)
        #expect(activation.httpURL == "http://127.0.0.1:11436/logs")
        #expect(activation.httpsURL == "https://127.0.0.1:11436/logs")
        #expect(activation.copyHelp == "Apply changes to make this endpoint available.")
        let deactivation = MonitoringLocalEndpointPresentation(
            path: "/metrics", enabled: false, appliedEnabled: true, httpsAvailable: false
        )
        #expect(deactivation.canCopy)
        #expect(deactivation.isPending)
        #expect(deactivation.copyHelp == "Available until you apply this change.")
        let available = MonitoringLocalEndpointPresentation(
            path: "/logs", enabled: true, appliedEnabled: true, httpsAvailable: true
        )
        #expect(available.canCopy)
        #expect(!available.isPending)
        #expect(available.copyHelp == "Copy a local endpoint URL.")
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
        let picker = try host.nativeView(of: NSPopUpButton.self)
        let presets: [(title: String, seconds: Int)] = [
            ("5 s", 5), ("10 s", 10), ("15 s", 15), ("30 s", 30),
            ("1 min", 60), ("2 min", 120), ("5 min", 300),
        ]
        #expect(picker.itemTitles == presets.map(\.title) + ["17 s (current)"])
        #expect(picker.titleOfSelectedItem == "17 s (current)")
        #expect(selection.value == 17)
        #expect(changes.isEmpty)

        for preset in presets {
            let menu = try #require(picker.menu)
            menu.performActionForItem(at: picker.indexOfItem(withTitle: preset.title))
            host.hosting.rootView = MonitoringMetricIntervalPicker(value: binding)
            host.render()

            #expect(selection.value == preset.seconds)
            #expect(picker.titleOfSelectedItem == preset.title)
            #expect(picker.itemTitles == presets.map(\.title))
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
