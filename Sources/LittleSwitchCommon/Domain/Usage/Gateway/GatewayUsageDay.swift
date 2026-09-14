import Foundation

/// One local calendar day of gateway traffic.
///
/// Counters stay bounded: routes, clients, and providers are configured
/// entities, and the key caps below keep a misbehaving client from growing the
/// file without limit.
public struct GatewayUsageDay: Equatable, Sendable {
    /// Most distinct route/provider/model targets counted in one day.
    public static let targetKeyLimit = 64
    /// Most distinct wire clients counted in one day.
    public static let clientKeyLimit = 8

    public var day: String
    public var requests: Int
    public var failures: Int
    public var cancellations: Int
    public var usage: GatewayUsageTotals
    public var estimatedTokens: Int
    public var reportedUsageRequests: Int
    public var toolSearchCount: Int
    public var webSearchCount: Int
    public var latency: GatewayLatencyHistogram
    public var targets: [String: Int]
    public var clients: [String: Int]
    public var clientUsage: [String: GatewayClientUsage]

    public init(day: String) {
        self.day = day
        requests = 0
        failures = 0
        cancellations = 0
        usage = GatewayUsageTotals()
        estimatedTokens = 0
        reportedUsageRequests = 0
        toolSearchCount = 0
        webSearchCount = 0
        latency = GatewayLatencyHistogram()
        targets = [:]
        clients = [:]
        clientUsage = [:]
    }

    /// Tokens for the day, preferring provider-reported usage and falling back to
    /// the gateway's own input estimate for requests that reported none.
    public var tokens: Int {
        saturatedGatewayUsageSum(usage.total, estimatedTokens)
    }

    public var usesEstimatedTokens: Bool {
        estimatedTokens > 0
    }

    public mutating func fold(_ event: GatewayUsageEvent) {
        requests = saturatedGatewayUsageSum(requests, 1)
        switch event.outcome {
        case .succeeded:
            break
        case .failed:
            failures = saturatedGatewayUsageSum(failures, 1)
        case .cancelled:
            cancellations = saturatedGatewayUsageSum(cancellations, 1)
        }
        if let reported = event.usage, !reported.isEmpty {
            usage += reported
            reportedUsageRequests = saturatedGatewayUsageSum(reportedUsageRequests, 1)
        } else if let estimate = event.estimatedInputTokens, estimate > 0 {
            estimatedTokens = saturatedGatewayUsageSum(estimatedTokens, estimate)
        }
        if let milliseconds = event.durationMilliseconds, event.outcome == .succeeded {
            latency.record(milliseconds: milliseconds)
        }
        toolSearchCount = saturatedGatewayUsageSum(toolSearchCount, event.toolSearchCount)
        webSearchCount = saturatedGatewayUsageSum(webSearchCount, event.webSearchCount)
        count(event.targetKey, in: &targets, limit: Self.targetKeyLimit)
        if let client = event.client {
            count(client.rawValue, in: &clients, limit: Self.clientKeyLimit)
            let reported = event.usage.flatMap { $0.isEmpty ? nil : $0 }
            add(
                GatewayClientUsage(
                    usage: reported ?? GatewayUsageTotals(),
                    estimatedTokens: reported == nil ? event.estimatedInputTokens ?? 0 : 0,
                    recordedRequests: 1,
                    failures: event.outcome == .failed ? 1 : 0,
                    webSearchCount: event.webSearchCount
                ),
                forKey: client.rawValue,
                limit: Self.clientKeyLimit
            )
        }
    }

    private func count(_ key: String, in counts: inout [String: Int], limit: Int) {
        guard !key.isEmpty else { return }
        guard counts[key] != nil || counts.count < limit else { return }
        counts[key] = saturatedGatewayUsageSum(counts[key] ?? 0, 1)
    }

    private mutating func add(_ addition: GatewayClientUsage, forKey key: String, limit: Int) {
        guard !key.isEmpty else { return }
        guard clientUsage[key] != nil || clientUsage.count < limit else { return }
        clientUsage[key] = (clientUsage[key] ?? GatewayClientUsage()) + addition
    }
}
