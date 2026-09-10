import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing

@testable import LittleSwitchCore

/// The gateway's own root and `/api/` surface, plus the `/_little_switch/*`
/// compat aliases that keep answering during the rename window.
extension GatewayTests {
    @Test("Legacy probe paths keep answering during the compat window")
    func legacyProbeAliases() async throws {
        let fixture = try makeFixture()
        let app = makeApplication(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )

        try await app.test(.router) { client in
            let health = try await client.execute(
                uri: "/_little_switch/health",
                method: .get,
                headers: HTTPFields()
            )
            #expect(health.status == .noContent)

            let about = try await client.execute(
                uri: "/_little_switch/about",
                method: .get,
                headers: HTTPFields()
            )
            #expect(about.status == .ok)
        }
    }

    @Test("The reserved metrics path stays unimplemented")
    func metricsPathStaysReserved() async throws {
        let fixture = try makeFixture()
        let app = makeApplication(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )

        try await app.test(.router) { client in
            let get = try await client.execute(
                uri: "/metrics",
                method: .get,
                headers: HTTPFields()
            )
            #expect(get.status == .notFound)

            let post = try await client.execute(
                uri: "/metrics",
                method: .post,
                headers: HTTPFields()
            )
            #expect(post.status == .notFound)
        }
    }
}
