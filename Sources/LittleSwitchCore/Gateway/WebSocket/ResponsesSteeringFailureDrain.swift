import Foundation

/// The connection's run owner owns this bounded drain, never its transport
/// callback or the task submitting a steer. Teardown cancels it without writes.
enum ResponsesSteeringFailureDrain {
    static func run(
        _ failures: [ResponsesUpstreamSteeringFailure],
        clock: ResponsesUpstreamClock,
        timeout: Duration,
        stop: AsyncStream<Void>,
        send: @escaping @Sendable (Data) async throws -> Void
    ) async throws {
        guard !failures.isEmpty else { return }
        try Task.checkCancellation()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for failure in failures {
                    try Task.checkCancellation()
                    try await send(failure.encoded())
                }
            }
            group.addTask {
                try await clock.sleep(until: clock.now.advanced(by: timeout))
                throw CancellationError()
            }
            group.addTask {
                for await _ in stop { break }
                throw CancellationError()
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }
}
