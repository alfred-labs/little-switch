import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Synthetic monitoring probe")
struct MonitoringProbeTests {
    static let runID = UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, 1))
    static let metrics = #"{"status":"success","data":{"result":[{"value":[0,"1"]}]}}"#
    static let logs = #"{"status":"success","data":{"result":[{"values":[["0","monitoring.test"]]}]}}"#

    @Test("The probe sends both complete OTLP payloads before proving both signals queryable")
    func exchange() async throws {
        let fixture = MonitoringFixture([
            .response(200, "{}", "application/json"), .response(204),
            .response(200, Self.metrics), .response(200, Self.logs),
        ])
        try await run(fixture)
        let requests = await fixture.requests
        #expect(
            requests.map { $0.url?.path } == [
                "/api/v1/otlp/v1/metrics", "/otlp/v1/logs", "/api/v1/query", "/loki/api/v1/query_range",
            ])
        #expect(requests.map(\.httpMethod) == ["POST", "POST", "GET", "GET"])
        #expect(requests.map(\.timeoutInterval) == [5, 5, 2, 2])
        try #require(requests.count == 4)
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(requests[1].value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try json(requests[0].httpBody) == json(Data(MonitoringPayloadFixture.metrics.utf8)))
        #expect(try json(requests[1].httpBody) == json(Data(MonitoringPayloadFixture.logs.utf8)))
        #expect(
            try query(requests[2]) == [
                "query": "littleswitch_monitoring_probe_total{probe_id=\"00000000-0000-4000-8000-000000000001\"}"
            ])
        #expect(
            try query(requests[3]) == [
                "query": "{service_name=\"littleswitch\"} | event_id=\"00000000-0000-4000-8000-000000000001\"",
                "start": "1782345618123000000", "end": "1782345738123000000", "limit": "100",
            ])
        #expect(await fixture.sleeps.isEmpty)
        let output = await fixture.output
        try #require(output.count == 3)
        #expect(
            try json(Data(output[0].utf8))
                == json(
                    Data(
                        #"{"endpoint":"/api/v1/otlp/v1/metrics","status":200,"contentType":"application/json","reply":"{}"}"#
                            .utf8)))
        #expect(
            try json(Data(output[1].utf8))
                == json(Data(#"{"endpoint":"/otlp/v1/logs","status":204,"contentType":null,"reply":""}"#.utf8)))
        #expect(output[2] == "OTLP JSON metrics and logs are queryable")
    }

    @Test("A rejected payload is reported and stops before any following request", arguments: [false, true])
    func rejectedPayload(logs: Bool) async throws {
        let fixture = MonitoringFixture((logs ? [.response(200)] : []) + [.response(400, "invalid")])
        await #expect(throws: MonitoringFailure.rejectedPayload) { try await run(fixture) }
        #expect(await fixture.requests.count == (logs ? 2 : 1))
        #expect(await fixture.output.count == (logs ? 2 : 1))
        #expect(await fixture.sleeps.isEmpty)
        #expect(MonitoringFailure.rejectedPayload.description == "The receiver rejected the synthetic JSON payload")
    }

    @Test("Only successful queries containing the exact metric and log evidence finish the probe")
    func retries() async throws {
        let fixture = MonitoringFixture([
            .response(200), .response(200),
            .response(503, Self.metrics), .response(200, #"{"status":"success","data":{"result":[]}}"#),
            .response(200, Self.metrics),
            .response(200, #"{"status":"success","data":{"result":[{"values":[["0","unrelated"]]}]}}"#),
            .response(200, Self.logs),
        ])
        try await run(fixture)
        #expect(await fixture.requests.count == 7)
        #expect(await fixture.sleeps == [.seconds(1), .seconds(1), .seconds(1)])
        #expect(await fixture.output.last == "OTLP JSON metrics and logs are queryable")
    }

    @Test("Each signal has a bounded 30-query deadline", arguments: [false, true])
    func deadline(logs: Bool) async throws {
        let fixture = MonitoringFixture(
            [.response(200), .response(200)] + (logs ? [.response(200, Self.metrics)] : [])
                + Array(repeating: .response(200, #"{"status":"success","data":{"result":[]}}"#), count: 30))
        await #expect(throws: MonitoringFailure.notQueryable) { try await run(fixture) }
        #expect(await fixture.requests.count == (logs ? 33 : 32))
        #expect(await fixture.sleeps == Array(repeating: .seconds(1), count: 30))
        #expect(await fixture.output.count == 2)
        #expect(
            MonitoringFailure.notQueryable.description == "Synthetic OTLP data was not queryable within the deadline")
    }

    @Test("HTTP transport errors propagate immediately", arguments: 0..<4)
    func unavailable(stage: Int) async throws {
        let successful: [MonitoringFixture.Action] = [.response(200), .response(200), .response(200, Self.metrics)]
        let fixture = MonitoringFixture(Array(successful.prefix(stage)) + [.unavailable])
        await #expect(throws: MonitoringFixture.Failure.unavailable) { try await run(fixture) }
        #expect(await fixture.requests.count == stage + 1)
        #expect(await fixture.sleeps.isEmpty)
    }

    @Test("Cancellation propagates at each HTTP stage", arguments: 0..<4)
    func cancelled(stage: Int) async throws {
        let successful: [MonitoringFixture.Action] = [.response(200), .response(200), .response(200, Self.metrics)]
        let fixture = MonitoringFixture(Array(successful.prefix(stage)) + [.cancelled])
        await #expect(throws: CancellationError.self) { try await run(fixture) }
        #expect(await fixture.requests.count == stage + 1)
        #expect(await fixture.sleeps.isEmpty)
    }

    @Test("Malformed query JSON fails without printing a success message")
    func malformedJSON() async throws {
        let fixture = MonitoringFixture([.response(200), .response(200), .response(200, "{")])
        await #expect(throws: (any Error).self) { try await run(fixture) }
        #expect(await fixture.requests.count == 3)
        #expect(await fixture.output.count == 2)
    }

    @Test("Cancellation during the visibility wait stops further queries")
    func sleepCancellation() async throws {
        let fixture = MonitoringFixture([.response(200), .response(200), .response(200, "{}")])
        await fixture.cancelDuringSleep()
        await #expect(throws: CancellationError.self) { try await run(fixture) }
        #expect(await fixture.requests.count == 3)
        #expect(await fixture.sleeps == [.seconds(1)])
    }

    private func run(_ fixture: MonitoringFixture) async throws {
        try await MonitoringProbe(client: fixture, sleep: fixture.sleep).run(
            id: Self.runID, unixMilliseconds: 1_782_345_678_123, emit: fixture.emit)
    }

    private func json(_ data: Data?) throws -> NSDictionary {
        let bytes = try #require(data)
        return try #require(JSONSerialization.jsonObject(with: bytes) as? NSDictionary)
    }

    private func query(_ request: URLRequest) throws -> [String: String] {
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: true))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}

@Test("Receipt JSON falls back to an empty endpoint when the request has no URL")
func receiptWithoutURL() throws {
    var request = URLRequest(url: URL(string: "https://example.invalid")!)
    request.url = nil
    let probe = MonitoringProbe(client: MonitoringFixture([])) { _ in }
    let receipt = try probe.receipt(
        request: request,
        response: MonitoringHTTPResponse(status: 204, contentType: nil, body: Data()))
    #expect(receipt == #"{"contentType":null,"endpoint":"","reply":"","status":204}"#)
}
