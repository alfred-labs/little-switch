import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Gateway usage event from traffic")
struct GatewayUsageEventTrafficTests {
    @Test("A finished request carries its route, usage, and duration")
    func completedRequest() throws {
        let startedAt = Date(timeIntervalSince1970: 1_788_000_000)
        let providerID = UUID()
        var event = trafficEvent(
            startedAt: startedAt,
            actions: [
                .routed(
                    TrafficRoute(
                        client: .codex,
                        modelIdentifier: "claude-opus-5",
                        target: TrafficRouteTarget(
                            providerID: providerID,
                            providerName: "z.ai",
                            modelID: "glm-4.7"
                        ),
                        streaming: true
                    )
                ),
                .initialUsageEstimate(
                    TrafficInitialUsageEstimate(
                        tokenCount: 900,
                        source: .provider,
                        providerOutcome: .success,
                        elapsedMilliseconds: 12
                    )
                ),
                .clientResponseChunk(Data(#"{"usage":{"input_tokens":40,"output_tokens":8}}"#.utf8)),
                .completed(
                    TrafficCompletion(status: 200, finishedAt: startedAt.addingTimeInterval(1.25))
                ),
            ]
        )
        event.retentionTruncated = false

        let usage = try #require(GatewayUsageEvent(trafficEvent: event))

        #expect(usage.outcome == .succeeded)
        #expect(usage.client == .codex)
        #expect(usage.routeID == "claude-opus-5")
        #expect(usage.providerName == "z.ai")
        #expect(usage.modelID == "glm-4.7")
        #expect(usage.durationMilliseconds == 1_250)
        #expect(usage.usage == GatewayUsageTotals(inputTokens: 40, outputTokens: 8))
        #expect(usage.estimatedInputTokens == 900)
        #expect(usage.finishedAt == startedAt.addingTimeInterval(1.25))
    }

    @Test("Failures and cancellations keep their outcome")
    func terminalOutcomes() throws {
        let startedAt = Date(timeIntervalSince1970: 1_788_000_000)
        let failed = trafficEvent(
            startedAt: startedAt,
            actions: [
                .failed(
                    TrafficFailureCompletion(
                        status: 502,
                        finishedAt: startedAt,
                        failure: TrafficFailure(kind: "provider", message: "upstream")
                    )
                )
            ]
        )
        let cancelled = trafficEvent(
            startedAt: startedAt,
            actions: [.cancelled(finishedAt: startedAt)]
        )

        #expect(GatewayUsageEvent(trafficEvent: failed)?.outcome == .failed)
        #expect(GatewayUsageEvent(trafficEvent: cancelled)?.outcome == .cancelled)
        #expect(try #require(GatewayUsageEvent(trafficEvent: failed)).usage == nil)

        // A retained event can reach a terminal state without a finish time; it
        // still belongs to the day it started.
        var truncated = failed
        truncated.finishedAt = nil
        #expect(GatewayUsageEvent(trafficEvent: truncated)?.finishedAt == startedAt)
        #expect(GatewayUsageEvent(trafficEvent: truncated)?.durationMilliseconds == nil)
    }

    @Test("The gateway's own probes are not routed traffic")
    func internalProbesAreSkipped() {
        let startedAt = Date(timeIntervalSince1970: 1_788_000_000)
        var probe = trafficEvent(startedAt: startedAt, actions: [])
        probe.path = ProductIdentity.gatewayHealthPath
        probe.apply(
            TrafficRecord(
                eventID: probe.id,
                sequence: 99,
                timestamp: startedAt,
                action: .completed(TrafficCompletion(status: 200, finishedAt: startedAt))
            )
        )

        #expect(probe.lifecycle == .completed)
        #expect(GatewayUsageEvent(trafficEvent: probe) == nil)
    }

    @Test("The compat aliases, the reserved metrics path, and /api probes are not traffic")
    func aliasAndReservedPathsAreSkipped() {
        let startedAt = Date(timeIntervalSince1970: 1_788_000_000)
        for path in [
            ProductIdentity.legacyGatewayInternalPathPrefix + "health",
            ProductIdentity.legacyGatewayInternalPathPrefix + "about",
            ProductIdentity.legacyGatewayInternalPathPrefix + "web_search",
            ProductIdentity.gatewayMetricsPath,
            ProductIdentity.gatewayAPIPathPrefix + "about",
            ProductIdentity.gatewayAPIPathPrefix + "web-search",
        ] {
            var probe = trafficEvent(startedAt: startedAt, actions: [])
            probe.path = path
            probe.apply(
                TrafficRecord(
                    eventID: probe.id,
                    sequence: 99,
                    timestamp: startedAt,
                    action: .completed(TrafficCompletion(status: 200, finishedAt: startedAt))
                )
            )

            #expect(probe.lifecycle == .completed)
            #expect(GatewayUsageEvent(trafficEvent: probe) == nil)
        }
    }

    @Test("A request still in flight has nothing to fold")
    func inFlightRequest() {
        let event = trafficEvent(
            startedAt: Date(timeIntervalSince1970: 1_788_000_000),
            actions: []
        )

        #expect(event.lifecycle == .inProgress)
        #expect(GatewayUsageEvent(trafficEvent: event) == nil)
    }
}

func trafficEvent(startedAt: Date, actions: [TrafficAction]) -> TrafficEvent {
    let eventID = UUID()
    var event = TrafficEvent(
        firstRecord: TrafficRecord(
            eventID: eventID,
            sequence: 0,
            timestamp: startedAt,
            action: .started(
                TrafficRequestStart(
                    startedAt: startedAt,
                    method: "POST",
                    path: "/v1/messages",
                    headers: []
                )
            )
        )
    )
    for (offset, action) in actions.enumerated() {
        event.apply(
            TrafficRecord(
                eventID: eventID,
                sequence: UInt64(offset + 1),
                timestamp: startedAt,
                action: action
            )
        )
    }
    return event
}
