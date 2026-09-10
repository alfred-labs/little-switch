import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Bounded web search retains thinking effort on result and terminal follow-ups", arguments: [false, true])
    func disabledThinkingWebSearchTurns(streaming: Bool) async throws {
        let fixture = try thinkingFixture(webSearch: true)
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_search_1",
                    content: [searchToolBlock(id: "search_1", query: "Swift release")],
                    stopReason: "tool_use"
                )
            ),
            response(status: .ok, body: gatewaySearchResponseBody(provider: .firecrawl)),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_search_2",
                    content: [searchToolBlock(id: "search_2", query: "Another search")],
                    stopReason: "tool_use"
                )
            ),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_final", content: [["type": "text", "text": "Done"]], stopReason: "end_turn"
                )
            ),
        ])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(fixture: fixture, transport: transport, trafficRecorder: recorder)
        let incoming = Data(
            #"""
            {"model":"claude-opus-5","stream":\#(streaming),"max_tokens":64,
             "thinking":{"type":"disabled"},"output_config":{"format":{"type":"text"}},
             "metadata":{"opaque":7},"stop_sequences":["stop"],
             "messages":[{"role":"user","content":[
               {"type":"text","text":"Search once.","cache_control":{"type":"ephemeral"}}
             ]}],"tools":[{"type":"web_search_20250305","max_uses":1}]}
            """#.utf8
        )

        try await app.test(.router) { client in
            let result = try await client.execute(uri: "/v1/messages", method: .post, body: ByteBuffer(bytes: incoming))
            #expect(result.status == .ok)
            #expect(String(buffer: result.body).contains("Done"))
        }

        let requests = await transport.requests
        #expect(requests.count == 4)
        #expect(requests.filter { $0.url == "https://api.firecrawl.dev/v2/search" }.count == 1)
        let modelRequests = requests.filter { $0.url.hasSuffix("/messages") }
        #expect(modelRequests.count == 3)
        var expected = try #require(JSONSerialization.jsonObject(with: incoming) as? [String: Any])
        expected["model"] = "glm-5.2"
        expected["output_config"] = ["format": ["type": "text"], "effort": "low"]
        let originalMessages = try #require(expected.removeValue(forKey: "messages") as? [[String: Any]])
        expected.removeValue(forKey: "tools")
        for (index, request) in modelRequests.enumerated() {
            var actual = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            let messages = try #require(actual.removeValue(forKey: "messages") as? [[String: Any]])
            #expect(messages.count == 1 + index * 2)
            #expect(messages.first as NSDictionary? == originalMessages.first as NSDictionary?)
            actual.removeValue(forKey: "tools")
            actual.removeValue(forKey: "tool_choice")
            #expect(actual as NSDictionary == expected as NSDictionary)
        }
        let event = try #require(recorder.events.first)
        #expect(event.claudeRequest.body == incoming)
        #expect(event.upstreamExchanges.compactMap { $0.request?.body } == modelRequests.map(\.body))
        #expect(await fixture.state.sessionRequestCount == 1)
    }
}
