import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Provider request pool reconfiguration")
struct ProviderRequestPoolReconfigurationTests {
    @Test("Increasing a limit grants available places immediately in FIFO order")
    func limitIncrease() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let active = providerRequestAdmission()
        let first = providerRequestAdmission()
        let second = providerRequestAdmission()
        try await pool.admit(active)
        let firstTask = providerRequestAdmissionTask(pool: pool, admission: first)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 1 }
        let secondTask = providerRequestAdmissionTask(pool: pool, admission: second)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 2 }

        await pool.reconfigure(providerRequestPoolConfiguration(alphaLimit: 3))

        #expect(await firstTask.value == .admitted)
        #expect(await secondTask.value == .admitted)
        let snapshot = await pool.snapshot()
        #expect(snapshot.providers[0].maximumParallelRequests == 3)
        #expect(snapshot.totalRunning == 3)
        #expect(snapshot.totalWaiting == 0)
        await pool.finish(eventID: active.eventID)
        await pool.finish(eventID: first.eventID)
        await pool.finish(eventID: second.eventID)
    }

    @Test("Decreasing a limit preserves active work and blocks grants until below the cap")
    func limitDecrease() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 3),
            timing: timing
        )
        let active = (0..<3).map { _ in providerRequestAdmission() }
        for admission in active {
            try await pool.admit(admission)
        }
        let waiting = providerRequestAdmission()
        let waitingTask = providerRequestAdmissionTask(pool: pool, admission: waiting)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 1 }

        await pool.reconfigure(providerRequestPoolConfiguration(alphaLimit: 1))
        var snapshot = await pool.snapshot()
        #expect(snapshot.totalRunning == 3)
        #expect(snapshot.totalWaiting == 1)
        #expect(snapshot.providers[0].maximumParallelRequests == 1)
        await pool.finish(eventID: active[0].eventID)
        await pool.finish(eventID: active[1].eventID)
        snapshot = await pool.snapshot()
        #expect(snapshot.totalRunning == 1)
        #expect(snapshot.totalWaiting == 1)

        await pool.finish(eventID: active[2].eventID)
        #expect(await waitingTask.value == .admitted)
        await pool.finish(eventID: waiting.eventID)
    }

    @Test("Name, status, catalog, and limit-only equivalents preserve queued work")
    func nonInvalidatingProviderUpdates() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1),
            timing: timing
        )
        let active = providerRequestAdmission()
        let waiting = providerRequestAdmission(retainedBodyBytes: 17)
        try await pool.admit(active)
        let waitingTask = providerRequestAdmissionTask(pool: pool, admission: waiting)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 1 }

        await pool.reconfigure(
            providerRequestPoolConfiguration(
                alphaLimit: 1,
                alphaName: "Alpha refreshed"
            ))
        let snapshot = await pool.snapshot()
        #expect(snapshot.providers[0].displayName == "Alpha refreshed")
        #expect(snapshot.totalRunning == 1)
        #expect(snapshot.totalWaiting == 1)
        #expect(snapshot.providers[0].retainedWaitingBytes == 17)

        await pool.finish(eventID: active.eventID)
        #expect(await waitingTask.value == .admitted)
        await pool.finish(eventID: waiting.eventID)
    }

    @Test("Provider revision changes invalidate only that provider's waiters")
    func selectiveProviderRevisionInvalidation() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1, betaLimit: 1),
            timing: timing
        )
        let alphaActive = providerRequestAdmission()
        let betaActive = providerRequestAdmission(
            providerID: ProviderRequestPoolTestIDs.beta,
            modelIdentifier: "claude-beta",
            targetModelID: "beta-model"
        )
        try await pool.admit(alphaActive)
        try await pool.admit(betaActive)
        let alphaWaiting = providerRequestAdmission()
        let betaWaiting = providerRequestAdmission(
            providerID: ProviderRequestPoolTestIDs.beta,
            modelIdentifier: "claude-beta",
            targetModelID: "beta-model"
        )
        let alphaTask = providerRequestAdmissionTask(pool: pool, admission: alphaWaiting)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 1 }
        let betaTask = providerRequestAdmissionTask(pool: pool, admission: betaWaiting)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 2 }

        await pool.reconfigure(
            providerRequestPoolConfiguration(
                alphaLimit: 1,
                betaLimit: 1,
                alphaRevision: 1
            ))

        #expect(await alphaTask.value == .failed(.invalidated))
        let afterRevision = await pool.snapshot()
        #expect(afterRevision.totalRunning == 2)
        #expect(afterRevision.totalWaiting == 1)
        #expect(afterRevision.providers.map(\.waitingCount) == [0, 1])
        await pool.finish(eventID: betaActive.eventID)
        #expect(await betaTask.value == .admitted)
        await pool.finish(eventID: alphaActive.eventID)
        await pool.finish(eventID: betaWaiting.eventID)
    }

    @Test("Route target changes and model removal invalidate only affected waiters")
    func routeAndModelInvalidation() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let initial = providerRequestPoolConfiguration(alphaLimit: 1, betaLimit: 1)
        let pool = ProviderRequestPool(configuration: initial, timing: timing)
        let alphaActive = providerRequestAdmission()
        let betaActive = providerRequestAdmission(
            providerID: ProviderRequestPoolTestIDs.beta,
            modelIdentifier: "claude-beta",
            targetModelID: "beta-model"
        )
        try await pool.admit(alphaActive)
        try await pool.admit(betaActive)
        let alphaWaiting = providerRequestAdmission()
        let betaWaiting = providerRequestAdmission(
            providerID: ProviderRequestPoolTestIDs.beta,
            modelIdentifier: "claude-beta",
            targetModelID: "beta-model"
        )
        let alphaTask = providerRequestAdmissionTask(pool: pool, admission: alphaWaiting)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 1 }
        let betaTask = providerRequestAdmissionTask(pool: pool, admission: betaWaiting)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 2 }
        var routes = initial.routes
        routes[ProviderRequestRouteKey(client: .claude, modelIdentifier: "claude-alpha")] =
            ProviderRequestRouteTarget(
                providerID: ProviderRequestPoolTestIDs.alpha,
                modelID: "replacement-model"
            )

        await pool.reconfigure(
            providerRequestPoolConfiguration(
                alphaLimit: 1,
                betaLimit: 1,
                routes: routes
            ))

        #expect(await alphaTask.value == .failed(.invalidated))
        #expect((await pool.snapshot()).totalWaiting == 1)
        await pool.finish(eventID: betaActive.eventID)
        #expect(await betaTask.value == .admitted)
        await pool.finish(eventID: alphaActive.eventID)
        await pool.finish(eventID: betaWaiting.eventID)

        let secondPool = ProviderRequestPool(configuration: initial, timing: timing)
        let secondActive = providerRequestAdmission()
        let removedModelWaiting = providerRequestAdmission()
        try await secondPool.admit(secondActive)
        let removedTask = providerRequestAdmissionTask(
            pool: secondPool,
            admission: removedModelWaiting
        )
        _ = try await waitForProviderRequestPoolSnapshot(secondPool) {
            $0.totalWaiting == 1
        }
        routes = initial.routes
        routes[ProviderRequestRouteKey(client: .claude, modelIdentifier: "claude-alpha")] = nil
        await secondPool.reconfigure(
            providerRequestPoolConfiguration(
                alphaLimit: 1,
                betaLimit: 1,
                routes: routes
            ))
        #expect(await removedTask.value == .failed(.invalidated))
        await secondPool.finish(eventID: secondActive.eventID)
    }

}

@Suite("Provider request pool removal reconfiguration")
struct ProviderRequestPoolRemovalTests {
    @Test("Removal drains active work after configured rows and preserves aggregate equality")
    func removalDrainingOrderAndAggregateEquality() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(
                alphaLimit: 1,
                betaLimit: 1,
                providerOrder: [ProviderRequestPoolTestIDs.beta, ProviderRequestPoolTestIDs.alpha]
            ),
            timing: timing
        )
        let alphaActive = providerRequestAdmission()
        let betaActive = providerRequestAdmission(
            providerID: ProviderRequestPoolTestIDs.beta,
            modelIdentifier: "claude-beta",
            targetModelID: "beta-model"
        )
        let alphaWaiting = providerRequestAdmission()
        try await pool.admit(alphaActive)
        try await pool.admit(betaActive)
        let alphaTask = providerRequestAdmissionTask(pool: pool, admission: alphaWaiting)
        _ = try await waitForProviderRequestPoolSnapshot(pool) { $0.totalWaiting == 1 }

        await pool.reconfigure(
            providerRequestPoolConfiguration(
                alphaLimit: 1,
                betaLimit: 1,
                providerOrder: [ProviderRequestPoolTestIDs.beta]
            ))

        #expect(await alphaTask.value == .failed(.invalidated))
        var snapshot = await pool.snapshot()
        #expect(
            snapshot.providers.map(\.id) == [
                ProviderRequestPoolTestIDs.beta,
                ProviderRequestPoolTestIDs.alpha,
            ])
        #expect(snapshot.providers.map(\.isRemoved) == [false, true])
        #expect(snapshot.providers[1].displayName == "Alpha")
        #expect(
            snapshot.totalRunning
                == snapshot.providers.reduce(0) {
                    $0 + $1.runningCount
                })
        #expect(
            snapshot.totalWaiting
                == snapshot.providers.reduce(0) {
                    $0 + $1.waitingCount
                })

        await pool.finish(eventID: alphaActive.eventID)
        snapshot = await pool.snapshot()
        #expect(snapshot.providers.map(\.id) == [ProviderRequestPoolTestIDs.beta])
        #expect(snapshot.totalRunning == 1)
        await pool.finish(eventID: betaActive.eventID)
    }

    @Test("A multi-removal preserves prior configured order and captured provider names")
    func multiRemovalPreservesOrderAndNames() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(
                alphaLimit: 1,
                betaLimit: 1,
                providerOrder: [ProviderRequestPoolTestIDs.beta, ProviderRequestPoolTestIDs.alpha],
                alphaName: "Alpha captured",
                betaName: "Beta captured"
            ),
            timing: timing
        )
        let alphaActive = providerRequestAdmission()
        let betaActive = providerRequestAdmission(
            providerID: ProviderRequestPoolTestIDs.beta,
            modelIdentifier: "claude-beta",
            targetModelID: "beta-model"
        )
        try await pool.admit(alphaActive)
        try await pool.admit(betaActive)

        await pool.reconfigure(ProviderRequestPoolConfiguration(providers: [], routes: [:]))

        #expect(
            await pool.snapshot()
                == ProviderRequestPoolSnapshot(
                    totalRunning: 2,
                    totalWaiting: 0,
                    providers: [
                        ProviderRequestPoolProviderSnapshot(
                            id: ProviderRequestPoolTestIDs.beta,
                            displayName: "Beta captured",
                            maximumParallelRequests: 1,
                            runningCount: 1,
                            waitingCount: 0,
                            retainedWaitingBytes: 0,
                            oldestWaitDuration: nil,
                            isRemoved: true
                        ),
                        ProviderRequestPoolProviderSnapshot(
                            id: ProviderRequestPoolTestIDs.alpha,
                            displayName: "Alpha captured",
                            maximumParallelRequests: 1,
                            runningCount: 1,
                            waitingCount: 0,
                            retainedWaitingBytes: 0,
                            oldestWaitDuration: nil,
                            isRemoved: true
                        ),
                    ]
                )
        )
        await pool.finish(eventID: alphaActive.eventID)
        await pool.finish(eventID: betaActive.eventID)
    }

    @Test("Removed buckets retain removal order and re-adding a UUID restores configured order")
    func removalOrderAndReaddition() async throws {
        let timing = ManualProviderRequestPoolTiming()
        let pool = ProviderRequestPool(
            configuration: providerRequestPoolConfiguration(alphaLimit: 1, betaLimit: 1),
            timing: timing
        )
        let alphaActive = providerRequestAdmission()
        let betaActive = providerRequestAdmission(
            providerID: ProviderRequestPoolTestIDs.beta,
            modelIdentifier: "claude-beta",
            targetModelID: "beta-model"
        )
        try await pool.admit(alphaActive)
        try await pool.admit(betaActive)

        await pool.reconfigure(
            providerRequestPoolConfiguration(
                alphaLimit: 1,
                betaLimit: 1,
                providerOrder: [ProviderRequestPoolTestIDs.beta]
            ))
        await pool.reconfigure(ProviderRequestPoolConfiguration(providers: [], routes: [:]))
        var snapshot = await pool.snapshot()
        #expect(
            snapshot.providers.map(\.id) == [
                ProviderRequestPoolTestIDs.alpha,
                ProviderRequestPoolTestIDs.beta,
            ])
        #expect(
            snapshot.providers.map(\.isRemoved)
                == Array(repeating: true, count: snapshot.providers.count)
        )

        await pool.reconfigure(
            providerRequestPoolConfiguration(
                alphaLimit: 2,
                alphaRevision: 1,
                providerOrder: [ProviderRequestPoolTestIDs.alpha],
                alphaName: "Alpha restored"
            ))
        snapshot = await pool.snapshot()
        #expect(
            snapshot.providers.map(\.id) == [
                ProviderRequestPoolTestIDs.alpha,
                ProviderRequestPoolTestIDs.beta,
            ])
        #expect(snapshot.providers.map(\.isRemoved) == [false, true])
        #expect(snapshot.providers[0].displayName == "Alpha restored")
        #expect(snapshot.providers[0].runningCount == 1)
        #expect(snapshot.providers[0].maximumParallelRequests == 2)

        let restored = providerRequestAdmission(providerRevision: 1)
        try await pool.admit(restored)
        #expect((await pool.snapshot()).providers[0].runningCount == 2)
        await pool.finish(eventID: alphaActive.eventID)
        await pool.finish(eventID: restored.eventID)
        await pool.finish(eventID: betaActive.eventID)
        snapshot = await pool.snapshot()
        #expect(snapshot.providers.map(\.id) == [ProviderRequestPoolTestIDs.alpha])
    }
}
