import Foundation
import LittleSwitchCommon

/// Lifetime is exactly one gateway request. No global completed-ID cache or traffic body is retained.
package actor MonitoringRequestContext {
    private let monitoring: GatewayMonitoring
    private let requestID: UUID
    private let client: MonitoringClient
    private let route: MonitoringRoute
    private let started = ContinuousClock.now
    private var providerID: UUID?
    private var model: String?
    private var modelTruncated = false
    private var exchangeUsage: [UUID: GatewayUsageTotals] = [:]
    private var estimatedInputTokens: Int?
    private var searchCount = 0
    private var observedError: MonitoringErrorKind?
    private var providerFailed = false
    private var finished = false

    package init(monitoring: GatewayMonitoring, requestID: UUID, client: MonitoringClient, route: MonitoringRoute) {
        self.monitoring = monitoring
        self.requestID = requestID
        self.client = client
        self.route = route
    }

    package func target(providerID: UUID, model: String) {
        guard !finished else { return }
        self.providerID = providerID
        self.model = monitoringBoundedText(model, maximumBytes: 256)
        self.modelTruncated = self.model != model
    }

    package func usage(exchangeID: UUID, totals: GatewayUsageTotals) async {
        guard !finished else { return }
        guard exchangeUsage[exchangeID] != nil || exchangeUsage.count < 128 else {
            await monitoring.store.recordDrop(signal: .metrics, reason: .oversize)
            return
        }
        exchangeUsage[exchangeID] = exchangeUsage[exchangeID]?.merging(totals) ?? totals
    }

    package func invalidUsage(count: Int) async {
        guard count > 0, !finished else { return }
        await monitoring.store.recordDrop(signal: .metrics, reason: .invalidUsage, count: UInt64(count))
    }

    package func estimatedInput(_ tokens: Int) {
        guard !finished, tokens >= 0 else { return }
        estimatedInputTokens = saturatedGatewayUsageSum(estimatedInputTokens ?? 0, tokens)
    }

    package func admission(_ outcome: MonitoringAdmissionOutcome) async {
        guard !finished else { return }
        observedError =
            switch outcome {
            case .admitted: nil
            case .overloaded: .overloaded
            case .timedOut: .timeout
            case .invalidated: .invalidated
            case .shutdown: .shutdown
            case .internalFailure: .internalFailure
            }
        await monitoring.store.recordAdmission(outcome)
    }

    package func searched() {
        guard !finished else { return }
        searchCount = saturatedGatewayUsageSum(searchCount, 1)
    }

    package func providerResponseFailed() {
        guard !finished else { return }
        providerFailed = true
    }

    package func finish(statusCode: Int? = nil, error: MonitoringErrorKind? = nil) async {
        guard !finished else { return }
        finished = true
        let failure = error ?? observedError ?? (providerFailed ? .providerResponse : nil)
        let duration = started.duration(to: .now).components
        let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        let usage = exchangeUsage.isEmpty ? nil : exchangeUsage.values.reduce(GatewayUsageTotals(), +)
        let observation = MonitoringObservation(
            requestID: requestID,
            finishedAt: Date(),
            durationSeconds: seconds,
            client: client,
            route: route,
            outcome: Self.outcome(
                status: statusCode,
                error: failure),
            providerID: providerID,
            resolvedModel: model,
            statusCode: statusCode,
            usage: usage,
            estimatedInputTokens: estimatedInputTokens,
            webSearchCount: searchCount,
            errorKind: failure ?? Self.httpError(statusCode),
            metadataTruncated: modelTruncated
        )
        exchangeUsage.removeAll()
        let entry = await monitoring.store.finish(observation)
        await monitoring.recordLog(entry)
    }

    private static func outcome(status: Int?, error: MonitoringErrorKind?) -> MonitoringOutcome {
        if error == .cancelled { return .cancelled }
        if error == .transport || error == .internalFailure { return .transportError }
        if error == .providerResponse { return .serverError }
        guard let status else { return .transportError }
        if status >= 500 { return .serverError }
        if status >= 400 { return .clientError }
        return .success
    }

    private static func httpError(_ status: Int?) -> MonitoringErrorKind? {
        guard let status, status >= 400 else { return nil }
        return status >= 500 ? .providerHTTP : .invalidRequest
    }
}
