import AsyncHTTPClient
import Foundation
import LittleSwitchCore
import LittleSwitchTransport

@testable import LittleSwitchUI

struct GatewayActivityFixture {
    let provider: Provider
    let snapshot: RoutingSnapshot
    let state: GatewayState
}

func gatewayActivityFixture() -> GatewayActivityFixture {
    let provider = Provider(
        id: UUID(),
        name: "Queue provider",
        baseURL: "https://example.com",
        authMode: .none,
        models: [DiscoveredModel(id: "model")],
        maximumParallelRequests: 1
    )
    let snapshot = RoutingSnapshot(
        generation: 0,
        providers: [provider],
        mappings: [
            "claude-sonnet-5": ModelMapping(
                providerID: provider.id,
                modelID: "model"
            )
        ]
    )
    return GatewayActivityFixture(
        provider: provider,
        snapshot: snapshot,
        state: GatewayState(snapshot: snapshot)
    )
}

func gatewayActivityAdmission(
    eventID: UUID,
    capture: GatewayRoutingCapture,
    provider: Provider
) -> GatewayRequestAdmission {
    GatewayRequestAdmission(
        eventID: eventID,
        capture: capture,
        client: .claude,
        modelIdentifier: "claude-sonnet-5",
        providerID: provider.id,
        targetModelID: "model",
        retainedBodyBytes: 1
    )
}

@MainActor
func makeGatewayActivityCoordinator(
    configuration: AppConfiguration = AppConfiguration(),
    discoveryTransport: any UpstreamTransport = StaticCatalogTransport(),
    state: GatewayState,
    server: any GatewayServing
) -> ApplicationCoordinator {
    ApplicationCoordinator(
        configurationStore: RecordingConfigurationStore(configuration: configuration),
        secretStore: MemorySecretStore(),
        profileManager: TestClaudeProfileManager(),
        claudeController: TestClaudeController(),
        discoveryTransport: discoveryTransport,
        gatewayTransport: TestGatewayTransport(),
        gatewayServerOverride: server,
        gatewayStateOverride: state
    )
}

@MainActor
func makeGatewayActivityCoordinator(
    configuration: AppConfiguration = AppConfiguration(),
    builder: any GatewayBuilding,
    startupObserver: any GatewayStartupObserving = LiveGatewayStartupObserver()
) -> ApplicationCoordinator {
    ApplicationCoordinator(
        configurationStore: RecordingConfigurationStore(configuration: configuration),
        secretStore: MemorySecretStore(),
        profileManager: TestClaudeProfileManager(),
        claudeController: TestClaudeController(),
        discoveryTransport: StaticCatalogTransport(),
        gatewayTransportBuilder: GatewayActivityTransportBuilder(),
        gatewayFactory: LiveGatewayFactory(builder: builder),
        gatewayStartupObserver: startupObserver
    )
}

private actor GatewayActivityTransportBuilder: GatewayTransportBuilding {
    func makeTransport() async -> any UpstreamTransport {
        TestGatewayTransport()
    }
}

actor SuspendedCatalogTransport: UpstreamTransport {
    private let executeEntered = AsyncTestGate()
    private let executeReleased = AsyncTestGate()
    private let delegate = StaticCatalogTransport()

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        await executeEntered.open()
        try await executeReleased.wait()
        return try await delegate.execute(request)
    }

    func shutdown() async throws {
        try await delegate.shutdown()
    }

    func waitUntilExecuteWasCalled() async throws {
        try await executeEntered.wait(
            description: "initial provider discovery to begin"
        )
    }

    func releaseExecute() async {
        await executeReleased.open()
    }
}

final class SequenceGatewayActivityBuilder: GatewayBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private let servers: [any GatewayServing]
    private var nextServerIndex = 0

    init(servers: [any GatewayServing]) {
        precondition(!servers.isEmpty)
        self.servers = servers
    }

    var makeCount: Int {
        lock.withLock { nextServerIndex }
    }

    func makeGateway(_ context: GatewayBuildContext) -> any GatewayServing {
        _ = context
        return lock.withLock {
            let index = min(nextServerIndex, servers.count - 1)
            nextServerIndex += 1
            return servers[index]
        }
    }
}

actor ControllableGatewayActivityServer: GatewayServing {
    private let suspendsStart: Bool
    private let suspendsStop: Bool
    private let suspendsLiveness: Bool
    private let startEntered = AsyncTestGate()
    private let startReleased = AsyncTestGate()
    private let stopEntered = AsyncTestGate()
    private let stopReleased = AsyncTestGate()
    private let livenessEntered = AsyncTestGate()
    private let livenessReleased = AsyncTestGate()
    private var running = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var livenessCheckCount = 0

    init(
        suspendsStart: Bool = false,
        suspendsStop: Bool = false,
        suspendsLiveness: Bool = false
    ) {
        self.suspendsStart = suspendsStart
        self.suspendsStop = suspendsStop
        self.suspendsLiveness = suspendsLiveness
    }

    var isRunning: Bool {
        get async {
            livenessCheckCount += 1
            await livenessEntered.open()
            if suspendsLiveness {
                try? await livenessReleased.wait()
            }
            return running
        }
    }

    func start() async throws {
        startCount += 1
        await startEntered.open()
        if suspendsStart {
            try await startReleased.wait()
        }
        running = true
    }

    func stop() async {
        stopCount += 1
        await stopEntered.open()
        if suspendsStop {
            try? await stopReleased.wait()
        }
        running = false
    }

    func fail() {
        running = false
    }

    func waitUntilStartWasCalled() async throws {
        try await startEntered.wait(
            description: "replacement gateway server to start"
        )
    }

    func releaseStart() async {
        await startReleased.open()
    }

    func waitUntilStopWasCalled() async throws {
        try await stopEntered.wait(
            description: "published gateway server to stop"
        )
    }

    func releaseStop() async {
        await stopReleased.open()
    }

    func waitUntilLivenessWasChecked() async throws {
        try await livenessEntered.wait(
            description: "published gateway liveness check"
        )
    }

    func releaseLiveness() async {
        await livenessReleased.open()
    }
}

actor SuspendedStartGatewayServer: GatewayServing {
    private var running = false
    private let startEntered = AsyncTestGate()
    private let startReleased = AsyncTestGate()

    var isRunning: Bool { running }

    func start() async throws {
        await startEntered.open()
        try await startReleased.wait()
        running = true
    }

    func stop() async {
        running = false
    }

    func waitUntilStartWasCalled() async throws {
        try await startEntered.wait(
            description: "the suspended gateway server to start"
        )
    }

    func releaseStart() async {
        await startReleased.open()
    }
}

actor SuspendedSnapshotRequestPool: ProviderRequestPooling {
    private let snapshotEntered = AsyncTestGate()
    private let snapshotReleased = AsyncTestGate()
    private(set) var snapshotCallCount = 0

    func admit(_ admission: ProviderRequestAdmission) async throws {
        _ = admission
    }

    func finish(eventID: UUID) async {
        _ = eventID
    }

    func shutdown() async {}

    func reconfigure(_ configuration: ProviderRequestPoolConfiguration) async {
        _ = configuration
    }

    func snapshot() async -> ProviderRequestPoolSnapshot {
        snapshotCallCount += 1
        await snapshotEntered.open()
        try? await snapshotReleased.wait()
        return ProviderRequestPoolSnapshot(
            totalRunning: 0,
            totalWaiting: 0,
            providers: []
        )
    }

    func waitUntilSnapshotWasCalled() async throws {
        try await snapshotEntered.wait(
            description: "the suspended provider pool snapshot"
        )
    }

    func releaseSnapshot() async {
        await snapshotReleased.open()
    }
}

actor StopSignalGatewayStartupObserver: GatewayStartupObserving {
    private let stoppingEntered = AsyncTestGate()

    func joinedStartup() async {}

    func readyToPublishStartup() async {}

    func waitingForAbandonedStartupCleanup() async {}

    func cancellingStartupWaiter() async {}

    func cancelledStartupWaiter() async {}

    func stoppingAbandonedStartup() async {
        await stoppingEntered.open()
    }

    func waitUntilStoppingAbandonedStartup() async throws {
        try await stoppingEntered.wait(
            description: "explicit gateway stop to own abandoned cleanup"
        )
    }
}

enum GatewayActivityEdgeCoverageError: Error {
    case gatewayNotPublished
}

extension ApplicationCoordinator {
    func mirrorPublishedStateAsStartupForEdgeCoverage() throws -> GatewayState {
        guard let state = gatewayState, let server = gatewayServer else {
            throw GatewayActivityEdgeCoverageError.gatewayNotPublished
        }
        gatewayStartup = GatewayStartup(
            generation: gatewayLifecycleGeneration,
            state: state,
            task: Task {
                GatewayStartupResult(
                    state: state,
                    server: server,
                    transport: nil
                )
            }
        )
        return state
    }

    func clearMirroredStartupForEdgeCoverage() {
        gatewayStartup = nil
    }
}
