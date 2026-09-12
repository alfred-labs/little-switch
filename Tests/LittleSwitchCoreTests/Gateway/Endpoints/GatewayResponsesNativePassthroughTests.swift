import AsyncHTTPClient
import Foundation
import HTTPTypes
import HummingbirdTesting
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    private static let nativeBody =
        #"{"model":"gpt-5.6-sol","stream":true,"input":[{"type":"message","role":"developer","content":[{"type":"input_text","text":"native instructions"}]}]}"#

    @Test("Codex's native reviewer reaches ChatGPT independently of the custom reviewer", arguments: [false, true])
    func nativeReviewerPassthrough(explicitReviewer: Bool) async throws {
        let fixture = try makeFixture()
        var snapshot = fixture.snapshot
        if explicitReviewer {
            snapshot.codex.autoReviewModel = snapshot.codex.resolvedDefaultModel(in: snapshot.providers)
        }
        let reviewFixture = GatewayFixture(
            snapshot: snapshot, state: GatewayState(snapshot: snapshot), secrets: fixture.secrets)
        let decision = #"{"outcome":"allow"}"#
        let body = Data(
            #"""
            {"model":"codex-auto-review","input":"Synthetic approval request.","instructions":"Review the action.",
            "reasoning":{"effort":"low"},"text":{"format":{"type":"json_schema","name":"review","schema":{"type":"object"}}}}
            """#.utf8)
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: decision)])
        let app = makeApplication(fixture: reviewFixture, transport: transport)
        let accountID = try #require(HTTPField.Name("ChatGPT-Account-ID"))

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.authorization: "Bearer synthetic-session", accountID: "synthetic-account"],
                body: ByteBuffer(bytes: body))
            #expect(result.status == .ok)
            #expect(String(buffer: result.body) == decision)
        }
        let requests = await transport.requests
        #expect(requests.count == 1)
        let upstream = try #require(requests.first)
        #expect(upstream.url == "https://chatgpt.com/backend-api/codex/responses")
        #expect(upstream.body == body)
        #expect(upstream.headers["authorization"] == ["Bearer synthetic-session"])
        #expect(upstream.headers["chatgpt-account-id"] == ["synthetic-account"])
    }

    @Test("A native model reaches the ChatGPT backend with the session preserved")
    func nativeChatGPTPassthrough() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .accepted, body: "native")
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let accountID = try #require(HTTPField.Name("ChatGPT-Account-ID"))
        let turnMetadata = try #require(HTTPField.Name("X-Codex-Turn-Metadata"))
        let keepAlive = try #require(HTTPField.Name("Keep-Alive"))
        let te = try #require(HTTPField.Name("TE"))

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer chatgpt-secret",
                    accountID: "account-123",
                    turnMetadata: #"{"thread":"kept"}"#,
                    .connection: "keep-alive",
                    keepAlive: "timeout=5",
                    te: "trailers",
                ],
                body: ByteBuffer(string: Self.nativeBody)
            )

            #expect(response.status == .accepted)
            #expect(String(data: data(response.body), encoding: .utf8) == "native")
        }

        let upstream = try #require(await transport.requests.first)
        #expect(upstream.url == "https://chatgpt.com/backend-api/codex/responses")
        #expect(upstream.headers["authorization"] == ["Bearer chatgpt-secret"])
        #expect(upstream.headers["ChatGPT-Account-ID"] == ["account-123"])
        #expect(upstream.headers["X-Codex-Turn-Metadata"] == [#"{"thread":"kept"}"#])
        #expect(upstream.headers["connection"].isEmpty)
        #expect(upstream.headers["keep-alive"].isEmpty)
        #expect(upstream.headers["te"].isEmpty)
        #expect(String(data: upstream.body, encoding: .utf8) == Self.nativeBody)
    }

    @Test("A native model without a ChatGPT session reaches the OpenAI endpoint")
    func nativeOpenAIPassthrough() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .accepted, body: "{}")
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let organization = try #require(HTTPField.Name("OpenAI-Organization"))

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer sk-test",
                    organization: "org-test",
                ],
                body: ByteBuffer(string: Self.nativeBody)
            )

            #expect(response.status == .accepted)
        }

        let upstream = try #require(await transport.requests.first)
        #expect(upstream.url == "https://api.openai.com/v1/responses")
        #expect(upstream.headers["authorization"] == ["Bearer sk-test"])
        #expect(upstream.headers["OpenAI-Organization"] == ["org-test"])
    }

    @Test("The LittleSwitch sentinel is rejected before any native forwarding")
    func sentinelRejection() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer \(CodexNativePassthrough.sentinelAPIKey)",
                ],
                body: ByteBuffer(string: Self.nativeBody)
            )

            #expect(response.status == .unauthorized)
            let body = String(data: data(response.body), encoding: .utf8) ?? ""
            #expect(body.contains("signing in to ChatGPT"))
        }

        #expect(await transport.requests.isEmpty)
    }

    @Test("A request body without a model slug still fails as unknown")
    func unparseableBodyStillUnknown() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: "not-json")
            )

            #expect(response.status == .badRequest)
            let body = String(data: data(response.body), encoding: .utf8) ?? ""
            #expect(body.contains("Unknown or invalid model"))
        }

        #expect(await transport.requests.isEmpty)
    }

    @Test("A LittleSwitch-shaped slug never leaks into native passthrough")
    func littleSwitchSlugIsRejectedNatively() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(
                    string: #"{"model":"stale/provider/model"}"#
                )
            )

            #expect(response.status == .badRequest)
        }

        #expect(await transport.requests.isEmpty)
    }

    @Test("A native upstream failure surfaces as a bad gateway")
    func nativeUpstreamFailure() async throws {
        let fixture = try makeFixture()
        struct FailingNativeTransport: UpstreamTransport {
            func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
                throw URLError(.badServerResponse)
            }
        }
        let app = makeApplication(fixture: fixture, transport: FailingNativeTransport())

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: Self.nativeBody)
            )

            #expect(response.status == .badGateway)
        }
    }

    @Test("A cancelled native exchange propagates cancellation")
    func nativeCancellationPropagates() async throws {
        let fixture = try makeFixture()
        let app = makeApplication(fixture: fixture, transport: CancellingGatewayTransport())

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: Self.nativeBody)
            )

            #expect(response.status == .internalServerError)
        }
    }
}
