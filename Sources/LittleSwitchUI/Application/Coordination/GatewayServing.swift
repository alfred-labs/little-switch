import LittleSwitchCore

public protocol GatewayServing: Sendable {
    var isRunning: Bool { get async }

    func start() async throws
    func stop() async
}

extension GatewayServer: GatewayServing {}
