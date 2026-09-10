import AsyncHTTPClient
import Foundation
import LittleSwitchCore
import LittleSwitchTransport
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application coordinator gateway cancellation")
struct CoordinatorGatewayCancellationTests {
    @Test("Transport allocation cancellation still cleans the allocated transport")
    func transportAllocationCancellation() async throws {
        let transport = CancellationCheckingCoordinatorTransport()
        let factory = CountingPassiveGatewayFactory()
        let coordinator = makePackageCoordinator(
            transportBuilder: CancellingCoordinatorTransportBuilder(transport: transport),
            gatewayFactory: factory
        )
        let task = Task {
            try await coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        #expect(await transport.shutdownCount == 1)
        #expect(factory.makeCount == 0)
        #expect(!(await coordinator.snapshot()).proxyRunning)
    }

    @Test("Factory cancellation cleans transport before publishing a server")
    func factoryCancellation() async throws {
        let transport = CancellationCheckingCoordinatorTransport()
        let factory = CancellingPassiveGatewayFactory()
        let coordinator = makePackageCoordinator(
            transportBuilder: FixedCoordinatorTransportBuilder(transport: transport),
            gatewayFactory: factory
        )
        let task = Task {
            try await coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        #expect(await transport.shutdownCount == 1)
        #expect(factory.makeCount == 1)
        #expect(!(await coordinator.snapshot()).proxyRunning)
    }

    @Test("A successful override start that marks cancellation is stopped and not published")
    func overrideStartCancellation() async throws {
        let server = CancellingSuccessfulCoordinatorServer()
        let coordinator = makeOverrideCoordinator(server: server)
        let task = Task {
            try await coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        #expect(await server.stopCount == 1)
        #expect(await !server.isRunning)
        #expect(!(await coordinator.snapshot()).proxyRunning)
    }

    @Test("A successful public builder start that marks cancellation is fully cleaned")
    func publicBuilderStartCancellation() async throws {
        let transport = CancellationCheckingCoordinatorTransport()
        let builder = CancellingPublicGatewayBuilder()
        let coordinator = makePublicCoordinator(
            transport: transport,
            builder: builder
        )
        let task = Task {
            try await coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        let server = try #require(builder.server)
        #expect(await server.stopCount == 1)
        #expect(await transport.shutdownCount == 1)
        #expect(!(await coordinator.snapshot()).proxyRunning)
    }

    @Test("Public startup preserves cancellation instead of mapping gateway unavailable")
    func publicStartPreservesCancellation() async throws {
        let server = CancellingSuccessfulCoordinatorServer()
        let coordinator = makeOverrideCoordinator(server: server)
        let task = Task {
            try await coordinator.start()
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        #expect(await server.stopCount == 1)
        #expect(!(await coordinator.snapshot()).proxyRunning)
    }

    @Test("A pre-cancelled caller cannot hide behind an already-running gateway")
    func preCancelledRunningGateway() async throws {
        let server = PassiveCoordinatorGatewayServer()
        let coordinator = makeOverrideCoordinator(server: server)
        try await coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        let task = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            try await coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        #expect(await server.isRunning)
        await coordinator.stopGateway()
    }

    private func makePackageCoordinator(
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

    private func makeOverrideCoordinator(
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

    private func makePublicCoordinator(
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

private actor CancellationCheckingCoordinatorTransport: UpstreamTransport {
    private(set) var shutdownCount = 0

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        throw CoordinatorGatewayCancellationTestError.execute
    }

    func shutdown() async throws {
        try Task.checkCancellation()
        shutdownCount += 1
    }
}

private struct CancellingCoordinatorTransportBuilder: GatewayTransportBuilding {
    let transport: any UpstreamTransport

    func makeTransport() async -> any UpstreamTransport {
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
        return transport
    }
}

private struct FixedCoordinatorTransportBuilder: GatewayTransportBuilding {
    let transport: any UpstreamTransport

    func makeTransport() async -> any UpstreamTransport {
        transport
    }
}

private final class CountingPassiveGatewayFactory: GatewayFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var storedMakeCount = 0

    var makeCount: Int {
        lock.withLock { storedMakeCount }
    }

    func makeGateway(_ context: GatewayBuildContext) -> any GatewayServing {
        _ = context
        lock.withLock {
            storedMakeCount += 1
        }
        return PassiveCoordinatorGatewayServer()
    }
}

private final class CancellingPassiveGatewayFactory: GatewayFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var storedMakeCount = 0

    var makeCount: Int {
        lock.withLock { storedMakeCount }
    }

    func makeGateway(_ context: GatewayBuildContext) -> any GatewayServing {
        _ = context
        lock.withLock {
            storedMakeCount += 1
        }
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
        return PassiveCoordinatorGatewayServer()
    }
}

private actor PassiveCoordinatorGatewayServer: GatewayServing {
    private(set) var isRunning = false

    func start() async throws {
        isRunning = true
    }

    func stop() async {
        isRunning = false
    }
}

private final class CancellingPublicGatewayBuilder: GatewayBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private var storedServer: CancellingSuccessfulCoordinatorServer?

    var server: CancellingSuccessfulCoordinatorServer? {
        lock.withLock { storedServer }
    }

    func makeGateway(_ context: GatewayBuildContext) -> any GatewayServing {
        let server = CancellingSuccessfulCoordinatorServer(transport: context.transport)
        lock.withLock {
            storedServer = server
        }
        return server
    }
}

private actor CancellingSuccessfulCoordinatorServer: GatewayServing {
    private(set) var isRunning = false
    private(set) var stopCount = 0
    private let transport: (any UpstreamTransport)?

    init(transport: (any UpstreamTransport)? = nil) {
        self.transport = transport
    }

    func start() async throws {
        isRunning = true
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
    }

    func stop() async {
        guard !Task.isCancelled else {
            return
        }
        stopCount += 1
        isRunning = false
        try? await transport?.shutdown()
    }
}

private enum CoordinatorGatewayCancellationTestError: Swift.Error {
    case execute
}
