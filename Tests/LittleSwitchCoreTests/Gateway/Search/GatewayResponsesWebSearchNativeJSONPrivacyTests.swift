import Foundation
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Gateway native Responses JSON privacy")
struct GatewayResponsesNativeJSONPrivacyTests {
    @Test("Provider JSON fallback cannot publish provider shell or item metadata")
    func nativeJSONFallbackPrivacy() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let providerData = try JSONSerialization.data(
            withJSONObject: nativeJSONPrivacyResponse(),
            options: [.sortedKeys]
        )
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [
                response(
                    status: .ok,
                    body: try #require(String(data: providerData, encoding: .utf8))
                )
            ]),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let result = try await responder.responsesWebSearchResponse(
            context: liveResponsesSearchContext(fixture: fixture, native: true)
        )
        let body = try await responseBodyData(result.body)
        let events = try ResponsesStreamingTestSupport.events(body)
        #expect(events.first?.name == "response.created")
        #expect(events.last?.name == "response.completed")
        #expect(events.map(\.sequenceNumber) == Array(events.indices).map(Optional.some))
        let stream = try #require(String(data: body, encoding: .utf8))
        #expect(!stream.contains("provider-secret"))

        for eventName in ["response.created", "response.in_progress", "response.completed"] {
            let shell = try #require(
                events.first { $0.name == eventName }?.payload["response"] as? [String: Any]
            )
            #expect(shell["metadata"] == nil)
            #expect(shell["parallel_tool_calls"] == nil)
            #expect(shell["model"] as? String != "provider-model")
        }
        let itemDone = try #require(
            events.first { $0.name == "response.output_item.done" }?
                .payload["item"] as? [String: Any]
        )
        #expect(itemDone["provider_secret"] == nil)
        let content = try #require(itemDone["content"] as? [[String: Any]])
        #expect(try #require(content.first)["provider_secret"] == nil)
    }
}

private func nativeJSONPrivacyResponse() -> [String: Any] {
    [
        "id": "resp_native_json_privacy",
        "object": "response",
        "created_at": 140,
        "completed_at": 141,
        "status": "completed",
        "model": "provider-model",
        "metadata": ["provider_secret": "provider-secret-root-metadata"],
        "parallel_tool_calls": false,
        "provider_secret": "provider-secret-root",
        "output": [
            [
                "id": "msg_native_json_privacy",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [
                    [
                        "type": "output_text",
                        "text": "JSON private boundary",
                        "annotations": [],
                        "logprobs": [],
                        "provider_secret": "provider-secret-part",
                    ]
                ],
                "provider_secret": "provider-secret-item",
            ]
        ],
        "usage": ["input_tokens": 2, "output_tokens": 3, "total_tokens": 5],
    ]
}
