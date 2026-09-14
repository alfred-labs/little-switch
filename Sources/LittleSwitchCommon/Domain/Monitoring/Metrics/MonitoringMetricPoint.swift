public struct MonitoringMetricPoint: Equatable, Sendable {
    public let attributes: [MonitoringMetricAttribute]
    public let value: MonitoringMetricValue

    package init(attributes: [MonitoringMetricAttribute], value: MonitoringMetricValue) {
        self.attributes = attributes
        self.value = value
    }
}
