public struct MonitoringMetricFamily: Equatable, Sendable {
    public let name: MonitoringMetricName
    public let points: [MonitoringMetricPoint]

    package init(name: MonitoringMetricName, points: [MonitoringMetricPoint]) {
        self.name = name
        self.points = points
    }
}
