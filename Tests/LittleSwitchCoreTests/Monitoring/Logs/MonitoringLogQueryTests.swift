import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring log queries")
struct MonitoringLogQueryTests {
    @Test("RFC3339 accepts lowercase date-time delimiters")
    func lowercaseTimestamp() throws {
        let upper = try MonitoringLogQuery(parameters: [.init(name: "since", value: "2026-09-08T10:20:30.125Z")])
        let lower = try MonitoringLogQuery(parameters: [.init(name: "since", value: "2026-09-08t10:20:30.125z")])
        #expect(lower.filters == upper.filters)
    }

    @Test("Strict parameters reject ambiguity and accept RFC3339 timestamps")
    func strictParameters() throws {
        let requestID = UUID()
        let query = try MonitoringLogQuery(parameters: [
            .init(name: "since", value: "2026-09-08T10:20:30.125Z"),
            .init(name: "level", value: "warn"),
            .init(name: "request_id", value: requestID.uuidString),
            .init(name: "limit", value: "500"),
        ])
        #expect(query.limit == 500)
        #expect(query.filters.minimumLevel == .warn)
        #expect(query.filters.requestID == requestID)
        #expect(query.filters.since != nil)
        for item in [
            URLQueryItem(name: "limit", value: "0"), .init(name: "limit", value: "501"),
            .init(name: "level", value: "debug"), .init(name: "since", value: "yesterday"),
            .init(name: "request_id", value: "private"), .init(name: "unknown", value: "true"),
            .init(name: "cursor", value: "invalid"), .init(name: "limit", value: nil),
            .init(name: "cursor", value: "-"), .init(name: "cursor", value: "_"),
        ] {
            #expect(throws: MonitoringLogQueryError.invalidQuery) {
                try MonitoringLogQuery(parameters: [item])
            }
        }
        #expect(throws: MonitoringLogQueryError.invalidQuery) {
            try MonitoringLogQuery(parameters: [
                .init(name: "level", value: "info"), .init(name: "level", value: "error"),
            ])
        }
    }

    @Test("Default reading is last 100, with a stable cursor for new-only polling")
    func defaultPageAndPolling() async throws {
        let store = MonitoringStore()
        for _ in 0..<120 { _ = await store.markTest() }
        let page = try await store.logs(query: MonitoringLogQuery())
        let payload = try #require(JSONSerialization.jsonObject(with: page.encoded()) as? [String: Any])
        #expect(payload["schemaVersion"] as? Int == 1)
        #expect(page.entries.count == 100)
        #expect(!page.retentionLost)
        let cursor = try #require(page.nextCursor)
        let continuation = try MonitoringLogQuery(parameters: [.init(name: "cursor", value: cursor)])
        #expect(try await store.logs(query: continuation).entries.isEmpty)
        let added = await store.markTest()
        #expect(try await store.logs(query: continuation).entries == [added])
        #expect(throws: MonitoringLogQueryError.invalidQuery) {
            try MonitoringLogQuery(parameters: [
                .init(name: "cursor", value: cursor), .init(name: "level", value: "info"),
            ])
        }
        let otherProcess = MonitoringStore()
        await #expect(throws: MonitoringLogQueryError.cursorExpired) {
            try await otherProcess.logs(query: continuation)
        }
    }

    @Test("Fixed cursor filters skip unrelated requests without repeating unmatched pages")
    func filteredPolling() async throws {
        let store = MonitoringStore()
        let requestID = UUID()
        for (identifier, (outcome, seconds)) in [
            (requestID, (MonitoringOutcome.success, 1.0)), (UUID(), (.clientError, 2)),
            (requestID, (.serverError, 3)), (requestID, (.cancelled, 4)),
        ] {
            await store.finish(
                MonitoringObservation(
                    requestID: identifier,
                    finishedAt: Date(timeIntervalSince1970: seconds),
                    durationSeconds: seconds,
                    client: .claude,
                    route: .messages,
                    outcome: outcome))
        }
        let query = try MonitoringLogQuery(parameters: [
            .init(name: "since", value: "1970-01-01T00:00:01Z"), .init(name: "level", value: "warn"),
            .init(name: "request_id", value: requestID.uuidString), .init(name: "limit", value: "1"),
        ])
        let first = try await store.logs(query: query)
        #expect(first.entries.map(\.level) == [.error])
        let cursor = try #require(first.nextCursor)
        let second = try await store.logs(query: MonitoringLogQuery(parameters: [.init(name: "cursor", value: cursor)]))
        #expect(second.entries.map(\.level) == [.warn])
        let endCursor = try #require(second.nextCursor)
        let end = try MonitoringLogQuery(parameters: [.init(name: "cursor", value: endCursor)])
        #expect(try await store.logs(query: end).entries.isEmpty)
        #expect(try await store.logs(query: end).nextCursor == endCursor)
    }

    @Test("Valid opaque encodings still reject unknown versions and impossible future positions")
    func cursorValidation() async throws {
        let store = MonitoringStore()
        let filters = MonitoringLogFilters(since: nil, minimumLevel: nil, requestID: nil)
        let unknownVersion = try MonitoringLogCursor(
            version: 2, instanceID: store.resource.instanceID, position: 0, filters: filters
        ).encoded()
        #expect(throws: MonitoringLogQueryError.invalidQuery) {
            try MonitoringLogQuery(parameters: [.init(name: "cursor", value: unknownVersion)])
        }
        let future = try MonitoringLogCursor(
            version: 1, instanceID: store.resource.instanceID, position: 1, filters: filters
        ).encoded()
        let query = try MonitoringLogQuery(parameters: [.init(name: "cursor", value: future)])
        await #expect(throws: MonitoringLogQueryError.invalidQuery) { try await store.logs(query: query) }
        let unmatched = try MonitoringLogQuery(parameters: [.init(name: "request_id", value: UUID().uuidString)])
        let page = try await store.logs(query: unmatched)
        #expect(page.entries.isEmpty)
        #expect(page.nextCursor != nil)
    }
}
