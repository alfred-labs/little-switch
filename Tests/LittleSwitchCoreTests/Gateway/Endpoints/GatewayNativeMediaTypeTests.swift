import Foundation
import HummingbirdTesting
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Native Responses media types")
struct GatewayNativeMediaTypeTests {
    @Test("Non-streaming native requests leave absent media types unchanged", arguments: ["", ",\"stream\":false"])
    func nonStreaming(streamField: String) async throws {
        try await preservesJSONResponse(status: .ok, contentType: nil, streamField: streamField)
    }

    @Test(
        "Explicit JSON responses remain authoritative for streaming requests",
        arguments: ["application/json", "text/plain"])
    func explicitMediaType(contentType: String) async throws {
        try await preservesJSONResponse(status: .ok, contentType: contentType, streamField: ",\"stream\":true")
    }

    @Test("Native HTTP errors retain their body and media type", arguments: [nil, "application/json"] as [String?])
    func httpError(contentType: String?) async throws {
        try await preservesJSONResponse(status: .badRequest, contentType: contentType, streamField: ",\"stream\":true")
    }

    private func preservesJSONResponse(
        status: HTTPResponseStatus, contentType: String?, streamField: String
    ) async throws {
        let fixture = try GatewayTests().makeFixture()
        let body = #"{"id":"native","output":[]}"#
        var headers = HTTPHeaders()
        if let contentType { headers.add(name: "content-type", value: contentType) }
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(status: status, headers: headers, chunks: [body])
        ])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: "{\"model\":\"gpt-6-astra\",\"input\":\"Synthetic probe\"\(streamField)}"))
            #expect(result.status.code == Int(status.code))
            #expect(result.headers[.contentType] == contentType)
            #expect(String(buffer: result.body) == body)
        }
    }
}
