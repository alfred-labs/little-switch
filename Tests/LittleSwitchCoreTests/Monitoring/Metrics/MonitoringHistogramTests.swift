import Testing

@testable import LittleSwitchCore

@Suite("Monitoring cumulative histograms")
struct MonitoringHistogramTests {
    @Test("Exact intervals and sum drive both cumulative and OTLP buckets")
    func fixedBuckets() {
        var histogram = MonitoringHistogram()
        for duration in [0.05, 0.1, 0.3] { histogram.record(duration) }
        let value = histogram.snapshot
        #expect(value.explicitBounds == [0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60, 120, 300])
        #expect(value.bucketCounts == [1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(value.cumulativeBucketCounts == [1, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3])
        #expect(value.count == 3)
        #expect(abs(value.sum - 0.45) < 1e-7)
    }

    @Test("Invalid durations are normalized and values above the final bound remain counted")
    func durationBounds() {
        var histogram = MonitoringHistogram()
        for duration in [-1, .nan, .infinity, 301] { histogram.record(duration) }
        #expect(histogram.snapshot.count == 4)
        #expect(histogram.snapshot.sum == 301)
        #expect(histogram.snapshot.bucketCounts.first == 3)
        #expect(histogram.snapshot.bucketCounts.last == 1)
    }
}
