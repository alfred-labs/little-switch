import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Traffic store lifecycle without a presentation subscriber")
struct TrafficLogStoreLifecycleTests {
    @Test("An idle store can be released without a wakeup command")
    func idleStoreRelease() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var store: TrafficLogStore? = TrafficLogStore(configuration: .init(directory: directory))
        await store?.start()
        weak let retainedStore = store
        store = nil
        #expect(retainedStore == nil)
    }

    @Test("Stop drains accepted records and later flush remains harmless")
    func stopDrainsRecords() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrafficLogStore(configuration: .init(directory: directory))
        await store.start()
        let id = UUID()
        store.record(
            eventID: id,
            action: .started(
                TrafficRequestStart(
                    startedAt: .now, method: "POST", path: "/lifecycle-test", headers: []
                )))
        await store.stop()
        await store.stop()
        await store.flush()
        #expect(await store.snapshot().events.map(\.id) == [id])
        let reopened = TrafficLogStore(configuration: .init(directory: directory))
        await reopened.start()
        #expect(await reopened.snapshot().events.map(\.id) == [id])
        await reopened.stop()
    }

    @Test("Stopping an idle inbox finishes once and refuses a subsequent start")
    func idleInboxStop() async {
        let inbox = TrafficLogInbox()
        let first = await inbox.requestStop()
        let second = await inbox.requestStop()
        await first.completion.wait()
        await second.completion.wait()
        #expect(await inbox.start() == false)
        await inbox.flush()
    }

    @Test("Concurrent stops join one drain and close admission before completion")
    func concurrentInboxStop() async {
        let inbox = TrafficLogInbox()
        #expect(await inbox.start())
        #expect(await inbox.start() == false)
        let id = UUID()
        let start = TrafficRequestStart(startedAt: .now, method: "POST", path: "/admitted", headers: [])
        inbox.record(eventID: id, timestamp: .now, action: .started(start))

        async let first = inbox.requestStop()
        async let second = inbox.requestStop()
        let requests = await (first, second)
        #expect(requests.0.completion === requests.1.completion)
        await inbox.flush()
        inbox.record(eventID: UUID(), timestamp: .now, action: .started(start))

        var admittedIDs: [UUID] = []
        var stopCount = 0
        for await command in inbox.stream {
            switch command {
            case .record(let eventID, _, _):
                admittedIDs.append(eventID)
            case .stop(let completion):
                stopCount += 1
                #expect(completion === requests.0.completion)
                await completion.finish()
            case .flush:
                Issue.record("Admission stayed open after stop")
            }
        }
        await requests.0.completion.wait()
        await requests.1.completion.wait()
        #expect(admittedIDs == [id])
        #expect(stopCount == 1)
    }
}
