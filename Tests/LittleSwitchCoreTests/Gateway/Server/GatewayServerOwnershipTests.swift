import AsyncHTTPClient
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("Gateway server ownership")
struct GatewayServerOwnershipTests {
    @Test("A failed start permanently consumes a server instance")
    func failedStartIsOneShot() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = ImmediatelyFailingGatewayServerRunner()
        let transport = OwnershipTrackingTransport()
        let server = GatewayServer(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            listenPort: 0,
            requiredAuthorityPort: nil,
            runnerFactory: OwnershipGatewayServerRunnerFactory(runner: runner)
        )

        await #expect(throws: OwnershipTestError.runner) {
            try await server.start()
        }
        await #expect(throws: GatewayServer.Error.alreadyStarted) {
            try await server.start()
        }

        #expect(await runner.runCount == 1)
        #expect(await transport.shutdownCount == 1)
    }

    @Test("Deallocation cancels the runner and owns exactly one transport shutdown")
    func deallocationCancelsOwnedRun() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = DeallocationGatewayServerRunner()
        let transport = CancellationCheckingOwnershipTransport()
        var server: GatewayServer? = GatewayServer(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            listenPort: 0,
            requiredAuthorityPort: nil,
            runnerFactory: OwnershipGatewayServerRunnerFactory(runner: runner)
        )
        weak let releasedServer = server

        try await server?.start()
        #expect(await server?.isRunning == true)
        server = nil

        try await waitForOwnershipSignal(runner.cancellationEvents)
        try await waitForOwnershipSignal(transport.shutdownEvents)

        #expect(releasedServer == nil)
        #expect(await runner.wasCancelled)
        #expect(await transport.shutdownCount == 1)
    }

    @Test("Stop shuts transport down from an uncancelled cleanup task")
    func stopUsesUncancelledCleanup() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = DeallocationGatewayServerRunner()
        let transport = CancellationCheckingOwnershipTransport()
        let server = GatewayServer(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            listenPort: 0,
            requiredAuthorityPort: nil,
            runnerFactory: OwnershipGatewayServerRunnerFactory(runner: runner)
        )

        try await server.start()
        await server.stop()

        #expect(await runner.wasCancelled)
        #expect(await transport.shutdownCount == 1)
    }

    @Test("Startup cancellation still shuts transport down once")
    func startupCancellationUsesUncancelledCleanup() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = PendingOwnershipGatewayServerRunner()
        let transport = CancellationCheckingOwnershipTransport()
        let server = GatewayServer(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            listenPort: 0,
            requiredAuthorityPort: nil,
            runnerFactory: OwnershipGatewayServerRunnerFactory(runner: runner)
        )
        let start = Task {
            try await server.start()
        }
        try await waitForOwnershipSignal(runner.startedEvents)

        start.cancel()

        await #expect(throws: CancellationError.self) {
            try await start.value
        }
        #expect(await runner.wasCancelled)
        #expect(await transport.shutdownCount == 1)
    }

    @Test("A cancelled failing runner still shuts transport down once")
    func cancelledFailureUsesUncancelledCleanup() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = CancellingFailingGatewayServerRunner()
        let transport = CancellationCheckingOwnershipTransport()
        let server = GatewayServer(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            listenPort: 0,
            requiredAuthorityPort: nil,
            runnerFactory: OwnershipGatewayServerRunnerFactory(runner: runner)
        )

        await #expect(throws: OwnershipTestError.runner) {
            try await server.start()
        }

        #expect(await transport.shutdownCount == 1)
    }

    @Test("Listener exit clears running state while stop still joins transport cleanup")
    func listenerExitDuringSuspendedShutdown() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = FinishingGatewayServerRunner()
        let transport = OwnershipSuspendingShutdownTransport()
        let server = GatewayServer(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            listenPort: 0,
            requiredAuthorityPort: nil,
            runnerFactory: OwnershipGatewayServerRunnerFactory(runner: runner)
        )

        try await server.start()
        #expect(await server.isRunning)
        await runner.finish()
        try await waitForOwnershipSignal(transport.shutdownEvents)

        #expect(await !server.isRunning)
        let stop = Task {
            await server.stop()
        }
        await transport.releaseShutdown()
        await stop.value

        #expect(await transport.shutdownCount == 1)
        #expect(await !server.isRunning)
    }
}

private struct OwnershipGatewayServerRunnerFactory: GatewayServerRunnerFactory {
    let runner: any GatewayServerRunning

    func makeRunner(configuration: GatewayServerConfiguration) -> any GatewayServerRunning {
        _ = configuration
        return runner
    }
}

private actor ImmediatelyFailingGatewayServerRunner: GatewayServerRunning {
    private(set) var runCount = 0

    func run(onReady: @escaping @Sendable () -> Void) async throws {
        _ = onReady
        runCount += 1
        throw OwnershipTestError.runner
    }
}

private actor DeallocationGatewayServerRunner: GatewayServerRunning {
    nonisolated let cancellationEvents: AsyncStream<Void>
    private let cancellationContinuation: AsyncStream<Void>.Continuation
    private var runContinuation: CheckedContinuation<Void, any Swift.Error>?
    private(set) var wasCancelled = false

    init() {
        let (events, continuation) = AsyncStream<Void>.makeStream()
        cancellationEvents = events
        cancellationContinuation = continuation
    }

    func run(onReady: @escaping @Sendable () -> Void) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                runContinuation = continuation
                onReady()
            }
        } onCancel: {
            Task {
                await self.cancel()
            }
        }
    }

    private func cancel() {
        wasCancelled = true
        runContinuation?.resume(throwing: CancellationError())
        runContinuation = nil
        cancellationContinuation.yield()
        cancellationContinuation.finish()
    }
}

private actor PendingOwnershipGatewayServerRunner: GatewayServerRunning {
    nonisolated let startedEvents: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private var runContinuation: CheckedContinuation<Void, any Swift.Error>?
    private(set) var wasCancelled = false

    init() {
        let (events, continuation) = AsyncStream<Void>.makeStream()
        startedEvents = events
        startedContinuation = continuation
    }

    func run(onReady: @escaping @Sendable () -> Void) async throws {
        _ = onReady
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                runContinuation = continuation
                startedContinuation.yield()
                startedContinuation.finish()
            }
        } onCancel: {
            Task {
                await self.cancel()
            }
        }
    }

    private func cancel() {
        wasCancelled = true
        runContinuation?.resume(throwing: CancellationError())
        runContinuation = nil
    }
}

private struct CancellingFailingGatewayServerRunner: GatewayServerRunning {
    func run(onReady: @escaping @Sendable () -> Void) async throws {
        _ = onReady
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
        throw OwnershipTestError.runner
    }
}

private actor FinishingGatewayServerRunner: GatewayServerRunning {
    private var continuation: CheckedContinuation<Void, Never>?

    func run(onReady: @escaping @Sendable () -> Void) async throws {
        onReady()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

private actor OwnershipTrackingTransport: UpstreamTransport {
    nonisolated let shutdownEvents: AsyncStream<Void>
    private let shutdownContinuation: AsyncStream<Void>.Continuation
    private(set) var shutdownCount = 0

    init() {
        let (events, continuation) = AsyncStream<Void>.makeStream()
        shutdownEvents = events
        shutdownContinuation = continuation
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        throw OwnershipTestError.execute
    }

    func shutdown() async throws {
        shutdownCount += 1
        shutdownContinuation.yield()
        shutdownContinuation.finish()
    }
}

private actor CancellationCheckingOwnershipTransport: UpstreamTransport {
    nonisolated let shutdownEvents: AsyncStream<Void>
    private let shutdownContinuation: AsyncStream<Void>.Continuation
    private(set) var shutdownCount = 0

    init() {
        let (events, continuation) = AsyncStream<Void>.makeStream()
        shutdownEvents = events
        shutdownContinuation = continuation
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        throw OwnershipTestError.execute
    }

    func shutdown() async throws {
        try Task.checkCancellation()
        shutdownCount += 1
        shutdownContinuation.yield()
        shutdownContinuation.finish()
    }
}

private actor OwnershipSuspendingShutdownTransport: UpstreamTransport {
    nonisolated let shutdownEvents: AsyncStream<Void>
    private let shutdownContinuation: AsyncStream<Void>.Continuation
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var shutdownCount = 0

    init() {
        let (events, continuation) = AsyncStream<Void>.makeStream()
        shutdownEvents = events
        shutdownContinuation = continuation
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        throw OwnershipTestError.execute
    }

    func shutdown() async throws {
        shutdownCount += 1
        shutdownContinuation.yield()
        shutdownContinuation.finish()
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func releaseShutdown() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private func waitForOwnershipSignal(_ events: AsyncStream<Void>) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            for await _ in events {
                return
            }
            throw OwnershipTestError.missingSignal
        }
        group.addTask {
            try await Task.sleep(for: .seconds(1))
            throw OwnershipTestError.missingSignal
        }
        _ = try await group.next()
        group.cancelAll()
    }
}

private enum OwnershipTestError: Swift.Error, Equatable {
    case execute
    case missingSignal
    case runner
}
