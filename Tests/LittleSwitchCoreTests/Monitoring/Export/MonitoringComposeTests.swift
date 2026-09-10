import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring Docker Compose integration", .serialized)
struct MonitoringComposeTests {
    @Test(
        "The product exporter sends metrics and logs that Prometheus and Loki can query",
        .enabled(if: ProcessInfo.processInfo.environment["LITTLESWITCH_MONITORING_LAB"] == "1")
    )
    func productExportIsQueryable() async throws {
        let store = MonitoringStore()
        let exporter = MonitoringExportService(store: store)
        let client = URLSession(configuration: .ephemeral)
        do {
            await exporter.configure(
                .init(
                    metrics: .init(enabled: true, endpoint: "http://127.0.0.1:19090/api/v1/otlp/v1/metrics"),
                    logs: .init(enabled: true, endpoint: "http://127.0.0.1:13100/otlp/v1/logs")
                )
            )
            let result = await exporter.testExport()
            #expect(result == .init(metrics: .accepted, logs: .accepted))
            let instance = store.resource.instanceID.uuidString.lowercased()
            let metrics = try url(
                "http://127.0.0.1:19090/api/v1/query",
                query: "littleswitch_monitoring_test{service_instance_id=\"\(instance)\"}"
            )
            try await eventually(client, url: metrics) { root in
                guard let data = root["data"] as? [String: Any],
                    let results = data["result"] as? [[String: Any]],
                    let value = results.first?["value"] as? [Any]
                else { return false }
                return results.count == 1 && value.last as? String == "1"
            }
            let event = try #require(try await store.logs().entries.first { $0.eventName == "monitoring.test" })
            let logs = try url(
                "http://127.0.0.1:13100/loki/api/v1/query_range",
                query: "{service_name=\"littleswitch\"} | event_id=\"\(event.eventID.uuidString.lowercased())\""
            )
            try await eventually(client, url: logs) { root in
                guard let data = root["data"] as? [String: Any], let streams = data["result"] as? [[String: Any]] else {
                    return false
                }
                return streams.contains { stream in
                    (stream["values"] as? [[Any]])?.contains { $0.dropFirst().first as? String == event.message }
                        == true
                }
            }
            #expect(await store.snapshot().family(.requests) == nil)
        } catch {
            await exporter.shutdown()
            client.invalidateAndCancel()
            throw error
        }
        await exporter.shutdown()
        client.invalidateAndCancel()
    }

    private func url(_ base: String, query: String) throws -> URL {
        var components = try #require(URLComponents(string: base))
        components.queryItems = [.init(name: "query", value: query)]
        return try #require(components.url)
    }

    private func eventually(
        _ client: URLSession,
        url: URL,
        matches: ([String: Any]) -> Bool
    ) async throws {
        for _ in 0..<30 {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            let (data, response) = try await client.data(for: request)
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if (response as? HTTPURLResponse)?.statusCode == 200, let root, matches(root) {
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        Issue.record("The synthetic product export was not queryable within 30 seconds: \(url.path)")
    }
}
