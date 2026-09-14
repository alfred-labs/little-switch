import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayNativeImagesTests {
    @Test("Image endpoints enforce local admission without forwarding", arguments: ["generations", "edits"])
    func rejectsImagesLocally(operation: String) async throws {
        let fixture = try GatewayTests().makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport, maximumRequestBytes: 8)
        let path = "/v1/images/\(operation)"

        try await app.test(.router) { client in
            let method = try await client.execute(uri: path, method: .get)
            #expect(method.status == .methodNotAllowed)
            #expect(method.headers[.allow] == "POST")
            try expectOpenAIError(method.body)

            let origin = try await client.execute(uri: path, method: .post, headers: [.origin: "https://example.com"])
            #expect(origin.status == .forbidden)
            try expectOpenAIError(origin.body)

            let sentinel = try await client.execute(
                uri: path,
                method: .post,
                headers: [.authorization: "Bearer little-switch-local-codex"],
                body: ByteBuffer(string: "{}"))
            #expect(sentinel.status == .unauthorized)
            try expectOpenAIError(sentinel.body)

            let oversized = try await client.execute(uri: path, method: .post, body: ByteBuffer(string: "123456789"))
            #expect(oversized.status == .contentTooLarge)
            try expectOpenAIError(oversized.body)

            let unknown = try await client.execute(uri: "/v1/images/arbitrary", method: .post)
            #expect(unknown.status == .notFound)
        }
        let strictApp = Application(
            responder: GatewayResponder(
                state: fixture.state, transport: transport, secretStore: fixture.secrets, requiredAuthorityPort: 11_436)
        )
        try await strictApp.test(.router) { client in
            let authority = try await client.execute(uri: path, method: .post)
            #expect(authority.status == .forbidden)
            try expectOpenAIError(authority.body)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Image provider errors preserve their status, body, and retry headers")
    func preservesImageProviderError() async throws {
        let fixture = try GatewayTests().makeFixture()
        let wire =
            #"{"error":{"message":"Synthetic image limit","type":"rate_limit_error","code":"rate_limit_exceeded"}}"#
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(
                status: .tooManyRequests,
                headers: [
                    "content-type": "application/json", "retry-after": "30", "connection": "X-Hop", "x-hop": "private",
                ],
                chunks: [wire])
        ])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/images/generations", method: .post, body: ByteBuffer(string: "{}"))
            #expect(result.status == .tooManyRequests)
            #expect(String(buffer: result.body) == wire)
            #expect(result.headers[.retryAfter] == "30")
            #expect(result.headers[try #require(HTTPField.Name("X-Hop"))] == nil)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test("Image transport failures use OpenAI errors and cancellation propagates")
    func imageTransportFailures() async throws {
        struct FailingImageTransport: UpstreamTransport {
            func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
                throw URLError(.badServerResponse)
            }
        }
        let fixture = try GatewayTests().makeFixture()
        let failingApp = GatewayTests().makeApplication(fixture: fixture, transport: FailingImageTransport())
        try await failingApp.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/images/edits", method: .post, body: ByteBuffer(string: "{}"))
            #expect(result.status == .badGateway)
            try expectOpenAIError(result.body)
        }
        let responder = GatewayResponder(
            state: fixture.state,
            transport: CancellingGatewayTransport(),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil)
        let request = Request(
            head: HTTPRequest(method: .post, scheme: "http", authority: "localhost", path: "/v1/images/edits"),
            body: RequestBody(buffer: ByteBuffer(string: "{}")))
        await #expect(throws: CancellationError.self) {
            _ = try await responder.routeResponse(request, eventID: UUID())
        }
    }

    private func expectOpenAIError(_ body: ByteBuffer) throws {
        let root = try #require(JSONSerialization.jsonObject(with: Data(body.readableBytesView)) as? [String: Any])
        let error = try #require(root["error"] as? [String: Any])
        #expect(error["message"] is String)
        #expect(error["type"] is String)
        #expect(root["type"] == nil)
    }
}
