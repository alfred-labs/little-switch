import Foundation
import Hummingbird
import HummingbirdCore
import LittleSwitchTransport

package struct GatewayServerConfiguration: Sendable {
    let state: GatewayState
    let transport: any UpstreamTransport
    let secretStore: any SecretStore
    let listenPort: Int
    let requiredAuthorityPort: Int?
    let trafficRecorder: any TrafficRecording
    /// When present the listener also speaks TLS on the same port, choosing
    /// the wire protocol per connection.
    let tlsIdentity: GatewayTLSIdentity?
    var monitoring: GatewayMonitoring?

    var bindAddress: BindAddress {
        .hostname(ProductIdentity.gatewayLoopbackHost, port: listenPort)
    }
}

package protocol GatewayServerRunning: Sendable {
    func run(onReady: @escaping @Sendable () -> Void) async throws
}

package protocol GatewayServerRunnerFactory: Sendable {
    func makeRunner(configuration: GatewayServerConfiguration) -> any GatewayServerRunning
}

private struct LiveGatewayServerRunnerFactory: GatewayServerRunnerFactory {
    func makeRunner(configuration: GatewayServerConfiguration) -> any GatewayServerRunning {
        LiveGatewayServerRunner(configuration: configuration)
    }
}

private struct LiveGatewayServerRunner: GatewayServerRunning {
    let configuration: GatewayServerConfiguration

    func run(onReady: @escaping @Sendable () -> Void) async throws {
        let responder = GatewayResponder(
            state: configuration.state,
            transport: configuration.transport,
            secretStore: configuration.secretStore,
            requiredAuthorityPort: configuration.requiredAuthorityPort,
            trafficRecorder: configuration.trafficRecorder,
            monitoring: configuration.monitoring
        )
        let server: HTTPServerBuilder
        if let tlsIdentity = configuration.tlsIdentity {
            server = try DualProtocolServerBuilder.make(
                tlsConfiguration: tlsIdentity.tlsConfiguration
            )
        } else {
            server = .http1()
        }
        let application = Application(
            responder: responder,
            server: server,
            configuration: .init(
                address: configuration.bindAddress,
                serverName: ProductIdentity.gatewayServerName
            )
        ) { _ in
            onReady()
        }
        try await application.run()
    }
}

public actor GatewayServer {
    public enum Error: Swift.Error, Equatable {
        case alreadyStarted
        case stoppedBeforeReady
    }

    private let configuration: GatewayServerConfiguration
    private let runnerFactory: any GatewayServerRunnerFactory
    private let stopsAdmissionsOnStop: Bool
    private var hasStarted = false
    private var activeRunID: UUID?
    private var serverTask: Task<Void, Never>?
    private var running = false
    private var runnerExited = false
    private var monitoringStartTask: Task<Void, Never>?

    package init(
        state: GatewayState,
        transport: any UpstreamTransport,
        secretStore: any SecretStore,
        listenPort: Int = 11_436,
        requiredAuthorityPort: Int? = 11_436,
        trafficRecorder: any TrafficRecording = NoopTrafficRecorder(),
        runnerFactory: (any GatewayServerRunnerFactory)? = nil,
        tlsIdentity: GatewayTLSIdentity? = nil,
        monitoring: GatewayMonitoring? = nil,
        stopsAdmissionsOnStop: Bool = true
    ) {
        self.configuration = GatewayServerConfiguration(
            state: state,
            transport: transport,
            secretStore: secretStore,
            listenPort: listenPort,
            requiredAuthorityPort: requiredAuthorityPort,
            trafficRecorder: trafficRecorder,
            tlsIdentity: tlsIdentity,
            monitoring: monitoring
        )
        self.runnerFactory =
            runnerFactory ?? LiveGatewayServerRunnerFactory()
        self.stopsAdmissionsOnStop = stopsAdmissionsOnStop
    }

    public var isRunning: Bool {
        running
    }

    public func start() async throws {
        guard !hasStarted else {
            throw Error.alreadyStarted
        }
        hasStarted = true

        let runID = UUID()
        let runner = runnerFactory.makeRunner(configuration: configuration)
        let transport = configuration.transport
        let (readyEvents, readyContinuation) = AsyncThrowingStream<Void, any Swift.Error>.makeStream()
        activeRunID = runID
        let task = Task { [weak self] in
            do {
                try await runner.run {
                    readyContinuation.yield()
                    readyContinuation.finish()
                }
                readyContinuation.finish()
            } catch is CancellationError {
                readyContinuation.finish()
            } catch {
                readyContinuation.finish(throwing: error)
            }
            await self?.runnerDidExit()
            let cleanupTask = Task {
                try? await transport.shutdown()
            }
            await cleanupTask.value
            await self?.runnerDidFinish()
        }
        serverTask = task

        do {
            let becameReady = try await withTaskCancellationHandler {
                try await readyEvents.contains { _ in true }
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard becameReady, activeRunID == runID, !runnerExited else {
                throw Error.stoppedBeforeReady
            }
            running = true
            if let monitoring = configuration.monitoring {
                let observation = Task { await monitoring.recordOperation(.gatewayStarted) }
                monitoringStartTask = observation
                await observation.value
                monitoringStartTask = nil
            }
        } catch {
            task.cancel()
            await task.value
            throw error
        }
    }

    public func stop() async {
        guard let task = serverTask else {
            return
        }
        if stopsAdmissionsOnStop {
            await configuration.state.stopAdmissions()
        }
        task.cancel()
        await task.value
    }

    deinit {
        serverTask?.cancel()
    }

    private func runnerDidExit() async {
        let wasRunning = running
        runnerExited = true
        running = false
        if wasRunning {
            // A stop can arrive while start is handing off its observation. Keep the pair ordered.
            await monitoringStartTask?.value
            await configuration.monitoring?.recordOperation(.gatewayStopped)
        }
    }

    private func runnerDidFinish() {
        running = false
        serverTask = nil
        activeRunID = nil
    }
}
