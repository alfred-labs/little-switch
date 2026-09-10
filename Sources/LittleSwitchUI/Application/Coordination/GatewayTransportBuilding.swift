import LittleSwitchTransport

package protocol GatewayTransportBuilding: Sendable {
    func makeTransport() async -> any UpstreamTransport
}

package struct LiveGatewayTransportBuilder: GatewayTransportBuilding {
    package init() {}

    package func makeTransport() async -> any UpstreamTransport {
        AsyncHTTPTransport()
    }
}

package actor InjectedGatewayTransportBuilder: GatewayTransportBuilding {
    private var injectedTransport: (any UpstreamTransport)?

    package init(transport: any UpstreamTransport) {
        injectedTransport = transport
    }

    package func makeTransport() async -> any UpstreamTransport {
        if let injectedTransport {
            self.injectedTransport = nil
            return injectedTransport
        }
        return AsyncHTTPTransport()
    }
}
