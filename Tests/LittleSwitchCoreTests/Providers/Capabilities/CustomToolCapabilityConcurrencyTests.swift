import Foundation
import LittleSwitchCommon
import Testing

import struct os.OSAllocatedUnfairLock

@testable import LittleSwitchCore

@Suite("Bounded custom capability flights")
struct CustomToolCapabilityConcurrencyTests {
    @Test("Concurrent callers share a probe while one cancelled caller returns promptly")
    func coalescing() async throws {
        let cache = CustomToolCapabilityCache()
        let key = customCapabilityKey()
        let gate = CustomCapabilityProbeGate()
        let first = Task { try await cache.mode(for: key) { await gate.probe() } }
        await gate.waitForStart()
        let second = Task { try await cache.mode(for: key) { .functionEnvelope } }
        try await waitForCustomCache(cache, waiters: 2)
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        await gate.release()
        #expect(try await second.value == .native)
        #expect(try await cache.mode(for: key) { .functionEnvelope } == .native)
    }

    @Test("Overload does not queue work or poison a later result")
    func overload() async throws {
        let cache = CustomToolCapabilityCache(maximumConcurrentProbes: 1)
        let gate = CustomCapabilityProbeGate()
        let first = Task { try await cache.mode(for: customCapabilityKey()) { await gate.probe() } }
        await gate.waitForStart()
        let other = customCapabilityKey()
        #expect(try await cache.mode(for: other) { .native } == .inconclusive)
        await gate.release()
        #expect(try await first.value == .native)
        #expect(try await cache.mode(for: other) { .functionEnvelope } == .functionEnvelope)
    }

    @Test("Coalesced waiter state is bounded too")
    func waiterOverload() async throws {
        let cache = CustomToolCapabilityCache(maximumEntries: 1)
        let key = customCapabilityKey()
        let gate = CustomCapabilityProbeGate()
        let first = Task { try await cache.mode(for: key) { await gate.probe() } }
        await gate.waitForStart()
        #expect(try await cache.mode(for: key) { .functionEnvelope } == .inconclusive)
        await gate.release()
        #expect(try await first.value == .native)
    }

    @Test("Invalidation fences late results even when the old probe ignores cancellation")
    func invalidatedFlight() async throws {
        let cache = CustomToolCapabilityCache()
        let key = customCapabilityKey()
        let gate = CustomCapabilityProbeGate()
        let first = Task { try await cache.mode(for: key) { await gate.probe() } }
        await gate.waitForStart()
        await cache.invalidate(providerIDs: [key.providerID])
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(try await cache.mode(for: key) { .functionEnvelope } == .functionEnvelope)
        await gate.release()
        try await waitForCustomCache(cache, probes: 0)
        #expect(try await cache.mode(for: key) { .native } == .functionEnvelope)
    }

    @Test("A cancelled last waiter fences its result and holds capacity until its job exits")
    func cancelledFlight() async throws {
        let cache = CustomToolCapabilityCache(maximumConcurrentProbes: 1)
        let key = customCapabilityKey()
        let gate = CustomCapabilityProbeGate()
        let first = Task { try await cache.mode(for: key) { await gate.probe() } }
        await gate.waitForStart()
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(try await cache.mode(for: key) { .functionEnvelope } == .inconclusive)
        await gate.release()
        try await waitForCustomCache(cache, probes: 0)
        #expect(try await cache.mode(for: key) { .functionEnvelope } == .functionEnvelope)
    }

    @Test("An already cancelled caller cannot read a cached result")
    func cancelledCacheHit() async throws {
        let cache = CustomToolCapabilityCache()
        let key = customCapabilityKey()
        _ = try await cache.mode(for: key) { .native }
        let gate = CustomCapabilityProbeGate()
        let task = Task {
            _ = await gate.probe()
            return try await cache.mode(for: key) { .functionEnvelope }
        }
        await gate.waitForStart()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("Cancellation in the completion window cannot install evidence")
    func cancellationDuringCompletion() async throws {
        let clock = CustomCapabilityCancellationClock()
        let cache = CustomToolCapabilityCache { clock.now() }
        let key = customCapabilityKey()
        let gate = CustomCapabilityProbeGate()
        let task = Task { try await cache.mode(for: key) { await gate.probe() } }
        await gate.waitForStart()
        clock.cancelOnRead(task)
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await cache.mode(for: key) { .functionEnvelope } == .functionEnvelope)
    }
}

private final class CustomCapabilityCancellationClock: Sendable {
    private let task = OSAllocatedUnfairLock<Task<CustomToolCapabilityMode, any Error>?>(initialState: nil)

    func cancelOnRead(_ value: Task<CustomToolCapabilityMode, any Error>) { task.withLock { $0 = value } }

    func now() -> Date {
        task.withLock { $0 }?.cancel()
        return Date(timeIntervalSince1970: 1_700_000_000)
    }
}

actor CustomCapabilityProbeGate {
    private var started = false
    private var open = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var resultWaiter: CheckedContinuation<CustomToolCapabilityMode, Never>?

    func probe() async -> CustomToolCapabilityMode {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        if open { return .native }
        return await withCheckedContinuation { resultWaiter = $0 }
    }

    func waitForStart() async {
        if !started { await withCheckedContinuation { startWaiter = $0 } }
    }

    func release() {
        open = true
        resultWaiter?.resume(returning: .native)
        resultWaiter = nil
    }
}

private func waitForCustomCache(
    _ cache: CustomToolCapabilityCache,
    waiters: Int? = nil,
    probes: Int? = nil
) async throws {
    for _ in 0..<10_000 {
        let currentWaiters = await cache.waiterCount
        let currentProbes = await cache.activeProbeCount
        let waiterMatches = waiters == nil || currentWaiters == waiters
        let probeMatches = probes == nil || currentProbes == probes
        if waiterMatches && probeMatches { return }
        await Task.yield()
    }
    Issue.record("The capability cache did not reach the expected state")
    throw CancellationError()
}
