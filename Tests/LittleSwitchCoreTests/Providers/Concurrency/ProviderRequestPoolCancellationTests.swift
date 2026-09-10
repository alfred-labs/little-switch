import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Provider request pool cancellation")
struct ProviderRequestPoolCancellationTests {
    @Test("Cancellation before registration never creates a live event", arguments: 0..<50)
    func cancellationBeforeRegistration(iteration _: Int) async {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let admission = providerRequestAdmission()
        let task = Task { () -> ProviderRequestAdmissionOutcome in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            do {
                try await pool.admit(admission)
                return .admitted
            } catch is CancellationError {
                return .cancelled
            } catch let error as GatewayAdmissionError {
                return .failed(error)
            } catch {
                Issue.record("Unexpected admission error: \(error)")
                return .admitted
            }
        }

        #expect(await task.value == .cancelled)
        #expect(
            await pool.snapshot()
                == ProviderRequestPoolSnapshot(
                    totalRunning: 0,
                    totalWaiting: 0,
                    providers: [
                        ProviderRequestPoolProviderSnapshot(
                            id: ProviderRequestPoolTestIDs.alpha,
                            displayName: "Alpha",
                            maximumParallelRequests: 1,
                            runningCount: 0,
                            waitingCount: 0,
                            retainedWaitingBytes: 0,
                            oldestWaitDuration: nil,
                            isRemoved: false
                        )
                    ]
                ))
    }

    @Test("Head, middle, and tail cancellation release bytes without disturbing FIFO")
    func headMiddleAndTailCancellation() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let active = providerRequestAdmission()
        try await pool.admit(active)
        let admissions = (0..<5).map { _ in providerRequestAdmission(retainedBodyBytes: 10) }
        var tasks: [Task<ProviderRequestAdmissionOutcome, Never>] = []
        for admission in admissions {
            tasks.append(providerRequestAdmissionTask(pool: pool, admission: admission))
            let expectedCount = tasks.count
            _ = try await waitForProviderRequestPoolSnapshot(pool) {
                $0.totalWaiting == expectedCount
            }
        }

        tasks[0].cancel()
        tasks[2].cancel()
        tasks[4].cancel()
        let cancelled = try await waitForProviderRequestPoolSnapshot(pool) {
            $0.totalWaiting == 2
        }
        #expect(cancelled.providers[0].retainedWaitingBytes == 20)
        #expect(await tasks[0].value == .cancelled)
        #expect(await tasks[2].value == .cancelled)
        #expect(await tasks[4].value == .cancelled)

        await pool.finish(eventID: active.eventID)
        #expect(await tasks[1].value == .admitted)
        await pool.finish(eventID: admissions[1].eventID)
        #expect(await tasks[3].value == .admitted)
        await pool.finish(eventID: admissions[3].eventID)
        #expect((await pool.snapshot()).totalRunning == 0)
    }

    @Test("Finishing a waiter is an idempotent cancellation transition")
    func finishWaitingEvent() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let active = providerRequestAdmission()
        let waiting = providerRequestAdmission()
        try await pool.admit(active)
        let waitingTask = providerRequestAdmissionTask(pool: pool, admission: waiting)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 1 }

        await pool.finish(eventID: waiting.eventID)
        await pool.finish(eventID: waiting.eventID)
        #expect(await waitingTask.value == .cancelled)
        #expect((await pool.snapshot()).totalWaiting == 0)
        await pool.finish(eventID: active.eventID)
    }

    @Test("Cancellation racing a grant has one terminal result and leaks no permit", arguments: 0..<100)
    func cancellationGrantRace(iteration _: Int) async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let active = providerRequestAdmission()
        let waiting = providerRequestAdmission()
        try await pool.admit(active)
        let waitingTask = providerRequestAdmissionTask(pool: pool, admission: waiting)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 1 }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { waitingTask.cancel() }
            group.addTask { await pool.finish(eventID: active.eventID) }
        }
        let result = await waitingTask.value
        #expect(result == .cancelled || result == .admitted)
        if result == .admitted {
            await pool.finish(eventID: waiting.eventID)
        }
        _ = try await waitForProviderRequestPoolSnapshot(pool) {
            $0.totalRunning == 0 && $0.totalWaiting == 0
        }
        try await waitForProviderRequestPoolSleeperCount(timing, 0)
    }

    @Test("Timeout racing a grant has one terminal result and leaves its event reusable", arguments: 0..<50)
    func timeoutGrantRace(iteration _: Int) async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let active = providerRequestAdmission()
        let waiting = providerRequestAdmission()
        try await pool.admit(active)
        let waitingTask = providerRequestAdmissionTask(pool: pool, admission: waiting)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 1 }
        try await waitForProviderRequestPoolSleeperCount(timing, 1)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await timing.advance(by: .seconds(300)) }
            group.addTask { await pool.finish(eventID: active.eventID) }
        }
        let result = await waitingTask.value
        #expect(result == .failed(.timedOut) || result == .admitted)
        if result == .admitted {
            await pool.finish(eventID: waiting.eventID)
        }
        let snapshot = try await waitForProviderRequestPoolSnapshot(pool) {
            $0.totalRunning == 0 && $0.totalWaiting == 0
        }
        #expect(snapshot.providers[0].retainedWaitingBytes == 0)
        #expect(snapshot.providers[0].oldestWaitDuration == nil)
        try await waitForProviderRequestPoolSleeperCount(timing, 0)
        try await pool.admit(waiting)
        await pool.finish(eventID: waiting.eventID)
    }

    @Test("Shutdown rejects new work, resumes every waiter once, and preserves active work")
    func shutdown() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let active = providerRequestAdmission()
        try await pool.admit(active)
        let admissions = (0..<3).map { _ in providerRequestAdmission() }
        let tasks = admissions.map { providerRequestAdmissionTask(pool: pool, admission: $0) }
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 3 }
        try await waitForProviderRequestPoolSleeperCount(timing, 3)

        await pool.shutdown()
        await pool.shutdown()
        for task in tasks {
            #expect(await task.value == .failed(.notAcceptingRequests))
        }
        let stopped = await pool.snapshot()
        #expect(stopped.totalRunning == 1)
        #expect(stopped.totalWaiting == 0)
        #expect(stopped.providers[0].retainedWaitingBytes == 0)
        try await waitForProviderRequestPoolSleeperCount(timing, 0)
        await #expect(throws: GatewayAdmissionError.notAcceptingRequests) {
            try await pool.admit(providerRequestAdmission())
        }

        await pool.finish(eventID: active.eventID)
        #expect((await pool.snapshot()).totalRunning == 0)
    }
}
