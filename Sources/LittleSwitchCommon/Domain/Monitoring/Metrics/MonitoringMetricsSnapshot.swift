import Foundation

public struct MonitoringMetricsSnapshot: Equatable, Sendable {
    public let resource: MonitoringResource
    public let capturedAt: Date
    public let families: [MonitoringMetricFamily]

    package init(resource: MonitoringResource, capturedAt: Date, families: [MonitoringMetricFamily]) {
        self.resource = resource
        self.capturedAt = capturedAt
        self.families = families
    }
}
