import Foundation
import Testing

@testable import LittleSwitchCore
@testable import LittleSwitchUI

@Suite("Traffic log store metadata recovery")
struct TrafficLogStoreTestsMetadataRecovery {
    @Test("A metadata failure after writing never duplicates the committed record")
    func postWriteMetadataFailureDoesNotDuplicate() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let metadata = MetadataUpdateController()
        let logger = MetadataFailureLogger()
        let store = makeStore(
            directory: directory,
            logger: logger,
            hooks: TrafficLogIOHooks(beforeUpdateModificationDate: metadata.beforeUpdate)
        )
        await store.start()

        let eventID = UUID()
        store.record(eventID: eventID, action: started(path: "/metadata"))
        await store.flush()

        #expect(await store.snapshot().persistenceError != nil)
        #expect(try retainedRecords(in: directory).map(\.sequence) == [0])

        metadata.recover()
        store.record(eventID: eventID, action: .claudeRequestBody(Data("one".utf8)))
        store.record(
            eventID: eventID,
            action: .completed(
                TrafficCompletion(status: 201, finishedAt: Date(timeIntervalSince1970: 11))
            )
        )
        await store.flush()

        #expect(await store.snapshot().persistenceError == nil)
        #expect(try retainedRecords(in: directory).map(\.sequence) == [0, 1, 2])
        await store.stop()

        let replay = makeStore(directory: directory, logger: logger, hooks: .none)
        await replay.start()
        let event = try #require(await replay.snapshot().events.first)
        #expect(event.id == eventID)
        #expect(event.lastSequence == 2)
        #expect(event.claudeRequest.body == Data("one".utf8))
        #expect(event.finalStatus == 201)
        await replay.stop()
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

    private func retainedRecords(in directory: URL) throws -> [TrafficRecord] {
        let decoder = JSONDecoder()
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix("traffic-") && $0.pathExtension == "jsonl" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .flatMap { url in
            try Data(contentsOf: url).split(separator: 0x0A).map { line in
                try decoder.decode(TrafficRecord.self, from: Data(line))
            }
        }
    }
}

private enum MetadataUpdateFailure: Error {
    case injected
}

private final class MetadataUpdateController: @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFail = true

    var beforeUpdate: @Sendable (URL) throws -> Void {
        { [self] _ in
            if lock.withLock({ shouldFail }) {
                throw MetadataUpdateFailure.injected
            }
        }
    }

    func recover() {
        lock.withLock { shouldFail = false }
    }
}

private final class MetadataFailureLogger: TrafficOperationalLogging, @unchecked Sendable {
    func requestFinished(_: TrafficOperationalSummary) {}
    func storeStateChanged(_: TrafficStoreOperationalState) {}
}
