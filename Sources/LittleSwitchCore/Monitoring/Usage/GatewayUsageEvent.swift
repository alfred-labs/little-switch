import Foundation
import LittleSwitchCommon

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
