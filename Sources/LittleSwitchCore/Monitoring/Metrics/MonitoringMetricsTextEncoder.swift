import Foundation

enum MonitoringMetricsFormat: Equatable, Sendable {
    case prometheus
    case openMetrics

    var contentType: String {
        switch self {
        case .prometheus: "text/plain; version=0.0.4; charset=utf-8"
        case .openMetrics: "application/openmetrics-text; version=1.0.0; charset=utf-8"
        }
    }
}

enum MonitoringMetricsTextEncoder {
    static func encode(
        _ snapshot: MonitoringMetricsSnapshot,
        format: MonitoringMetricsFormat = .prometheus
    ) -> String {
        var lines: [String] = []
        for family in snapshot.families.sorted(by: { $0.name.prometheusName < $1.name.prometheusName }) {
            let name = family.name.prometheusName
            let metadataName = format == .openMetrics && family.name.type == "counter" ? String(name.dropLast(6)) : name
            lines.append("# HELP \(metadataName) \(escape(family.name.help))")
            lines.append("# TYPE \(metadataName) \(family.name.type)")
            for point in family.points.sorted(by: { labels($0.attributes) < labels($1.attributes) }) {
                append(point, name: name, to: &lines)
            }
        }
        if format == .openMetrics { lines.append("# EOF") }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    static func negotiate(accept: [String]) -> MonitoringMetricsFormat? {
        MonitoringMetricsNegotiation.resolve(accept)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func append(_ point: MonitoringMetricPoint, name: String, to lines: inout [String]) {
        switch point.value {
        case .counter(let value), .gauge(let value):
            lines.append("\(name)\(labels(point.attributes)) \(value)")
        case .histogram(let histogram):
            for (index, count) in histogram.cumulativeBucketCounts.enumerated() {
                let bound = index < histogram.explicitBounds.count ? String(histogram.explicitBounds[index]) : "+Inf"
                lines.append("\(name)_bucket\(labels(point.attributes, bound: bound)) \(count)")
            }
            lines.append("\(name)_sum\(labels(point.attributes)) \(histogram.sum)")
            lines.append("\(name)_count\(labels(point.attributes)) \(histogram.count)")
        }
    }

    private static func labels(_ attributes: [MonitoringMetricAttribute], bound: String? = nil) -> String {
        var values = attributes.map { ($0.name, $0.value) }
        if let bound { values.append(("le", bound)) }
        guard !values.isEmpty else { return "" }
        return "{" + values.sorted { $0.0 < $1.0 }.map { "\($0.0)=\"\(escape($0.1))\"" }.joined(separator: ",") + "}"
    }
}
