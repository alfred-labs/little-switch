import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Provider request pool bounds")
struct ProviderRequestPoolBoundsTests {
    @Test("Exactly 128 waiters fit and waiter 129 is rejected immediately")
    func waitingRequestBoundary() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let active = providerRequestAdmission()
        try await pool.admit(active)

        let waiters = (0..<ProviderRequestPool.maximumWaitingRequests).map { _ in
            providerRequestAdmission()
        }
        let tasks = waiters.map { providerRequestAdmissionTask(pool: pool, admission: $0) }
        let atCapacity = try await waitForProviderRequestPoolSnapshot(pool) {
            $0.totalWaiting == ProviderRequestPool.maximumWaitingRequests
        }

        await #expect(throws: GatewayAdmissionError.overloaded) {
            try await pool.admit(providerRequestAdmission())
        }
        let rejected = await pool.snapshot()
        #expect(rejected.totalWaiting == 128)
        #expect(rejected == atCapacity)

        await pool.shutdown()
        for task in tasks {
            #expect(await task.value == .failed(.notAcceptingRequests))
        }
        await pool.finish(eventID: active.eventID)
    }

    @Test("Exactly 256 MiB fits while one additional byte is rejected")
    func retainedBodyBoundary() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let active = providerRequestAdmission(retainedBodyBytes: Int.max)
        let exact = providerRequestAdmission(
            retainedBodyBytes: ProviderRequestPool.maximumRetainedWaitingBytes
        )
        try await pool.admit(active)
        let exactTask = providerRequestAdmissionTask(pool: pool, admission: exact)
        let atCapacity = try await waitForProviderRequestPoolSnapshot(pool) {
            $0.providers[0].retainedWaitingBytes
                == ProviderRequestPool.maximumRetainedWaitingBytes
        }

        await #expect(throws: GatewayAdmissionError.overloaded) {
            try await pool.admit(providerRequestAdmission(retainedBodyBytes: 1))
        }
        let snapshot = await pool.snapshot()
        #expect(snapshot.totalWaiting == 1)
        #expect(snapshot == atCapacity)

        await pool.finish(eventID: active.eventID)
        #expect(await exactTask.value == .admitted)
        await pool.finish(eventID: exact.eventID)
    }

    @Test("Negative and overflow-sized byte charges cannot undercharge or wrap")
    func invalidAndOverflowingBodyCharges() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )

        await #expect(throws: GatewayAdmissionError.invalidRetainedBodyBytes) {
            try await pool.admit(providerRequestAdmission(retainedBodyBytes: -1))
        }
        let active = providerRequestAdmission(retainedBodyBytes: 0)
        try await pool.admit(active)
        let oneByte = providerRequestAdmission(retainedBodyBytes: 1)
        let oneByteTask = providerRequestAdmissionTask(pool: pool, admission: oneByte)
        let beforeRejection = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 1 }

        await #expect(throws: GatewayAdmissionError.overloaded) {
            try await pool.admit(providerRequestAdmission(retainedBodyBytes: Int.max))
        }
        let snapshot = await pool.snapshot()
        #expect(snapshot.providers[0].retainedWaitingBytes == 1)
        #expect(snapshot == beforeRejection)

        await pool.finish(eventID: active.eventID)
        #expect(await oneByteTask.value == .admitted)
        await pool.finish(eventID: oneByte.eventID)
    }

    @Test("Active request bodies never consume the waiting-body budget")
    func activeBodiesAreExcluded() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 2),
            timing: timing
        )
        let first = providerRequestAdmission(retainedBodyBytes: Int.max)
        let second = providerRequestAdmission(retainedBodyBytes: Int.max)
        let waiting = providerRequestAdmission(
            retainedBodyBytes: ProviderRequestPool.maximumRetainedWaitingBytes
        )

        try await pool.admit(first)
        try await pool.admit(second)
        let waitingTask = providerRequestAdmissionTask(pool: pool, admission: waiting)
        let snapshot = try await waitForProviderRequestPoolSnapshot(pool) {
            $0.totalWaiting == 1
        }
        #expect(snapshot.providers[0].retainedWaitingBytes == 256 * 1_024 * 1_024)

        await pool.finish(eventID: first.eventID)
        #expect(await waitingTask.value == .admitted)
        await pool.finish(eventID: second.eventID)
        await pool.finish(eventID: waiting.eventID)
    }

    @Test("Timeout fires at exactly 300 monotonic seconds and releases its charge")
    func exactTimeout() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let active = providerRequestAdmission()
        let waiting = providerRequestAdmission(retainedBodyBytes: 42)
        try await pool.admit(active)
        let waitingTask = providerRequestAdmissionTask(pool: pool, admission: waiting)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 1 }
        try await waitForProviderRequestPoolSleeperCount(timing, 1)

        await timing.advance(by: .seconds(299))
        let before = await pool.snapshot()
        #expect(before.totalWaiting == 1)
        #expect(before.providers[0].oldestWaitDuration == .seconds(299))
        #expect(before.providers[0].retainedWaitingBytes == 42)

        await timing.advance(by: .seconds(1))
        #expect(await waitingTask.value == .failed(.timedOut))
        let after = await pool.snapshot()
        #expect(after.totalWaiting == 0)
        #expect(after.providers[0].retainedWaitingBytes == 0)
        #expect(after.providers[0].oldestWaitDuration == nil)
        #expect(after.totalRunning == 1)
        await pool.finish(eventID: active.eventID)
    }

    @Test("Consumed-prefix compaction waits for both exact thresholds")
    func consumedPrefixCompactionThreshold() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        var active = providerRequestAdmission()
        try await pool.admit(active)
        let admissions = (0..<128).map { _ in providerRequestAdmission() }
        var tasks: [Task<ProviderRequestAdmissionOutcome, Never>] = []
        for admission in admissions {
            tasks.append(providerRequestAdmissionTask(pool: pool, admission: admission))
            let expectedCount = tasks.count
            _ = try await waitForProviderRequestPoolSnapshot(pool) {
                $0.totalWaiting == expectedCount
            }
        }

        for index in 0..<63 {
            await pool.finish(eventID: active.eventID)
            #expect(await tasks[index].value == .admitted)
            active = admissions[index]
        }
        var storage = await pool.queueStorageSnapshot(providerID: ProviderRequestPoolTestIDs.alpha)
        #expect(
            storage
                == ProviderRequestPoolQueueStorageSnapshot(
                    storedEventIDCount: 128,
                    consumedPrefixCount: 63,
                    liveWaiterCount: 65
                ))

        await pool.finish(eventID: active.eventID)
        #expect(await tasks[63].value == .admitted)
        active = admissions[63]
        storage = await pool.queueStorageSnapshot(providerID: ProviderRequestPoolTestIDs.alpha)
        #expect(
            storage
                == ProviderRequestPoolQueueStorageSnapshot(
                    storedEventIDCount: 64,
                    consumedPrefixCount: 0,
                    liveWaiterCount: 64
                ))

        for index in 64..<128 {
            await pool.finish(eventID: active.eventID)
            let outcome = try await valueWithinTimeout(
                tasks[index],
                description: "FIFO waiter \(index) after consumed-prefix compaction"
            )
            try #require(outcome == .admitted)
            active = admissions[index]
        }
        await pool.finish(eventID: active.eventID)
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
        #expect(
            await pool.queueStorageSnapshot(providerID: ProviderRequestPoolTestIDs.alpha)
                == ProviderRequestPoolQueueStorageSnapshot(
                    storedEventIDCount: 0,
                    consumedPrefixCount: 0,
                    liveWaiterCount: 0
                ))
    }

    @Test("Sparse-array compaction triggers only after its strict threshold")
    func sparseStorageCompactionThreshold() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let active = providerRequestAdmission()
        try await pool.admit(active)
        let admissions = (0..<128).map { _ in providerRequestAdmission() }
        var tasks: [Task<ProviderRequestAdmissionOutcome, Never>] = []
        for admission in admissions {
            tasks.append(providerRequestAdmissionTask(pool: pool, admission: admission))
            let expectedCount = tasks.count
            _ = try await waitForProviderRequestPoolSnapshot(pool) {
                $0.totalWaiting == expectedCount
            }
        }

        let interleavedCancellationIndices = (0..<128).filter { !$0.isMultiple(of: 4) }
        for index in interleavedCancellationIndices {
            tasks[index].cancel()
        }
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 32 }
        var storage = await pool.queueStorageSnapshot(providerID: ProviderRequestPoolTestIDs.alpha)
        #expect(
            storage
                == ProviderRequestPoolQueueStorageSnapshot(
                    storedEventIDCount: 128,
                    consumedPrefixCount: 0,
                    liveWaiterCount: 32
                ))

        tasks[124].cancel()
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 31 }
        storage = await pool.queueStorageSnapshot(providerID: ProviderRequestPoolTestIDs.alpha)
        #expect(
            storage
                == ProviderRequestPoolQueueStorageSnapshot(
                    storedEventIDCount: 31,
                    consumedPrefixCount: 0,
                    liveWaiterCount: 31
                ))

        for index in interleavedCancellationIndices + [124] {
            let outcome = try await valueWithinTimeout(
                tasks[index],
                description: "cancelled sparse waiter \(index)"
            )
            #expect(outcome == .cancelled)
        }

        var running = active
        for index in stride(from: 0, through: 120, by: 4) {
            await pool.finish(eventID: running.eventID)
            let outcome = try await valueWithinTimeout(
                tasks[index],
                description: "FIFO waiter \(index) after sparse compaction"
            )
            try #require(outcome == .admitted)
            running = admissions[index]
        }
        await pool.finish(eventID: running.eventID)
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
        #expect(
            await pool.queueStorageSnapshot(providerID: ProviderRequestPoolTestIDs.alpha)
                == ProviderRequestPoolQueueStorageSnapshot(
                    storedEventIDCount: 31,
                    consumedPrefixCount: 31,
                    liveWaiterCount: 0
                ))
    }
}
