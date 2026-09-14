import Foundation
import LittleSwitchCommon
import LittleSwitchCore

actor TrafficLogStore: TrafficRecording {
    nonisolated private let inbox = TrafficLogInbox()
    nonisolated private let clock: TrafficLogClock
    private let configuration: Configuration
    private let operationalLogger: any TrafficOperationalLogging
    nonisolated private let usageRecorder: (any GatewayUsageRecording)?
    private let ioHooks: TrafficLogIOHooks
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var errorLog: TrafficErrorLog

    private var consumerTask: Task<Void, Never>?
    private var events: [UUID: TrafficEvent] = [:]
    private var eventOrder: [UUID] = []
    private var eventBytes: [UUID: Int] = [:]
    private var memoryBytes = 0
    private var nextSequences: [UUID: UInt64] = [:]
    private var persistenceError: String?
    private var pendingLines: [Data] = []
    private var currentSegmentURL: URL?
    private var currentSegmentBytes = 0
    private var currentHandle: FileHandle?
    private var lastSegmentMilliseconds: Int64 = 0

    init(
        configuration: Configuration = .standard,
        clock: TrafficLogClock = .system,
        operationalLogger: any TrafficOperationalLogging = OSLogTrafficLogger(),
        ioHooks: TrafficLogIOHooks = .none,
        usageRecorder: (any GatewayUsageRecording)? = nil
    ) {
        self.configuration = configuration
        self.clock = clock
        self.operationalLogger = operationalLogger
        self.ioHooks = ioHooks
        self.usageRecorder = usageRecorder
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        errorLog = TrafficErrorLog(directory: configuration.directory, maxAge: configuration.maxAge)
    }

    deinit {
        inbox.continuation.finish()
    }

    func start() async {
        guard consumerTask == nil, await inbox.start() else { return }
        await prepareAndReplay()
        let stream = inbox.stream
        consumerTask = Task { [weak self, stream] in
            for await command in stream {
                guard let shouldStop = await self?.process(command) else { return }
                if shouldStop {
                    break
                }
            }
        }
    }

    nonisolated func record(eventID: UUID, action: TrafficAction) {
        inbox.record(eventID: eventID, timestamp: clock.now(), action: action)
    }

    nonisolated func flush() async {
        await inbox.flush()
    }

    nonisolated func stop() async {
        let request = await inbox.requestStop()
        await request.completion.wait()
    }

    func snapshot() -> TrafficLogSnapshot {
        TrafficLogSnapshot(
            events: eventOrder.compactMap { events[$0] },
            persistenceError: persistenceError
        )
    }

}

extension TrafficLogStore {
    private func process(_ command: TrafficLogCommand) async -> Bool {
        switch command {
        // swiftlint:disable:next pattern_matching_keywords
        case .record(let eventID, let timestamp, let action):
            await ingest(eventID: eventID, timestamp: timestamp, action: action)
            return false
        case .flush(let completion):
            await completion.finish()
            return false
        case .stop(let completion):
            closeCurrentSegment()
            consumerTask = nil
            await completion.finish()
            return true
        }
    }

    private func prepareAndReplay() async {
        do {
            try prepareDirectory()
            _ = try pruneSegments()
            try rebuildFromSegments()
            try errorLog.persist(now: clock.now(), beforeWrite: ioHooks.beforeWrite)
            recoverPersistenceIfNeeded()
        } catch {
            reportPersistenceFailure(error)
        }
    }

    private func ingest(eventID: UUID, timestamp: Date, action: TrafficAction) async {
        let sequence = nextSequences[eventID] ?? 0
        nextSequences[eventID] = sequence == .max ? .max : sequence + 1
        let record = TrafficRecord(
            eventID: eventID,
            sequence: sequence,
            timestamp: timestamp,
            action: action
        )
        apply(record, retainedBytes: 0)
        let errorRecord = TrafficErrorRecord(record: record, event: events[eventID])
        var writeFailure: (any Error)?

        do {
            var line = try encoder.encode(record)
            line.append(0x0A)
            pendingLines.append(line)
            eventBytes[eventID, default: 0] += line.count
            memoryBytes += line.count
            enforceMemoryLimit()
            let pruned = try persistPendingLines()
            if pruned {
                try rebuildFromSegments()
            }
        } catch {
            writeFailure = error
        }
        do {
            try errorLog.append(errorRecord)
            try errorLog.persist(now: timestamp, beforeWrite: ioHooks.beforeWrite)
        } catch {
            writeFailure = error
        }
        if let writeFailure {
            reportPersistenceFailure(writeFailure)
        } else {
            recoverPersistenceIfNeeded()
        }

        if action.isTerminal, let event = events[eventID] {
            operationalLogger.requestFinished(TrafficOperationalSummary(event: event))
            if let usage = GatewayUsageEvent(trafficEvent: event) {
                usageRecorder?.record(usage)
            }
        }
    }

    private func persistPendingLines() throws -> Bool {
        var pruned = false
        while let line = pendingLines.first {
            pruned = try prepareSegment(for: line.count) || pruned
            guard let url = currentSegmentURL, let handle = currentHandle else {
                throw TrafficLogStoreError.missingSegment
            }
            try ioHooks.beforeWrite(url, line)
            try handle.write(contentsOf: line)
            currentSegmentBytes += line.count
            pendingLines.removeFirst()
            try ioHooks.beforeUpdateModificationDate(url)
            try FileManager.default.setAttributes(
                [.modificationDate: clock.now()],
                ofItemAtPath: url.path
            )
        }
        return pruned
    }

    private func prepareSegment(for lineBytes: Int) throws -> Bool {
        let exceedsLimit =
            currentHandle != nil && currentSegmentBytes > 0
            && currentSegmentBytes + lineBytes > configuration.segmentByteLimit
        if exceedsLimit {
            closeCurrentSegment()
        }
        guard currentHandle == nil else { return false }

        try prepareDirectory()
        let url = configuration.directory.appendingPathComponent(segmentName())
        try ioHooks.beforeCreateSegment(url)
        guard
            FileManager.default.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [
                    .posixPermissions: NSNumber(value: 0o600),
                    .modificationDate: clock.now(),
                ]
            )
        else {
            throw TrafficLogStoreError.segmentCreationFailed
        }
        try FileManager.default.setAttributes(
            [
                .posixPermissions: NSNumber(value: 0o600),
                .modificationDate: clock.now(),
            ],
            ofItemAtPath: url.path
        )
        currentSegmentURL = url
        currentSegmentBytes = 0
        currentHandle = try FileHandle(forWritingTo: url)
        return try pruneSegments()
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: configuration.directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
    }

    private func pruneSegments() throws -> Bool {
        let now = clock.now()
        var retained: [TrafficSegmentInfo] = []
        var removed: [TrafficSegmentInfo] = []
        for segment in try segmentInfos() {
            if now.timeIntervalSince(segment.createdAt) > configuration.maxAge {
                removed.append(segment)
            } else {
                retained.append(segment)
            }
        }
        if retained.count > configuration.maxSegments {
            let overflow = retained.count - configuration.maxSegments
            removed.append(contentsOf: retained.prefix(overflow))
            retained.removeFirst(overflow)
        }
        for segment in removed {
            if segment.url.standardizedFileURL.path == currentSegmentURL?.standardizedFileURL.path {
                closeCurrentSegment()
            }
            try ioHooks.beforeRemoveSegment(segment.url)
            try FileManager.default.removeItem(at: segment.url)
        }
        return !removed.isEmpty
    }

    private func rebuildFromSegments() throws {
        events.removeAll(keepingCapacity: true)
        eventOrder.removeAll(keepingCapacity: true)
        eventBytes.removeAll(keepingCapacity: true)
        nextSequences.removeAll(keepingCapacity: true)
        memoryBytes = 0

        for segment in try segmentInfos() {
            let contents = try Data(contentsOf: segment.url)
            for rawLine in contents.split(separator: 0x0A, omittingEmptySubsequences: true) {
                let line = Data(rawLine)
                guard let record = try? decoder.decode(TrafficRecord.self, from: line) else {
                    operationalLogger.storeStateChanged(
                        .corruptRecordIgnored(segment.url.lastPathComponent)
                    )
                    continue
                }
                let next = record.sequence == .max ? .max : record.sequence + 1
                nextSequences[record.eventID] = max(nextSequences[record.eventID] ?? 0, next)
                apply(record, retainedBytes: line.count + 1)
            }
        }
        enforceMemoryLimit()
    }

    private func apply(_ record: TrafficRecord, retainedBytes: Int) {
        if var event = events[record.eventID] {
            event.apply(record)
            events[record.eventID] = event
        } else {
            events[record.eventID] = TrafficEvent(firstRecord: record)
            eventOrder.append(record.eventID)
        }
        if retainedBytes > 0 {
            eventBytes[record.eventID, default: 0] += retainedBytes
            memoryBytes += retainedBytes
        }
    }

    private func enforceMemoryLimit() {
        while memoryBytes > configuration.memoryByteLimit, eventOrder.count > 1 {
            let removedID = eventOrder.removeFirst()
            events.removeValue(forKey: removedID)
            memoryBytes = Self.remainingMemoryBytes(
                memoryBytes,
                removing: eventBytes.removeValue(forKey: removedID)
            )
        }
    }

    private func segmentInfos() throws -> [TrafficSegmentInfo] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: configuration.directory,
            includingPropertiesForKeys: nil
        )
        return urls.compactMap { url in
            guard url.lastPathComponent.hasPrefix("traffic-"), url.pathExtension == "jsonl" else {
                return nil
            }
            return TrafficSegmentInfo(
                url: url,
                createdAt: segmentDate(from: url) ?? .distantPast
            )
        }
        .sorted {
            if $0.createdAt == $1.createdAt {
                return $0.url.lastPathComponent < $1.url.lastPathComponent
            }
            return $0.createdAt < $1.createdAt
        }
    }

    private func segmentName() -> String {
        let requested = Int64(clock.now().timeIntervalSince1970 * 1_000)
        let milliseconds = max(requested, lastSegmentMilliseconds + 1)
        lastSegmentMilliseconds = milliseconds
        return String(
            format: "traffic-%016lld-%@.jsonl",
            milliseconds,
            UUID().uuidString.lowercased()
        )
    }

    private func segmentDate(from url: URL) -> Date? {
        let name = url.deletingPathExtension().lastPathComponent
        let suffix = name.dropFirst("traffic-".count)
        guard let separator = suffix.firstIndex(of: "-") else { return nil }
        guard let milliseconds = Int64(suffix[..<separator]) else { return nil }
        lastSegmentMilliseconds = max(lastSegmentMilliseconds, milliseconds)
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }

    private func closeCurrentSegment() {
        try? currentHandle?.close()
        currentHandle = nil
        currentSegmentURL = nil
        currentSegmentBytes = 0
    }

    private func reportPersistenceFailure(_ error: Error) {
        let message = error.localizedDescription
        if persistenceError == nil {
            operationalLogger.storeStateChanged(.persistenceFailed(message))
        }
        persistenceError = message
    }

    private func recoverPersistenceIfNeeded() {
        guard persistenceError != nil else { return }
        persistenceError = nil
        operationalLogger.storeStateChanged(.persistenceRecovered)
    }

}

private struct TrafficSegmentInfo {
    var url: URL
    var createdAt: Date
}

private enum TrafficLogStoreError: Error {
    case missingSegment
    case segmentCreationFailed
}
