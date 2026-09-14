import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Traffic initial usage estimates")
struct TrafficInitialUsageEstimateTests {
    @Test("The reducer records estimate provenance")
    func reducerRecordsEstimate() {
        let timestamp = Date(timeIntervalSince1970: 125)
        var event = makeEvent(timestamp: timestamp)
        let estimate = TrafficInitialUsageEstimate(
            tokenCount: 1_506,
            source: .provider,
            providerOutcome: .success,
            elapsedMilliseconds: 27
        )

        event.apply(
            TrafficRecord(
                eventID: event.id,
                sequence: 1,
                timestamp: timestamp,
                action: .initialUsageEstimate(estimate)
            )
        )

        #expect(event.initialUsageEstimate == estimate)
    }

    @Test("The latest local estimate replaces earlier provenance without accumulating tokens")
    func latestEstimateWins() {
        let timestamp = Date(timeIntervalSince1970: 150)
        var event = makeEvent(timestamp: timestamp)
        let outcomes: [TrafficProviderCountOutcome] = [.timeout, .http, .invalid, .transport]

        for (offset, outcome) in outcomes.enumerated() {
            let estimate = TrafficInitialUsageEstimate(
                tokenCount: 100 + offset,
                source: .localDividedByFour,
                providerOutcome: outcome,
                elapsedMilliseconds: offset * 10
            )
            event.apply(
                TrafficRecord(
                    eventID: event.id,
                    sequence: UInt64(offset + 1),
                    timestamp: timestamp,
                    action: .initialUsageEstimate(estimate)
                )
            )
            #expect(event.initialUsageEstimate == estimate)
        }

        #expect(event.initialUsageEstimate?.tokenCount == 103)
        #expect(!event.retentionTruncated)
    }

    @Test("Events decode without estimate metadata written by older versions")
    func backwardDecoding() throws {
        let event = makeEvent(timestamp: Date(timeIntervalSince1970: 175))
        let encoded = try JSONEncoder().encode(event)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "initialUsageEstimate")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(TrafficEvent.self, from: legacyData)

        #expect(decoded.initialUsageEstimate == nil)
    }

    private func makeEvent(timestamp: Date) -> TrafficEvent {
        TrafficEvent(
            firstRecord: TrafficRecord(
                eventID: UUID(),
                sequence: 0,
                timestamp: timestamp,
                action: .started(
                    TrafficRequestStart(
                        startedAt: timestamp,
                        method: "POST",
                        path: "/v1/messages",
                        headers: []
                    )
                )
            )
        )
    }
}
