import Testing

@Suite("AppKit test isolation")
struct AppKitTestIsolationTests {
    @Test("A throwing scope releases its AppKit lease")
    func throwingScopeReleasesLease() async throws {
        let lease = AppKitTestLease()
        await #expect(throws: TestFailure.self) {
            try await lease.withLease { throw TestFailure.expected }
        }
        try await withAsyncTestTimeout(description: "the AppKit lease after a throwing scope") {
            try await lease.withLease {}
        }
    }

    @Test("Cancellation removes a queued scope without entering or releasing another scope's lease")
    func cancelledWaiterPreservesHolder() async throws {
        let lease = AppKitTestLease()
        let entered = AsyncTestGate()
        let unblock = AsyncTestGate()
        let holder = Task {
            try await lease.withLease {
                await entered.open()
                try await unblock.wait()
            }
        }
        defer { holder.cancel() }
        try await entered.wait(description: "the first AppKit scope")

        let cancelled = Task {
            try await lease.withLease {
                Issue.record("A cancelled AppKit scope must not run")
            }
        }
        defer { cancelled.cancel() }
        try await expectWaiter(in: lease)
        cancelled.cancel()
        await #expect(throws: CancellationError.self) {
            try await valueWithinTimeout(cancelled, description: "the cancelled AppKit scope")
        }
        #expect(await lease.waitingCount == 0)

        let successor = Task { try await lease.withLease {} }
        defer { successor.cancel() }
        try await expectWaiter(in: lease)
        await unblock.open()
        try await valueWithinTimeout(holder, description: "the first AppKit scope's release")
        try await valueWithinTimeout(successor, description: "the following AppKit scope")
    }

    @Test("Cancellation inside a scope releases its AppKit lease")
    func cancelledHolderReleasesLease() async throws {
        let lease = AppKitTestLease()
        let entered = AsyncTestGate()
        let blocked = AsyncTestGate()
        let holder = Task {
            try await lease.withLease {
                await entered.open()
                try await blocked.wait()
            }
        }
        defer { holder.cancel() }
        try await entered.wait(description: "the cancellable AppKit scope")
        holder.cancel()
        await #expect(throws: CancellationError.self) {
            try await valueWithinTimeout(holder, description: "cancellation inside the AppKit scope")
        }
        try await withAsyncTestTimeout(description: "the AppKit lease after cancellation") {
            try await lease.withLease {}
        }
    }

    private func expectWaiter(in lease: AppKitTestLease) async throws {
        _ = try await eventually(description: "an AppKit scope waiting for the occupied lease") {
            await lease.waitingCount == 1 ? true : nil
        }
    }

    private enum TestFailure: Error {
        case expected
    }
}
