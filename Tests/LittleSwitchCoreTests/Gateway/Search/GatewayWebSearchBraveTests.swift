import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("One search interleaves provider, Brave, and provider requests")
    func singleWebSearchWithBrave() async throws {
        let fixture = try makeWebSearchFixture(provider: .brave)
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
                body: #"{"type":"search","web":{"results":[{"title":"Swift.org","url":"https://swift.org/","#
                    + #""description":"The Swift project website"}]}}"#
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
            try #require(requests.count == 3)
            #expect(requests[0].url == "https://api.z.ai/api/anthropic/v1/messages")
            #expect(
                requests[1].url
                    == "https://api.search.brave.com/res/v1/web/search?q=Swift%206.2%20release&count=10"
            )
            #expect(requests[2].url == "https://api.z.ai/api/anthropic/v1/messages")
            #expect(requests[0].headers["authorization"] == ["Bearer selected-secret"])
            // Brave's credential rides the subscription header, not a bearer.
            #expect(requests[1].headers["x-subscription-token"] == ["brave-secret"])
            #expect(requests[1].headers["authorization"].isEmpty)
            #expect(requests[2].headers["authorization"] == ["Bearer selected-secret"])
            let searchComponents = try #require(URLComponents(string: requests[1].url))
            #expect(
                searchComponents.queryItems == [
                    URLQueryItem(name: "q", value: "Swift 6.2 release"),
                    URLQueryItem(name: "count", value: "10"),
                ])
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
