import Foundation
import Testing

@testable import LittleSwitchCore
@testable import LittleSwitchUI

@Suite("Traffic log usage recording")
struct TrafficLogStoreUsageRecordingTests {
    @Test("A finished request reaches the usage recorder once, in flight requests do not")
    func finishedRequestsAreRecorded() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("little-switch-usage-log-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = UsageRecorderSpy()
        let startedAt = Date(timeIntervalSince1970: 1_788_000_000)
        let store = TrafficLogStore(
            configuration: TrafficLogStore.Configuration(directory: directory),
            clock: TrafficLogClock { startedAt },
            operationalLogger: NoopTrafficOperationalLogger(),
            usageRecorder: recorder
        )
        await store.start()
        let eventID = UUID()

        store.record(
            eventID: eventID,
            action: .started(
                TrafficRequestStart(
                    startedAt: startedAt,
                    method: "POST",
                    path: "/v1/messages",
                    headers: []
                )
            )
        )
        store.record(
            eventID: eventID,
            action: .routed(
                TrafficRoute(
                    client: .claude,
                    modelIdentifier: "claude-opus-5",
                    target: TrafficRouteTarget(
                        providerID: UUID(),
                        providerName: "z.ai",
                        modelID: "glm-4.7"
                    ),
                    streaming: false
                )
            )
        )
        await store.flush()
        #expect(recorder.events.isEmpty)

        store.record(
            eventID: eventID,
            action: .clientResponseChunk(Data(#"{"usage":{"input_tokens":12,"output_tokens":3}}"#.utf8))
        )
        store.record(
            eventID: eventID,
            action: .completed(
                TrafficCompletion(status: 200, finishedAt: startedAt.addingTimeInterval(2))
            )
        )
        await store.flush()
        await store.stop()

        let events = recorder.events
        #expect(events.count == 1)
        #expect(events.first?.outcome == .succeeded)
        #expect(events.first?.routeID == "claude-opus-5")
        #expect(events.first?.providerName == "z.ai")
        #expect(events.first?.usage == GatewayUsageTotals(inputTokens: 12, outputTokens: 3))
        #expect(events.first?.durationMilliseconds == 2_000)
    }

    @Test("An annotation before completion folds into usage exactly once")
    func annotatedCompletionRecordsOnce() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("little-switch-usage-log-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = UsageRecorderSpy()
        let startedAt = Date(timeIntervalSince1970: 1_788_000_000)
        let store = TrafficLogStore(
            configuration: TrafficLogStore.Configuration(directory: directory),
            clock: TrafficLogClock { startedAt },
            operationalLogger: NoopTrafficOperationalLogger(),
            usageRecorder: recorder
        )
        await store.start()
        let eventID = UUID()

        store.record(
            eventID: eventID,
            action: .started(
                TrafficRequestStart(
                    startedAt: startedAt,
                    method: "POST",
                    path: "/v1/responses",
                    headers: []
                )
            )
        )
        store.record(
            eventID: eventID,
            action: .annotation(
                TrafficAnnotation(
                    kind: "agent-mail",
                    message: "Dropped 1 unparseable agent message(s)"
                )
            )
        )
        store.record(
            eventID: eventID,
            action: .completed(
                TrafficCompletion(status: 200, finishedAt: startedAt.addingTimeInterval(1))
            )
        )
        await store.flush()
        await store.stop()

        // The annotation is not a terminal action: only the completion
        // reaches usage, and the request counts as the success it was.
        #expect(recorder.events.count == 1)
        #expect(recorder.events.first?.outcome == .succeeded)
    }
}

private final class UsageRecorderSpy: GatewayUsageRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [GatewayUsageEvent] = []

    var events: [GatewayUsageEvent] {
        lock.withLock { storage }
    }

    func record(_ event: GatewayUsageEvent) {
        lock.withLock { storage.append(event) }
    }
}
