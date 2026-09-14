import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayNativeImagesTests {
    @Test("Image edits preserve binary multipart bodies and their encoding", arguments: [false, true])
    func preservesOpaqueImageBody(compressed: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let contentType = "multipart/form-data; boundary=synthetic-image"
        let multipart =
            Data(
                "--synthetic-image\r\nContent-Disposition: form-data; name=\"image\"; filename=\"image.png\"\r\nContent-Type: image/png\r\n\r\n"
                    .utf8)
            + Data([0x89, 0x50, 0x4e, 0x47, 0x00, 0xff])
            + Data("\r\n--synthetic-image--\r\n".utf8)
        let body = compressed ? try zstdCompressed(multipart) : multipart
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: "{}")])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)
        var headers: HTTPFields = [.contentType: contentType, .authorization: "Bearer synthetic-api-key"]
        if compressed { headers[.contentEncoding] = "zstd" }
        let requestHeaders = headers
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/images/edits", method: .post, headers: requestHeaders, body: ByteBuffer(bytes: body))
            #expect(result.status == .ok)
        }
        let upstream = try #require(await transport.requests.first)
        #expect(upstream.body == body)
        #expect(upstream.headers["content-type"] == [contentType])
        #expect(upstream.headers["content-encoding"] == (compressed ? ["zstd"] : []))
    }

    @Test("Image output exceeding diagnostic limits is forwarded in full")
    func imageOutputIsNotTruncated() async throws {
        let fixture = try GatewayTests().makeFixture()
        let chunks = [#"{"created":1,"data":[{"b64_json":""#, String(repeating: "aGVsbG8=", count: 100), #""}]}"#]
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(status: .ok, headers: ["content-type": "application/json"], chunks: chunks)
        ])
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: fixture.secrets,
                maximumErrorBytes: 64,
                requiredAuthorityPort: nil))
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/images/generations", method: .post, body: ByteBuffer(string: "{}"))
            #expect(result.status == .ok)
            #expect(String(buffer: result.body) == chunks.joined())
        }
    }

    @Test("Image request stream failures are reported without reaching the provider", arguments: [false, true])
    func imageBodyFailure(cancelled: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let responder = GatewayResponder(
            state: fixture.state, transport: transport, secretStore: fixture.secrets, requiredAuthorityPort: nil)
        let request = Request(
            head: HTTPRequest(method: .post, scheme: "http", authority: "localhost", path: "/v1/images/edits"),
            body: cancelled
                ? RequestBody(asyncSequence: CancellingGatewayBodySequence())
                : RequestBody(asyncSequence: FailingGatewayBodySequence()))
        if cancelled {
            await #expect(throws: CancellationError.self) {
                _ = try await responder.routeResponse(request, eventID: UUID())
            }
        } else {
            let result = try await responder.routeResponse(request, eventID: UUID())
            #expect(result.status == .badRequest)
        }
        #expect(await transport.requests.isEmpty)
    }
}
