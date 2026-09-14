import LittleSwitchCommon
import LittleSwitchCore

/// Coordinator-owned, memory-only edits. Token values never enter this snapshot.
public struct MonitoringPendingSettings: Equatable, Sendable {
    public var configuration: MonitoringConfiguration
    public var removeMetricsToken: Bool
    public var removeLogsToken: Bool
    public var hasTypedToken: Bool

    public init(
        configuration: MonitoringConfiguration,
        removeMetricsToken: Bool = false,
        removeLogsToken: Bool = false,
        hasTypedToken: Bool = false
    ) {
        self.configuration = configuration
        self.removeMetricsToken = removeMetricsToken
        self.removeLogsToken = removeLogsToken
        self.hasTypedToken = hasTypedToken
    }

    func matches(_ configuration: MonitoringConfiguration) -> Bool {
        self.configuration == configuration && !removeMetricsToken && !removeLogsToken && !hasTypedToken
    }
}
