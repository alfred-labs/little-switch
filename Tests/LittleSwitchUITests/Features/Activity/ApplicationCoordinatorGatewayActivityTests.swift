import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application coordinator gateway activity")
struct CoordinatorGatewayActivityTests {
    @Test("Initial provider refresh remains a starting gateway activity")
    func initialProviderRefresh() async throws {
        let fixture = gatewayActivityFixture()
        let discoveryTransport = SuspendedCatalogTransport()
        let server = TestGatewayServer()
        let coordinator = makeGatewayActivityCoordinator(
            configuration: AppConfiguration(providers: [fixture.provider]),
            discoveryTransport: discoveryTransport,
            state: fixture.state,
            server: server
        )
        let startup = Task {
            try await coordinator.start()
        }
        defer {
            startup.cancel()
            Task { await discoveryTransport.releaseExecute() }
        }

        try await discoveryTransport.waitUntilExecuteWasCalled()

        #expect(await coordinator.gatewayActivity() == .starting)

        await discoveryTransport.releaseExecute()
        _ = try await valueWithinTimeout(
            startup,
            description: "initial coordinator startup after discovery"
        )
        guard case .running = await coordinator.gatewayActivity() else {
            Issue.record("Expected running activity after initial startup")
            return
        }
        await coordinator.stopGateway()
    }

    @Test("Activity moves from unavailable through starting to a live pool snapshot")
    func lifecycleAndPoolSnapshot() async throws {
        let fixture = gatewayActivityFixture()
        let server = SuspendedStartGatewayServer()
        let coordinator = makeGatewayActivityCoordinator(
            state: fixture.state,
            server: server
        )

        #expect(await coordinator.gatewayActivity() == .unavailable)
        let startup = Task {
            try await coordinator.startGateway(snapshot: fixture.snapshot)
        }
        defer { startup.cancel() }
        try await server.waitUntilStartWasCalled()
        #expect(await coordinator.gatewayActivity() == .starting)
        await server.releaseStart()
        _ = try await valueWithinTimeout(
            startup,
            description: "gateway startup after its release"
        )

        let capture = await fixture.state.routingCapture()
        let activeID = UUID()
        let waitingID = UUID()
        try await fixture.state.admit(
            gatewayActivityAdmission(
                eventID: activeID,
                capture: capture,
                provider: fixture.provider
            )
        )
        let pollingUpdate = await GatewayActivityPollingUpdate.load(from: coordinator)
        #expect(pollingUpdate.requestCount == 1)
        #expect(pollingUpdate.claudeRequestCount == 1)
        #expect(pollingUpdate.codexRequestCount == 0)
        guard case .running(let pollingActivity) = pollingUpdate.activity else {
            Issue.record("Expected running polling activity")
            return
        }
        #expect(pollingActivity.totalRunning == 1)
        let waiting = Task {
            try await fixture.state.admit(
                gatewayActivityAdmission(
                    eventID: waitingID,
                    capture: capture,
                    provider: fixture.provider
                )
            )
        }
        defer { waiting.cancel() }
        let queued: ProviderRequestPoolSnapshot = try await eventually(
            description: "one active and one queued gateway request"
        ) {
            guard case .running(let activity) = await coordinator.gatewayActivity(),
                activity.totalWaiting == 1
            else {
                return nil
            }
            return activity
        }
        #expect(queued.totalRunning == 1)

        await fixture.state.finish(eventID: activeID)
        _ = try await valueWithinTimeout(
            waiting,
            description: "the queued gateway request to be admitted"
        )
        await fixture.state.finish(eventID: waitingID)
        guard case .running(let idle) = await coordinator.gatewayActivity() else {
            Issue.record("Expected idle running gateway activity")
            return
        }
        #expect(idle.totalRunning == 0)
        #expect(idle.totalWaiting == 0)

        await coordinator.stopGateway()
        #expect(await coordinator.gatewayActivity() == .unavailable)
    }

    @Test("Activity retries when the gateway stops during a suspended pool snapshot")
    func stopDuringPoolSnapshot() async throws {
        let fixture = gatewayActivityFixture()
        let pool = SuspendedSnapshotRequestPool()
        let state = GatewayState(snapshot: fixture.snapshot, requestPool: pool)
        let coordinator = makeGatewayActivityCoordinator(
            state: state,
            server: TestGatewayServer()
        )
        try await coordinator.startGateway(snapshot: fixture.snapshot)

        let activity = Task { await coordinator.gatewayActivity() }
        defer { activity.cancel() }
        try await pool.waitUntilSnapshotWasCalled()
        #expect(await pool.snapshotCallCount == 1)

        await coordinator.stopGateway()
        await pool.releaseSnapshot()

        let stopped = try await valueWithinTimeout(
            activity,
            description: "gateway activity after stop"
        )
        #expect(stopped == .unavailable)
    }

    @Test("A stop landing during the liveness check re-loops instead of answering stale")
    func stopDuringLivenessCheck() async throws {
        let fixture = gatewayActivityFixture()
        let server = ControllableGatewayActivityServer(
            suspendsStop: true,
            suspendsLiveness: true
        )
        let coordinator = makeGatewayActivityCoordinator(
            state: GatewayState(snapshot: fixture.snapshot),
            server: server
        )
        try await coordinator.startGateway(snapshot: fixture.snapshot)

        let activity = Task { await coordinator.gatewayActivity() }
        try await server.waitUntilLivenessWasChecked()

        // The stop bumps the lifecycle generation and drops the published
        // server while gatewayActivity() is suspended inside isRunning.
        // Without the generation guard this snapshot would answer .running
        // from the captured server; with it, the loop restarts and finds
        // no published gateway at all.
        let stopTask = Task { await coordinator.stopGateway() }
        try await server.waitUntilStopWasCalled()
        await server.releaseLiveness()

        let stopped = try await valueWithinTimeout(
            activity,
            description: "gateway activity after a mid-liveness stop"
        )
        #expect(stopped == .unavailable)

        await server.releaseStop()
        _ = await stopTask.result
        activity.cancel()
    }

    @Test("A dead published server is unavailable and can be replaced")
    func deadPublishedServerRecovery() async throws {
        let fixture = gatewayActivityFixture()
        let deadServer = ControllableGatewayActivityServer()
        let replacementServer = ControllableGatewayActivityServer()
        let builder = SequenceGatewayActivityBuilder(
            servers: [deadServer, replacementServer]
        )
        let coordinator = makeGatewayActivityCoordinator(builder: builder)
        try await coordinator.startGateway(snapshot: fixture.snapshot)
        await deadServer.fail()

        #expect(await coordinator.gatewayActivity() == .unavailable)

        try await coordinator.startGateway(snapshot: fixture.snapshot)
        #expect(builder.makeCount == 2)
        #expect(await deadServer.stopCount == 1)
        #expect(await replacementServer.startCount == 1)
        guard case .running = await coordinator.gatewayActivity() else {
            Issue.record("Expected running activity after replacing the dead server")
            return
        }
        await coordinator.stopGateway()
    }

    @Test("An explicit stop wins over a suspended published-server liveness check")
    func stopDuringPublishedServerLivenessCheck() async throws {
        let fixture = gatewayActivityFixture()
        let publishedServer = ControllableGatewayActivityServer(
            suspendsLiveness: true
        )
        let replacementServer = ControllableGatewayActivityServer()
        let builder = SequenceGatewayActivityBuilder(
            servers: [publishedServer, replacementServer]
        )
        let coordinator = makeGatewayActivityCoordinator(builder: builder)
        try await coordinator.startGateway(snapshot: fixture.snapshot)
        let redundantStart = Task {
            try await coordinator.startGateway(snapshot: fixture.snapshot)
        }
        defer {
            redundantStart.cancel()
            Task { await publishedServer.releaseLiveness() }
        }
        try await publishedServer.waitUntilLivenessWasChecked()

        await coordinator.stopGateway()
        await publishedServer.releaseLiveness()

        await #expect(throws: CancellationError.self) {
            try await redundantStart.value
        }
        #expect(builder.makeCount == 1)
        #expect(await coordinator.gatewayActivity() == .unavailable)
    }

}
