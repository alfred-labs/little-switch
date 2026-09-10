import Darwin
import Foundation
import Testing

@testable import LittleSwitchUI

@Suite("Application handoff")
struct ApplicationHandoffTests {
    @Test("Process identities order by launch date and then PID")
    func processIdentityOrdering() {
        let first = identity(pid: 30, launchedAt: 10)
        let sameLaunchLowerPID = identity(pid: 10, launchedAt: 20)
        let sameLaunchHigherPID = identity(pid: 20, launchedAt: 20)

        #expect(first < sameLaunchLowerPID)
        #expect(sameLaunchLowerPID < sameLaunchHigherPID)
        #expect(!(sameLaunchHigherPID < sameLaunchLowerPID))
    }

    @Test("A handoff termination request cannot be downgraded to user quit")
    func handoffTerminationIsSticky() {
        var state = ApplicationTerminationState()

        #expect(state.mode == .userQuit)
        state.request(.userQuit)
        state.request(.userQuit)
        state.request(.handoff)
        state.request(.handoff)
        state.request(.userQuit)

        #expect(state.mode == .handoff)
    }

    @Test("Zero required empty snapshots normalizes to one")
    func zeroRequiredSnapshotsNormalizesToOne() async throws {
        let current = identity(pid: 20, launchedAt: 20)
        let discovery = ScriptedProcessDiscovery([[current]])
        let coordinator = ApplicationHandoffCoordinator(
            current: current,
            discovery: discovery,
            signaler: RecordingProcessSignaler(),
            timing: VirtualHandoffTiming(),
            policy: ApplicationHandoffPolicy(requiredEmptySnapshots: 0)
        )

        #expect(try await coordinator.acquireOwnership() == .owner)
        #expect(await discovery.readCount == 1)
    }

    @Test("The newest process asks older instances to hand off and confirms ownership")
    func newestProcessTakesOwnership() async throws {
        let older = identity(pid: 10, launchedAt: 10)
        let current = identity(pid: 20, launchedAt: 20)
        let discovery = ScriptedProcessDiscovery([
            [older, current],
            [current],
            [current],
        ])
        let signaler = RecordingProcessSignaler()
        let timing = VirtualHandoffTiming()
        let coordinator = ApplicationHandoffCoordinator(
            current: current,
            discovery: discovery,
            signaler: signaler,
            timing: timing,
            policy: testPolicy
        )

        let outcome = try await coordinator.acquireOwnership()

        #expect(outcome == .owner)
        #expect(await signaler.calls == [SignalCall(signal: .handoff, identity: older)])
        #expect(await discovery.readCount == 3)
    }

    @Test("An older launch relinquishes ownership to a newer process")
    func olderProcessRelinquishesOwnership() async throws {
        let current = identity(pid: 10, launchedAt: 10)
        let newer = identity(pid: 20, launchedAt: 20)
        let discovery = ScriptedProcessDiscovery([[current, newer]])
        let signaler = RecordingProcessSignaler()
        let coordinator = ApplicationHandoffCoordinator(
            current: current,
            discovery: discovery,
            signaler: signaler,
            timing: VirtualHandoffTiming(),
            policy: testPolicy
        )

        let outcome = try await coordinator.acquireOwnership()

        #expect(outcome == .superseded)
        #expect(await signaler.calls.isEmpty)
    }

    @Test("A stuck older process receives each bounded escalation once")
    func escalationIsBounded() async throws {
        let older = identity(pid: 10, launchedAt: 10)
        let current = identity(pid: 20, launchedAt: 20)
        let discovery = ScriptedProcessDiscovery([[older, current]])
        let signaler = RecordingProcessSignaler()
        let coordinator = ApplicationHandoffCoordinator(
            current: current,
            discovery: discovery,
            signaler: signaler,
            timing: VirtualHandoffTiming(),
            policy: testPolicy
        )

        await #expect(throws: ApplicationHandoffError.timedOut([older])) {
            _ = try await coordinator.acquireOwnership()
        }
        #expect(
            await signaler.calls == [
                SignalCall(signal: .handoff, identity: older),
                SignalCall(signal: .terminate, identity: older),
                SignalCall(signal: .kill, identity: older),
            ]
        )
    }

    @Test("Each escalation stage deduplicates signals and times out with current identities")
    func stageTransitionsTrackRediscovery() async throws {
        let oldest = identity(pid: 10, launchedAt: 10)
        let rediscovered = identity(pid: 11, launchedAt: 11)
        let current = identity(pid: 20, launchedAt: 20)
        let discovery = ScriptedProcessDiscovery([
            [oldest, current],
            [oldest, rediscovered, current],
            [oldest, rediscovered, current],
            [rediscovered, current],
            [oldest, rediscovered, current],
            [rediscovered, current],
        ])
        let signaler = RecordingProcessSignaler()
        let coordinator = ApplicationHandoffCoordinator(
            current: current,
            discovery: discovery,
            signaler: signaler,
            timing: VirtualHandoffTiming(),
            policy: testPolicy
        )

        await #expect(throws: ApplicationHandoffError.timedOut([rediscovered])) {
            _ = try await coordinator.acquireOwnership()
        }
        #expect(
            await signaler.calls == [
                SignalCall(signal: .handoff, identity: oldest),
                SignalCall(signal: .handoff, identity: rediscovered),
                SignalCall(signal: .terminate, identity: oldest),
                SignalCall(signal: .terminate, identity: rediscovered),
                SignalCall(signal: .kill, identity: oldest),
                SignalCall(signal: .kill, identity: rediscovered),
            ]
        )
    }

    @Test("Exact identity validation prevents signalling a recycled PID")
    func recycledPIDIsNotSignalled() async {
        let expected = identity(pid: 42, launchedAt: 10)
        let recycled = identity(pid: 42, launchedAt: 30)
        let sent = SentSignalRecorder()
        let signaler = POSIXApplicationProcessSignaler(
            identityForPID: { _ in recycled },
            sendSignal: { pid, signal in
                sent.record(pid: pid, signal: signal)
                return 0
            }
        )

        await signaler.send(.kill, to: expected)

        #expect(sent.calls.isEmpty)
    }

    @Test("Exact identity validation delivers the requested POSIX signal")
    func exactIdentityIsSignalled() async {
        let expected = identity(pid: 42, launchedAt: 10)
        let sent = SentSignalRecorder()
        let signaler = POSIXApplicationProcessSignaler(
            identityForPID: { _ in expected },
            sendSignal: { pid, signal in
                sent.record(pid: pid, signal: signal)
                return 0
            }
        )

        await signaler.send(.terminate, to: expected)

        #expect(sent.calls.count == 1)
        #expect(sent.calls.first?.0 == expected.processIdentifier)
        #expect(sent.calls.first?.1 == SIGTERM)
    }

    @Test("Injected POSIX signal failures are safely ignored")
    func signalFailureIsIgnored() async {
        let expected = identity(pid: 42, launchedAt: 10)
        let sent = SentSignalRecorder()
        let signaler = POSIXApplicationProcessSignaler(
            identityForPID: { _ in expected },
            sendSignal: { pid, signal in
                sent.record(pid: pid, signal: signal)
                return -1
            }
        )

        await signaler.send(.handoff, to: expected)
        await signaler.send(.kill, to: expected)

        #expect(sent.calls.map(\.0) == [expected.processIdentifier, expected.processIdentifier])
        #expect(sent.calls.map(\.1) == [SIGUSR1, SIGKILL])
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
