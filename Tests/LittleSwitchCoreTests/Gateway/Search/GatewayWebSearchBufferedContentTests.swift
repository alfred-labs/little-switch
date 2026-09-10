import Foundation
import HTTPTypes
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Buffered search preserves public text and thinking but suppresses searched-turn tools")
    func bufferedSearchPublicContent() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_search",
                    content: [
                        ["type": "text", "text": "I will check."],
                        [
                            "type": "thinking",
                            "thinking": "Need a current source.",
                            "signature": "opaque-signature",
                        ],
                        [
                            "type": "tool_use",
                            "id": "weather_private",
                            "name": "weather",
                            "input": ["city": "Paris"],
                        ],
                        searchToolBlock(id: "search_private", query: "Swift release"),
                    ],
                    stopReason: "tool_use"
                )
            ),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_final",
                    content: [["type": "text", "text": "Done."]],
                    stopReason: "end_turn"
                )
            ),
        ])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: webSearchRequest(streaming: false, maximumUses: 2))
            )

            let object = try anthropicObject(data(result.body))
            let content = try #require(object["content"] as? [[String: Any]])
            #expect(
                content.compactMap { $0["type"] as? String }
                    == [
                        "text",
                        "thinking",
                        "server_tool_use",
                        "web_search_tool_result",
                        "text",
                    ]
            )
            #expect(content[0]["text"] as? String == "I will check.")
            #expect(content[1]["thinking"] as? String == "Need a current source.")
            #expect(!String(buffer: result.body).contains("weather_private"))
            #expect(!String(buffer: result.body).contains("search_private"))
        }
    }
}
