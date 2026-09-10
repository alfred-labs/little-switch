import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Traffic web search")
struct TrafficWebSearchTests {
    private func event(_ actions: [TrafficAction]) -> TrafficEvent {
        let id = UUID()
        let started = TrafficRecord(
            eventID: id,
            sequence: 0,
            timestamp: Date(timeIntervalSince1970: 0),
            action: .started(
                TrafficRequestStart(
                    startedAt: Date(timeIntervalSince1970: 0),
                    method: "POST",
                    path: "/v1/responses",
                    headers: []
                )
            )
        )
        var event = TrafficEvent(firstRecord: started)
        for (offset, action) in actions.enumerated() {
            event.apply(
                TrafficRecord(
                    eventID: id,
                    sequence: UInt64(offset + 1),
                    timestamp: Date(timeIntervalSince1970: Double(offset + 1)),
                    action: action
                )
            )
        }
        return event
    }

    @Test("A completed search is recorded with its result count")
    func completedSearch() {
        let search = TrafficWebSearch(
            provider: "firecrawl",
            query: "GTA VI news",
            startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 3),
            resultCount: 10,
            failure: nil
        )

        let event = event([.webSearch(search)])

        #expect(event.webSearches == [search])
        #expect(event.webSearches.first?.resultCount == 10)
        #expect(event.webSearches.first?.failure == nil)
        #expect(!event.retentionTruncated)
    }

    @Test("A failed search records its cause")
    func failedSearch() {
        let search = TrafficWebSearch(
            provider: "firecrawl",
            query: "GTA VI news",
            startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 2),
            resultCount: nil,
            failure: TrafficFailure(kind: "web-search", message: "unauthorized")
        )

        let event = event([.webSearch(search)])

        #expect(event.webSearches.first?.failure?.message == "unauthorized")
        #expect(event.lifecycle == .inProgress)
    }

    @Test("Several searches accumulate in order")
    func searchesAccumulate() {
        let first = TrafficWebSearch(
            provider: "firecrawl",
            query: "first",
            startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 2),
            resultCount: 3,
            failure: nil
        )
        let second = TrafficWebSearch(
            provider: "firecrawl",
            query: "second",
            startedAt: Date(timeIntervalSince1970: 3),
            finishedAt: Date(timeIntervalSince1970: 4),
            resultCount: 5,
            failure: nil
        )

        let event = event([.webSearch(first), .webSearch(second)])

        #expect(event.webSearches.map(\.query) == ["first", "second"])
    }

    @Test("The action round-trips through Codable")
    func codableRoundTrip() throws {
        let action = TrafficAction.webSearch(
            TrafficWebSearch(
                provider: "firecrawl",
                query: "round trip",
                startedAt: Date(timeIntervalSince1970: 1),
                finishedAt: Date(timeIntervalSince1970: 2),
                resultCount: 1,
                failure: nil
            )
        )

        let encoded = try JSONEncoder().encode(action)

        #expect(try JSONDecoder().decode(TrafficAction.self, from: encoded) == action)
    }
}
