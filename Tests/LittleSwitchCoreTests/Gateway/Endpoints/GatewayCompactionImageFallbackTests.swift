import AsyncHTTPClient
import Foundation
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Compaction image rejection fallback")
struct GatewayCompactionImageFallbackTests {
    @Test("The original incident retries text and retains the original image")
    func incident() async throws {
        let fixture = try await GatewayImageFixture.make(wire: .chatCompletions)
        let transport = RecordingGatewayTransport(responses: [
            response(status: .badRequest, body: GatewayImageFixture.rejection),
            response(status: .ok, body: try summary()),
        ])
        try await fixture.application(transport).test(.router) { client in
            let body = try ResponsesCompactionFixture.request(
                items: [GatewayImageFixture.imageMessage], fields: ["model": fixture.slug])
            let result = try await client.execute(uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: body))
            #expect(result.status == .ok)
            var decoder = ServerSentEventDecoder(maximumFrameBytes: 32_768)
            let frames = try decoder.append(result.body) + decoder.finish()
            let root = try ResponsesCompactionFixture.object(try #require(frames.last).data)
            let response = try #require(root["response"] as? [String: Any])
            let item = try #require((response["output"] as? [[String: Any]])?.first)
            let payload = try ResponsesCompactionFixture.object(
                Data(try #require(item["encrypted_content"] as? String).utf8))
            #expect(
                try ResponsesCompactionFixture.data(payload["retained"] as Any)
                    == ResponsesCompactionFixture.data([GatewayImageFixture.imageMessage]))
        }
        #expect(await transport.requests.count == 2)
        #expect(
            try !GatewayImageFixture.containsImage(
                try #require(await transport.requests.last).body, wire: .chatCompletions))
        #expect(await fixture.registry.observations().first?.verdict == .unsupported)
        await fixture.registry.shutdown()
    }

    @Test("Route, image, selection and context retries share exactly five calls")
    func sharedBudget() async throws {
        let fixture = try await GatewayImageFixture.make(wire: .responses)
        let transport = RecordingGatewayTransport(responses: [
            response(status: .notFound, body: "missing"),
            response(status: .badRequest, body: GatewayImageFixture.rejection),
            response(status: .ok, body: try summary(text: "")),
            response(status: .badRequest, body: #"{"error":{"code":"context_length_exceeded"}}"#),
            response(status: .ok, body: try summary()),
        ])
        let old = ["type": "message", "role": "assistant", "content": String(repeating: "old detail ", count: 300)]
        try await fixture.application(transport).test(.router) { client in
            let body = try ResponsesCompactionFixture.request(
                items: [old, GatewayImageFixture.imageMessage, ResponsesCompactionFixture.message],
                fields: ["model": fixture.slug])
            let result = try await client.execute(uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: body))
            #expect(result.status == .ok)
        }
        let requests = await transport.requests
        #expect(requests.count == 5)
        #expect(requests[0].url.hasSuffix("/responses"))
        #expect(requests.dropFirst().allSatisfy { $0.url.hasSuffix("/chat/completions") })
        #expect(
            try requests.dropFirst(2).allSatisfy {
                try !GatewayImageFixture.containsImage($0.body, wire: .chatCompletions)
            })
        await fixture.registry.shutdown()
    }

    private func summary(text: String = "Continue the task") throws -> String {
        let root = try ResponsesCompactionFixture.object(ResponsesCompactionFixture.response(summary: text))
        return responsesModelResponse(id: "summary", output: try #require(root["output"] as? [[String: Any]]))
    }
}
