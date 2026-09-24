import Testing

@testable import LittleSwitchCore

extension GatewayServerTests {
    @Test("Stopping a secondary listener leaves shared admissions available")
    func secondaryListenerKeepsAdmissions() async throws {
        let fixture = try GatewayTests().makeFixture()
        let runner = AutomaticallyReadyGatewayServerRunner()
        let server = GatewayServer(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            listenPort: 0,
            requiredAuthorityPort: nil,
            runnerFactory: ReusableGatewayServerRunnerFactory(runner: runner),
            stopsAdmissionsOnStop: false
        )
        try await server.start()
        await server.stop()
        try await fixture.state.admit(client: .codex)
        #expect(await fixture.state.codexSessionRequestCount == 1)
    }
}
