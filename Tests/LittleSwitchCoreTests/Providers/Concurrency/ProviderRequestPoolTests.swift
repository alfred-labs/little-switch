import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Provider request pool")
struct ProviderRequestPoolTests {
    @Test("Production policy and explicit public snapshots expose the locked contract")
    func productionPolicyAndPublicSnapshots() {
        #expect(ProviderRequestPool.maximumWaitingRequests == 128)
        #expect(ProviderRequestPool.maximumRetainedWaitingBytes == 256 * 1_024 * 1_024)
        #expect(ProviderRequestPool.waitTimeout == .seconds(300))

        let provider = ProviderRequestPoolProviderSnapshot(
            id: ProviderRequestPoolTestIDs.alpha,
            displayName: "Alpha",
            maximumParallelRequests: 2,
            runningCount: 1,
            waitingCount: 2,
            retainedWaitingBytes: 3,
            oldestWaitDuration: .seconds(4),
            isRemoved: false
        )
        let snapshot = ProviderRequestPoolSnapshot(
            totalRunning: 1,
            totalWaiting: 2,
            providers: [provider]
        )

        #expect(snapshot.providers == [provider])
        #expect(snapshot.totalRunning == 1)
        #expect(snapshot.totalWaiting == 2)

        let admission = providerRequestAdmission(eventID: ProviderRequestPoolTestIDs.beta)
        #expect(admission == providerRequestAdmission(eventID: ProviderRequestPoolTestIDs.beta))
    }

    @Test("Continuous timing and the production pool initializer use monotonic time")
    func continuousTiming() async throws {
        let timing = ContinuousProviderRequestPoolTiming()
        let now = await timing.now()
        try await timing.sleep(until: now)
        #expect(await timing.now() >= now)

        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1)
        )
        #expect((await pool.snapshot()).totalRunning == 0)
    }

    @Test("Cancellation during actor registration is observed before queue insertion")
    func cancellationDuringRegistration() async throws {
        let timing = RegistrationCancellationTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let active = providerRequestAdmission()
        try await pool.admit(active)
        await timing.cancelOnNextRead()

        let cancelled = providerRequestAdmissionTask(
            pool: pool,
            admission: providerRequestAdmission()
        )
        #expect(await cancelled.value == .cancelled)
        let snapshot = await pool.snapshot()
        #expect(snapshot.totalRunning == 1)
        #expect(snapshot.totalWaiting == 0)
        await pool.finish(eventID: active.eventID)
    }

    @Test("Snapshot projection is captured before its asynchronous clock read")
    func snapshotProjectionPrecedesClockRead() async throws {
        let timing = SnapshotBlockingTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let active = providerRequestAdmission()
        let waiting = providerRequestAdmission()
        try await pool.admit(active)
        await timing.blockNextRead(at: .seconds(10))

        let snapshotTask = Task { await pool.snapshot() }
        try await timing.waitUntilReadIsBlocked()
        await timing.setInstant(.seconds(20))
        let waitingTask = providerRequestAdmissionTask(pool: pool, admission: waiting)
        let _: ProviderRequestPoolQueueStorageSnapshot = try await eventually(
            description: "the waiter registration during a suspended snapshot"
        ) {
            let storage = await pool.queueStorageSnapshot(
                providerID: ProviderRequestPoolTestIDs.alpha
            )
            return storage.liveWaiterCount == 1 ? storage : nil
        }
        #expect(
            (await pool.queueStorageSnapshot(providerID: ProviderRequestPoolTestIDs.alpha))
                .liveWaiterCount == 1
        )

        await timing.releaseBlockedRead()

        #expect(
            await snapshotTask.value
                == ProviderRequestPoolSnapshot(
                    totalRunning: 1,
                    totalWaiting: 0,
                    providers: [
                        ProviderRequestPoolProviderSnapshot(
                            id: ProviderRequestPoolTestIDs.alpha,
                            displayName: "Alpha",
                            maximumParallelRequests: 1,
                            runningCount: 1,
                            waitingCount: 0,
                            retainedWaitingBytes: 0,
                            oldestWaitDuration: nil,
                            isRemoved: false
                        )
                    ]
                )
        )
        await pool.finish(eventID: active.eventID)
        #expect(await waitingTask.value == .admitted)
        await pool.finish(eventID: waiting.eventID)
    }

    @Test("Invalid routing metadata is rejected and unknown storage inspection is empty")
    func invalidAdmissionAndUnknownStorage() async {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )

        await #expect(throws: GatewayAdmissionError.invalidated) {
            try await pool.admit(providerRequestAdmission(providerRevision: 1))
        }
        #expect(
            await pool.queueStorageSnapshot(providerID: UUID())
                == ProviderRequestPoolQueueStorageSnapshot(
                    storedEventIDCount: 0,
                    consumedPrefixCount: 0,
                    liveWaiterCount: 0
                ))
    }

    @Test("Zero-activity providers retain configured order")
    func configuredProviderOrder() async {
        let timing = ManualProviderRequestPoolTiming()
        let configuration = providerRequestPoolConfiguration(
            alphaLimit: 2,
            betaLimit: 3,
            providerOrder: [ProviderRequestPoolTestIDs.beta, ProviderRequestPoolTestIDs.alpha]
        )
        let pool = ProviderRequestPool(configuration: configuration, timing: timing)

        let snapshot = await pool.snapshot()

        #expect(snapshot.totalRunning == 0)
        #expect(snapshot.totalWaiting == 0)
        #expect(
            snapshot.providers.map(\.id) == [
                ProviderRequestPoolTestIDs.beta,
                ProviderRequestPoolTestIDs.alpha,
            ])
        #expect(snapshot.providers.map(\.maximumParallelRequests) == [3, 2])
        #expect(snapshot.providers.allSatisfy { !$0.isRemoved })
    }

    @Test("Limit two grants two and resumes later tickets in strict FIFO order")
    func strictFIFO() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 2),
            timing: timing
        )
        let first = providerRequestAdmission()
        let second = providerRequestAdmission()
        let third = providerRequestAdmission()
        let fourth = providerRequestAdmission()

        try await pool.admit(first)
        try await pool.admit(second)
        let thirdTask = providerRequestAdmissionTask(pool: pool, admission: third)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 1 }
        let fourthTask = providerRequestAdmissionTask(pool: pool, admission: fourth)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 2 }

        await pool.finish(eventID: second.eventID)
        #expect(await thirdTask.value == .admitted)
        let afterThird = await pool.snapshot()
        #expect(afterThird.totalRunning == 2)
        #expect(afterThird.totalWaiting == 1)

        await pool.finish(eventID: first.eventID)
        #expect(await fourthTask.value == .admitted)
        let afterFourth = await pool.snapshot()
        #expect(afterFourth.totalRunning == 2)
        #expect(afterFourth.totalWaiting == 0)

        await pool.finish(eventID: third.eventID)
        await pool.finish(eventID: fourth.eventID)
    }

    @Test("A newer request never bypasses an existing waiter")
    func noWaiterBypass() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let active = providerRequestAdmission()
        let older = providerRequestAdmission()
        let newer = providerRequestAdmission()

        try await pool.admit(active)
        let olderTask = providerRequestAdmissionTask(pool: pool, admission: older)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 1 }
        let newerTask = providerRequestAdmissionTask(pool: pool, admission: newer)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 2 }

        await pool.finish(eventID: active.eventID)
        #expect(await olderTask.value == .admitted)
        #expect((await pool.snapshot()).totalWaiting == 1)
        await pool.finish(eventID: older.eventID)
        #expect(await newerTask.value == .admitted)
        await pool.finish(eventID: newer.eventID)
    }

    @Test("Providers have independent pools and protocol clients share provider capacity")
    func providerIsolationAndCrossClientSharing() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1, betaLimit: 1),
            timing: timing
        )
        let claude = providerRequestAdmission()
        let codex = providerRequestAdmission(
            client: .codex,
            modelIdentifier: "codex-alpha"
        )
        let beta = providerRequestAdmission(
            providerID: ProviderRequestPoolTestIDs.beta,
            modelIdentifier: "claude-beta",
            targetModelID: "beta-model"
        )

        try await pool.admit(claude)
        let codexTask = providerRequestAdmissionTask(pool: pool, admission: codex)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 1 }
        try await pool.admit(beta)

        let snapshot = await pool.snapshot()
        #expect(snapshot.totalRunning == 2)
        #expect(snapshot.totalWaiting == 1)
        #expect(snapshot.providers.map(\.runningCount) == [1, 1])

        await pool.finish(eventID: claude.eventID)
        #expect(await codexTask.value == .admitted)
        await pool.finish(eventID: codex.eventID)
        await pool.finish(eventID: beta.eventID)
    }

    @Test("Duplicate live IDs are rejected and all finish variants are idempotent")
    func duplicateAndIdempotentFinish() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let admission = providerRequestAdmission()

        try await pool.admit(admission)
        await #expect(throws: GatewayAdmissionError.duplicateEventID) {
            try await pool.admit(admission)
        }
        await pool.finish(eventID: UUID())
        #expect((await pool.snapshot()).totalRunning == 1)
        await pool.finish(eventID: admission.eventID)
        await pool.finish(eventID: admission.eventID)
        #expect((await pool.snapshot()).totalRunning == 0)
    }
}
