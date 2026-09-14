import LittleSwitchCommon

/// Cumulative series are never evicted. One slot is permanently reserved for overflow.
package struct MonitoringMetricSeries<Value: Sendable>: Sendable {
    private var values: [[MonitoringMetricAttribute]: Value] = [:]

    package mutating func update(
        _ attributes: [MonitoringMetricAttribute],
        initial: @autoclosure () -> Value,
        _ update: (inout Value) -> Void
    ) {
        let sorted = attributes.sorted { $0.name < $1.name }
        let key = values[sorted] != nil || values.count < 2_047 ? sorted : [.overflow]
        var value = values[key] ?? initial()
        update(&value)
        values[key] = value
    }

    package mutating func reset(to value: Value) {
        values = values.mapValues { _ in value }
    }

    package func points(_ convert: (Value) -> MonitoringMetricValue) -> [MonitoringMetricPoint] {
        values.map { MonitoringMetricPoint(attributes: $0.key, value: convert($0.value)) }
            .sorted { left, right in
                let leftKey = left.attributes.map { $0.name + "=" + $0.value }.joined(separator: "\0")
                let rightKey = right.attributes.map { $0.name + "=" + $0.value }.joined(separator: "\0")
                return leftKey < rightKey
            }
    }
}
