import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("JSON fallback streams empty ordinary tool input as a delta")
    func liveAnthropicJSONFallbackEmptyToolInput() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "json_empty_tool",
                    content: [
                        [
                            "type": "tool_use",
                            "id": "weather_empty",
                            "name": "weather",
                            "input": [:],
                        ]
                    ],
                    stopReason: "tool_use"
                )
            )
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let response = try await responder.webSearchResponse(
            context: gatewayLiveContext(fixture: fixture)
        )
        let events = try gatewayPublicEvents(try await responseBodyData(response.body))
        let start = try #require(
            events.first {
                ($0.payload["content_block"] as? [String: Any])?["id"] as? String
                    == "weather_empty"
            }
        )
        let index = try #require(start.payload["index"] as? Int)
        let tool = try #require(start.payload["content_block"] as? [String: Any])
        #expect((tool["input"] as? [String: Any])?.isEmpty == true)

        let toolEvents = events.filter { $0.payload["index"] as? Int == index }
        #expect(
            toolEvents.map(\.name)
                == ["content_block_start", "content_block_delta", "content_block_stop"]
        )
        let delta = try #require(toolEvents[1].payload["delta"] as? [String: Any])
        #expect(delta["type"] as? String == "input_json_delta")
        #expect(delta["partial_json"] as? String == "{}")
    }

    @Test("Two live searches use native independent IDs and cumulative indices")
    func liveAnthropicTwoSearchesUseNativeIDs() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "PROVIDER-LEAKME/first?",
                    content: [searchToolBlock(id: "private-one", query: "first")],
                    stopReason: "tool_use",
                    inputTokens: 2,
                    outputTokens: 3
                )
            ),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "PROVIDER:LEAKME-second!",
                    content: [searchToolBlock(id: "private-two", query: "second")],
                    stopReason: "tool_use",
                    inputTokens: 4,
                    outputTokens: 5
                )
            ),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "provider_terminal",
                    content: [["type": "text", "text": "Done"]],
                    stopReason: "end_turn",
                    inputTokens: 6,
                    outputTokens: 7
                )
            ),
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let response = try await responder.webSearchResponse(
            context: gatewayLiveContext(fixture: fixture)
        )
        let events = try gatewayPublicEvents(try await responseBodyData(response.body))
        let starts = events.compactMap {
            $0.payload["content_block"] as? [String: Any]
        }
        let serverIDs = starts.compactMap { block -> String? in
            guard block["type"] as? String == "server_tool_use" else { return nil }
            return block["id"] as? String
        }
        let resultIDs = starts.compactMap { block -> String? in
            guard block["type"] as? String == "web_search_tool_result" else { return nil }
            return block["tool_use_id"] as? String
        }
        #expect(serverIDs.count == 2)
        #expect(Set(serverIDs).count == 2)
        #expect(serverIDs.allSatisfy(isNativeServerToolID))
        #expect(serverIDs.allSatisfy { !$0.contains("PROVIDER") })
        #expect(resultIDs == serverIDs)

        let indices = events.compactMap { event -> Int? in
            guard event.name == "content_block_start" else { return nil }
            return event.payload["index"] as? Int
        }
        #expect(indices == [0, 1, 2, 3, 4])
        let finalDelta = try #require(events.last { $0.name == "message_delta" })
        let usage = try #require(finalDelta.payload["usage"] as? [String: Any])
        #expect(
            serverToolUsage(usage)
                == ["web_search_requests": 2, "web_fetch_requests": 0]
        )
        #expect(events.filter { $0.name == "message_start" }.count == 1)
        #expect(events.filter { $0.name == "message_stop" }.count == 1)

        let requests = await transport.requests
        #expect(requests.map(\.url).filter { $0.contains("firecrawl") }.count == 2)
    }
}

private func gatewayPublicEvents(_ data: Data) throws -> [PublicAnthropicEvent] {
    var decoder = ServerSentEventDecoder(maximumFrameBytes: max(data.count, 1))
    var frames = try decoder.append(ByteBuffer(bytes: data))
    frames += try decoder.finish()
    return try frames.map { frame in
        PublicAnthropicEvent(
            name: try #require(frame.event),
            payload: try liveJSONObject(frame.data)
        )
    }
}

func isNativeServerToolID(_ id: String) -> Bool {
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_")
    return id.hasPrefix("srvtoolu_") && id.allSatisfy { allowed.contains($0) }
}
