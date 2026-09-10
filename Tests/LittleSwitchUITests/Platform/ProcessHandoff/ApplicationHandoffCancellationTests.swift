import Darwin
import Foundation
import Testing

@testable import LittleSwitchUI

@Suite("Application handoff cancellation")
struct ApplicationHandoffTestsCancellation {
    @Test("Cancellation while polling propagates from the timing boundary")
    func cancellationDuringSleep() async throws {
        let current = identity(pid: 20, launchedAt: 20)
        let timing = SuspendingHandoffTiming()
        let coordinator = ApplicationHandoffCoordinator(
            current: current,
            discovery: ScriptedProcessDiscovery([[current]]),
            signaler: RecordingProcessSignaler(),
            timing: timing,
            policy: ApplicationHandoffPolicy(requiredEmptySnapshots: 2)
        )
        let task = Task {
            try await coordinator.acquireOwnership()
        }

        try await timing.waitUntilSleeping()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("Cancellation is observed when a timing adapter returns from sleep")
    func cancellationAfterNonThrowingSleep() async {
        let current = identity(pid: 20, launchedAt: 20)
        let coordinator = ApplicationHandoffCoordinator(
            current: current,
            discovery: ScriptedProcessDiscovery([[current]]),
            signaler: RecordingProcessSignaler(),
            timing: CancellingHandoffTiming(),
            policy: ApplicationHandoffPolicy(requiredEmptySnapshots: 2)
        )
        let task = Task {
            try await coordinator.acquireOwnership()
        }

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("Cancellation during discovery prevents every process signal")
    func cancellationDuringDiscovery() async throws {
        let older = identity(pid: 10, launchedAt: 10)
        let current = identity(pid: 20, launchedAt: 20)
        let discovery = SuspendingProcessDiscovery([older, current])
        let signaler = RecordingProcessSignaler()
        let coordinator = ApplicationHandoffCoordinator(
            current: current,
            discovery: discovery,
            signaler: signaler,
            timing: VirtualHandoffTiming(),
            policy: testPolicy
        )
        let task = Task {
            try await coordinator.acquireOwnership()
        }

        try await discovery.waitUntilRequested()
        task.cancel()
        await discovery.resume()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await signaler.calls.isEmpty)
    }

    @Test("Cancellation from a signal stops before another timing read")
    func cancellationFromSignalerStopsImmediately() async {
        let older = identity(pid: 10, launchedAt: 10)
        let current = identity(pid: 20, launchedAt: 20)
        let timing = CountingHandoffTiming()
        let signaler = CancellingProcessSignaler()
        let coordinator = ApplicationHandoffCoordinator(
            current: current,
            discovery: ScriptedProcessDiscovery([[older, current]]),
            signaler: signaler,
            timing: timing,
            policy: testPolicy
        )
        let task = Task {
            try await coordinator.acquireOwnership()
        }

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await signaler.calls == [SignalCall(signal: .handoff, identity: older)])
        #expect(await timing.readCount == 1)
    }

    @Test("Cancellation during the kill deadline check wins over timeout")
    func cancellationDuringDeadlineCheck() async throws {
        let older = identity(pid: 10, launchedAt: 10)
        let current = identity(pid: 20, launchedAt: 20)
        let timing = SuspendingDeadlineHandoffTiming()
        let coordinator = ApplicationHandoffCoordinator(
            current: current,
            discovery: ScriptedProcessDiscovery([[older, current]]),
            signaler: RecordingProcessSignaler(),
            timing: timing,
            policy: ApplicationHandoffPolicy(
                handoffTimeout: .zero,
                terminateTimeout: .zero,
                killTimeout: .zero,
                pollInterval: .seconds(1)
            )
        )
        let task = Task {
            try await coordinator.acquireOwnership()
        }

        try await timing.waitUntilDeadlineCheck()
        task.cancel()
        await timing.resume()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("Cancellation during identity validation prevents the POSIX signal")
    func cancellationDuringIdentityLookup() async throws {
        let expected = identity(pid: 42, launchedAt: 10)
        let lookup = SuspendingIdentityLookup(expected)
        let sent = SentSignalRecorder()
        let signaler = POSIXApplicationProcessSignaler(
            identityForPID: { pid in await lookup.identity(for: pid) },
            sendSignal: { pid, signal in
                sent.record(pid: pid, signal: signal)
                return 0
            }
        )
        let task = Task {
            await signaler.send(.terminate, to: expected)
        }

        try await lookup.waitUntilRequested()
        task.cancel()
        await lookup.resume()
        await task.value

        #expect(sent.calls.isEmpty)
    }

    private var testPolicy: ApplicationHandoffPolicy {
        ApplicationHandoffPolicy(
            handoffTimeout: .seconds(1),
            terminateTimeout: .seconds(1),
            killTimeout: .seconds(1),
            pollInterval: .seconds(1),
            requiredEmptySnapshots: 2
        )
    }

    private func identity(pid: pid_t, launchedAt: TimeInterval) -> ApplicationProcessIdentity {
        ApplicationProcessIdentity(
            processIdentifier: pid,
            launchDate: Date(timeIntervalSinceReferenceDate: launchedAt)
        )
    }
}
