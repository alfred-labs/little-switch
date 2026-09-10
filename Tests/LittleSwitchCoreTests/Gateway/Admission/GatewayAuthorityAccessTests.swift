import HTTPTypes
import Hummingbird
import Logging
import NIOCore
import NIOEmbedded
import Testing

@testable import LittleSwitchCore

private struct GatewayAuthorityExpectation {
    let authority: String
    let allowed: Bool
}

extension GatewayTests {
    @Test("Gateway authority accepts only loopback hosts on the pinned port")
    func authorityLoopbackOnly() {
        let cases = [
            GatewayAuthorityExpectation(authority: "localhost:11436", allowed: true),
            GatewayAuthorityExpectation(authority: "127.0.0.1:11436", allowed: true),
            GatewayAuthorityExpectation(authority: "127.0.0.2:11436", allowed: true),
            GatewayAuthorityExpectation(authority: "[::1]:11436", allowed: true),
            GatewayAuthorityExpectation(authority: "192.168.1.40:11436", allowed: false),
            GatewayAuthorityExpectation(authority: "203.0.113.10:11436", allowed: false),
            GatewayAuthorityExpectation(authority: "little-switch.example:11436", allowed: false),
            GatewayAuthorityExpectation(authority: "little-switch.example", allowed: false),
            GatewayAuthorityExpectation(authority: "little-switch.example:11435", allowed: false),
            GatewayAuthorityExpectation(authority: "user@little-switch.example:11436", allowed: false),
            GatewayAuthorityExpectation(authority: "", allowed: false),
        ]

        for testCase in cases {
            #expect(
                GatewaySecurity.isAllowedAuthority(
                    testCase.authority,
                    requiredPort: 11_436
                ) == testCase.allowed
            )
        }
    }

    @Test("The responder rejects a remote authority outright")
    func remoteResponderAuthority() async throws {
        let fixture = try makeFixture()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: 11_436
        )
        let request = Request(
            head: HTTPRequest(
                method: .get,
                scheme: "http",
                authority: "192.168.1.40:11436",
                path: "/v1/models"
            ),
            body: RequestBody(buffer: ByteBuffer())
        )
        let channel = EmbeddedChannel()
        let context = BasicRequestContext(
            source: ApplicationRequestContextSource(
                channel: channel,
                logger: Logger(label: #function)
            )
        )

        let response = try await responder.respond(to: request, context: context)
        #expect(response.status == .forbidden)
        _ = try channel.finish()
    }
}
