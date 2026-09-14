import Foundation
import HTTPTypes
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Native Codex images")
struct GatewayNativeImagesTests {
    @Test(
        "Native image generation and edits preserve the subscription or API session",
        arguments: ["generations", "edits"], [false, true])
    func forwardsImages(operation: String, accountSession: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let wire = #"{"created":1,"data":[{"b64_json":"c3ludGhldGlj","revised_prompt":"Synthetic image"}]}"#
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(
                status: .ok,
                headers: ["content-type": "application/json", "x-codex-imagegen-request-id": "image-request-123"],
                chunks: [String(wire.prefix(20)), String(wire.dropFirst(20))])
        ])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)
        let accountID = try #require(HTTPField.Name("ChatGPT-Account-ID"))
        let imageTurnID = try #require(HTTPField.Name("X-Codex-Image-Turn-ID"))
        let imageRequestID = try #require(HTTPField.Name("X-Codex-Imagegen-Request-ID"))
        let hop = try #require(HTTPField.Name("X-Hop"))
        var headers: HTTPFields = [
            .contentType: "application/json",
            .authorization: "Bearer synthetic-native-session",
            imageTurnID: "image-turn-123",
            .connection: "keep-alive, X-Hop",
            hop: "local-only",
        ]
        if accountSession { headers[accountID] = "synthetic-account" }
        let requestHeaders = headers
        let body =
            operation == "edits"
            ? #"{"model":"gpt-image-2","prompt":"Synthetic edit","images":[{"image_url":"data:image/png;base64,c3ludGhldGlj"}]}"#
            : #"{"model":"gpt-image-2","prompt":"Synthetic image","size":"auto"}"#

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/images/\(operation)",
                method: .post,
                headers: requestHeaders,
                body: ByteBuffer(string: body))
            #expect(result.status == .ok)
            #expect(String(buffer: result.body) == wire)
            #expect(result.headers[.contentType] == "application/json")
            #expect(result.headers[imageRequestID] == "image-request-123")
        }

        let requests = await transport.requests
        #expect(requests.count == 1)
        let upstream = try #require(requests.first)
        let baseURL = accountSession ? "https://chatgpt.com/backend-api/codex" : "https://api.openai.com/v1"
        #expect(upstream.url == "\(baseURL)/images/\(operation)")
        #expect(upstream.body == Data(body.utf8))
        #expect(upstream.headers["authorization"] == ["Bearer synthetic-native-session"])
        #expect(upstream.headers["chatgpt-account-id"] == (accountSession ? ["synthetic-account"] : []))
        #expect(upstream.headers["x-codex-image-turn-id"] == ["image-turn-123"])
        #expect(upstream.headers["content-type"] == ["application/json"])
        #expect(upstream.headers["connection"].isEmpty)
        #expect(upstream.headers["x-hop"].isEmpty)
    }

    @Test("Native image routes work over a real HTTP listener", arguments: ["generations", "edits"])
    func imagesOverHTTP(operation: String) async throws {
        let fixture = try GatewayTests().makeFixture()
        let wire = #"{"created":1,"data":[{"b64_json":"c3ludGhldGlj"}]}"#
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: wire)])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)
        let accountID = try #require(HTTPField.Name("ChatGPT-Account-ID"))
        let body =
            operation == "edits"
            ? #"{"model":"gpt-image-2","prompt":"Synthetic edit","images":[{"image_url":"data:image/png;base64,c3ludGhldGlj"}]}"#
            : #"{"model":"gpt-image-2","prompt":"Synthetic image"}"#
        try await app.test(.live) { client in
            let result = try await client.execute(
                uri: "/v1/images/\(operation)",
                method: .post,
                headers: [.authorization: "Bearer synthetic-session", accountID: "synthetic-account"],
                body: ByteBuffer(string: body))
            #expect(result.status == .ok)
            #expect(String(buffer: result.body) == wire)
        }
        let upstream = try #require(await transport.requests.first)
        #expect(upstream.url == "https://chatgpt.com/backend-api/codex/images/\(operation)")
        #expect(upstream.body == Data(body.utf8))
        #expect(upstream.headers["authorization"] == ["Bearer synthetic-session"])
        #expect(upstream.headers["chatgpt-account-id"] == ["synthetic-account"])
    }
}
