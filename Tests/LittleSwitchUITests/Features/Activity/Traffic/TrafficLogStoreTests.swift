import Foundation
import Testing

@testable import LittleSwitchCore
@testable import LittleSwitchUI

@Suite("Traffic log store")
struct TrafficLogStoreTests {
    @Test("System clock, no-op logger, and default IO hooks are usable")
    func defaultSupportValues() throws {
        let lowerBound = Date()
        let now = TrafficLogClock.system.now()
        let upperBound = Date()
        #expect((lowerBound...upperBound).contains(now))

        let hooks = TrafficLogIOHooks()
        let unusedURL = URL(fileURLWithPath: "/unused")
        try hooks.beforeCreateSegment(unusedURL)
        try hooks.beforeWrite(unusedURL, Data("ignored".utf8))
        try hooks.beforeRemoveSegment(unusedURL)
        let eventID = UUID()
        let startedAt = Date(timeIntervalSince1970: 10)
        let event = TrafficEvent(
            firstRecord: TrafficRecord(
                eventID: eventID,
                sequence: 0,
                timestamp: startedAt,
                action: start(at: startedAt)
            )
        )
        let logger = NoopTrafficOperationalLogger()
        logger.requestFinished(TrafficOperationalSummary(event: event))
        for state in [
            TrafficStoreOperationalState.persistenceFailed("unavailable"),
            .persistenceRecovered,
            .corruptRecordIgnored("traffic.jsonl"),
        ] {
            logger.storeStateChanged(state)
        }
    }

    @Test("The live store uses the documented local path and can stop before startup")
    func defaultPathAndEarlyStop() async {
        #expect(
            TrafficLogStore.Configuration.standard.directory.path.hasSuffix(
                "/Library/Application Support/LittleSwitch/Logs"
            )
        )
        let store = TrafficLogStore()
        await store.stop()
        await store.flush()
    }

    @Test("Live events persist as user-only JSONL and replay exact bytes")
    func livePersistenceAndReplay() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTrafficClock(Date(timeIntervalSince1970: 1_000))
        let store = makeStore(directory: directory, clock: clock)
        await store.start()

        let eventID = UUID()
        store.record(eventID: eventID, action: start(at: clock.now()))
        await store.flush()

        var snapshot = await store.snapshot()
        #expect(snapshot.events.count == 1)
        #expect(snapshot.events[0].id == eventID)
        #expect(snapshot.events[0].lifecycle == .inProgress)

        let rawBody = Data([0x00, 0xFF, 0x7B, 0x7D])
        store.record(eventID: eventID, action: .claudeRequestBody(rawBody))
        store.record(
            eventID: eventID,
            action: .completed(
                TrafficCompletion(status: 204, finishedAt: clock.now().addingTimeInterval(1))
            )
        )
        await store.flush()
        snapshot = await store.snapshot()

        #expect(snapshot.events.count == 1)
        #expect(snapshot.events[0].claudeRequest.body == rawBody)
        #expect(snapshot.events[0].lifecycle == .completed)
        #expect(snapshot.events[0].finalStatus == 204)
        #expect(snapshot.persistenceError == nil)

        let segments = try segmentURLs(in: directory)
        #expect(segments.count == 1)
        let attributes = try FileManager.default.attributesOfItem(atPath: segments[0].path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        await store.stop()
        try append(Data("{broken final record".utf8), to: segments[0])

        let logger = CapturingTrafficOperationalLogger()
        let replay = makeStore(directory: directory, clock: clock, logger: logger)
        await replay.start()
        let replayed = await replay.snapshot()
        #expect(replayed.events.count == 1)
        #expect(replayed.events[0].id == eventID)
        #expect(replayed.events[0].claudeRequest.body == rawBody)
        #expect(replayed.events[0].finalStatus == 204)
        #expect(
            logger.states.contains {
                if case .corruptRecordIgnored = $0 { true } else { false }
            }
        )
        await replay.stop()
    }

    @Test("Rotation prunes old prefixes and marks a retained suffix partial")
    func rotationAndPartialRetention() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTrafficClock(Date(timeIntervalSince1970: 2_000))
        let store = makeStore(
            directory: directory,
            clock: clock,
            segmentByteLimit: 1,
            maxSegments: 2
        )
        await store.start()

        let eventID = UUID()
        store.record(eventID: eventID, action: start(at: clock.now()))
        store.record(eventID: eventID, action: .claudeRequestBody(Data("retained".utf8)))
        store.record(
            eventID: eventID,
            action: .completed(TrafficCompletion(status: 200, finishedAt: clock.now()))
        )
        await store.flush()

        let snapshot = await store.snapshot()
        #expect(try segmentURLs(in: directory).count == 2)
        #expect(snapshot.events.count == 1)
        #expect(snapshot.events[0].retentionTruncated)
        #expect(snapshot.events[0].claudeRequest.body == Data("retained".utf8))
        #expect(snapshot.events[0].lifecycle == .completed)
        await store.stop()
    }

    @Test("Segments older than the retention age expire on replay")
    func ageExpiry() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTrafficClock(Date(timeIntervalSince1970: 3_000))
        let first = makeStore(directory: directory, clock: clock, maxAge: 10)
        await first.start()
        first.record(eventID: UUID(), action: start(at: clock.now()))
        await first.flush()
        await first.stop()
        #expect(try segmentURLs(in: directory).count == 1)

        clock.advance(by: 11)
        let replay = makeStore(directory: directory, clock: clock, maxAge: 10)
        await replay.start()
        #expect(try segmentURLs(in: directory).isEmpty)
        #expect(await replay.snapshot().events.isEmpty)
        await replay.stop()
    }

    @Test(
        "Persistence failures preserve live traffic and recover on a later record",
        arguments: [TrafficFailurePoint.create, .write]
    )
    func persistenceFailureRecovery(failurePoint: TrafficFailurePoint) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestTrafficClock(Date(timeIntervalSince1970: 4_000))
        let failures = TrafficFaultController(failurePoint)
        let logger = CapturingTrafficOperationalLogger()
        let store = makeStore(
            directory: directory,
            clock: clock,
            logger: logger,
            ioHooks: failures.hooks
        )
        await store.start()

        let eventID = UUID()
        store.record(eventID: eventID, action: start(at: clock.now()))
        store.record(
            eventID: eventID,
            action: .claudeRequestBody(Data("top-secret-request-body".utf8))
        )
        await store.flush()

        var snapshot = await store.snapshot()
        #expect(snapshot.events.count == 1)
        #expect(snapshot.events[0].claudeRequest.body == Data("top-secret-request-body".utf8))
        #expect(snapshot.persistenceError != nil)

        failures.recover()
        store.record(
            eventID: eventID,
            action: .completed(TrafficCompletion(status: 200, finishedAt: clock.now()))
        )
        await store.flush()
        snapshot = await store.snapshot()

        #expect(snapshot.persistenceError == nil)
        #expect(snapshot.events[0].lifecycle == .completed)
        #expect(logger.states.contains(.persistenceRecovered))
        let summary = try #require(logger.summaries.last)
        #expect(summary.eventID == eventID)
        #expect(summary.status == 200)
        #expect(!String(describing: summary).contains("top-secret-request-body"))
        await store.stop()
    }

    private func makeStore(
        directory: URL,
        clock: TestTrafficClock,
        segmentByteLimit: Int = 1_024 * 1_024,
        maxSegments: Int = 10,
        maxAge: TimeInterval = 7 * 24 * 60 * 60,
        logger: any TrafficOperationalLogging = NoopTrafficOperationalLogger(),
        ioHooks: TrafficLogIOHooks = .none
    ) -> TrafficLogStore {
        TrafficLogStore(
            configuration: TrafficLogStore.Configuration(
                directory: directory,
                segmentByteLimit: segmentByteLimit,
                maxSegments: maxSegments,
                maxAge: maxAge,
                memoryByteLimit: 4 * 1_024 * 1_024
            ),
            clock: TrafficLogClock(now: clock.now),
            operationalLogger: logger,
            ioHooks: ioHooks
        )
    }

    private func start(
        at date: Date,
        path: String = "/v1/messages"
    ) -> TrafficAction {
        .started(
            TrafficRequestStart(
                startedAt: date,
                method: "POST",
                path: path,
                headers: [TrafficHeader(name: "authorization", value: "<redacted>")]
            )
        )
    }

    private func segmentURLs(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix("traffic-") && $0.pathExtension == "jsonl" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    }
}

private final class TestTrafficClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { value = value.addingTimeInterval(interval) }
    }
}

enum TrafficFailurePoint: Sendable {
    case create
    case write
}

private enum InjectedTrafficIOError: Error {
    case unavailable
}

private final class TrafficFaultController: @unchecked Sendable {
    private let lock = NSLock()
    private var active: TrafficFailurePoint?

    init(_ active: TrafficFailurePoint) {
        self.active = active
    }

    var hooks: TrafficLogIOHooks {
        TrafficLogIOHooks(
            beforeCreateSegment: { [self] _ in
                try failIfActive(.create)
            },
            beforeWrite: { [self] _, _ in
                try failIfActive(.write)
            }
        )
    }

    func recover() {
        lock.withLock { active = nil }
    }

    private func failIfActive(_ point: TrafficFailurePoint) throws {
        let shouldFail = lock.withLock { active == point }
        if shouldFail {
            throw InjectedTrafficIOError.unavailable
        }
    }
}

private final class CapturingTrafficOperationalLogger: TrafficOperationalLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedSummaries: [TrafficOperationalSummary] = []
    private var capturedStates: [TrafficStoreOperationalState] = []

    var summaries: [TrafficOperationalSummary] {
        lock.withLock { capturedSummaries }
    }

    var states: [TrafficStoreOperationalState] {
        lock.withLock { capturedStates }
    }

    func requestFinished(_ summary: TrafficOperationalSummary) {
        lock.withLock { capturedSummaries.append(summary) }
    }

    func storeStateChanged(_ state: TrafficStoreOperationalState) {
        lock.withLock { capturedStates.append(state) }
    }
}
