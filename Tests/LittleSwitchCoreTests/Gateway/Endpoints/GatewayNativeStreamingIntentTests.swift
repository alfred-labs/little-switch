import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Native Responses streaming intent")
struct GatewayNativeStreamingIntentTests {
    @Test(
        "Only stream true infers SSE when the provider omits its media type",
        arguments: ["", "false", "true", "1", "null"])
    func inferredMediaType(stream: String) async throws {
        let response = try await nativeResponse(stream: stream, contentType: nil)
        #expect(response.status == .ok)
        #expect(response.headers[.contentType] == (stream == "true" ? "text/event-stream" : nil))
        #expect(try await responseBodyData(response.body) == Data("{}".utf8))
    }

    @Test(
        "Explicit provider media types remain authoritative over the request stream flag",
        arguments: [false, true], ["application/json", "text/event-stream"])
    func explicitMediaType(stream: Bool, contentType: String) async throws {
        let response = try await nativeResponse(stream: String(stream), contentType: contentType)
        #expect(response.status == .ok)
        #expect(response.headers[.contentType] == contentType)
        #expect(try await responseBodyData(response.body) == Data("{}".utf8))
    }

    private func nativeResponse(stream: String, contentType: String?) async throws -> Response {
        let fixture = try GatewayTests().makeFixture()
        var headers = HTTPHeaders()
        if let contentType { headers.add(name: "content-type", value: contentType) }
        let http = RecordingGatewayTransport(responses: [
            streamingResponse(status: .ok, headers: headers, chunks: ["{}"])
        ])
        let responder = GatewayResponder(
            state: fixture.state, transport: http, secretStore: fixture.secrets, requiredAuthorityPort: nil)
        let streamField = stream.isEmpty ? "" : ",\"stream\":\(stream)"
        let body = Data("{\"model\":\"gpt-6-astra\",\"input\":\"Synthetic\"\(streamField)}".utf8)
        let request = Request(
            head: HTTPRequest(method: .post, scheme: "http", authority: "localhost", path: "/v1/responses"),
            body: .init(buffer: ByteBuffer(bytes: body)))
        let response = try await responder.responsesResponse(request, eventID: UUID())
        #expect(await http.requests.count == 1)
        #expect(await http.requests.first?.body == body)
        return response
    }
}
