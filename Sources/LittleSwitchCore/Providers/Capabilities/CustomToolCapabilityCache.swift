import Foundation
import LittleSwitchCommon

package actor CustomToolCapabilityCache {
    private struct Resolution: Sendable {
        let mode: CustomToolCapabilityMode
        let flightID: UUID?
    }

    private struct Waiter {
        var continuation: CheckedContinuation<Resolution, any Error>?
    }

    private struct Flight {
        let key: CustomToolCapabilityStore.Key
        var task: Task<Void, Never>?
        var completedMode: CustomToolCapabilityMode?
        var waiters: [UUID: Waiter]
    }

    private let storeURL: URL?
    private let now: @Sendable () -> Date
    private let maximumEntries: Int
    private let maximumConcurrentProbes: Int
    private let maximumWaiters: Int
    private var entries: [CustomToolCapabilityStore.Key: CustomToolCapabilityStore.Entry]
    private var flights: [UUID: Flight] = [:]
    private var flightsByKey: [CustomToolCapabilityStore.Key: UUID] = [:]

    var waiterCount: Int { flights.values.reduce(0) { $0 + $1.waiters.count } }
    var activeProbeCount: Int { flights.values.filter { $0.task != nil }.count }

    package init(
        storeURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        maximumEntries: Int = 512,
        maximumConcurrentProbes: Int = 2
    ) {
        self.storeURL = storeURL
        self.now = now
        self.maximumEntries = max(0, maximumEntries)
        self.maximumConcurrentProbes = max(0, maximumConcurrentProbes)
        maximumWaiters = max(1, maximumEntries)
        entries = CustomToolCapabilityStore.load(url: storeURL, now: now(), maximumEntries: max(0, maximumEntries))
    }

    package func mode(
        for key: CustomToolCapabilityKey,
        probe: @escaping @Sendable () async throws -> CustomToolCapabilityMode
    ) async throws -> CustomToolCapabilityMode {
        try Task.checkCancellation()
        let storedKey = CustomToolCapabilityStore.Key(key)
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let resolution = try await withCheckedThrowingContinuation { continuation in
                enqueue(key: storedKey, waiterID: waiterID, continuation: continuation, probe: probe)
            }
            try Task.checkCancellation()
            if let flightID = resolution.flightID { try accept(flightID: flightID, waiterID: waiterID) }
            try Task.checkCancellation()
            return resolution.mode
        } onCancel: {
            Task { await self.cancel(waiterID: waiterID) }
        }
    }

    package func invalidate(providerIDs: Set<UUID>) {
        guard !providerIDs.isEmpty else { return }
        entries = entries.filter { !providerIDs.contains($0.key.providerID) }
        for (id, flight) in flights where providerIDs.contains(flight.key.providerID) { cancelFlight(id) }
        CustomToolCapabilityStore.save(entries, url: storeURL)
    }

    private func enqueue(
        key: CustomToolCapabilityStore.Key,
        waiterID: UUID,
        continuation: CheckedContinuation<Resolution, any Error>,
        probe: @escaping @Sendable () async throws -> CustomToolCapabilityMode
    ) {
        if let entry = entries[key], entry.isFresh(at: now()) {
            continuation.resume(returning: Resolution(mode: entry.mode, flightID: nil))
            return
        }
        entries[key] = nil
        guard waiterCount < maximumWaiters else {
            continuation.resume(returning: Resolution(mode: .inconclusive, flightID: nil))
            return
        }
        if let id = flightsByKey[key], let flight = flights[id] {
            if let mode = flight.completedMode {
                flights[id]?.waiters[waiterID] = Waiter()
                continuation.resume(returning: Resolution(mode: mode, flightID: id))
            } else {
                flights[id]?.waiters[waiterID] = Waiter(continuation: continuation)
            }
            return
        }
        guard activeProbeCount < maximumConcurrentProbes else {
            continuation.resume(returning: Resolution(mode: .inconclusive, flightID: nil))
            return
        }
        let id = UUID()
        flights[id] = Flight(key: key, waiters: [waiterID: Waiter(continuation: continuation)])
        flightsByKey[key] = id
        flights[id]?.task = Task { await self.run(id: id, probe: probe) }
    }

    private func run(id: UUID, probe: @escaping @Sendable () async throws -> CustomToolCapabilityMode) async {
        let result: Result<CustomToolCapabilityMode, any Error>
        do {
            try Task.checkCancellation()
            let mode = try await probe()
            try Task.checkCancellation()
            result = .success(mode)
        } catch {
            result = .failure(error)
        }
        complete(id: id, result: result)
    }

    private func complete(id: UUID, result: Result<CustomToolCapabilityMode, any Error>) {
        guard var flight = flights.removeValue(forKey: id) else { return }
        guard flightsByKey[flight.key] == id, !flight.waiters.isEmpty else { return }
        switch result {
        case .failure(let error):
            flightsByKey[flight.key] = nil
            for waiter in flight.waiters.values { waiter.continuation?.resume(throwing: error) }
        case .success(let mode):
            flight.task = nil
            flight.completedMode = mode
            for (waiterID, waiter) in flight.waiters {
                flight.waiters[waiterID] = Waiter()
                waiter.continuation?.resume(returning: Resolution(mode: mode, flightID: id))
            }
            flights[id] = flight
        }
    }

    /// Publish evidence only when an uncancelled caller accepts the result. A
    /// cancellation handler may still be waiting for the actor when a job ends.
    private func accept(flightID: UUID, waiterID: UUID) throws {
        guard var flight = flights[flightID], flightsByKey[flight.key] == flightID,
            flight.waiters[waiterID] != nil, let mode = flight.completedMode
        else { throw CancellationError() }
        defer {
            flight.waiters[waiterID] = nil
            flights[flightID] = flight.waiters.isEmpty ? nil : flight
            if flight.waiters.isEmpty { flightsByKey[flight.key] = nil }
        }
        let observedAt = now()
        try Task.checkCancellation()
        if maximumEntries > 0, entries[flight.key] == nil {
            entries = entries.filter { $0.value.isFresh(at: observedAt) }
            while entries.count >= maximumEntries { evictOldestEntry() }
            entries[flight.key] = CustomToolCapabilityStore.Entry(key: flight.key, mode: mode, observedAt: observedAt)
            CustomToolCapabilityStore.save(entries, url: storeURL)
        }
    }

    private func evictOldestEntry() {
        if let oldest = entries.min(by: { $0.value.observedAt < $1.value.observedAt }) { entries[oldest.key] = nil }
    }

    private func cancel(waiterID: UUID) {
        for (id, var flight) in flights {
            guard let waiter = flight.waiters.removeValue(forKey: waiterID) else { continue }
            flights[id] = flight
            waiter.continuation?.resume(throwing: CancellationError())
            if flight.waiters.isEmpty { cancelFlight(id) }
            return
        }
    }

    private func cancelFlight(_ id: UUID) {
        guard var flight = flights[id] else { return }
        if flightsByKey[flight.key] == id { flightsByKey[flight.key] = nil }
        flight.task?.cancel()
        for waiter in flight.waiters.values { waiter.continuation?.resume(throwing: CancellationError()) }
        flight.waiters.removeAll()
        // An uncooperative cancelled job still occupies capacity until it exits.
        flights[id] = flight.task == nil ? nil : flight
    }
}
