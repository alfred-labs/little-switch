import Foundation

struct MonitoringProbeRequests {
    let metrics: URLRequest
    let logs: URLRequest
    let metricsQuery: URLRequest
    let logsQuery: URLRequest

    init(id: UUID, unixMilliseconds: Int64) throws {
        let run = id.uuidString.lowercased()
        let now = Decimal(unixMilliseconds) * 1_000_000
        metrics = try Self.post(
            "http://127.0.0.1:19090/api/v1/otlp/v1/metrics", body: Self.metrics(run: run, now: now))
        logs = try Self.post("http://127.0.0.1:13100/otlp/v1/logs", body: Self.logs(run: run, now: now))
        metricsQuery = URLRequest(
            url: try URL("http://127.0.0.1:19090/api/v1/query", strategy: .url).appending(queryItems: [
                URLQueryItem(name: "query", value: "littleswitch_monitoring_probe_total{probe_id=\"\(run)\"}")
            ]), timeoutInterval: 2)
        logsQuery = URLRequest(
            url: try URL("http://127.0.0.1:13100/loki/api/v1/query_range", strategy: .url).appending(queryItems: [
                URLQueryItem(name: "query", value: "{service_name=\"littleswitch\"} | event_id=\"\(run)\""),
                URLQueryItem(name: "start", value: (now - 60_000_000_000).description),
                URLQueryItem(name: "end", value: (now + 60_000_000_000).description),
                URLQueryItem(name: "limit", value: "100"),
            ]), timeoutInterval: 2)
    }

    private static func post(_ endpoint: String, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: try URL(endpoint, strategy: .url), timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    private static func attribute(_ key: String, _ value: String) -> [String: Any] {
        ["key": key, "value": ["stringValue": value]]
    }

    private static func resource(_ run: String) -> [String: Any] {
        ["attributes": [attribute("service.name", "littleswitch"), attribute("service.instance.id", run)]]
    }

    private static func metrics(run: String, now: Decimal) -> [String: Any] {
        let point: [String: Any] = [
            "attributes": [attribute("probe_id", run)],
            "timeUnixNano": now.description,
            "startTimeUnixNano": (now - 1_000_000_000).description,
            "asInt": "1",
        ]
        let metric: [String: Any] = [
            "name": "littleswitch_monitoring_probe",
            "sum": ["aggregationTemporality": 2, "isMonotonic": true, "dataPoints": [point]],
        ]
        return [
            "resourceMetrics": [
                [
                    "resource": resource(run),
                    "scopeMetrics": [["scope": ["name": "littleswitch.monitoring.probe"], "metrics": [metric]]],
                ]
            ]
        ]
    }

    private static func logs(run: String, now: Decimal) -> [String: Any] {
        let record: [String: Any] = [
            "timeUnixNano": now.description, "observedTimeUnixNano": now.description,
            "severityNumber": 9, "severityText": "INFO", "body": ["stringValue": "monitoring.test"],
            "attributes": [attribute("event.id", run)],
        ]
        return [
            "resourceLogs": [
                [
                    "resource": resource(run),
                    "scopeLogs": [["scope": ["name": "littleswitch.monitoring.probe"], "logRecords": [record]]],
                ]
            ]
        ]
    }
}
