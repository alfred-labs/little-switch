import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OTLP metric encoding")
struct OTLPMetricsEncoderTests {
    @Test("A complete cumulative metric preserves integers beyond JavaScript precision")
    func fullCounterEnvelope() throws {
        let resource = MonitoringResource(
            serviceVersion: "v1",
            instanceID: try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            startedAt: Date(timeIntervalSince1970: 1))
        let snapshot = MonitoringMetricsSnapshot(
            resource: resource,
            capturedAt: Date(timeIntervalSince1970: 2),
            families: [
                .init(
                    name: .requests,
                    points: [.init(attributes: [.client(.claude)], value: .counter(9_007_199_254_740_993))])
            ])
        let data = try OTLPMetricsEncoder.encode(snapshot)
        let expected = #"""
            {"resourceMetrics":[{"resource":{"attributes":[
              {"key":"service.name","value":{"stringValue":"littleswitch"}},
              {"key":"service.version","value":{"stringValue":"v1"}},
              {"key":"service.instance.id","value":{"stringValue":"11111111-1111-1111-1111-111111111111"}}
            ]},"scopeMetrics":[{"scope":{"name":"littleswitch.gateway","version":"1"},"metrics":[{
              "name":"littleswitch.gateway.requests","description":"Completed gateway requests.","unit":"",
              "sum":{"aggregationTemporality":2,"isMonotonic":true,"dataPoints":[{
                "attributes":[{"key":"client","value":{"stringValue":"claude"}}],
                "startTimeUnixNano":"1000000000","timeUnixNano":"2000000000","asInt":"9007199254740993"
              }]}
            }]}]}]}
            """#
        #expect(
            try JSONSerialization.jsonObject(with: data) as? NSDictionary == JSONSerialization.jsonObject(
                with: Data(expected.utf8)) as? NSDictionary)
    }

    @Test("Histograms contain interval counts while gauges have no cumulative start")
    func histogramAndGauge() throws {
        var histogram = MonitoringHistogram()
        for duration in [0.05, 0.1, 0.3] { histogram.record(duration) }
        let snapshot = MonitoringMetricsSnapshot(
            resource: .init(),
            capturedAt: Date(),
            families: [
                .init(name: .duration, points: [.init(attributes: [], value: .histogram(histogram.snapshot))]),
                .init(name: .test, points: [.init(attributes: [], value: .gauge(1))]),
            ])
        let text = try #require(String(data: OTLPMetricsEncoder.encode(snapshot), encoding: .utf8))
        #expect(text.contains(#""bucketCounts":["1","1","0","1","0","0","0","0","0","0","0","0","0"]"#))
        #expect(text.contains(#""count":"3""#))
        #expect(text.contains(#""aggregationTemporality":2"#))
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let resources = try #require(object["resourceMetrics"] as? [[String: Any]])
        let scopes = try #require(resources[0]["scopeMetrics"] as? [[String: Any]])
        let metrics = try #require(scopes[0]["metrics"] as? [[String: Any]])
        let testMetric = metrics.first { $0["name"] as? String == MonitoringMetricName.test.rawValue }
        let gauge = try #require(testMetric?["gauge"] as? [String: Any])
        let points = try #require(gauge["dataPoints"] as? [[String: Any]])
        #expect(points[0]["asInt"] as? String == "1")
        #expect(points[0]["startTimeUnixNano"] == nil)
        #expect(gauge["aggregationTemporality"] == nil)
    }

    @Test("Payloads split at data points, retain every point, and reject an oversized point")
    func payloadBounds() throws {
        let snapshot = MonitoringMetricsSnapshot(
            resource: .init(),
            capturedAt: Date(),
            families: [
                .init(
                    name: .requests, points: (0..<20).map { .init(attributes: [.status(200 + $0)], value: .counter(1)) }
                )
            ])
        let result = try OTLPMetricsEncoder.batches(snapshot, maximumBytes: 1_400)
        #expect(result.payloads.count > 1)
        #expect(result.payloads.allSatisfy { $0.body.count <= 1_400 })
        #expect(result.payloads.reduce(0) { $0 + $1.itemCount } == 20)
        #expect(result.dropped == 0)
        let tooSmall = try OTLPMetricsEncoder.batches(snapshot, maximumBytes: 1)
        #expect(tooSmall.payloads.isEmpty)
        #expect(tooSmall.dropped == 20)
    }
}
