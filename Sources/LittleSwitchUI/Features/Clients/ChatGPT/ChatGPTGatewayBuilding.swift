import Foundation
import LittleSwitchCore

public protocol ChatGPTGatewayBuilding: Sendable {
    func makeGateway(
        state: GatewayState,
        secretStore: any SecretStore,
        identity: GatewayTLSIdentity,
        monitoring: GatewayMonitoring
    ) throws -> any GatewayServing
}

struct LiveChatGPTGatewayBuilder: ChatGPTGatewayBuilding {
    let historyFileURL: URL
    let trafficRecorder: any TrafficRecording

    func makeGateway(
        state: GatewayState,
        secretStore: any SecretStore,
        identity: GatewayTLSIdentity,
        monitoring: GatewayMonitoring
    ) throws -> any GatewayServing {
        try ChatGPTGatewayServer(
            state: state,
            secretStore: secretStore,
            tlsIdentity: identity,
            historyFileURL: historyFileURL,
            trafficRecorder: trafficRecorder,
            monitoring: monitoring
        )
    }
}

extension ChatGPTGatewayServer: GatewayServing {}
