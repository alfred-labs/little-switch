import Foundation
import Testing

@testable import LittleSwitchCore
@testable import LittleSwitchUI

@Suite("Traffic log store failure coverage")
struct TrafficLogStoreTestsFailureCoverage {
    @Test("Configuration clamps every persistence limit")
    func configurationNormalization() {
        let configuration = TrafficLogStore.Configuration(
            directory: URL(fileURLWithPath: "/test"),
            segmentByteLimit: 0,
            maxSegments: -1,
            maxAge: -1,
            memoryByteLimit: 0
        )

        #expect(configuration.segmentByteLimit == 1)
        #expect(configuration.maxSegments == 1)
        #expect(configuration.maxAge == 0)
        #expect(configuration.memoryByteLimit == 1)
    }

    @Test("Memory accounting clamps removals at zero")
    func memoryUnderflowProtection() {
        #expect(TrafficLogStore.remainingMemoryBytes(5, removing: 10) == 0)
        #expect(TrafficLogStore.remainingMemoryBytes(10, removing: nil) == 10)
    }

    @Test("Standard configuration accepts deterministic directory fallbacks")
    func standardConfigurationFallback() {
        let applicationSupport = URL(fileURLWithPath: "/test/Application Support")
        let home = URL(fileURLWithPath: "/test/home")

        let preferred = TrafficLogStore.Configuration.standard(
            applicationSupportDirectory: applicationSupport,
            homeDirectory: home
        )
        let fallback = TrafficLogStore.Configuration.standard(
            applicationSupportDirectory: nil,
            homeDirectory: home
        )

        #expect(preferred.directory.path == "/test/Application Support/LittleSwitch/Logs")
        #expect(fallback.directory.path == "/test/home/LittleSwitch/Logs")
    }

    @Test("Startup directory failures publish once and start remains idempotent")
    func startupFailureAndStartIdempotency() async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let blocked = parent.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: blocked)
        let logger = FailureStateLogger()
        let store = makeStore(
            directory: blocked,
            logger: logger,
            hooks: .none
        )

        await store.start()
        await store.start()
        #expect(await store.snapshot().persistenceError != nil)
        #expect(logger.failureCount == 1)

        await store.stop()
        await store.start()
        #expect(logger.failureCount == 1)
    }

    @Test("A segment creation returning false is reported without losing live state")
    func segmentCreationFailure() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = FailureStateLogger()
        let beforeCreateSegment: @Sendable (URL) throws -> Void = { url in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
        let hooks = TrafficLogIOHooks(beforeCreateSegment: beforeCreateSegment)
        let store = makeStore(directory: directory, logger: logger, hooks: hooks)
        await store.start()

        let eventID = UUID()
        store.record(eventID: eventID, action: started(path: "/creation-failure"))
        await store.flush()

        #expect(await store.snapshot().events.map(\.id) == [eventID])
        #expect(await store.snapshot().persistenceError != nil)
        #expect(logger.failureCount == 1)
        await store.stop()
    }

    @Test("Retention can remove a just-created segment before its pending write")
    func missingSegmentAfterImmediateExpiry() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let detour = root.appendingPathComponent("detour", isDirectory: true)
        try FileManager.default.createDirectory(
            at: detour,
            withIntermediateDirectories: false
        )

        let directory =
            detour
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        let clock = AdvancingCallClock(
            initial: Date(timeIntervalSince1970: 10),
            advanceAfterCall: 4,
            advancedBy: 1
        )
        let logger = FailureStateLogger()
        let writes = CallCounter()
        let paths = SegmentPathRecorder()
        let beforeWrite: @Sendable (URL, Data) throws -> Void = { _, _ in writes.record() }
        let store = TrafficLogStore(
            configuration: TrafficLogStore.Configuration(directory: directory, maxAge: 0),
            clock: TrafficLogClock(now: clock.now),
            operationalLogger: logger,
            ioHooks: TrafficLogIOHooks(
                beforeCreateSegment: paths.recordCreated,
                beforeWrite: beforeWrite,
                beforeRemoveSegment: paths.recordRemoved
            )
        )
        await store.start()

        let eventID = UUID()
        store.record(eventID: eventID, action: started(path: "/expired"))
        await store.flush()

        #expect(await store.snapshot().events.map(\.id) == [eventID])
        #expect(await store.snapshot().persistenceError != nil)
        #expect(logger.failureCount == 1)
        #expect(try trafficSegments(in: directory).isEmpty)
        #expect(writes.isEmpty)
        let created = try #require(paths.created.first)
        let removed = try #require(paths.removed.first)
        #expect(created.path != removed.path)
        #expect(
            standardizedParentIdentity(created)
                == standardizedParentIdentity(removed)
        )
        await store.stop()
    }

    @Test("Memory retention evicts whole older events")
    func memoryRetentionEviction() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrafficLogStore(
            configuration: TrafficLogStore.Configuration(
                directory: directory,
                memoryByteLimit: 1
            ),
            clock: TrafficLogClock { Date(timeIntervalSince1970: 10) }
        )
        await store.start()

        store.record(eventID: UUID(), action: started(path: "/evicted"))
        let retained = UUID()
        store.record(eventID: retained, action: started(path: "/retained"))
        await store.flush()

        #expect(await store.snapshot().events.map(\.id) == [retained])
        await store.stop()
    }

    @Test("Malformed segment names and corrupt records replay in stable order")
    func malformedSegmentOrdering() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let brokenID = UUID()
        let malformedID = UUID()
        let validID = UUID()
        try write(
            records: [record(id: brokenID, sequence: 0, path: "/broken-name")],
            to: directory.appendingPathComponent("traffic-broken.jsonl")
        )
        try write(
            records: [record(id: malformedID, sequence: 0, path: "/malformed-date")],
            to: directory.appendingPathComponent("traffic-not-a-number-id.jsonl")
        )
        try write(
            records: [record(id: validID, sequence: .max, path: "/valid")],
            to: directory.appendingPathComponent("traffic-0000000001000-a.jsonl")
        )
        try Data("not-json\n".utf8).append(
            to: directory.appendingPathComponent("traffic-0000000001000-b.jsonl")
        )
        try Data("ignored".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        try Data("ignored".utf8).write(to: directory.appendingPathComponent("traffic-ignore.txt"))
        let logger = FailureStateLogger()
        let store = TrafficLogStore(
            configuration: TrafficLogStore.Configuration(
                directory: directory,
                maxAge: .greatestFiniteMagnitude
            ),
            clock: TrafficLogClock { Date(timeIntervalSince1970: 10) },
            operationalLogger: logger
        )
        await store.start()

        #expect(await store.snapshot().events.map(\.id) == [brokenID, malformedID, validID])
        #expect(logger.corruptRecordCount == 1)

        store.record(eventID: validID, action: .claudeRequestBody(Data("max".utf8)))
        await store.flush()
        let valid = try #require(await store.snapshot().events.last)
        #expect(valid.lastSequence == .max)
        await store.stop()
    }

    private func makeStore(
        directory: URL,
        logger: any TrafficOperationalLogging,
        hooks: TrafficLogIOHooks
    ) -> TrafficLogStore {
        TrafficLogStore(
            configuration: TrafficLogStore.Configuration(directory: directory),
            clock: TrafficLogClock { Date(timeIntervalSince1970: 10) },
            operationalLogger: logger,
            ioHooks: hooks
        )
    }

    private func started(path: String) -> TrafficAction {
        .started(
            TrafficRequestStart(
                startedAt: Date(timeIntervalSince1970: 10),
                method: "POST",
                path: path,
                headers: []
            )
        )
    }

    private func trafficSegments(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("traffic-") && $0.pathExtension == "jsonl" }
    }

    private func record(id: UUID, sequence: UInt64, path: String) -> TrafficRecord {
        TrafficRecord(
            eventID: id,
            sequence: sequence,
            timestamp: Date(timeIntervalSince1970: 10),
            action: started(path: path)
        )
    }

    private func write(records: [TrafficRecord], to url: URL) throws {
        let encoder = JSONEncoder()
        let data = try records.reduce(into: Data()) { result, record in
            result.append(try encoder.encode(record))
            result.append(0x0A)
        }
        try data.write(to: url)
    }

    private func standardizedParentIdentity(_ url: URL) -> String {
        url.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent)
            .standardizedFileURL.path
    }
}

private final class AdvancingCallClock: @unchecked Sendable {
    private let lock = NSLock()
    private let initial: Date
    private let advanceAfterCall: Int
    private let advancedBy: TimeInterval
    private var calls = 0

    init(initial: Date, advanceAfterCall: Int, advancedBy: TimeInterval) {
        self.initial = initial
        self.advanceAfterCall = advanceAfterCall
        self.advancedBy = advancedBy
    }

    func now() -> Date {
        lock.withLock {
            calls += 1
            return calls > advanceAfterCall ? initial.addingTimeInterval(advancedBy) : initial
        }
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var isEmpty: Bool {
        lock.withLock { storage == 0 }
    }

    func record() {
        lock.withLock { storage += 1 }
    }
}

private final class SegmentPathRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var createdStorage: [URL] = []
    private var removedStorage: [URL] = []

    var created: [URL] {
        lock.withLock { createdStorage }
    }

    var removed: [URL] {
        lock.withLock { removedStorage }
    }

    var recordCreated: @Sendable (URL) throws -> Void {
        { [self] url in lock.withLock { createdStorage.append(url) } }
    }

    var recordRemoved: @Sendable (URL) throws -> Void {
        { [self] url in lock.withLock { removedStorage.append(url) } }
    }
}

extension Data {
    fileprivate func append(to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data().write(to: url)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: self)
        try handle.close()
    }
}

private final class FailureStateLogger: TrafficOperationalLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [TrafficStoreOperationalState] = []

    var states: [TrafficStoreOperationalState] {
        lock.withLock { storage }
    }

    var failureCount: Int {
        states.filter { if case .persistenceFailed = $0 { true } else { false } }.count
    }

    var corruptRecordCount: Int {
        states.filter { if case .corruptRecordIgnored = $0 { true } else { false } }.count
    }

    func requestFinished(_: TrafficOperationalSummary) {}

    func storeStateChanged(_ state: TrafficStoreOperationalState) {
        lock.withLock { storage.append(state) }
    }
}
