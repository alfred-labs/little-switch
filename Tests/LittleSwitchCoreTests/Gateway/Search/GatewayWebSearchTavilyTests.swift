import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("One search interleaves provider, Tavily, and provider requests")
    func singleWebSearchWithTavily() async throws {
        let fixture = try makeWebSearchFixture(provider: .tavily)
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "PROVIDER-LEAKME/id?search",
                    content: [
                        [
                            "type": "tool_use",
                            "id": "tool_search",
                            "name": "web_search",
                            "input": ["query": "Swift 6.2 release"],
                        ]
                    ],
                    stopReason: "tool_use",
                    inputTokens: 5,
                    outputTokens: 2
                )
            ),
            response(
                status: .ok,
                body: #"{"results":[{"title":"Swift.org","url":"https://swift.org/","#
                    + #""content":"The Swift project website"}]}"#
            ),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_final",
                    content: [["type": "text", "text": "Swift is current."]],
                    stopReason: "end_turn",
                    inputTokens: 8,
                    outputTokens: 4
                )
            ),
        ])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(
            fixture: fixture,
            transport: transport,
            trafficRecorder: recorder
        )

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: webSearchRequest(streaming: false, maximumUses: 2))
            )
            #expect(result.status == .ok)
            let responseObject = try anthropicObject(data(result.body))
            #expect(responseObject["model"] as? String == "claude-opus-5")
            let content = try #require(responseObject["content"] as? [[String: Any]])
            #expect(
                content.map { $0["type"] as? String }
                    == ["server_tool_use", "web_search_tool_result", "text"]
            )

            let requests = await transport.requests
            #expect(
                requests.map(\.url) == [
                    "https://api.z.ai/api/anthropic/v1/messages",
                    "https://api.tavily.com/search",
                    "https://api.z.ai/api/anthropic/v1/messages",
                ]
            )
            try #require(requests.count == 3)
            #expect(requests[0].headers["authorization"] == ["Bearer selected-secret"])
            #expect(requests[1].headers["authorization"] == ["Bearer tavily-secret"])
            #expect(requests[2].headers["authorization"] == ["Bearer selected-secret"])
            let search = try #require(
                JSONSerialization.jsonObject(with: requests[1].body) as? [String: Any]
            )
            #expect(search["query"] as? String == "Swift 6.2 release")
            #expect(search["max_results"] as? Int == 10)
            let followUp = try anthropicObject(requests[2].body)
            let messages = try #require(followUp["messages"] as? [[String: Any]])
            #expect(messages.count == 3)
            let toolResult = try #require(messages.last?["content"] as? [[String: Any]])
            #expect((toolResult[0]["content"] as? String)?.contains("Title: Swift.org") == true)
            #expect(await fixture.state.sessionRequestCount == 1)
        }

        let event = try #require(recorder.events.first)
        #expect(event.upstreamExchanges.count == 2)
    }
}
