import LittleSwitchCommon

package struct MonitoringHistogram: Sendable {
    package static let bounds: [Double] = [0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60, 120, 300]
    private var bucketCounts = [UInt64](repeating: 0, count: bounds.count + 1)
    private var count: UInt64 = 0
    private var sum: Double = 0

    package mutating func record(_ duration: Double) {
        guard count < monitoringMaximumInteger else { return }
        let seconds = monitoringDuration(duration)
        let finiteBucket = Self.bounds.firstIndex { seconds <= $0 }
        let index = finiteBucket ?? Self.bounds.count
        bucketCounts[index] = monitoringSum(bucketCounts[index], 1)
        count = monitoringSum(count, 1)
        sum = min(Double.greatestFiniteMagnitude, sum + seconds)
    }

    package var snapshot: MonitoringHistogramSnapshot {
        MonitoringHistogramSnapshot(explicitBounds: Self.bounds, bucketCounts: bucketCounts, count: count, sum: sum)
    }
}
