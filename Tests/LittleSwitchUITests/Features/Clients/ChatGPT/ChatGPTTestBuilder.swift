import LittleSwitchCore
import os

@testable import LittleSwitchUI

final class ChatGPTTestBuilder: ChatGPTGatewayBuilding, Sendable {
    let server: ChatGPTTestServer
    private let capturedStates = OSAllocatedUnfairLock(initialState: [GatewayState]())
    var states: [GatewayState] { capturedStates.withLock { $0 } }

    init(server: ChatGPTTestServer) { self.server = server }

    func makeGateway(
        state: GatewayState,
        secretStore: any SecretStore,
        identity: GatewayTLSIdentity,
        monitoring: GatewayMonitoring
    ) throws -> any GatewayServing {
        capturedStates.withLock { $0.append(state) }
        return server
    }
}
