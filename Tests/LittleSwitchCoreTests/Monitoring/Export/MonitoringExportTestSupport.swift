import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

actor MonitoringManualExportClock: MonitoringExportClock {
    struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var elapsed = Duration.zero
    private var sleepers: [UUID: Sleeper] = [:]

    func now() -> MonitoringExportTime {
        .init(monotonic: elapsed, date: Date(timeIntervalSince1970: 1_000 + elapsed.seconds))
    }

    func sleep(until deadline: Duration) async throws {
        let identifier = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if deadline <= elapsed { return }
            try await withCheckedThrowingContinuation { continuation in
                sleepers[identifier] = Sleeper(deadline: deadline, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancel(identifier) }
        }
    }

    func advance(by duration: Duration) {
        elapsed += duration
        for (identifier, sleeper) in sleepers where sleeper.deadline <= elapsed {
            sleepers.removeValue(forKey: identifier)?.continuation.resume()
        }
    }

    func isSleeping(until deadline: Duration) -> Bool {
        sleepers.values.contains { $0.deadline == deadline }
    }

    private func cancel(_ identifier: UUID) {
        sleepers.removeValue(forKey: identifier)?.continuation.resume(throwing: CancellationError())
    }
}

actor MonitoringRecordingTransport: OTLPTransporting {
    struct Call: Sendable {
        let endpoint: URL
        let body: Data
    }

    var responses: [OTLPHTTPResponse]
    var calls: [Call] = []
    var shutdownCount = 0
    var activeCount = 0
    var maximumActiveCount = 0
    var suspended = false
    private var gate: CheckedContinuation<Void, Never>?

    init(responses: [OTLPHTTPResponse] = []) { self.responses = responses }

    func send(to endpoint: URL, body: Data, bearer: String?) async throws -> OTLPHTTPResponse {
        calls.append(.init(endpoint: endpoint, body: body))
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        defer { activeCount -= 1 }
        if suspended {
            await withTaskCancellationHandler {
                await withCheckedContinuation { gate = $0 }
            } onCancel: {
                Task { await self.release() }
            }
        }
        return responses.isEmpty ? exportResponse() : responses.removeFirst()
    }

    func hold() { suspended = true }
    func release() {
        suspended = false
        gate?.resume()
        gate = nil
    }
    func shutdown() { shutdownCount += 1 }
}

struct MonitoringThrowingTransport: OTLPTransporting {
    let error: URLError

    func send(to endpoint: URL, body: Data, bearer: String?) async throws -> OTLPHTTPResponse { throw error }
    func shutdown() async {}
}

func exportResponse(_ status: Int = 200, retryAfter: String? = nil, body: String = "{}") -> OTLPHTTPResponse {
    .init(status: status, contentType: "application/json", retryAfter: retryAfter, body: Data(body.utf8))
}

func exportConfiguration(metrics: Bool = false, logs: Bool = true, interval: Int = 5) -> MonitoringConfiguration {
    .init(
        metrics: .init(enabled: metrics, endpoint: "http://127.0.0.1:4318/v1/metrics"),
        logs: .init(enabled: logs, endpoint: "http://127.0.0.1:4318/v1/logs"),
        metricIntervalSeconds: interval)
}

func exportEventually(_ condition: @escaping @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !(await condition()) {
        guard ContinuousClock.now < deadline else {
            Issue.record("The exporter did not reach its expected state.")
            return
        }
        try await Task.sleep(for: .milliseconds(1))
    }
}

extension Duration {
    fileprivate var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
