import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("A websocket upgrade probe on responses switches Codex to HTTP, not a retry loop")
    func responsesWebsocketUpgradeSignalsHTTPFallback() async throws {
        let fixture = try makeFixture()
        let app = makeApplication(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )

        try await app.test(.router) { client in
            // Codex's native provider streams each turn over a websocket
            // first and only falls back to HTTP SSE when the upgrade fails
            // with 426 Upgrade Required. Any other status — including the
            // router's default 405 — reads as a retryable stream error, so
            // the turn exhausts its retries on the websocket and dies.
            let probe = try await client.execute(
                uri: "/v1/responses",
                method: .get,
                headers: [
                    .connection: "Upgrade",
                    .upgrade: "websocket",
                ]
            )
            #expect(probe.status == .upgradeRequired)

            // A plain GET without upgrade intent is just the wrong method.
            let plainGet = try await client.execute(
                uri: "/v1/responses",
                method: .get,
                headers: HTTPFields()
            )
            #expect(plainGet.status == .methodNotAllowed)
            #expect(plainGet.headers[.allow] == "POST")

            // Any other upgrade protocol is likewise not this route's
            // handshake — it answers the plain wrong-method 405.
            let otherProtocol = try await client.execute(
                uri: "/v1/responses",
                method: .get,
                headers: [
                    .connection: "Upgrade",
                    .upgrade: "h2c",
                ]
            )
            #expect(otherProtocol.status == .methodNotAllowed)
            #expect(otherProtocol.headers[.allow] == "POST")
        }
    }
}
