import Foundation
import LittleSwitchCommon

/// Process-owned aggregates. Actor methods never perform network or file I/O.
/// Request contexts own terminal idempotency; no completed-request ID set is retained here.
public actor MonitoringStore {
    nonisolated public let resource: MonitoringResource
    private var counters: [MonitoringMetricName: MonitoringMetricSeries<UInt64>] = [:]
    private var durations = MonitoringMetricSeries<MonitoringHistogram>()
    private var inFlight = MonitoringMetricSeries<UInt64>()
    private var waiting = MonitoringMetricSeries<UInt64>()
    private var hasTestMarker = false
    private var logBuffer: MonitoringLogBuffer

    public init(resource: MonitoringResource = .init()) {
        self.resource = resource
        logBuffer = MonitoringLogBuffer(instanceID: resource.instanceID)
    }

    public func beginRequest(client: MonitoringClient, route: MonitoringRoute) {
        inFlight.update([.client(client), .route(route)], initial: 0) { $0 = monitoringSum($0, 1) }
    }

    /// The returned safe entry can be handed directly to the independent export queue.
    @discardableResult
    public func finish(_ observation: MonitoringObservation) -> MonitoringLogEntry {
        let base: [MonitoringMetricAttribute] = [
            .client(observation.client), .route(observation.route), .providerID(observation.providerID),
        ]
        increment(.requests, attributes: base + [.outcome(observation.outcome), .status(observation.statusCode)])
        durations.update(base + [.outcome(observation.outcome)], initial: MonitoringHistogram()) {
            $0.record(observation.durationSeconds)
        }
        inFlight.update([.client(observation.client), .route(observation.route)], initial: 0) { $0 -= min($0, 1) }
        if let usage = observation.usage {
            let values: [(MonitoringTokenType, Int)] = [
                (.input, usage.inputTokens), (.output, usage.outputTokens),
                (.cacheRead, usage.cacheReadTokens), (.cacheWrite, usage.cacheWriteTokens),
            ]
            for (type, count) in values {
                increment(.tokens, attributes: base + [.tokenType(type)], count: UInt64(count))
            }
        }
        if let estimate = observation.estimatedInputTokens {
            increment(.estimatedInputTokens, attributes: base, count: UInt64(estimate))
        }
        return append(MonitoringLogEntry(observation: observation))
    }

    public func recordAdmission(_ outcome: MonitoringAdmissionOutcome) {
        switch outcome {
        case .admitted: break
        case .timedOut: increment(.admissionTimeouts, attributes: [])
        case .overloaded, .invalidated, .shutdown, .internalFailure:
            increment(.admissionRejections, attributes: [.admissionReason(outcome)])
        }
    }

    public func recordWebSearch(provider: WebSearchProvider, outcome: MonitoringWebSearchOutcome) {
        increment(.webSearches, attributes: [.searchProvider(provider), .searchOutcome(outcome)])
    }

    public func recordDrop(signal: MonitoringSignal, reason: MonitoringDropReason, count: UInt64 = 1) {
        increment(.dropped, attributes: [.signal(signal), .dropReason(reason)], count: count)
    }

    @discardableResult
    public func recordOperation(_ operation: MonitoringOperation, at date: Date = Date()) -> MonitoringLogEntry {
        append(.operation(operation, at: date))
    }

    @discardableResult
    public func markTest(at date: Date = Date()) -> MonitoringLogEntry {
        hasTestMarker = true
        return recordOperation(.test, at: date)
    }

    public func snapshot(
        at date: Date = Date(),
        providerPool: ProviderRequestPoolSnapshot? = nil
    ) -> MonitoringMetricsSnapshot {
        var families = counters.map { name, series in
            MonitoringMetricFamily(name: name, points: series.points(MonitoringMetricValue.counter))
        }
        addFamily(.duration, points: durations.points { .histogram($0.snapshot) }, to: &families)
        addFamily(.inFlight, points: inFlight.points(MonitoringMetricValue.gauge), to: &families)
        if let providerPool {
            waiting.reset(to: 0)
            for provider in providerPool.providers {
                waiting.update([.providerID(provider.id)], initial: 0) {
                    $0 = monitoringSum($0, UInt64(max(0, provider.waitingCount)))
                }
            }
        }
        addFamily(.waiting, points: waiting.points(MonitoringMetricValue.gauge), to: &families)
        if hasTestMarker {
            addFamily(.test, points: [MonitoringMetricPoint(attributes: [], value: .gauge(1))], to: &families)
        }
        return MonitoringMetricsSnapshot(
            resource: resource, capturedAt: date, families: families.sorted { $0.name.rawValue < $1.name.rawValue })
    }

    public func logs(query: MonitoringLogQuery = .init()) throws -> MonitoringLogPage {
        try logBuffer.page(query: query)
    }

    private func increment(_ name: MonitoringMetricName, attributes: [MonitoringMetricAttribute], count: UInt64 = 1) {
        counters[name, default: MonitoringMetricSeries()].update(attributes, initial: 0) {
            $0 = monitoringSum($0, count)
        }
    }

    private func append(_ entry: MonitoringLogEntry) -> MonitoringLogEntry {
        if !logBuffer.append(entry) { recordDrop(signal: .logs, reason: .oversize) }
        return entry
    }

    private func addFamily(
        _ name: MonitoringMetricName,
        points: [MonitoringMetricPoint],
        to families: inout [MonitoringMetricFamily]
    ) {
        if !points.isEmpty { families.append(MonitoringMetricFamily(name: name, points: points)) }
    }
}
