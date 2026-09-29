/// Erases only a clock's instant type, keeping deadlines on one monotonic
/// timeline. Sessions can pass an injected Clock without becoming generic.
package struct ResponsesUpstreamClock: Clock {
    package struct Instant: InstantProtocol {
        let offset: Duration
        package func advanced(by duration: Duration) -> Self { Self(offset: offset + duration) }
        package func duration(to other: Self) -> Duration { other.offset - offset }
        package static func < (lhs: Self, rhs: Self) -> Bool { lhs.offset < rhs.offset }
    }

    private let read: @Sendable () -> Instant
    private let suspend: @Sendable (Instant, Duration?) async throws -> Void
    package let minimumResolution: Duration
    package var now: Instant { read() }

    package init<C: Clock>(_ clock: C) where C.Duration == Duration {
        let origin = clock.now
        minimumResolution = clock.minimumResolution
        read = { Instant(offset: origin.duration(to: clock.now)) }
        suspend = { deadline, tolerance in
            try await clock.sleep(until: origin.advanced(by: deadline.offset), tolerance: tolerance)
        }
    }

    package func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        try await suspend(deadline, tolerance)
    }
}
