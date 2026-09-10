import Darwin
import Foundation

@testable import LittleSwitchUI

actor ScriptedProcessDiscovery: ApplicationProcessDiscovering {
    private let snapshots: [[ApplicationProcessIdentity]]
    private var index = 0

    init(_ snapshots: [[ApplicationProcessIdentity]]) {
        self.snapshots = snapshots
    }

    var readCount: Int {
        index
    }

    func instances() -> [ApplicationProcessIdentity] {
        let snapshot = snapshots[min(index, snapshots.count - 1)]
        index += 1
        return snapshot
    }
}

struct SignalCall: Equatable, Sendable {
    let signal: ApplicationHandoffSignal
    let identity: ApplicationProcessIdentity
}

actor RecordingProcessSignaler: ApplicationProcessSignaling {
    private(set) var calls: [SignalCall] = []

    func send(_ signal: ApplicationHandoffSignal, to identity: ApplicationProcessIdentity) {
        calls.append(SignalCall(signal: signal, identity: identity))
    }
}

actor VirtualHandoffTiming: ApplicationHandoffTiming {
    private var elapsed = Duration.zero

    func now() -> Duration {
        elapsed
    }

    func sleep(for duration: Duration) {
        elapsed += duration
    }
}

final class SentSignalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(pid_t, Int32)] = []

    var calls: [(pid_t, Int32)] {
        lock.withLock { storage }
    }

    func record(pid: pid_t, signal: Int32) {
        lock.withLock { storage.append((pid, signal)) }
    }
}

actor SuspendingProcessDiscovery: ApplicationProcessDiscovering {
    private let snapshot: [ApplicationProcessIdentity]
    private let requestEvents: AsyncStream<Void>
    private let requestContinuation: AsyncStream<Void>.Continuation
    private var resultContinuation: CheckedContinuation<[ApplicationProcessIdentity], Never>?

    init(_ snapshot: [ApplicationProcessIdentity]) {
        self.snapshot = snapshot
        (requestEvents, requestContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func instances() async -> [ApplicationProcessIdentity] {
        await withCheckedContinuation { continuation in
            resultContinuation = continuation
            requestContinuation.yield()
        }
    }

    func waitUntilRequested() async throws {
        try await waitForHandoffSignal(requestEvents, missing: .missingDiscoverySignal)
    }

    func resume() {
        resultContinuation?.resume(returning: snapshot)
        resultContinuation = nil
        requestContinuation.finish()
    }
}

actor SuspendingHandoffTiming: ApplicationHandoffTiming {
    private let sleepEvents: AsyncStream<Void>
    private let sleepEventContinuation: AsyncStream<Void>.Continuation
    private var sleepContinuation: CheckedContinuation<Void, any Error>?

    init() {
        (sleepEvents, sleepEventContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func now() -> Duration {
        .zero
    }

    func sleep(for _: Duration) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepContinuation = continuation
                sleepEventContinuation.yield()
            }
        } onCancel: {
            Task { await self.cancelSleep() }
        }
    }

    func waitUntilSleeping() async throws {
        try await waitForHandoffSignal(sleepEvents, missing: .missingSleepSignal)
    }

    private func cancelSleep() {
        sleepContinuation?.resume(throwing: CancellationError())
        sleepContinuation = nil
        sleepEventContinuation.finish()
    }
}

actor CancellingHandoffTiming: ApplicationHandoffTiming {
    private var didCancel = false

    func now() -> Duration {
        .zero
    }

    func sleep(for _: Duration) throws {
        guard !didCancel else {
            throw HandoffTestError.unexpectedRepeatedSleep
        }
        didCancel = true
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
    }
}

actor SuspendingIdentityLookup {
    private let result: ApplicationProcessIdentity?
    private let requestEvents: AsyncStream<Void>
    private let requestContinuation: AsyncStream<Void>.Continuation
    private var resultContinuation: CheckedContinuation<ApplicationProcessIdentity?, Never>?

    init(_ result: ApplicationProcessIdentity?) {
        self.result = result
        (requestEvents, requestContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func identity(for _: pid_t) async -> ApplicationProcessIdentity? {
        await withCheckedContinuation { continuation in
            resultContinuation = continuation
            requestContinuation.yield()
        }
    }

    func waitUntilRequested() async throws {
        try await waitForHandoffSignal(requestEvents, missing: .missingIdentityLookupSignal)
    }

    func resume() {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
        requestContinuation.finish()
    }
}

actor CountingHandoffTiming: ApplicationHandoffTiming {
    private(set) var readCount = 0

    func now() -> Duration {
        readCount += 1
        return .zero
    }

    func sleep(for _: Duration) throws {
        try Task.checkCancellation()
    }
}

actor CancellingProcessSignaler: ApplicationProcessSignaling {
    private(set) var calls: [SignalCall] = []

    func send(_ signal: ApplicationHandoffSignal, to identity: ApplicationProcessIdentity) {
        calls.append(SignalCall(signal: signal, identity: identity))
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
    }
}

actor SuspendingDeadlineHandoffTiming: ApplicationHandoffTiming {
    private let deadlineEvents: AsyncStream<Void>
    private let deadlineEventContinuation: AsyncStream<Void>.Continuation
    private var deadlineContinuation: CheckedContinuation<Void, Never>?
    private var readCount = 0

    init() {
        (deadlineEvents, deadlineEventContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func now() async -> Duration {
        readCount += 1
        guard readCount == 4 else { return .zero }
        await withCheckedContinuation { continuation in
            deadlineContinuation = continuation
            deadlineEventContinuation.yield()
        }
        return .zero
    }

    func sleep(for _: Duration) throws {
        throw HandoffTestError.unexpectedSleep
    }

    func waitUntilDeadlineCheck() async throws {
        try await waitForHandoffSignal(deadlineEvents, missing: .missingDeadlineSignal)
    }

    func resume() {
        deadlineContinuation?.resume()
        deadlineContinuation = nil
        deadlineEventContinuation.finish()
    }
}

private func waitForHandoffSignal(
    _ stream: AsyncStream<Void>,
    missing error: HandoffTestError
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            guard await iterator.next() != nil else { throw error }
        }
        group.addTask {
            try await Task.sleep(for: .seconds(2))
            throw HandoffTestError.timedOut
        }
        defer { group.cancelAll() }
        _ = try await group.next()
    }
}

private enum HandoffTestError: Error, Sendable {
    case missingDeadlineSignal
    case missingDiscoverySignal
    case missingIdentityLookupSignal
    case missingSleepSignal
    case timedOut
    case unexpectedSleep
    case unexpectedRepeatedSleep
}
