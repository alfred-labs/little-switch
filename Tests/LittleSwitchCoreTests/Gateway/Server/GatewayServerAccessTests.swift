import Hummingbird
import Testing

@testable import LittleSwitchCore

@Suite("Gateway server access")
struct GatewayServerAccessTests {
    @Test("Server configuration binds loopback only")
    func loopbackBindAddress() throws {
        let fixture = try GatewayTests().makeFixture()
        let configuration = GatewayServerConfiguration(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            listenPort: 11_436,
            requiredAuthorityPort: 11_436,
            trafficRecorder: NoopTrafficRecorder(),
            tlsIdentity: nil
        )
        #expect(configuration.bindAddress == .hostname("127.0.0.1", port: 11_436))
    }
}
