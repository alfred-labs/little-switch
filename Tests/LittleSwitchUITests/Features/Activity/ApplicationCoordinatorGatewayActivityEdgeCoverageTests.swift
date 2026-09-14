import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
extension CoordinatorGatewayActivityTests {
    @Test("Concurrent recovery retries after another caller starts dead-server cleanup")
    func concurrentDeadServerRecovery() async throws {
        let fixture = gatewayActivityFixture()
        let deadServer = ControllableGatewayActivityServer(
            suspendsStop: true,
            suspendsLiveness: true
        )
        let replacementServer = ControllableGatewayActivityServer()
        let builder = SequenceGatewayActivityBuilder(
            servers: [deadServer, replacementServer]
        )
        let coordinator = makeGatewayActivityCoordinator(builder: builder)
        try await coordinator.startGateway(snapshot: fixture.snapshot)
        await deadServer.fail()

        let firstRecovery = Task {
            try await coordinator.startGateway(snapshot: fixture.snapshot)
        }
        let secondRecovery = Task {
            try await coordinator.startGateway(snapshot: fixture.snapshot)
        }
        defer {
            firstRecovery.cancel()
            secondRecovery.cancel()
            Task {
                await deadServer.releaseLiveness()
                await deadServer.releaseStop()
            }
        }

        _ = try await eventually(
            description: "both recovery liveness checks"
        ) {
            await deadServer.livenessCheckCount == 2 ? true : nil
        }
        await deadServer.releaseLiveness()
        try await deadServer.waitUntilStopWasCalled()
        await deadServer.releaseStop()

        _ = try await valueWithinTimeout(
            firstRecovery,
            description: "first concurrent gateway recovery"
        )
        _ = try await valueWithinTimeout(
            secondRecovery,
            description: "second concurrent gateway recovery"
        )
        #expect(builder.makeCount == 2)
        #expect(await replacementServer.startCount == 1)
        await coordinator.stopGateway()
    }

    @Test("An explicit stop cancels recovery suspended in dead-server cleanup")
    func stopDuringDeadServerCleanup() async throws {
        let fixture = gatewayActivityFixture()
        let deadServer = ControllableGatewayActivityServer(suspendsStop: true)
        let replacementServer = ControllableGatewayActivityServer()
        let builder = SequenceGatewayActivityBuilder(
            servers: [deadServer, replacementServer]
        )
        let startupObserver = StopSignalGatewayStartupObserver()
        let coordinator = makeGatewayActivityCoordinator(
            builder: builder,
            startupObserver: startupObserver
        )
        try await coordinator.startGateway(snapshot: fixture.snapshot)
        await deadServer.fail()

        let recovery = Task {
            try await coordinator.startGateway(snapshot: fixture.snapshot)
        }
        defer {
            recovery.cancel()
            Task { await deadServer.releaseStop() }
        }
        try await deadServer.waitUntilStopWasCalled()

        let explicitStop = Task { await coordinator.stopGateway() }
        try await startupObserver.waitUntilStoppingAbandonedStartup()
        await deadServer.releaseStop()
        _ = try await valueWithinTimeout(
            explicitStop,
            description: "explicit stop during dead-server cleanup"
        )

        await #expect(throws: CancellationError.self) {
            _ = try await recovery.value
        }
        #expect(builder.makeCount == 1)
        #expect(await coordinator.gatewayActivity() == .unavailable)
    }

    @Test("Provider updates reach a gateway state whose server is still starting")
    func providerUpdateDuringGatewayStartup() async throws {
        let fixture = gatewayActivityFixture()
        let server = SuspendedStartGatewayServer()
        let coordinator = makeGatewayActivityCoordinator(
            state: fixture.state,
            server: server
        )
        let startup = Task {
            try await coordinator.startGateway(snapshot: fixture.snapshot)
        }
        defer {
            startup.cancel()
            Task { await server.releaseStart() }
        }
        try await server.waitUntilStartWasCalled()

        let saved = try await coordinator.saveProvider(
            ProviderInput(
                name: "Added during startup",
                baseURL: "https://example.com",
                authMode: .none
            )
        )
        let addedID = try #require(saved.configuration.providers.first?.id)
        let capture = await fixture.state.routingCapture()
        #expect(capture.snapshot.providers.map(\.id) == [addedID])

        await server.releaseStart()
        _ = try await valueWithinTimeout(
            startup,
            description: "gateway startup after provider update"
        )
        await coordinator.stopGateway()
    }

    @Test("A published state mirrored by startup is replaced only once")
    func identicalPublishedAndStartupStateReplacement() async throws {
        let fixture = gatewayActivityFixture()
        let coordinator = makeGatewayActivityCoordinator(
            state: fixture.state,
            server: TestGatewayServer()
        )
        try await coordinator.startGateway(snapshot: fixture.snapshot)
        defer {
            Task {
                await coordinator.clearMirroredStartupForEdgeCoverage()
                await coordinator.stopGateway()
            }
        }
        let generationBefore = await fixture.state.routingCapture().snapshot.generation

        let startupState = try await coordinator.mirrorPublishedStateAsStartupForEdgeCoverage()
        #expect(startupState === fixture.state)
        await coordinator.replaceGatewayRoutingIfNeeded()

        let generationAfter = await fixture.state.routingCapture().snapshot.generation
        #expect(generationAfter == generationBefore + 1)
        await coordinator.clearMirroredStartupForEdgeCoverage()
        await coordinator.stopGateway()
    }
}
