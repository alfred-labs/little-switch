import Foundation

/// One generation can be invalidated synchronously by its connection owner.
/// The sole monitor joins the obsolete sleep before observing its replacement,
/// even when the replacement expires earlier rather than later.
struct ResponsesSteeringDeadline: Sendable {
    enum Kind: Sendable { case acknowledgement, continuation }

    struct Budget: Sendable {
        let kind: Kind
        let remaining: Duration
    }

    let identifier = UUID()
    let kind: Kind
    let instant: ResponsesUpstreamClock.Instant
    private let invalidation = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

    func invalidate() { invalidation.continuation.finish() }

    func wait(clock: ResponsesUpstreamClock) async throws -> Bool {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                try await clock.sleep(until: instant)
                try Task.checkCancellation()
                return true
            }
            group.addTask {
                for await _ in invalidation.stream {}
                try Task.checkCancellation()
                return false
            }
            defer { group.cancelAll() }
            return try await group.next() ?? false
        }
    }
}
