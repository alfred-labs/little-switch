import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

extension MonitoringComposeTests {
    @Test(
        "Real gateway terminals, usage and histogram values are queryable after cumulative exports",
        .enabled(if: ProcessInfo.processInfo.environment["LITTLESWITCH_MONITORING_LAB"] == "1")
    )
    func gatewaySignals() async throws {
        let fixture = try GatewayTests().makeFixture()
        let store = MonitoringStore()
        let exporter = MonitoringExportService(store: store)
        let query = MonitoringComposeQuery(instanceID: store.resource.instanceID)
        let transport = MonitoringComposeProvider()
        await exporter.configure(
            .init(
                exposeLogs: true,
                metrics: .init(enabled: true, endpoint: "http://127.0.0.1:19090/api/v1/otlp/v1/metrics"),
                logs: .init(enabled: true, endpoint: "http://127.0.0.1:13100/otlp/v1/logs")
            )
        )
        await exporter.updateProviderPool(fixture.state)
        let monitoring = GatewayMonitoring(store: store) {
            await exporter.configuration
        } recordLog: {
            await exporter.enqueue($0)
        }
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                monitoring: monitoring
            )
        )
        do {
            try await app.test(.live) { client in
                for _ in 0..<4 {
                    _ = try await client.execute(
                        uri: "/v1/messages",
                        method: .post,
                        headers: [.contentType: "application/json"],
                        body: .init(string: Self.request)
                    )
                }
                let logs = try await client.execute(uri: "/logs", method: .get)
                #expect(logs.status == .ok)
                #expect(!String(buffer: logs.body).contains("PRIVATE_"))
                let metrics = try await client.execute(uri: "/metrics", method: .get)
                #expect(metrics.status == .ok)
                #expect(String(buffer: metrics.body).contains("littleswitch_gateway_requests_total"))
            }
            let entries = try await store.logs().entries
            #expect(entries.count == 4)
            #expect(entries.map(\.attributes.outcome) == [.success, .serverError, .cancelled, .serverError])
            #expect(entries.map(\.level) == [.info, .error, .warn, .error])
            #expect(entries[3].attributes.statusCode == 200)
            #expect(entries[3].attributes.errorKind?.rawValue == "provider_response")
            #expect(
                entries[0].attributes.usage
                    == .init(inputTokens: 6, outputTokens: 4, cacheReadTokens: 3, cacheWriteTokens: 2))
            let expected = await store.snapshot()
            for _ in 0..<2 {
                #expect(await exporter.testExport() == .init(metrics: .accepted, logs: .accepted))
                try await query.metrics(expected)
            }
            for entry in entries { try await query.log(entry) }
            #expect(await transport.requestCount == 4)
            try await verifyLokiOutage(app: app, exporter: exporter, store: store, query: query)
        } catch {
            await exporter.shutdown()
            query.close()
            throw error
        }
        await exporter.shutdown()
        query.close()
    }

    private static let request =
        #"{"model":"claude-opus-5","stream":true,"max_tokens":20,"messages":[{"role":"user","content":"PRIVATE_PROMPT"}]}"#

    private func verifyLokiOutage(
        app: Application<GatewayResponder>,
        exporter: MonitoringExportService,
        store: MonitoringStore,
        query: MonitoringComposeQuery
    ) async throws {
        try await MonitoringComposeLab.command([
            "docker", "compose", "-f", "tools/monitoring/compose.yaml", "stop", "loki",
        ])
        do {
            try await app.test(.live) { client in
                _ = try await client.execute(
                    uri: "/v1/messages",
                    method: .post,
                    headers: [.contentType: "application/json"],
                    body: .init(string: Self.request)
                )
            }
            let result = await exporter.testExport()
            #expect(result.metrics == .accepted)
            #expect(result.logs == .retrying(.network))
            try await query.cancelledRequests(2)
            let entry = try #require(try await store.logs().entries.last { $0.attributes.outcome == .cancelled })
            try await MonitoringComposeLab.restoreLoki()
            try await query.log(entry)
        } catch {
            try await MonitoringComposeLab.restoreLoki()
            throw error
        }
    }
}

private actor MonitoringComposeProvider: UpstreamTransport {
    private(set) var requestCount = 0

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        requestCount += 1
        switch requestCount {
        case 1:
            return streamingResponse(
                status: .ok,
                headers: ["content-type": "text/event-stream"],
                chunks: [
                    #"data: {"type":"message_start","message":{"id":"synthetic","type":"message","role":"assistant","model":"glm-5.2","content":[],"#
                        + #""usage":{"input_tokens":6,"output_tokens":0,"cache_read_input_tokens":3,"cache_creation_input_tokens":2}}}"#
                        + "\n\n",
                    #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"PRIVATE_REPLY"}}"#
                        + "\n\n",
                    #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":4}}"#
                        + "\n\n",
                    #"data: {"type":"message_stop"}"# + "\n\n",
                ]
            )
        case 2:
            return response(
                status: .badGateway, body: #"{"type":"error","error":{"type":"api_error","message":"PRIVATE_ERROR"}}"#)
        case 4:
            return streamingResponse(
                status: .ok,
                headers: ["content-type": "text/event-stream"],
                chunks: [
                    "event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\","
                        + "\"message\":\"PRIVATE_ERROR\"}}\n\n"
                ])
        default: throw CancellationError()
        }
    }
}

private struct MonitoringComposeQuery {
    let instanceID: UUID
    private let client = URLSession(configuration: .ephemeral)

    func close() { client.invalidateAndCancel() }

    func cancelledRequests(_ count: Double) async throws {
        try await value("littleswitch_gateway_requests_total", labels: "outcome=\"cancelled\"", equals: count)
    }

    func metrics(_ snapshot: MonitoringMetricsSnapshot) async throws {
        for outcome in ["success", "server_error", "cancelled"] {
            try await value(
                "littleswitch_gateway_requests_total",
                labels: "outcome=\"\(outcome)\"",
                equals: outcome == "server_error" ? 2 : 1)
            try await value(
                "littleswitch_gateway_request_duration_seconds_count",
                labels: "outcome=\"\(outcome)\"",
                equals: outcome == "server_error" ? 2 : 1)
        }
        for (kind, count) in [("input", 6.0), ("output", 4.0), ("cache_read", 3.0), ("cache_write", 2.0)] {
            try await value("littleswitch_gateway_tokens_total", labels: "token_type=\"\(kind)\"", equals: count)
        }
        try await value("littleswitch_gateway_requests_in_flight", equals: 0)
        if let family = snapshot.family(.duration) {
            for point in family.points {
                guard case .histogram(let histogram) = point.value else { continue }
                let outcome = try #require(point.attributes.first { $0.name == "outcome" }?.value)
                let labels = "outcome=\"\(outcome)\""
                try await value(
                    "littleswitch_gateway_request_duration_seconds_sum", labels: labels, equals: histogram.sum)
                try await value(
                    "littleswitch_gateway_request_duration_seconds_bucket",
                    labels: labels + ",le=\"+Inf\"",
                    equals: Double(histogram.count))
            }
        }
    }

    func log(_ entry: MonitoringLogEntry) async throws {
        let query = "{service_name=\"littleswitch\"} | event_id=\"\(entry.eventID.uuidString.lowercased())\""
        let status = entry.attributes.statusCode.map { String($0) }
        try await eventually(base: "http://127.0.0.1:13100/loki/api/v1/query_range", query: query) { results in
            results.contains { stream in
                guard let values = stream["values"] as? [[Any]],
                    let metadata = stream["stream"] as? [String: String]
                else { return false }
                return values.contains { value in
                    guard value.count >= 2, value[1] as? String == entry.message else { return false }
                    return metadata["outcome"] == entry.attributes.outcome?.rawValue
                        && metadata["status"] == status
                        && metadata["error_type"] == entry.attributes.errorKind?.rawValue
                        && metadata["request_id"] == entry.attributes.requestID?.uuidString.lowercased()
                        && metadata["severity_number"] == String(entry.level.severityNumber)
                }
            }
        }
    }

    private func value(_ metric: String, labels: String = "", equals expected: Double) async throws {
        let suffix = labels.isEmpty ? "" : "," + labels
        let query = "sum(" + metric + "{service_instance_id=\"\(instanceID.uuidString.lowercased())\"\(suffix)})"
        try await eventually(base: "http://127.0.0.1:19090/api/v1/query", query: query) { results in
            guard results.count == 1, let pair = results[0]["value"] as? [Any],
                let raw = pair.last as? String, let actual = Double(raw)
            else { return false }
            return abs(actual - expected) < 1e-10
        }
    }

    private func eventually(base: String, query: String, matches: ([[String: Any]]) -> Bool) async throws {
        var components = try #require(URLComponents(string: base))
        components.queryItems = [.init(name: "query", value: query)]
        // Prometheus and Loki parse query values as form data, where a literal '+' means a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        let url = try #require(components.url)
        for _ in 0..<30 {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            let (body, response) = try await client.data(for: request)
            let root = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let data = root?["data"] as? [String: Any]
            let results = data?["result"] as? [[String: Any]]
            if (response as? HTTPURLResponse)?.statusCode == 200, let results, matches(results) {
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw MonitoringComposeQueryFailure(query: query)
    }
}

private struct MonitoringComposeQueryFailure: Error {
    let query: String
}
