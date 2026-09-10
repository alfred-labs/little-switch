import Foundation
import Testing

struct AsyncTestTimeout: Error, Equatable, Sendable, CustomStringConvertible {
    let operation: String

    var description: String {
        "Timed out waiting for \(operation)"
    }
}

private enum AsyncTestRace<Value: Sendable>: Sendable {
    case value(Value)
    case timedOut
}

func eventually<Value: Sendable>(
    timeout: Duration = .seconds(5),
    description: String,
    probe: @escaping @Sendable () async throws -> Value?
) async throws -> Value {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while true {
        try Task.checkCancellation()
        if let value = try await probe() {
            return value
        }
        guard clock.now < deadline else {
            throw AsyncTestTimeout(operation: description)
        }
        await Task.yield()
    }
}

func withAsyncTestTimeout<Value: Sendable>(
    _ timeout: Duration = .seconds(5),
    description: String,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: AsyncTestRace<Value>.self) { group in
        group.addTask {
            .value(try await operation())
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            return .timedOut
        }
        defer { group.cancelAll() }

        guard let first = try await group.next() else {
            throw CancellationError()
        }
        switch first {
        case .value(let value):
            return value
        case .timedOut:
            throw AsyncTestTimeout(operation: description)
        }
    }
}

func valueWithinTimeout<Value: Sendable>(
    _ task: Task<Value, Never>,
    timeout: Duration = .seconds(5),
    description: String
) async throws -> Value {
    try await withThrowingTaskGroup(of: AsyncTestRace<Value>.self) { group in
        group.addTask {
            .value(await task.value)
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            return .timedOut
        }
        defer { group.cancelAll() }

        guard let first = try await group.next() else {
            task.cancel()
            throw CancellationError()
        }
        switch first {
        case .value(let value):
            return value
        case .timedOut:
            task.cancel()
            throw AsyncTestTimeout(operation: description)
        }
    }
}

func valueWithinTimeout<Value: Sendable>(
    _ task: Task<Value, any Error>,
    timeout: Duration = .seconds(5),
    description: String
) async throws -> Value {
    try await withThrowingTaskGroup(of: AsyncTestRace<Value>.self) { group in
        group.addTask {
            .value(try await task.value)
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            return .timedOut
        }
        defer { group.cancelAll() }

        guard let first = try await group.next() else {
            task.cancel()
            throw CancellationError()
        }
        switch first {
        case .value(let value):
            return value
        case .timedOut:
            task.cancel()
            throw AsyncTestTimeout(operation: description)
        }
    }
}

actor AsyncTestGate {
    private var isOpen = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters.values
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    func wait() async throws {
        try Task.checkCancellation()
        guard !isOpen else { return }
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isOpen || Task.isCancelled {
                    continuation.resume()
                } else {
                    waiters[waiterID] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        }
        try Task.checkCancellation()
    }

    func wait(
        timeout: Duration = .seconds(5),
        description: String
    ) async throws {
        try await withAsyncTestTimeout(timeout, description: description) {
            try await self.wait()
        }
    }

    private func cancelWaiter(_ waiterID: UUID) {
        waiters.removeValue(forKey: waiterID)?.resume()
    }
}

@Suite("Core async test support")
struct CoreAsyncTestSupportTests {
    @Test("Gates remember early release and cancel timed-out waiters")
    func gateReleaseAndTimeout() async throws {
        let opened = AsyncTestGate()
        await opened.open()
        try await opened.wait(
            timeout: .milliseconds(10),
            description: "an already-open gate"
        )

        let blocked = AsyncTestGate()
        await #expect(throws: AsyncTestTimeout.self) {
            try await blocked.wait(
                timeout: .milliseconds(1),
                description: "a blocked gate"
            )
        }
    }

    @Test("A task-value timeout cancels its target")
    func taskTimeoutCancelsTarget() async {
        let blocked = AsyncTestGate()
        let task = Task {
            do {
                try await blocked.wait()
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }

        await #expect(throws: AsyncTestTimeout.self) {
            _ = try await valueWithinTimeout(
                task,
                timeout: .milliseconds(1),
                description: "a blocked task"
            )
        }
        #expect(await task.value)
    }
}

/// A fresh throwaway directory per test — the single shared replacement for
/// the private per-file copies that drifted through the persistence suites.
func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
