import Foundation
import Hummingbird
import HummingbirdTLS
import LittleSwitchTransport

/// A separately owned HTTPS listener. Its transport and lifecycle are local to
/// ChatGPT; stopping it must leave the shared provider admission pool running.
public actor ChatGPTGatewayServer {
    private let server: GatewayServer
    private let activeTurns: ChatGPTActiveTurns
    private let transport: ShutdownOnceUpstreamTransport
    private var stopped = false
    private var startup: Task<Void, any Swift.Error>?

    public init(
        state: GatewayState,
        secretStore: any SecretStore,
        tlsIdentity: GatewayTLSIdentity,
        historyFileURL: URL,
        trafficRecorder: any TrafficRecording = NoopTrafficRecorder(),
        monitoring: GatewayMonitoring? = nil
    ) throws {
        // Validate storage before allocating a transport that needs asynchronous
        // shutdown. A failed connection must leave the existing history intact.
        let history = try ChatGPTHistoryStore(fileURL: historyFileURL)
        self.init(
            state: state,
            secretStore: secretStore,
            tlsIdentity: tlsIdentity,
            transport: AsyncHTTPTransport(followsRedirects: false),
            history: history,
            trafficRecorder: trafficRecorder,
            monitoring: monitoring
        )
    }

    package init(
        state: GatewayState,
        secretStore: any SecretStore,
        tlsIdentity: GatewayTLSIdentity,
        transport: any UpstreamTransport,
        history: ChatGPTHistoryStore,
        activeTurns: ChatGPTActiveTurns = ChatGPTActiveTurns(),
        trafficRecorder: any TrafficRecording = NoopTrafficRecorder(),
        monitoring: GatewayMonitoring? = nil,
        listenPort: Int = ChatGPTLaunchEnvironment.port
    ) {
        self.activeTurns = activeTurns
        let transport = ShutdownOnceUpstreamTransport(upstream: transport)
        self.transport = transport
        server = GatewayServer(
            state: state,
            transport: transport,
            secretStore: secretStore,
            listenPort: listenPort,
            requiredAuthorityPort: listenPort,
            trafficRecorder: trafficRecorder,
            runnerFactory: ChatGPTServerRunnerFactory(
                identity: tlsIdentity,
                history: history,
                activeTurns: activeTurns,
                monitoring: monitoring
            ),
            stopsAdmissionsOnStop: false
        )
    }

    public var isRunning: Bool { get async { await server.isRunning } }

    public func start() async throws {
        guard !stopped else { throw GatewayServer.Error.stoppedBeforeReady }
        guard startup == nil else { throw GatewayServer.Error.alreadyStarted }
        let server = self.server
        let operation = Task { try await server.start() }
        startup = operation
        try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
        guard !stopped else { throw GatewayServer.Error.stoppedBeforeReady }
    }

    public func stop() async {
        stopped = true
        startup?.cancel()
        _ = try? await startup?.value
        await activeTurns.shutdown()
        await server.stop()
        try? await transport.shutdown()
    }
}

private struct ChatGPTServerRunnerFactory: GatewayServerRunnerFactory {
    let identity: GatewayTLSIdentity
    let history: ChatGPTHistoryStore
    let activeTurns: ChatGPTActiveTurns
    let monitoring: GatewayMonitoring?

    func makeRunner(configuration: GatewayServerConfiguration) -> any GatewayServerRunning {
        ChatGPTServerRunner(
            configuration: configuration,
            identity: identity,
            history: history,
            activeTurns: activeTurns,
            monitoring: monitoring
        )
    }
}

private struct ChatGPTServerRunner: GatewayServerRunning {
    let configuration: GatewayServerConfiguration
    let identity: GatewayTLSIdentity
    let history: ChatGPTHistoryStore
    let activeTurns: ChatGPTActiveTurns
    let monitoring: GatewayMonitoring?

    func run(onReady: @escaping @Sendable () -> Void) async throws {
        let responder = ChatGPTGatewayResponder(
            state: configuration.state,
            transport: configuration.transport,
            secretStore: configuration.secretStore,
            requiredAuthorityPort: configuration.requiredAuthorityPort,
            history: history,
            activeTurns: activeTurns,
            trafficRecorder: configuration.trafficRecorder,
            monitoring: monitoring
        )
        let application = Application(
            responder: responder,
            server: try .tls(.http1(), tlsConfiguration: identity.tlsConfiguration),
            configuration: .init(address: configuration.bindAddress, serverName: ProductIdentity.gatewayServerName)
        ) { _ in onReady() }
        do {
            try await application.run()
        } catch {
            await activeTurns.shutdown()
            throw error
        }
        await activeTurns.shutdown()
    }
}
