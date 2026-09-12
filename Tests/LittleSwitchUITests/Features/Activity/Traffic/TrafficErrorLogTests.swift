import Foundation
import Testing

@testable import LittleSwitchCore
@testable import LittleSwitchUI

@Suite("Compact traffic error log")
struct TrafficErrorLogTests {
    @Test("Failures have a private, body-free JSONL index that survives traffic rotation and restart")
    func indexedFailures() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_000)
        let configuration = TrafficLogStore.Configuration(directory: directory, segmentByteLimit: 1, maxSegments: 1)
        let store = TrafficLogStore(configuration: configuration, clock: TrafficLogClock { now })
        await store.start()
        let failedID = UUID()
        let successID = UUID()
        store.record(
            eventID: failedID,
            action: .started(
                .init(
                    startedAt: now,
                    method: "POST",
                    path: "/v1/responses",
                    headers: [.init(name: "private-header", value: "synthetic-secret")]
                )))
        store.record(eventID: failedID, action: .claudeRequestBody(Data("synthetic-private-body".utf8)))
        store.record(
            eventID: failedID,
            action: .routed(
                .init(
                    client: .codex,
                    modelIdentifier: "enablers/xlarge",
                    target: .init(providerID: UUID(), providerName: "Enablers", modelID: "xlarge"),
                    streaming: true
                )))
        store.record(
            eventID: failedID,
            action: .failed(
                .init(
                    status: 200,
                    finishedAt: now,
                    failure: .init(
                        kind: "stream",
                        message: "Response stream reported failure: undeclaredTool",
                        toolName: "unknown\n</arg_value>",
                        toolNamespace: "tools"
                    )
                )))
        store.record(eventID: successID, action: .completed(.init(status: 200, finishedAt: now)))
        await store.flush()
        #expect(await store.snapshot().persistenceError == nil)
        await store.stop()

        let url = directory.appendingPathComponent("errors.jsonl")
        let contents = try Data(contentsOf: url)
        let lines = contents.split(separator: 0x0A)
        #expect(lines.count == 1)
        let first = try #require(lines.first)
        let row = try #require(JSONSerialization.jsonObject(with: Data(first)) as? [String: Any])
        #expect(row["eventID"] as? String == failedID.uuidString)
        #expect(row["status"] as? Int == 200)
        #expect(row["providerName"] as? String == "Enablers")
        #expect(row["modelID"] as? String == "xlarge")
        #expect(
            row["failure"] as? [String: String] == [
                "kind": "stream", "message": "Response stream reported failure: undeclaredTool",
                "toolName": "unknown\n</arg_value>", "toolNamespace": "tools",
            ])
        let text = try #require(String(data: contents, encoding: .utf8))
        #expect(!text.contains("synthetic-secret"))
        #expect(!text.contains("synthetic-private-body"))
        #expect(!text.contains(successID.uuidString))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        let replay = TrafficLogStore(configuration: configuration, clock: TrafficLogClock { now })
        await replay.start()
        await replay.stop()
        #expect(try Data(contentsOf: url) == contents)
    }

    @Test("The compact log bounds bytes, expires old failures and ignores duplicate or corrupt records")
    func retention() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("errors.jsonl")
        let now = Date(timeIntervalSince1970: 1_000)
        let first = errorRecord(at: now)
        var log = TrafficErrorLog(directory: directory, maxAge: 10)
        try log.append(first)
        try log.append(first)
        try log.persist(now: now) { _, _ in }
        let original = try Data(contentsOf: url)
        #expect(try rows(at: url).map(\.eventID) == [first?.eventID])
        try (original + original + Data("{broken}\n".utf8)).write(to: url)

        var bounded = TrafficErrorLog(directory: directory, maxAge: 10, byteLimit: original.count)
        try bounded.persist(now: now) { _, _ in }
        #expect(try Data(contentsOf: url) == original)
        let second = errorRecord(at: now.addingTimeInterval(1))
        try bounded.append(second)
        try bounded.persist(now: now) { _, _ in }
        #expect(try rows(at: url).map(\.eventID) == [second?.eventID])
        #expect(try Data(contentsOf: url).count <= original.count)
        try bounded.persist(now: now.addingTimeInterval(12)) { _, _ in }
        #expect(try rows(at: url).isEmpty)
    }

    @Test("Pending failures merge with persisted failures without duplicate references")
    func pendingReplay() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_000)
        let first = errorRecord(at: now)
        let second = errorRecord(at: now)
        var initial = TrafficErrorLog(directory: directory, maxAge: 10)
        try initial.append(first)
        try initial.persist(now: now) { _, _ in }
        var replay = TrafficErrorLog(directory: directory, maxAge: 10)
        try replay.append(first)
        try replay.append(second)
        try replay.persist(now: now) { _, _ in }
        #expect(
            try rows(at: directory.appendingPathComponent("errors.jsonl")).map(\.eventID)
                == [first?.eventID, second?.eventID])
    }

    @Test("An error-index IO failure stays visible and pending errors are retried on the next record")
    func persistenceRecovery() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("errors.jsonl")
        let store = TrafficLogStore(configuration: .init(directory: directory))
        await store.start()
        // A directory at the file path forces an actual write failure.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let eventID = UUID()
        store.record(
            eventID: eventID,
            action: .failed(
                .init(
                    status: 502, finishedAt: Date(), failure: .init(kind: "provider", message: "failed")
                )))
        await store.flush()
        #expect(await store.snapshot().persistenceError != nil)
        #expect(await store.snapshot().events.first?.lifecycle == .failed)
        try FileManager.default.removeItem(at: url)
        store.record(eventID: UUID(), action: .completed(.init(status: 200, finishedAt: Date())))
        await store.flush()
        #expect(await store.snapshot().persistenceError == nil)
        #expect(try rows(at: url).map(\.eventID) == [eventID])
        await store.stop()
    }

    @Test("Pending failures remain bounded while the existing index cannot be read")
    func unreadableIndexRetention() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("errors.jsonl")
        let now = Date(timeIntervalSince1970: 1_000)
        var initial = TrafficErrorLog(directory: directory, maxAge: 10)
        try initial.append(errorRecord(at: now))
        try initial.persist(now: now) { _, _ in }
        let byteLimit = try Data(contentsOf: url).count
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)

        var blocked = TrafficErrorLog(directory: directory, maxAge: 10, byteLimit: byteLimit)
        for _ in 0..<4 {
            try blocked.append(errorRecord(at: now))
            #expect(throws: (any Error).self) { try blocked.persist(now: now) { _, _ in } }
        }
        // Check memory while IO is still blocked, before any successful write.
        #expect(blocked.retainedByteCount <= byteLimit)
    }

    private func errorRecord(at date: Date) -> TrafficErrorRecord? {
        TrafficErrorRecord(
            record: .init(
                eventID: UUID(),
                sequence: 0,
                timestamp: date,
                action: .failed(.init(status: 200, finishedAt: date, failure: .init(kind: "stream", message: "failed")))
            ), event: nil)
    }

    private func rows(at url: URL) throws -> [TrafficErrorRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try Data(contentsOf: url).split(separator: 0x0A).map {
            try decoder.decode(TrafficErrorRecord.self, from: Data($0))
        }
    }
}
