import Foundation

/// Each caller owns its wait independently of the connection's lifetime.
actor ResponsesUpstreamReadiness {
    private var result: Result<Void, any Error>?
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

    func wait() async throws {
        try Task.checkCancellation()
        if let result {
            try result.get()
            return
        }
        let identifier = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
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
    }

    func resolve(_ result: Result<Void, any Error>) {
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
