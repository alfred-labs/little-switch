import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring request ownership")
struct MonitoringRequestContextTests {
    @Test("Metadata truncated before retention remains marked in the terminal event")
    func boundedModelFlag() async throws {
        let store = MonitoringStore()
        let monitoring = GatewayMonitoring(store: store)
        let context = await monitoring.begin(requestID: UUID(), route: .messages)
        await context.target(providerID: UUID(), model: String(repeating: "猫", count: 100))
        await context.finish(statusCode: 200)
        let entry = try #require(try await store.logs().entries.first)
        #expect(entry.truncated)
        #expect(entry.attributes.resolvedModel?.utf8.count == 255)
    }

    @Test("One request terminal sums independent exchanges but merges repeated cumulative samples")
    func exchangeIdentityAndTerminalIdempotency() async throws {
        let store = MonitoringStore()
        let monitoring = GatewayMonitoring(store: store)
        let context = await monitoring.begin(requestID: UUID(), route: .messages)
        let first = UUID()
        let second = UUID()
        await context.usage(exchangeID: first, totals: .init(inputTokens: 5, outputTokens: 1))
        await context.usage(exchangeID: first, totals: .init(inputTokens: 5, outputTokens: 3))
        await context.usage(exchangeID: second, totals: .init(inputTokens: 7, outputTokens: 2))
        await context.estimatedInput(10)
        await context.estimatedInput(12)
        await context.finish(statusCode: 200)
        await context.finish(statusCode: 503)
        let snapshot = await store.snapshot()
        #expect(snapshot.family(.requests)?.points.map(\.value) == [.counter(1)])
        #expect(snapshot.family(.inFlight)?.points.map(\.value) == [.gauge(0)])
        let logs = try await store.logs()
        #expect(logs.entries.count == 1)
        #expect(logs.entries[0].attributes.usage == .init(inputTokens: 12, outputTokens: 5))
        #expect(logs.entries[0].attributes.estimatedInputTokens == 22)
    }

    @Test("Explicit failure wins over a committed HTTP 200 and abandonment is a cancellation")
    func terminalOutcomes() async throws {
        let store = MonitoringStore()
        let monitoring = GatewayMonitoring(store: store)
        let failed = await monitoring.begin(requestID: UUID(), route: .responses)
        await failed.finish(statusCode: 200, error: .transport)
        let abandoned = await monitoring.begin(requestID: UUID(), route: .models)
        await abandoned.finish(error: .cancelled)
        let entries = try await store.logs().entries
        #expect(entries.map(\.attributes.outcome) == [.transportError, .cancelled])
        #expect(entries.map(\.attributes.client) == [.codex, .unknown])
        #expect(entries.map(\.level) == [.error, .warn])
    }
}
