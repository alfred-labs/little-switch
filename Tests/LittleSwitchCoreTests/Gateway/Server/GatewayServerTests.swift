import AsyncHTTPClient
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("Gateway server lifecycle")
struct GatewayServerTests {
    @Test("A second start is rejected while the runner is active")
    func duplicateStart() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = ControllableGatewayServerRunner()
        let server = GatewayServer(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            listenPort: 0,
            requiredAuthorityPort: nil,
            runnerFactory: TestGatewayServerRunnerFactory(runner: runner)
        )

        let firstStart = Task {
            try await server.start()
        }
        await runner.waitUntilStarted()

        await #expect(throws: GatewayServer.Error.alreadyStarted) {
            try await server.start()
        }

        firstStart.cancel()
        await #expect(throws: CancellationError.self) {
            try await firstStart.value
        }
    }

    @Test("Ready and stop own the complete runner lifecycle")
    func readyAndStop() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = ControllableGatewayServerRunner()
        let transport = ShutdownTrackingTransport()
        let server = makeServer(fixture: fixture, runner: runner, transport: transport)

        let start = Task {
            try await server.start()
        }
        await runner.waitUntilStarted()
        await runner.reportReady()
        try await start.value

        #expect(await server.isRunning)
        await server.stop()
        #expect(await runner.wasCancelled)
        #expect(await transport.shutdownCount == 1)
        #expect(await !server.isRunning)
    }

    @Test("A start remains rejected until transport shutdown completes")
    func startDuringShutdown() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = AutomaticallyReadyGatewayServerRunner()
        let transport = SuspendingShutdownTransport()
        let server = GatewayServer(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            listenPort: 0,
            requiredAuthorityPort: nil,
            runnerFactory: ReusableGatewayServerRunnerFactory(runner: runner)
        )

        try await server.start()
        let stopCompletions = CompletionCounter()
        let stop = Task {
            await server.stop()
            await stopCompletions.record()
        }
        await transport.waitUntilFirstShutdownBegins()
        let concurrentStop = Task {
            await server.stop()
            await stopCompletions.record()
        }

        let overlappingStart = Task<GatewayServerStartResult, Never> {
            do {
                try await server.start()
                return .started
            } catch let error as GatewayServer.Error {
                return .gatewayError(error)
            } catch {
                return .unexpectedError
            }
        }
        let overlappingResult = await overlappingStart.value

        #expect(overlappingResult == .gatewayError(.alreadyStarted))
        #expect(await stopCompletions.total == 0)
        await transport.releaseFirstShutdown()
        await stop.value
        await concurrentStop.value

        guard overlappingResult == .gatewayError(.alreadyStarted) else {
            await server.stop()
            return
        }

        #expect(await stopCompletions.total == 2)
        #expect(await transport.shutdownCount == 1)
        #expect(await !server.isRunning)

        await #expect(throws: GatewayServer.Error.alreadyStarted) {
            try await server.start()
        }
        await server.stop()

        #expect(await runner.runCount == 1)
        #expect(await transport.shutdownCount == 1)
        #expect(await !server.isRunning)
    }

    @Test("Stop before start is a no-op")
    func stopBeforeStart() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = ControllableGatewayServerRunner()
        let transport = ShutdownTrackingTransport()
        let server = makeServer(fixture: fixture, runner: runner, transport: transport)

        await server.stop()

        #expect(await !runner.hasStarted)
        #expect(await transport.shutdownCount == 0)
        #expect(await !server.isRunning)
    }

    @Test("Stop while readiness is pending cancels startup and fully resets")
    func stopBeforeReady() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = ControllableGatewayServerRunner()
        let transport = ShutdownTrackingTransport()
        let server = makeServer(fixture: fixture, runner: runner, transport: transport)

        let start = Task {
            try await server.start()
        }
        await runner.waitUntilStarted()
        await server.stop()

        await #expect(throws: GatewayServer.Error.stoppedBeforeReady) {
            try await start.value
        }
        #expect(await runner.wasCancelled)
        #expect(await transport.shutdownCount == 1)
        #expect(await !server.isRunning)
        await #expect(throws: GatewayState.Error.notAcceptingRequests) {
            try await fixture.state.admit()
        }
    }

    @Test("A runner that stops before readiness rejects start")
    func runnerStopsBeforeReady() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = ControllableGatewayServerRunner()
        let server = makeServer(
            fixture: fixture,
            runner: runner,
            transport: ShutdownTrackingTransport()
        )

        let start = Task {
            try await server.start()
        }
        await runner.waitUntilStarted()
        await runner.succeed()

        await #expect(throws: GatewayServer.Error.stoppedBeforeReady) {
            try await start.value
        }
        #expect(await !server.isRunning)
    }

    @Test("A runner failure before readiness is preserved")
    func runnerFailureBeforeReady() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = ControllableGatewayServerRunner()
        let server = makeServer(
            fixture: fixture,
            runner: runner,
            transport: ShutdownTrackingTransport()
        )

        let start = Task {
            try await server.start()
        }
        await runner.waitUntilStarted()
        await runner.fail(TestError.runner)

        await #expect(throws: TestError.runner) {
            try await start.value
        }
        #expect(await !server.isRunning)
    }

    @Test("A runner failure after readiness resets the server")
    func runnerFailureAfterReady() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = ControllableGatewayServerRunner()
        let transport = ShutdownTrackingTransport()
        let server = makeServer(fixture: fixture, runner: runner, transport: transport)

        let start = Task {
            try await server.start()
        }
        await runner.waitUntilStarted()
        await runner.reportReady()
        try await start.value
        #expect(await server.isRunning)

        await runner.fail(TestError.runner)
        await server.stop()

        #expect(await transport.shutdownCount == 1)
        #expect(await !server.isRunning)
    }

    @Test("Cancelling start cancels the runner and resets the server")
    func startCancellation() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = ControllableGatewayServerRunner()
        let server = makeServer(
            fixture: fixture,
            runner: runner,
            transport: ShutdownTrackingTransport()
        )

        let start = Task {
            try await server.start()
        }
        await runner.waitUntilStarted()
        start.cancel()

        await #expect(throws: CancellationError.self) {
            try await start.value
        }
        #expect(await runner.wasCancelled)
        #expect(await !server.isRunning)
    }

    @Test("A transport shutdown failure still leaves the server stopped")
    func shutdownFailure() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = ControllableGatewayServerRunner()
        let transport = ShutdownTrackingTransport(shutdownError: TestError.shutdown)
        let server = makeServer(fixture: fixture, runner: runner, transport: transport)

        let start = Task {
            try await server.start()
        }
        await runner.waitUntilStarted()
        await runner.reportReady()
        try await start.value

        await server.stop()

        #expect(await transport.shutdownCount == 1)
        #expect(await !server.isRunning)
    }

    @Test("The live runner can bind an ephemeral loopback port")
    func liveLoopback() async throws {
        let fixture = try GatewayTests().makeFixture()
        let server = GatewayServer(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            listenPort: 0,
            requiredAuthorityPort: nil
        )

        try await server.start()
        #expect(await server.isRunning)
        await server.stop()
        #expect(await !server.isRunning)
    }

    private func makeServer(
        fixture: GatewayFixture,
        runner: ControllableGatewayServerRunner,
        transport: any UpstreamTransport
    ) -> GatewayServer {
        GatewayServer(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            listenPort: 0,
            requiredAuthorityPort: nil,
            runnerFactory: TestGatewayServerRunnerFactory(runner: runner)
        )
    }

}

private struct TestGatewayServerRunnerFactory: GatewayServerRunnerFactory {
    let runner: ControllableGatewayServerRunner

    func makeRunner(configuration: GatewayServerConfiguration) -> any GatewayServerRunning {
        _ = configuration
        return runner
    }
}

private struct ReusableGatewayServerRunnerFactory: GatewayServerRunnerFactory {
    let runner: AutomaticallyReadyGatewayServerRunner

    func makeRunner(configuration: GatewayServerConfiguration) -> any GatewayServerRunning {
        _ = configuration
        return runner
    }
}

private enum GatewayServerStartResult: Equatable {
    case started
    case gatewayError(GatewayServer.Error)
    case unexpectedError
}

private actor CompletionCounter {
    private(set) var total = 0

    func record() {
        total += 1
    }
}

private actor AutomaticallyReadyGatewayServerRunner: GatewayServerRunning {
    private var continuations: [Int: CheckedContinuation<Void, any Swift.Error>] = [:]
    private(set) var runCount = 0

    func run(onReady: @escaping @Sendable () -> Void) async throws {
        let runID = runCount
        runCount += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[runID] = continuation
                onReady()
            }
        } onCancel: {
            Task {
                await self.cancel(runID: runID)
            }
        }
    }

    private func cancel(runID: Int) {
        continuations.removeValue(forKey: runID)?.resume(throwing: CancellationError())
    }
}

private actor ControllableGatewayServerRunner: GatewayServerRunning {
    private var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var readyCallback: (@Sendable () -> Void)?
    private var continuation: CheckedContinuation<Void, any Swift.Error>?
    private(set) var wasCancelled = false

    var hasStarted: Bool {
        started
    }

    func run(onReady: @escaping @Sendable () -> Void) async throws {
        started = true
        let waiters = startedWaiters
        startedWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        readyCallback = onReady
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        } onCancel: {
            Task {
                await self.cancel()
            }
        }
    }

    func waitUntilStarted() async {
        guard !started else {
            return
        }
        await withCheckedContinuation { continuation in
            if started {
                continuation.resume()
            } else {
                startedWaiters.append(continuation)
            }
        }
    }

    func reportReady() {
        readyCallback?()
    }

    func succeed() {
        continuation?.resume()
        continuation = nil
    }

    func fail(_ error: any Swift.Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func cancel() {
        wasCancelled = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

private actor ShutdownTrackingTransport: UpstreamTransport {
    private(set) var shutdownCount = 0
    private let shutdownError: TestError?

    init(shutdownError: TestError? = nil) {
        self.shutdownError = shutdownError
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        throw TestError.execute
    }

    func shutdown() async throws {
        shutdownCount += 1
        if let shutdownError {
            throw shutdownError
        }
    }
}

private actor SuspendingShutdownTransport: UpstreamTransport {
    private var firstShutdownContinuation: CheckedContinuation<Void, Never>?
    private var firstShutdownBegan = false
    private var firstShutdownWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var shutdownCount = 0

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        throw TestError.execute
    }

    func shutdown() async throws {
        shutdownCount += 1
        guard shutdownCount == 1 else {
            return
        }
        await withCheckedContinuation { continuation in
            firstShutdownContinuation = continuation
            firstShutdownBegan = true
            let waiters = firstShutdownWaiters
            firstShutdownWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func waitUntilFirstShutdownBegins() async {
        guard !firstShutdownBegan else {
            return
        }
        await withCheckedContinuation { continuation in
            if firstShutdownBegan {
                continuation.resume()
            } else {
                firstShutdownWaiters.append(continuation)
            }
        }
    }

    func releaseFirstShutdown() {
        firstShutdownContinuation?.resume()
        firstShutdownContinuation = nil
    }
}

private enum TestError: Swift.Error, Equatable {
    case execute
    case runner
    case shutdown
}
