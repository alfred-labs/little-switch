import LittleSwitchCore
import LittleSwitchTransport

public protocol GatewayBuilding: Sendable {
    func makeGateway(_ context: GatewayBuildContext) -> any GatewayServing
}

package protocol GatewayFactory: Sendable {
    func makeGateway(_ context: GatewayBuildContext) throws -> any GatewayServing
}

package struct LiveGatewayFactory: GatewayFactory {
    let builder: any GatewayBuilding

    package func makeGateway(_ context: GatewayBuildContext) -> any GatewayServing {
        builder.makeGateway(context)
    }
}

public struct GatewayBuildContext: Sendable {
    public var state: GatewayState
    public var transport: any UpstreamTransport
    public var secretStore: any SecretStore
    public var listenPort: Int
    public var requiredAuthorityPort: Int?
    public var trafficRecorder: any TrafficRecording
    /// Serves TLS alongside plain HTTP on the same port when present.
    public var tlsIdentity: GatewayTLSIdentity?
    public var monitoring: GatewayMonitoring?

    public init(
        state: GatewayState,
        transport: any UpstreamTransport,
        secretStore: any SecretStore,
        listenPort: Int,
        requiredAuthorityPort: Int?,
        trafficRecorder: any TrafficRecording,
        tlsIdentity: GatewayTLSIdentity? = nil,
        monitoring: GatewayMonitoring? = nil
    ) {
        self.state = state
        self.transport = transport
        self.secretStore = secretStore
        self.listenPort = listenPort
        self.requiredAuthorityPort = requiredAuthorityPort
        self.trafficRecorder = trafficRecorder
        self.tlsIdentity = tlsIdentity
        self.monitoring = monitoring
    }
}

public struct LiveGatewayBuilder: GatewayBuilding {
    public init() {}

    public func makeGateway(_ context: GatewayBuildContext) -> any GatewayServing {
        GatewayServer(
            state: context.state,
            transport: context.transport,
            secretStore: context.secretStore,
            listenPort: context.listenPort,
            requiredAuthorityPort: context.requiredAuthorityPort,
            trafficRecorder: context.trafficRecorder,
            tlsIdentity: context.tlsIdentity,
            monitoring: context.monitoring
        )
    }
}
