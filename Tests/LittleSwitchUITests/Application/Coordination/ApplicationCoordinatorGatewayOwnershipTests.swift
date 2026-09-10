import AsyncHTTPClient
import Foundation
import LittleSwitchCore
import LittleSwitchTransport
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application coordinator gateway ownership")
struct CoordinatorGatewayOwnershipTests {
    @Test("A failed server override owns its transport shutdown exactly once")
    func failedOverrideHasSingleShutdownOwner() async throws {
        let transport = CountingCoordinatorGatewayTransport()
        let coordinator = makeCoordinator(
            server: StartFailingOwningGatewayServer(transport: transport)
        )

        await #expect(throws: CoordinatorGatewayOwnershipError.startFailed) {
            try await coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }

        #expect(await transport.shutdownCount == 1)
    }

    @Test("A gateway build failure shuts the unowned transport down once")
    func buildFailureShutsUnownedTransport() async throws {
        let transport = CountingCoordinatorGatewayTransport()
        let transportBuilder = CoordinatorTransportSequence([transport])
        let coordinator = makeCoordinator(
            transportBuilder: transportBuilder,
            gatewayFactory: ThrowingCoordinatorGatewayFactory()
        )

        await #expect(throws: CoordinatorGatewayOwnershipError.buildFailed) {
            try await coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }

        #expect(transportBuilder.makeCount == 1)
        #expect(await transport.shutdownCount == 1)
    }

    @Test("A public builder start failure is cleaned by the coordinator")
    func publicBuilderFailureIsCleaned() async throws {
        let transport = CountingCoordinatorGatewayTransport()
        let coordinator = makePublicBuilderCoordinator(
            transport: transport,
            builder: FailingPublicGatewayBuilder(shutsDownBeforeFailure: false)
        )

        await #expect(throws: CoordinatorGatewayOwnershipError.startFailed) {
            try await coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }

        #expect(await transport.shutdownCount == 1)
    }

    @Test("Builder and coordinator cleanup share one underlying shutdown")
    func publicBuilderCleanupIsIdempotent() async throws {
        let transport = CountingCoordinatorGatewayTransport()
        let coordinator = makePublicBuilderCoordinator(
            transport: transport,
            builder: FailingPublicGatewayBuilder(shutsDownBeforeFailure: true)
        )

        await #expect(throws: CoordinatorGatewayOwnershipError.startFailed) {
            try await coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }

        #expect(await transport.shutdownCount == 1)
    }

    @Test("A retry after failed start uses a fresh server and transport")
    func retryUsesFreshTransport() async throws {
        let firstTransport = CountingCoordinatorGatewayTransport()
        let secondTransport = CountingCoordinatorGatewayTransport()
        let transportBuilder = CoordinatorTransportSequence([
            firstTransport,
            secondTransport,
        ])
        let gatewayFactory = RetryingCoordinatorGatewayFactory()
        let coordinator = makeCoordinator(
            transportBuilder: transportBuilder,
            gatewayFactory: gatewayFactory
        )

        await #expect(throws: CoordinatorGatewayOwnershipError.startFailed) {
            try await coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }
        try await coordinator.startGateway(snapshot: emptyRoutingSnapshot())

        #expect(transportBuilder.makeCount == 2)
        #expect(gatewayFactory.makeCount == 2)
        #expect(await firstTransport.shutdownCount == 1)
        #expect(await secondTransport.shutdownCount == 0)
        #expect((await coordinator.snapshot()).proxyRunning)

        await coordinator.stopGateway()
        #expect(await secondTransport.shutdownCount == 1)
    }

    @Test("Existing public gateway injection creates the coordinator and produces a gateway")
    func publicGatewayInjectionCompatibility() {
        let transport = CountingCoordinatorGatewayTransport()
        let builder: any GatewayBuilding = CompatibilityCoordinatorGatewayBuilder()
        let coordinator = ApplicationCoordinator(
            configurationStore: RecordingConfigurationStore(configuration: AppConfiguration()),
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: transport,
            gatewayBuilder: builder
        )
        // The injected builder must produce a usable gateway from the
        // coordinator's context, proving source compatibility.
        let context = GatewayBuildContext(
            state: GatewayState(snapshot: emptyRoutingSnapshot()),
            transport: transport,
            secretStore: MemorySecretStore(),
            listenPort: 0,
            requiredAuthorityPort: nil,
            trafficRecorder: NoopTrafficRecorder()
        )
        let gateway = builder.makeGateway(context)
        // The gateway must be a concrete instance, proving source compatibility.
        _ = String(describing: type(of: gateway))
        _ = coordinator  // Coordinator construction must not crash
    }

    private func makeCoordinator(
        server: any GatewayServing
    ) -> ApplicationCoordinator {
        ApplicationCoordinator(
            configurationStore: RecordingConfigurationStore(configuration: AppConfiguration()),
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: server
        )
    }

    private func makeCoordinator(
        transportBuilder: any GatewayTransportBuilding,
        gatewayFactory: any GatewayFactory
    ) -> ApplicationCoordinator {
        ApplicationCoordinator(
            configurationStore: RecordingConfigurationStore(configuration: AppConfiguration()),
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransportBuilder: transportBuilder,
            gatewayFactory: gatewayFactory
        )
    }

    private func makePublicBuilderCoordinator(
        transport: any UpstreamTransport,
        builder: any GatewayBuilding
    ) -> ApplicationCoordinator {
        ApplicationCoordinator(
            configurationStore: RecordingConfigurationStore(configuration: AppConfiguration()),
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: transport,
            gatewayBuilder: builder
        )
    }

    private func emptyRoutingSnapshot() -> RoutingSnapshot {
        RoutingSnapshot(generation: 0, providers: [], mappings: [:])
    }
}

private actor StartFailingOwningGatewayServer: GatewayServing {
    private(set) var isRunning = false
    private let transport: any UpstreamTransport

    init(transport: any UpstreamTransport) {
        self.transport = transport
    }

    func start() async throws {
        try await transport.shutdown()
        throw CoordinatorGatewayOwnershipError.startFailed
    }

    func stop() async {}
}

private actor CountingCoordinatorGatewayTransport: UpstreamTransport {
    private(set) var shutdownCount = 0

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        throw CoordinatorGatewayOwnershipError.executeFailed
    }

    func shutdown() async throws {
        shutdownCount += 1
    }
}

private final class CoordinatorTransportSequence: GatewayTransportBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private var transports: [any UpstreamTransport]
    private var storedMakeCount = 0

    init(_ transports: [any UpstreamTransport]) {
        self.transports = transports
    }

    var makeCount: Int {
        lock.withLock { storedMakeCount }
    }

    func makeTransport() async -> any UpstreamTransport {
        lock.withLock {
            storedMakeCount += 1
            return transports.removeFirst()
        }
    }
}

private struct ThrowingCoordinatorGatewayFactory: GatewayFactory {
    func makeGateway(_ context: GatewayBuildContext) throws -> any GatewayServing {
        _ = context
        throw CoordinatorGatewayOwnershipError.buildFailed
    }
}

private struct CompatibilityCoordinatorGatewayBuilder: GatewayBuilding {
    func makeGateway(_ context: GatewayBuildContext) -> any GatewayServing {
        CoordinatorOwningGatewayServer(transport: context.transport, failsStart: false)
    }
}

private struct FailingPublicGatewayBuilder: GatewayBuilding {
    let shutsDownBeforeFailure: Bool

    func makeGateway(_ context: GatewayBuildContext) -> any GatewayServing {
        PublicBuilderFailingGatewayServer(
            transport: context.transport,
            shutsDownBeforeFailure: shutsDownBeforeFailure
        )
    }
}

private actor PublicBuilderFailingGatewayServer: GatewayServing {
    private(set) var isRunning = false
    private let transport: any UpstreamTransport
    private let shutsDownBeforeFailure: Bool

    init(transport: any UpstreamTransport, shutsDownBeforeFailure: Bool) {
        self.transport = transport
        self.shutsDownBeforeFailure = shutsDownBeforeFailure
    }

    func start() async throws {
        if shutsDownBeforeFailure {
            try await transport.shutdown()
        }
        throw CoordinatorGatewayOwnershipError.startFailed
    }

    func stop() async {}
}

private final class RetryingCoordinatorGatewayFactory: GatewayFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var storedMakeCount = 0

    var makeCount: Int {
        lock.withLock { storedMakeCount }
    }

    func makeGateway(_ context: GatewayBuildContext) -> any GatewayServing {
        lock.withLock {
            storedMakeCount += 1
            return CoordinatorOwningGatewayServer(
                transport: context.transport,
                failsStart: storedMakeCount == 1
            )
        }
    }
}

private actor CoordinatorOwningGatewayServer: GatewayServing {
    private(set) var isRunning = false
    private let transport: any UpstreamTransport
    private let failsStart: Bool

    init(transport: any UpstreamTransport, failsStart: Bool) {
        self.transport = transport
        self.failsStart = failsStart
    }

    func start() async throws {
        if failsStart {
            try await transport.shutdown()
            throw CoordinatorGatewayOwnershipError.startFailed
        }
        isRunning = true
    }

    func stop() async {
        guard isRunning else {
            return
        }
        isRunning = false
        try? await transport.shutdown()
    }
}

private enum CoordinatorGatewayOwnershipError: Swift.Error, Equatable {
    case buildFailed
    case executeFailed
    case startFailed
}
