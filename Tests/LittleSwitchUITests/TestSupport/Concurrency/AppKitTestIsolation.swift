import Foundation
import Testing

/// AppKit's key window and application state belong to the whole test process.
/// Hold this shared lease across suspension points only for suites that use them.
struct AppKitTestIsolation: TestTrait, SuiteTrait, TestScoping {
    typealias TestScopeProvider = Self

    private static let lease = AppKitTestLease()

    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await Self.lease.withLease(performing: function)
    }
}

extension Trait where Self == AppKitTestIsolation {
    static var appKitIsolation: Self { Self() }
}

actor AppKitTestLease {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var isHeld = false
    private var waiters: [Waiter] = []

    var waitingCount: Int { waiters.count }

    func withLease(performing operation: @Sendable () async throws -> Void) async throws {
        try await acquire()
        do {
            // Cancellation can race with a queued waiter's acquisition.
            try Task.checkCancellation()
            try await operation()
        } catch {
            release()
            throw error
        }
        release()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        guard isHeld else {
            isHeld = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isHeld = false
            return
        }
        waiters.removeFirst().continuation.resume()
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
