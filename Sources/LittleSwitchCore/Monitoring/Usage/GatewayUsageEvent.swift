import Foundation

/// One finished gateway request, reduced to what the usage history keeps.
public struct GatewayUsageEvent: Equatable, Sendable {
    public enum Outcome: String, Equatable, Sendable {
        case succeeded
        case failed
        case cancelled
    }

    public var finishedAt: Date
    public var outcome: Outcome
    public var client: GatewayClient?
    public var routeID: String?
    public var providerName: String?
    public var modelID: String?
    public var durationMilliseconds: Int?
    public var usage: GatewayUsageTotals?
    public var estimatedInputTokens: Int?
    /// ToolSearch calls the model made in this request's response, counted
    /// off the hot path from the recorded body (see `GatewayUsageScanner`).
    public var toolSearchCount: Int = 0
    /// Web search calls the gateway ran while serving this request.
    public var webSearchCount: Int = 0

    public init(
        finishedAt: Date,
        outcome: Outcome,
        client: GatewayClient? = nil,
        routeID: String? = nil,
        providerName: String? = nil,
        modelID: String? = nil,
        durationMilliseconds: Int? = nil,
        usage: GatewayUsageTotals? = nil,
        estimatedInputTokens: Int? = nil,
        toolSearchCount: Int = 0,
        webSearchCount: Int = 0
    ) {
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.client = client
        self.routeID = routeID
        self.providerName = providerName
        self.modelID = modelID
        self.durationMilliseconds = durationMilliseconds
        self.usage = usage
        self.estimatedInputTokens = estimatedInputTokens
        self.toolSearchCount = toolSearchCount
        self.webSearchCount = webSearchCount
    }

    /// Route, provider, and model as one countable key. Missing parts stay empty
    /// so a target that only resolved half way still groups with its peers; a
    /// request that never resolved one has no target to count.
    public var targetKey: String {
        let parts = [routeID, providerName, modelID]
        guard parts.contains(where: { $0?.isEmpty == false }) else { return "" }
        return parts.map { $0 ?? "" }.joined(separator: "\u{001F}")
    }
}

extension GatewayUsageEvent {
    /// Reduces a finished traffic event to its usage record. Requests still in
    /// flight have nothing to fold yet, and the gateway's own surface — the
    /// root health and reserved metrics probes, the `/api/` namespace, and
    /// the legacy `/_little_switch/*` aliases, which retained log segments
    /// still carry — is not traffic anyone routed. Counting it would inflate
    /// a quiet day with the app's own polling.
    public init?(trafficEvent event: TrafficEvent) {
        guard !ProductIdentity.isInternalGatewayPath(event.path) else {
            return nil
        }
        let outcome: Outcome
        switch event.lifecycle {
        case .completed:
            outcome = .succeeded
        case .failed:
            outcome = .failed
        case .cancelled:
            outcome = .cancelled
        case .inProgress:
            return nil
        }
        self.init(
            finishedAt: event.finishedAt ?? event.startedAt,
            outcome: outcome,
            client: event.client,
            routeID: event.claudeRoute,
            providerName: event.providerName,
            modelID: event.modelID,
            durationMilliseconds: event.duration.map { Int(($0 * 1_000).rounded()) },
            usage: GatewayUsageScanner.totals(in: event.clientResponse.body),
            estimatedInputTokens: event.initialUsageEstimate?.tokenCount,
            toolSearchCount: GatewayUsageScanner.toolSearchCalls(
                in: event.clientResponse.body
            ),
            webSearchCount: event.webSearches.count
        )
    }
}
