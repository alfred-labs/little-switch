import Atomics
import Foundation

/// Shared manual time for resolver, image-cache and WebSocket tests. Clock.now
/// is synchronous; its scalar snapshot is atomic, while an actor owns all
/// advances and sleeper continuations. No lock or unchecked conformance.
final class ResolverTestClock: Clock, Sendable {
    struct Instant: InstantProtocol, Hashable {
        let offset: Duration
        func advanced(by duration: Duration) -> Self { Self(offset: offset + duration) }
        func duration(to other: Self) -> Duration { other.offset - offset }
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.offset < rhs.offset }
    }

    private let nanoseconds: ManagedAtomic<Int64>
    private let sleepers: ResolverClockSleepers

    init(milliseconds: UInt64 = 0) {
        let value = ManagedAtomic<Int64>(Int64(milliseconds) * 1_000_000)
        nanoseconds = value
        sleepers = ResolverClockSleepers(nanoseconds: value)
    }

    var now: Instant { Instant(offset: .nanoseconds(nanoseconds.load(ordering: .sequentiallyConsistent))) }
    var minimumResolution: Duration { .nanoseconds(1) }
    func nowMilliseconds() -> UInt64 { UInt64(nanoseconds.load(ordering: .sequentiallyConsistent)) / 1_000_000 }

    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        try await sleepers.sleep(until: deadline)
    }

    func advance(by delta: UInt64) async { await advance(by: .milliseconds(delta)) }

    func advance(by delta: Duration) async {
        precondition(delta >= .zero)
        let components = delta.components
        await sleepers.advance(nanoseconds: components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000)
    }

    func waitForSleeps(_ count: Int) async throws { try await sleepers.waitForSleeps(count) }
    var deadlines: [Instant] { get async { await sleepers.deadlines } }
    var pendingSleeps: Int { get async { await sleepers.pendingCount } }
}

private actor ResolverClockSleepers {
    private let nanoseconds: ManagedAtomic<Int64>
    private var waiters: [UUID: (ResolverTestClock.Instant, CheckedContinuation<Void, any Error>)] = [:]
    private var observers: [UUID: (count: Int, continuation: AsyncStream<Void>.Continuation)] = [:]
    private(set) var deadlines: [ResolverTestClock.Instant] = []
    var pendingCount: Int { waiters.count }

    init(nanoseconds: ManagedAtomic<Int64>) { self.nanoseconds = nanoseconds }

    func sleep(until deadline: ResolverTestClock.Instant) async throws {
        try Task.checkCancellation()
        let identifier = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if deadline.offset <= .nanoseconds(nanoseconds.load(ordering: .sequentiallyConsistent)) {
                    continuation.resume()
                } else {
                    waiters[identifier] = (deadline, continuation)
                }
                // Publish registration without an actor hop: readiness must
                // never become visible before this continuation is installed.
                deadlines.append(deadline)
                for observer in observers.keys.filter({ observers[$0].map { $0.count <= deadlines.count } ?? false }) {
                    observers.removeValue(forKey: observer)?.continuation.finish()
                }
            }
        } onCancel: {
            Task { await self.cancel(identifier) }
        }
        try Task.checkCancellation()
    }

    func advance(nanoseconds delta: Int64) {
        let now = Duration.nanoseconds(
            nanoseconds.wrappingIncrementThenLoad(by: delta, ordering: .sequentiallyConsistent))
        for identifier in waiters.keys.filter({ waiters[$0].map { $0.0.offset <= now } ?? false }) {
            waiters.removeValue(forKey: identifier)?.1.resume()
        }
    }

    func waitForSleeps(_ count: Int) async throws {
        try Task.checkCancellation()
        guard deadlines.count < count else { return }
        let identifier = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[identifier] = (count, continuation)
        defer { observers.removeValue(forKey: identifier)?.continuation.finish() }
        for await _ in stream {}
        try Task.checkCancellation()
    }

    private func cancel(_ identifier: UUID) {
        waiters.removeValue(forKey: identifier)?.1.resume(throwing: CancellationError())
    }
}
