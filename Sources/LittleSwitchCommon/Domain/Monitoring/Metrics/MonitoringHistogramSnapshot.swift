public struct MonitoringHistogramSnapshot: Equatable, Sendable {
    public let explicitBounds: [Double]
    public let bucketCounts: [UInt64]
    public let count: UInt64
    public let sum: Double

    package init(explicitBounds: [Double], bucketCounts: [UInt64], count: UInt64, sum: Double) {
        self.explicitBounds = explicitBounds
        self.bucketCounts = bucketCounts
        self.count = count
        self.sum = sum
    }

    public var cumulativeBucketCounts: [UInt64] {
        var total: UInt64 = 0
        return bucketCounts.map {
            total = monitoringSum(total, $0)
            return total
        }
    }
}

/// OTLP integer datapoints are signed 64-bit values, even though counts are nonnegative.
package let monitoringMaximumInteger = UInt64(Int64.max)

package func monitoringSum(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    let boundedLeft = min(lhs, monitoringMaximumInteger)
    return boundedLeft + min(rhs, monitoringMaximumInteger - boundedLeft)
}
