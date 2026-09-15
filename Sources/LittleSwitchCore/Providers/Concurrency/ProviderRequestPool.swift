import Foundation
import LittleSwitchCommon

package actor ProviderRequestPool: ProviderRequestPooling {
    package static let maximumWaitingRequests = 128
    package static let maximumRetainedWaitingBytes = 256 * 1_024 * 1_024
    package static let waitTimeout = Duration.seconds(300)

    private struct Waiter {
        let admission: ProviderRequestAdmission
        let enqueuedAt: Duration
        let continuation: CheckedContinuation<Void, any Error>
        let timeoutTask: Task<Void, Never>
    }

    private struct Bucket {
        var displayName: String
        var maximumParallelRequests: Int
        var activeEventIDs: Set<UUID> = []
        var waitersByID: [UUID: Waiter] = [:]
        var waiterOrder: [UUID] = []
        var waiterHead = 0
        var retainedWaitingBytes = 0
        var isRemoved = false
    }

    private struct ProviderSnapshotProjection: Sendable {
        let id: UUID
        let displayName: String
        let maximumParallelRequests: Int
        let runningCount: Int
        let waitingCount: Int
        let retainedWaitingBytes: Int
        let oldestEnqueuedAt: Duration?
        let isRemoved: Bool

        func snapshot(at now: Duration) -> ProviderRequestPoolProviderSnapshot {
            ProviderRequestPoolProviderSnapshot(
                id: id,
                displayName: displayName,
                maximumParallelRequests: maximumParallelRequests,
                runningCount: runningCount,
                waitingCount: waitingCount,
                retainedWaitingBytes: retainedWaitingBytes,
                oldestWaitDuration: oldestEnqueuedAt.map { now - $0 },
                isRemoved: isRemoved
            )
        }
    }

    private var configuration: ProviderRequestPoolConfiguration
    nonisolated private let timing: any ProviderRequestPoolTiming
    private var configuredOrder: [UUID]
    private var removedOrder: [UUID] = []
    private var bucketsByProviderID: [UUID: Bucket]
    private var eventProviderIDs: [UUID: UUID] = [:]
    private var isAcceptingRequests = true

    package init(
        configuration: ProviderRequestPoolConfiguration,
        timing: any ProviderRequestPoolTiming = ContinuousProviderRequestPoolTiming()
    ) {
        self.configuration = configuration
        self.timing = timing
        configuredOrder = configuration.providers.map(\.id)
        bucketsByProviderID = Dictionary(
            uniqueKeysWithValues: configuration.providers.map { provider in
                (
                    provider.id,
                    Bucket(
                        displayName: provider.displayName,
                        maximumParallelRequests: provider.maximumParallelRequests
                    )
                )
            }
        )
    }

    package nonisolated func admit(_ admission: ProviderRequestAdmission) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let enqueuedAt = await timing.now()
            try await register(admission, enqueuedAt: enqueuedAt)
            do {
                try Task.checkCancellation()
            } catch {
                await cancel(eventID: admission.eventID)
                throw error
            }
        } onCancel: {
            Task {
                await self.cancel(eventID: admission.eventID)
            }
        }
    }

    package func finish(eventID: UUID) {
        guard let providerID = eventProviderIDs[eventID],
            var bucket = bucketsByProviderID[providerID]
        else {
            return
        }
        if let waiter = removeWaiter(eventID: eventID, from: &bucket) {
            bucketsByProviderID[providerID] = bucket
            waiter.continuation.resume(throwing: CancellationError())
            return
        }
        bucket.activeEventIDs.remove(eventID)
        eventProviderIDs[eventID] = nil
        grantAvailableWaiters(in: &bucket)
        storeOrRemoveDrainedBucket(bucket, providerID: providerID)
    }

    package func shutdown() {
        guard isAcceptingRequests else {
            return
        }
        isAcceptingRequests = false
        var stoppedWaiters: [Waiter] = []
        let buckets = bucketsByProviderID
        for (providerID, var bucket) in buckets {
            for eventID in Array(bucket.waitersByID.keys) {
                if let waiter = removeWaiter(eventID: eventID, from: &bucket) {
                    stoppedWaiters.append(waiter)
                }
            }
            bucketsByProviderID[providerID] = bucket
        }
        for waiter in stoppedWaiters {
            waiter.continuation.resume(
                throwing: GatewayAdmissionError.notAcceptingRequests
            )
        }
    }

    package func reconfigure(_ newConfiguration: ProviderRequestPoolConfiguration) {
        let previousConfiguredIDs = Set(configuredOrder)
        let newProvidersByID = Dictionary(
            uniqueKeysWithValues: newConfiguration.providers.map { ($0.id, $0) }
        )
        var invalidatedWaiters: [Waiter] = []

        let existingBuckets = (configuredOrder + removedOrder).compactMap { providerID in
            bucketsByProviderID[providerID].map { (providerID, $0) }
        }
        for (providerID, var bucket) in existingBuckets {
            guard let provider = newProvidersByID[providerID] else {
                for eventID in Array(bucket.waitersByID.keys) {
                    if let waiter = removeWaiter(eventID: eventID, from: &bucket) {
                        invalidatedWaiters.append(waiter)
                    }
                }
                bucket.isRemoved = true
                if bucket.activeEventIDs.isEmpty {
                    bucketsByProviderID[providerID] = nil
                    removedOrder.removeAll { $0 == providerID }
                } else {
                    bucketsByProviderID[providerID] = bucket
                    let isNewlyRemoved =
                        previousConfiguredIDs.contains(providerID)
                        && !removedOrder.contains(providerID)
                    if isNewlyRemoved {
                        removedOrder.append(providerID)
                    }
                }
                continue
            }

            for waiter in Array(bucket.waitersByID.values)
            where !isValid(waiter.admission, for: provider, in: newConfiguration) {
                if let removed = removeWaiter(
                    eventID: waiter.admission.eventID,
                    from: &bucket
                ) {
                    invalidatedWaiters.append(removed)
                }
            }
            bucket.displayName = provider.displayName
            bucket.maximumParallelRequests = provider.maximumParallelRequests
            bucket.isRemoved = false
            bucketsByProviderID[providerID] = bucket
            removedOrder.removeAll { $0 == providerID }
        }

        for provider in newConfiguration.providers
        where bucketsByProviderID[provider.id] == nil {
            bucketsByProviderID[provider.id] = Bucket(
                displayName: provider.displayName,
                maximumParallelRequests: provider.maximumParallelRequests
            )
        }

        configuration = newConfiguration
        configuredOrder = newConfiguration.providers.map(\.id)
        for providerID in configuredOrder {
            if var bucket = bucketsByProviderID[providerID] {
                grantAvailableWaiters(in: &bucket)
                bucketsByProviderID[providerID] = bucket
            }
        }
        for waiter in invalidatedWaiters {
            waiter.continuation.resume(throwing: GatewayAdmissionError.invalidated)
        }
    }

    package func queueStorageSnapshot(
        providerID: UUID
    ) -> ProviderRequestPoolQueueStorageSnapshot {
        guard let bucket = bucketsByProviderID[providerID] else {
            return ProviderRequestPoolQueueStorageSnapshot(
                storedEventIDCount: 0,
                consumedPrefixCount: 0,
                liveWaiterCount: 0
            )
        }
        return ProviderRequestPoolQueueStorageSnapshot(
            storedEventIDCount: bucket.waiterOrder.count,
            consumedPrefixCount: bucket.waiterHead,
            liveWaiterCount: bucket.waitersByID.count
        )
    }

    package func snapshot() async -> ProviderRequestPoolSnapshot {
        let providerOrder = configuredOrder + removedOrder
        let projections = providerOrder.compactMap {
            providerSnapshotProjection(providerID: $0)
        }
        let now = await timing.now()
        let providers = projections.map { $0.snapshot(at: now) }
        return ProviderRequestPoolSnapshot(
            totalRunning: providers.reduce(0) { $0 + $1.runningCount },
            totalWaiting: providers.reduce(0) { $0 + $1.waitingCount },
            providers: providers
        )
    }
}

extension ProviderRequestPool {
    private func register(
        _ admission: ProviderRequestAdmission,
        enqueuedAt: Duration
    ) async throws {
        try Task.checkCancellation()
        guard isAcceptingRequests else {
            throw GatewayAdmissionError.notAcceptingRequests
        }
        guard eventProviderIDs[admission.eventID] == nil else {
            throw GatewayAdmissionError.duplicateEventID
        }
        guard admission.retainedBodyBytes >= 0 else {
            throw GatewayAdmissionError.invalidRetainedBodyBytes
        }
        guard var bucket = bucketsByProviderID[admission.providerID], !bucket.isRemoved,
            let provider = configuration.providers.first(where: { $0.id == admission.providerID }),
            isValid(admission, for: provider, in: configuration)
        else {
            throw GatewayAdmissionError.invalidated
        }

        let canRunImmediately =
            bucket.activeEventIDs.count < bucket.maximumParallelRequests
            && bucket.waitersByID.isEmpty
        if canRunImmediately {
            bucket.activeEventIDs.insert(admission.eventID)
            bucketsByProviderID[admission.providerID] = bucket
            eventProviderIDs[admission.eventID] = admission.providerID
            return
        }

        guard bucket.waitersByID.count < Self.maximumWaitingRequests,
            admission.retainedBodyBytes <= Self.maximumRetainedWaitingBytes,
            bucket.retainedWaitingBytes <= Self.maximumRetainedWaitingBytes,
            admission.retainedBodyBytes
                <= Self.maximumRetainedWaitingBytes - bucket.retainedWaitingBytes
        else {
            throw GatewayAdmissionError.overloaded
        }

        let deadline = enqueuedAt + Self.waitTimeout
        try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { [timing] in
                do {
                    try await timing.sleep(until: deadline)
                } catch {
                    return
                }
                self.timeout(eventID: admission.eventID)
            }
            bucket.waitersByID[admission.eventID] = Waiter(
                admission: admission,
                enqueuedAt: enqueuedAt,
                continuation: continuation,
                timeoutTask: timeoutTask
            )
            bucket.waiterOrder.append(admission.eventID)
            bucket.retainedWaitingBytes += admission.retainedBodyBytes
            bucketsByProviderID[admission.providerID] = bucket
            eventProviderIDs[admission.eventID] = admission.providerID
        }
    }

    private func cancel(eventID: UUID) {
        guard let providerID = eventProviderIDs[eventID],
            var bucket = bucketsByProviderID[providerID]
        else {
            return
        }
        if let waiter = removeWaiter(eventID: eventID, from: &bucket) {
            bucketsByProviderID[providerID] = bucket
            waiter.continuation.resume(throwing: CancellationError())
            return
        }
        bucket.activeEventIDs.remove(eventID)
        eventProviderIDs[eventID] = nil
        grantAvailableWaiters(in: &bucket)
        storeOrRemoveDrainedBucket(bucket, providerID: providerID)
    }

    private func timeout(eventID: UUID) {
        guard let providerID = eventProviderIDs[eventID],
            var bucket = bucketsByProviderID[providerID],
            let waiter = removeWaiter(eventID: eventID, from: &bucket)
        else {
            return
        }
        bucketsByProviderID[providerID] = bucket
        waiter.continuation.resume(throwing: GatewayAdmissionError.timedOut)
    }

    private func grantAvailableWaiters(in bucket: inout Bucket) {
        while canGrant(in: bucket) {
            guard let waiter = nextWaiter(in: &bucket) else {
                return
            }
            waiter.timeoutTask.cancel()
            bucket.retainedWaitingBytes -= waiter.admission.retainedBodyBytes
            bucket.activeEventIDs.insert(waiter.admission.eventID)
            waiter.continuation.resume()
            compactWaiterOrderIfNeeded(&bucket)
        }
    }

    private func canGrant(in bucket: Bucket) -> Bool {
        isAcceptingRequests && !bucket.isRemoved
            && bucket.activeEventIDs.count < bucket.maximumParallelRequests
    }

    private func nextWaiter(in bucket: inout Bucket) -> Waiter? {
        while bucket.waiterHead < bucket.waiterOrder.count {
            let eventID = bucket.waiterOrder[bucket.waiterHead]
            bucket.waiterHead += 1
            if let waiter = bucket.waitersByID.removeValue(forKey: eventID) {
                return waiter
            }
        }
        return nil
    }

    private func removeWaiter(eventID: UUID, from bucket: inout Bucket) -> Waiter? {
        guard let waiter = bucket.waitersByID.removeValue(forKey: eventID) else {
            return nil
        }
        eventProviderIDs[eventID] = nil
        bucket.retainedWaitingBytes -= waiter.admission.retainedBodyBytes
        waiter.timeoutTask.cancel()
        compactWaiterOrderIfNeeded(&bucket)
        return waiter
    }

    private func compactWaiterOrderIfNeeded(_ bucket: inout Bucket) {
        let storedCount = bucket.waiterOrder.count
        let liveCount = bucket.waitersByID.count
        let consumedPrefixShouldCompact =
            bucket.waiterHead >= 64
            && bucket.waiterHead * 2 >= storedCount
        let sparseStorageShouldCompact = storedCount > 2 * liveCount + 64
        guard consumedPrefixShouldCompact || sparseStorageShouldCompact else {
            return
        }
        bucket.waiterOrder = bucket.waiterOrder.dropFirst(bucket.waiterHead).filter {
            bucket.waitersByID[$0] != nil
        }
        bucket.waiterHead = 0
    }

    private func isValid(
        _ admission: ProviderRequestAdmission,
        for provider: ProviderRequestPoolProviderConfiguration,
        in configuration: ProviderRequestPoolConfiguration
    ) -> Bool {
        guard admission.providerRevision == provider.revision else {
            return false
        }
        if admission.purpose == .imageProbe {
            return provider.diagnosticModelIDs.contains(admission.targetModelID)
        }
        let route = configuration.routes[
            ProviderRequestRouteKey(
                client: admission.client,
                modelIdentifier: admission.modelIdentifier
            )]
        return route
            == ProviderRequestRouteTarget(
                providerID: admission.providerID,
                modelID: admission.targetModelID
            )
    }

    private func storeOrRemoveDrainedBucket(_ bucket: Bucket, providerID: UUID) {
        let isDrainedRemoval =
            bucket.isRemoved && bucket.activeEventIDs.isEmpty
            && bucket.waitersByID.isEmpty
        if isDrainedRemoval {
            bucketsByProviderID[providerID] = nil
            removedOrder.removeAll { $0 == providerID }
        } else {
            bucketsByProviderID[providerID] = bucket
        }
    }

    private func providerSnapshotProjection(
        providerID: UUID
    ) -> ProviderSnapshotProjection? {
        bucketsByProviderID[providerID].map { bucket in
            let oldestEnqueue = bucket.waiterOrder.dropFirst(bucket.waiterHead)
                .compactMap { bucket.waitersByID[$0]?.enqueuedAt }
                .first
            return ProviderSnapshotProjection(
                id: providerID,
                displayName: bucket.displayName,
                maximumParallelRequests: bucket.maximumParallelRequests,
                runningCount: bucket.activeEventIDs.count,
                waitingCount: bucket.waitersByID.count,
                retainedWaitingBytes: bucket.retainedWaitingBytes,
                oldestEnqueuedAt: oldestEnqueue,
                isRemoved: bucket.isRemoved
            )
        }
    }
}
