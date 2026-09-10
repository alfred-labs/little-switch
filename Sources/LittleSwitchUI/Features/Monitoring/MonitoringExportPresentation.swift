import LittleSwitchCore

enum MonitoringExportPresentation {
    static func title(for status: MonitoringSignalExportStatus, pending: Bool) -> String {
        if pending { return "Pending" }
        switch status.state {
        case .disabled: return "Disabled"
        case .idle: return status.lastAccepted == nil ? "Waiting" : "Ready"
        case .sending: return "Sending…"
        case .retrying: return "Retry scheduled"
        case .failed: return "Export failed"
        }
    }

    static func hasPendingChanges(
        for signal: MonitoringSignal, draft: MonitoringSettingsDraft, applied: MonitoringConfiguration
    ) -> Bool {
        switch signal {
        case .metrics:
            draft.configuration.metrics != applied.metrics || draft.input.metricsCredential != .keep
                || draft.configuration.metricIntervalSeconds != applied.metricIntervalSeconds
        case .logs:
            draft.configuration.logs != applied.logs || draft.input.logsCredential != .keep
                || draft.configuration.minimumLogLevel != applied.minimumLogLevel
        }
    }
}

struct MonitoringLocalEndpointPresentation {
    let path: String
    let enabled: Bool
    let appliedEnabled: Bool
    let httpsAvailable: Bool

    var canCopy: Bool { appliedEnabled }
    var isPending: Bool { enabled != appliedEnabled }
    var httpURL: String { "http://127.0.0.1:11436\(path)" }
    var httpsURL: String? { httpsAvailable ? "https://127.0.0.1:11436\(path)" : nil }

    var copyHelp: String {
        if appliedEnabled {
            return enabled ? "Copy a local endpoint URL." : "Available until you apply this change."
        }
        return enabled
            ? "Apply changes to make this endpoint available."
            : "Enable this endpoint and apply changes to make it available."
    }
}
