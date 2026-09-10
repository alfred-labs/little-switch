import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

func realisticProviderFrames() throws -> [ServerSentEventFrame] {
    try realisticPublicContentFrames()
        + realisticSearchToolFrames()
        + realisticTerminalFrames()
}

private func realisticPublicContentFrames() throws -> [ServerSentEventFrame] {
    [
        try providerFrame(
            "message_start",
            [
                "type": "message_start",
                "message": providerMessage(id: "msg_provider", inputTokens: 12),
            ]
        ),
        try providerFrame(
            "content_block_start",
            [
                "type": "content_block_start",
                "index": 0,
                "content_block": ["type": "text", "text": "", "citations": []],
            ]
        ),
        try providerFrame(
            "content_block_delta",
            [
                "type": "content_block_delta",
                "index": 0,
                "delta": ["type": "text_delta", "text": "I should search."],
            ]
        ),
        try providerFrame(
            "content_block_delta",
            [
                "type": "content_block_delta",
                "index": 0,
                "delta": [
                    "type": "citations_delta",
                    "citation": [
                        "type": "web_search_result_location",
                        "url": "https://swift.org/",
                        "title": "Swift.org",
                        "cited_text": "Swift documentation",
                        "encrypted_index": "opaque-index",
                    ],
                ],
            ]
        ),
        try providerFrame(
            "content_block_stop",
            ["type": "content_block_stop", "index": 0]
        ),
        try providerFrame(
            "content_block_start",
            [
                "type": "content_block_start",
                "index": 1,
                "content_block": ["type": "thinking", "thinking": "", "signature": ""],
            ]
        ),
        try providerFrame(
            "content_block_delta",
            [
                "type": "content_block_delta",
                "index": 1,
                "delta": ["type": "thinking_delta", "thinking": "Need current sources."],
            ]
        ),
        try providerFrame(
            "content_block_delta",
            [
                "type": "content_block_delta",
                "index": 1,
                "delta": ["type": "signature_delta", "signature": "opaque-signature"],
            ]
        ),
        try providerFrame(
            "content_block_stop",
            ["type": "content_block_stop", "index": 1]
        ),
    ]
}

private func realisticSearchToolFrames() throws -> [ServerSentEventFrame] {
    [
        try providerFrame(
            "content_block_start",
            [
                "type": "content_block_start",
                "index": 2,
                "content_block": [
                    "type": "tool_use",
                    "id": "toolu_search",
                    "name": "web_search",
                    "input": [:],
                ],
            ]
        ),
        try providerFrame(
            "content_block_delta",
            [
                "type": "content_block_delta",
                "index": 2,
                "delta": [
                    "type": "input_json_delta",
                    "partial_json": #"{"query":"latest "#,
                ],
            ]
        ),
        try providerFrame("ping", ["type": "ping"]),
        try providerFrame(
            "content_block_delta",
            [
                "type": "content_block_delta",
                "index": 2,
                "delta": [
                    "type": "input_json_delta",
                    "partial_json": #"Swift"}"#,
                ],
            ]
        ),
        try providerFrame(
            "content_block_stop",
            ["type": "content_block_stop", "index": 2]
        ),
    ]
}

private func realisticTerminalFrames() throws -> [ServerSentEventFrame] {
    [
        try providerFrame(
            "message_delta",
            [
                "type": "message_delta",
                "delta": [
                    "stop_reason": NSNull(),
                    "stop_sequence": "provider-sequence",
                ],
                "usage": ["input_tokens": NSNull(), "output_tokens": 5],
            ]
        ),
        try providerFrame(
            "message_delta",
            [
                "type": "message_delta",
                "delta": ["stop_reason": "tool_use", "stop_sequence": NSNull()],
                "usage": ["input_tokens": NSNull(), "output_tokens": 7],
            ]
        ),
        try providerFrame("message_stop", ["type": "message_stop"]),
    ]
}

func providerMessage(
    id: String,
    inputTokens: Int = 0
) -> [String: Any] {
    [
        "id": id,
        "type": "message",
        "role": "assistant",
        "model": "provider-model",
        "content": [],
        "stop_reason": NSNull(),
        "stop_sequence": NSNull(),
        "usage": ["input_tokens": inputTokens, "output_tokens": 0],
    ]
}

func providerFrame(
    _ event: String,
    _ payload: [String: Any]
) throws -> ServerSentEventFrame {
    ServerSentEventFrame(
        event: event,
        data: try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ),
        terminal: false
    )
}

func messageStartEvent(
    id: String,
    inputTokens: Int
) throws -> AnthropicProviderStreamEvent {
    .messageStart(
        messageJSON: try jsonData(providerMessage(id: id, inputTokens: inputTokens))
    )
}

func contentStartEvent(
    index: Int,
    block: [String: Any]
) throws -> AnthropicProviderStreamEvent {
    .contentStart(index: index, blockJSON: try jsonData(block))
}

func contentDeltaEvent(
    index: Int,
    delta: [String: Any]
) throws -> AnthropicProviderStreamEvent {
    .contentDelta(index: index, deltaJSON: try jsonData(delta))
}

func feedPrivateSearchTurn(
    into session: inout AnthropicPublicStreamSession,
    providerToolID: String,
    query: String
) throws -> [Data] {
    var frames: [Data] = []
    frames += try session.consumePublic(
        contentStartEvent(
            index: 0,
            block: [
                "type": "tool_use",
                "id": providerToolID,
                "name": "web_search",
                "input": [:],
            ]
        )
    )
    let partialJSON = try utf8String(jsonData(["query": query]))
    frames += try session.consumePublic(
        contentDeltaEvent(
            index: 0,
            delta: ["type": "input_json_delta", "partial_json": partialJSON]
        )
    )
    frames += try session.consumePublic(.contentStop(index: 0))
    frames += try closeProviderTurn(&session, stopReason: "tool_use", outputTokens: 7)
    return frames
}

func closeProviderTurn(
    _ session: inout AnthropicPublicStreamSession,
    stopReason: String,
    outputTokens: Int
) throws -> [Data] {
    var frames = try session.consumePublic(
        .messageDelta(
            deltaJSON: try jsonData([
                "stop_reason": stopReason,
                "stop_sequence": NSNull(),
            ]),
            usageJSON: try jsonData(["output_tokens": outputTokens])
        )
    )
    frames += try session.consumePublic(.messageStop)
    return frames
}

func terminalTurn(id: String, stopReason: String) throws -> AnthropicModelTurn {
    try AnthropicWebSearch.parseModelTurn(
        jsonData([
            "id": id,
            "content": [],
            "stop_reason": stopReason,
            "stop_sequence": NSNull(),
            "usage": ["input_tokens": 0, "output_tokens": 0],
        ])
    )
}

struct PublicAnthropicEvent {
    let name: String
    let payload: [String: Any]
}

func parsePublicFrames(_ frames: [Data]) throws -> [PublicAnthropicEvent] {
    try frames.map { frame in
        let text = try #require(String(data: frame, encoding: .utf8))
        #expect(text.hasSuffix("\n\n"))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 4)
        let eventPrefix = "event: "
        let dataPrefix = "data: "
        let eventLine = try #require(lines.first)
        let dataLine = try #require(lines.dropFirst().first)
        #expect(eventLine.hasPrefix(eventPrefix))
        #expect(dataLine.hasPrefix(dataPrefix))
        return PublicAnthropicEvent(
            name: String(eventLine.dropFirst(eventPrefix.count)),
            payload: try liveJSONObject(Data(dataLine.dropFirst(dataPrefix.count).utf8))
        )
    }
}

func jsonData(_ value: Any) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: value,
        options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
    )
}

func liveJSONObject(_ data: Data) throws -> [String: Any] {
    try #require(
        JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            as? [String: Any]
    )
}

func jsonDictionary(_ value: Any) throws -> [String: Any] {
    try #require(value as? [String: Any])
}

func jsonArray(_ data: Data) throws -> [Any] {
    try #require(
        JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [Any]
    )
}

func serverToolUsage(_ usage: [String: Any]) -> [String: Int]? {
    usage["server_tool_use"] as? [String: Int]
}

func utf8String(_ data: Data) throws -> String {
    try #require(String(data: data, encoding: .utf8))
}

func assertOneSearchPublicContract(_ frames: [Data]) throws {
    let events = try parsePublicFrames(frames)
    #expect(
        events.map(\.name) == [
            "message_start",
            "content_block_start",
            "content_block_delta",
            "content_block_stop",
            "content_block_start",
            "content_block_stop",
            "content_block_start",
            "content_block_delta",
            "content_block_stop",
            "message_delta",
            "message_stop",
        ]
    )
    let message = try #require(events[0].payload["message"] as? [String: Any])
    #expect(message["id"] as? String == "msg_public")
    #expect(message["model"] as? String == "claude-opus-5")
    #expect((message["content"] as? [Any])?.isEmpty == true)
    #expect(message["stop_reason"] is NSNull)
    #expect(message["stop_sequence"] is NSNull)
    let initialUsage = try #require(message["usage"] as? [String: Any])
    #expect(initialUsage["input_tokens"] as? Int == 12)
    #expect(initialUsage["output_tokens"] as? Int == 0)
    #expect(
        serverToolUsage(initialUsage)
            == ["web_search_requests": 0, "web_fetch_requests": 0]
    )
    let serverStart = try #require(events[1].payload["content_block"] as? [String: Any])
    #expect(serverStart["type"] as? String == "server_tool_use")
    #expect(serverStart["id"] as? String == "srvtoolu_public_1")
    #expect(serverStart["name"] as? String == "web_search")
    #expect((serverStart["input"] as? [String: Any])?.isEmpty == true)
    #expect((serverStart["caller"] as? [String: String]) == ["type": "direct"])
    let queryDelta = try #require(events[2].payload["delta"] as? [String: Any])
    #expect(queryDelta["type"] as? String == "input_json_delta")
    let queryJSON = try #require(queryDelta["partial_json"] as? String)
    #expect(
        try liveJSONObject(Data(queryJSON.utf8))["query"] as? String == "latest Swift"
    )
    let result = try #require(events[4].payload["content_block"] as? [String: Any])
    #expect(result["type"] as? String == "web_search_tool_result")
    #expect(result["tool_use_id"] as? String == "srvtoolu_public_1")
    #expect((result["caller"] as? [String: String]) == ["type": "direct"])
    let hits = try #require(result["content"] as? [[String: Any]])
    #expect(hits.count == 1)
    #expect(hits[0]["type"] as? String == "web_search_result")
    #expect(hits[0]["url"] as? String == "https://swift.org/")
    #expect(hits[0]["title"] as? String == "Swift.org")
    #expect((hits[0]["encrypted_content"] as? String)?.isEmpty == false)
    #expect(hits[0]["page_age"] is NSNull)

    let indexed = events.compactMap { $0.payload["index"] as? Int }
    #expect(indexed == [0, 0, 0, 1, 1, 2, 2, 2])
    let finalUsage = try #require(events[9].payload["usage"] as? [String: Any])
    #expect(finalUsage["input_tokens"] as? Int == 16)
    #expect(finalUsage["output_tokens"] as? Int == 16)
    #expect(
        serverToolUsage(finalUsage)
            == ["web_search_requests": 1, "web_fetch_requests": 0]
    )
    #expect(
        (events[9].payload["delta"] as? [String: Any])?["stop_reason"] as? String
            == "end_turn"
    )
    #expect(!(try utf8String(Data(frames.joined()))).contains("toolu_private"))
}
