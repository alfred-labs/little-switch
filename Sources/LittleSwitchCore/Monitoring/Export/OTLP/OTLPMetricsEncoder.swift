import Foundation
import LittleSwitchCommon

package enum OTLPMetricsEncoder {
    package enum Failure: Error { case inconsistentMetric }

    package static func encode(_ snapshot: MonitoringMetricsSnapshot) throws -> Data {
        try OTLPJSON.encode(
            Envelope(resourceMetrics: [
                ResourceMetrics(
                    resource: OTLPResource(snapshot.resource),
                    scopeMetrics: [
                        ScopeMetrics(
                            scope: OTLPScope(),
                            metrics: snapshot.families.map {
                                Metric(
                                    family: $0,
                                    start: OTLPJSON.nanoseconds(snapshot.resource.startedAt),
                                    time: OTLPJSON.nanoseconds(snapshot.capturedAt))
                            })
                    ])
            ]))
    }

    package static func batches(
        _ snapshot: MonitoringMetricsSnapshot,
        maximumBytes: Int = 512 * 1_024
    ) throws -> OTLPEncodingResult {
        let points = snapshot.families.flatMap { family in family.points.map { (family.name, $0) } }
        return try OTLPPayloadPartitioner.partition(points, maximumBytes: maximumBytes) { segment in
            let groups = Dictionary(grouping: segment, by: \.0)
            let families = groups.sorted { $0.key.rawValue < $1.key.rawValue }.map { name, entries in
                MonitoringMetricFamily(name: name, points: entries.map(\.1))
            }
            return try encode(.init(resource: snapshot.resource, capturedAt: snapshot.capturedAt, families: families))
        }
    }

    private struct Envelope: Encodable {
        let resourceMetrics: [ResourceMetrics]
        private enum CodingKeys: String, CodingKey { case resourceMetrics }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(resourceMetrics, forKey: .resourceMetrics)
        }
    }
    private struct ResourceMetrics: Encodable {
        let resource: OTLPResource
        let scopeMetrics: [ScopeMetrics]
        private enum CodingKeys: String, CodingKey { case resource, scopeMetrics }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(resource, forKey: .resource)
            try container.encode(scopeMetrics, forKey: .scopeMetrics)
        }
    }
    private struct ScopeMetrics: Encodable {
        let scope: OTLPScope
        let metrics: [Metric]
        private enum CodingKeys: String, CodingKey { case scope, metrics }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(scope, forKey: .scope)
            try container.encode(metrics, forKey: .metrics)
        }
    }

    private struct Metric: Encodable {
        let family: MonitoringMetricFamily
        let start: String
        let time: String

        private enum CodingKeys: String, CodingKey { case name, description, unit, sum, gauge, histogram }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(family.name.rawValue, forKey: .name)
            try container.encode(family.name.help, forKey: .description)
            try container.encode(family.name.unit, forKey: .unit)
            switch family.name {
            case .duration:
                let points = try family.points.map { try HistogramPoint($0, start: start, time: time) }
                try container.encode(Histogram(dataPoints: points), forKey: .histogram)
            case .inFlight, .waiting, .test:
                let points = try family.points.map { try NumberPoint($0, start: nil, time: time) }
                try container.encode(Gauge(dataPoints: points), forKey: .gauge)
            default:
                let points = try family.points.map { try NumberPoint($0, start: start, time: time) }
                try container.encode(Sum(dataPoints: points), forKey: .sum)
            }
        }
    }

    private struct NumberPoint: Encodable {
        let attributes: [OTLPAttribute]
        let startTimeUnixNano: String?
        let timeUnixNano: String
        let asInt: String

        private enum CodingKeys: String, CodingKey { case attributes, startTimeUnixNano, timeUnixNano, asInt }

        init(_ point: MonitoringMetricPoint, start: String?, time: String) throws {
            attributes = point.attributes.map { .init($0.name, .string($0.value)) }
            startTimeUnixNano = start
            timeUnixNano = time
            switch point.value {
            case .counter(let value), .gauge(let value): asInt = String(min(value, UInt64(Int64.max)))
            case .histogram: throw Failure.inconsistentMetric
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(attributes, forKey: .attributes)
            try container.encodeIfPresent(startTimeUnixNano, forKey: .startTimeUnixNano)
            try container.encode(timeUnixNano, forKey: .timeUnixNano)
            try container.encode(asInt, forKey: .asInt)
        }
    }

    private struct HistogramPoint: Encodable {
        let attributes: [OTLPAttribute]
        let startTimeUnixNano: String
        let timeUnixNano: String
        let count: String
        let sum: Double
        let bucketCounts: [String]
        let explicitBounds: [Double]

        private enum CodingKeys: String, CodingKey {
            case attributes, startTimeUnixNano, timeUnixNano, count, sum, bucketCounts, explicitBounds
        }

        init(_ point: MonitoringMetricPoint, start: String, time: String) throws {
            guard case .histogram(let value) = point.value else { throw Failure.inconsistentMetric }
            attributes = point.attributes.map { .init($0.name, .string($0.value)) }
            startTimeUnixNano = start
            timeUnixNano = time
            count = String(value.count)
            sum = value.sum
            bucketCounts = value.bucketCounts.map(String.init)
            explicitBounds = value.explicitBounds
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(attributes, forKey: .attributes)
            try container.encode(startTimeUnixNano, forKey: .startTimeUnixNano)
            try container.encode(timeUnixNano, forKey: .timeUnixNano)
            try container.encode(count, forKey: .count)
            try container.encode(sum, forKey: .sum)
            try container.encode(bucketCounts, forKey: .bucketCounts)
            try container.encode(explicitBounds, forKey: .explicitBounds)
        }
    }

    private struct Sum: Encodable {
        let dataPoints: [NumberPoint]
        private enum CodingKeys: String, CodingKey { case dataPoints, aggregationTemporality, isMonotonic }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(dataPoints, forKey: .dataPoints)
            try container.encode(2, forKey: .aggregationTemporality)
            try container.encode(true, forKey: .isMonotonic)
        }
    }
    private struct Gauge: Encodable {
        let dataPoints: [NumberPoint]
        private enum CodingKeys: String, CodingKey { case dataPoints }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(dataPoints, forKey: .dataPoints)
        }
    }
    private struct Histogram: Encodable {
        let dataPoints: [HistogramPoint]
        private enum CodingKeys: String, CodingKey { case dataPoints, aggregationTemporality }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(dataPoints, forKey: .dataPoints)
            try container.encode(2, forKey: .aggregationTemporality)
        }
    }
}
