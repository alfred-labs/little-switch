import AsyncHTTPClient
import Foundation
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchSearch
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Responses search image fallback")
struct GatewayResponsesImageSearchTests {
    @Test("An image retry reuses completed search results instead of running search again")
    func bufferedFollowUp() async throws {
        let owner = GatewayTests()
        let fixture = try await owner.makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: searchCall),
            response(status: .ok, body: gatewaySearchResponseBody(provider: .firecrawl)),
            response(status: .badRequest, body: GatewayImageFixture.rejection),
            response(status: .ok, body: finalAnswer),
        ])
        try await owner.makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: request(stream: false)))
            #expect(result.status == .ok)
        }
        let calls = await transport.requests
        #expect(calls.count == 4)
        #expect(calls.filter { $0.url.contains("firecrawl") }.count == 1)
        let retry = try #require(calls.last)
        #expect(try !GatewayImageFixture.containsImage(retry.body, wire: .chatCompletions))
        let messages = try #require(ResponsesCompactionFixture.object(retry.body)["messages"] as? [[String: Any]])
        #expect(messages.contains { ($0["content"] as? String)?.contains("Title:") == true })
    }

    @Test("A streaming first head may retry before publishing success")
    func streamingFirstHead() async throws {
        let owner = GatewayTests()
        let fixture = try await owner.makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .badRequest, body: GatewayImageFixture.rejection),
            response(status: .ok, body: finalAnswer),
        ])
        try await owner.makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: request(stream: true)))
            #expect(result.status == .ok)
            #expect(String(buffer: result.body).contains("response.completed"))
        }
        #expect(await transport.requests.count == 2)
    }

    @Test("A rejected follow-up after published stream events fails without a second success stream")
    func streamingFollowUp() async throws {
        let owner = GatewayTests()
        let fixture = try await owner.makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: searchCall),
            response(status: .ok, body: gatewaySearchResponseBody(provider: .firecrawl)),
            response(status: .badRequest, body: GatewayImageFixture.rejection),
        ])
        try await owner.makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: request(stream: true)))
            #expect(String(buffer: result.body).contains("response.failed"))
        }
        #expect(await transport.requests.count == 3)
        #expect(await transport.requests.filter { $0.url.contains("firecrawl") }.count == 1)
    }

    private func request(stream: Bool) throws -> Data {
        try ResponsesCompactionFixture.data([
            "model": "z.ai/glm-5.2", "stream": stream,
            "input": [GatewayImageFixture.imageMessage], "tools": [["type": "web_search"]],
        ])
    }

    private var searchCall: String {
        responsesModelResponse(
            id: "search",
            output: [
                [
                    "type": "function_call", "call_id": "search", "name": "web_search",
                    "arguments": #"{"query":"Swift"}"#,
                ]
            ])
    }

    private var finalAnswer: String {
        responsesModelResponse(
            id: "final",
            output: [
                [
                    "type": "message", "role": "assistant", "content": [["type": "output_text", "text": "Done"]],
                ]
            ])
    }
}
