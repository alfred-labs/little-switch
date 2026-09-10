import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Monitoring readiness")
struct MonitoringReadinessTests {
    @Test("Both receivers are checked in order with a two-second request timeout")
    func ready() async throws {
        let fixture = MonitoringFixture([.response(200), .response(204)])
        try await MonitoringReadiness(client: fixture, sleep: fixture.sleep).run(emit: fixture.emit)
        let requests = await fixture.requests
        #expect(
            requests.map { $0.url?.absoluteString } == [
                "http://127.0.0.1:19090/-/ready", "http://127.0.0.1:13100/ready",
            ])
        #expect(requests.map(\.httpMethod) == ["GET", "GET"])
        #expect(requests.map(\.timeoutInterval) == [2, 2])
        #expect(await fixture.sleeps.isEmpty)
        #expect(await fixture.output == ["Prometheus ready", "Loki ready"])
    }

    @Test("Unavailable and unsuccessful receivers retry once per second")
    func retries() async throws {
        let fixture = MonitoringFixture([
            .unavailable, .response(503), .response(302), .response(299), .response(200),
        ])
        try await MonitoringReadiness(client: fixture, sleep: fixture.sleep).run(emit: fixture.emit)
        #expect(await fixture.requests.count == 5)
        #expect(await fixture.sleeps == [.seconds(1), .seconds(1), .seconds(1)])
        #expect(await fixture.output == ["Prometheus ready", "Loki ready"])
    }

    @Test("A receiver has at most 45 attempts and failure identifies the service", arguments: [false, true])
    func deadline(loki: Bool) async throws {
        let fixture = MonitoringFixture((loki ? [.response(200)] : []) + Array(repeating: .response(503), count: 45))
        do {
            try await MonitoringReadiness(client: fixture, sleep: fixture.sleep).run(emit: fixture.emit)
            Issue.record("Readiness unexpectedly succeeded")
        } catch {
            let name = loki ? "Loki" : "Prometheus"
            #expect(
                String(describing: error)
                    == "\(name) is not ready. Start the lab with docker compose -f tools/monitoring/compose.yaml up -d")
        }
        #expect(await fixture.requests.count == (loki ? 46 : 45))
        #expect(await fixture.sleeps == Array(repeating: .seconds(1), count: 45))
        #expect(await fixture.output == (loki ? ["Prometheus ready"] : []))
    }

    @Test("Cancellation propagates without another attempt", arguments: [false, true])
    func cancellation(duringSleep: Bool) async throws {
        let fixture = MonitoringFixture([duringSleep ? .response(503) : .cancelled])
        if duringSleep { await fixture.cancelDuringSleep() }
        await #expect(throws: CancellationError.self) {
            try await MonitoringReadiness(client: fixture, sleep: fixture.sleep).run(emit: fixture.emit)
        }
        #expect(await fixture.requests.count == 1)
        #expect(await fixture.sleeps.count == (duringSleep ? 1 : 0))
        #expect(await fixture.output.isEmpty)
    }
}
