/// Bounded latency distribution for one day of gateway traffic.
///
/// Keeping every duration would grow without limit, so samples land in fixed
/// exponential buckets, keeping the persisted history stable in size no matter
/// how much traffic a day carries.
public struct GatewayLatencyHistogram: Equatable, Sendable {
    /// Inclusive upper bounds in milliseconds. Anything slower lands in the
    /// overflow bucket that follows the last edge.
    public static let edges = [50, 100, 200, 400, 800, 1_600, 3_200, 6_400, 12_800, 25_600, 51_200, 102_400]

    public var buckets: [Int]

    public init() {
        buckets = Array(repeating: 0, count: Self.edges.count + 1)
    }

    public init(buckets: [Int]) {
        let normalized = buckets.prefix(Self.edges.count + 1).map { max(0, $0) }
        self.buckets =
            normalized
            + Array(repeating: 0, count: Self.edges.count + 1 - normalized.count)
    }

    public mutating func record(milliseconds: Int) {
        let index = Self.edges.firstIndex { milliseconds <= $0 } ?? Self.edges.count
        buckets[index] = saturatedGatewayUsageSum(buckets[index], 1)
    }

    public func merging(_ other: Self) -> Self {
        var merged = self
        for index in merged.buckets.indices {
            merged.buckets[index] = saturatedGatewayUsageSum(merged.buckets[index], other.buckets[index])
        }
        return merged
    }

}
