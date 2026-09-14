import Foundation

public enum MonitoringClient: String, Codable, CaseIterable, Sendable {
    case claude, codex, unknown
}

public enum MonitoringRoute: String, Codable, CaseIterable, Sendable {
    case messages, responses, models, unknown
    case countTokens = "count_tokens"
}

public enum MonitoringOutcome: String, Codable, CaseIterable, Sendable {
    case success
    case clientError = "client_error"
    case serverError = "server_error"
    case transportError = "transport_error"
    case cancelled
}

public enum MonitoringErrorKind: String, Codable, CaseIterable, Sendable {
    case invalidRequest = "invalid_request"
    case providerHTTP = "provider_http"
    case providerResponse = "provider_response"
    case transport, timeout, overloaded, invalidated, shutdown, cancelled
    case internalFailure = "internal"
}

public enum MonitoringAdmissionOutcome: String, Codable, CaseIterable, Sendable {
    case admitted, overloaded, invalidated, shutdown
    case timedOut = "timed_out"
    case internalFailure = "internal"
}

public enum MonitoringWebSearchOutcome: String, Codable, CaseIterable, Sendable {
    case success, failure, cancelled
}

public enum MonitoringDropReason: String, Codable, CaseIterable, Sendable {
    case invalidUsage = "invalid_usage"
    case oversize
    case queueFull = "queue_full"
    case expired, reconfigured, rejected
    case partialRejection = "partial_rejection"
    case transportFailure = "transport_failure"
}

/// Only metadata explicitly allowed on the monitoring surfaces can be supplied.
/// This value cannot retain captures, headers, tool arguments or free-form errors.
public struct MonitoringObservation: Equatable, Sendable {
    public let requestID: UUID
    public let finishedAt: Date
    public let durationSeconds: Double
    public let client: MonitoringClient
    public let route: MonitoringRoute
    public let outcome: MonitoringOutcome
    public let providerID: UUID?
    public let resolvedModel: String?
    public let statusCode: Int?
    public let usage: GatewayUsageTotals?
    public let estimatedInputTokens: Int?
    public let webSearchCount: Int
    public let errorKind: MonitoringErrorKind?
    public let truncated: Bool

    public init(
        requestID: UUID,
        finishedAt: Date,
        durationSeconds: Double,
        client: MonitoringClient,
        route: MonitoringRoute,
        outcome: MonitoringOutcome,
        providerID: UUID? = nil,
        resolvedModel: String? = nil,
        statusCode: Int? = nil,
        usage: GatewayUsageTotals? = nil,
        estimatedInputTokens: Int? = nil,
        webSearchCount: Int = 0,
        errorKind: MonitoringErrorKind? = nil,
        metadataTruncated: Bool = false
    ) {
        self.requestID = requestID
        self.finishedAt = finishedAt
        self.durationSeconds = monitoringDuration(durationSeconds)
        self.client = client
        self.route = route
        self.outcome = outcome
        self.providerID = providerID
        self.resolvedModel = resolvedModel.map { monitoringBoundedText($0, maximumBytes: 256) }
        self.truncated = metadataTruncated || self.resolvedModel != resolvedModel
        self.statusCode = statusCode.flatMap { (100...599).contains($0) ? $0 : nil }
        self.usage = usage.map {
            GatewayUsageTotals(
                inputTokens: $0.inputTokens,
                outputTokens: $0.outputTokens,
                cacheReadTokens: $0.cacheReadTokens,
                cacheWriteTokens: $0.cacheWriteTokens)
        }
        self.estimatedInputTokens = estimatedInputTokens.map { max(0, $0) }
        self.webSearchCount = max(0, webSearchCount)
        self.errorKind = errorKind
    }
}

package func monitoringBoundedText(_ text: String, maximumBytes: Int) -> String {
    var byteCount = 0
    var result = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
        let size = scalar.utf8.count
        guard byteCount + size <= maximumBytes else { break }
        result.append(scalar)
        byteCount += size
    }
    return String(result)
}

package func monitoringDuration(_ value: Double) -> Double {
    value.isFinite ? max(0, value) : 0
}
