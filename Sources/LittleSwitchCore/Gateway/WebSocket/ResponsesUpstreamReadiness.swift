import Foundation

/// Each caller owns its wait independently of the connection's lifetime.
actor ResponsesUpstreamReadiness<Value: Sendable> {
    private var result: Result<Value, any Error>?
    private var waiters: [UUID: CheckedContinuation<Value, any Error>] = [:]

    func wait() async throws -> Value {
        try Task.checkCancellation()
        if let result {
            return try result.get()
        }
        let identifier = UUID()
        let value = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if let result {
                    continuation.resume(with: result)
                } else {
                    waiters[identifier] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(identifier) }
        }
        try Task.checkCancellation()
        return value
    }

    func resolve(_ result: Result<Value, any Error>) {
        guard self.result == nil else { return }
        self.result = result
        let pending = waiters.values
        waiters.removeAll()
        for waiter in pending { waiter.resume(with: result) }
    }

    private func cancel(_ identifier: UUID) {
        waiters.removeValue(forKey: identifier)?.resume(throwing: CancellationError())
    }
}
