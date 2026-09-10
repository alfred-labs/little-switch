import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic public projection privacy")
struct AnthropicPublicPrivacyTests {
    @Test("Live SSE strips provider metadata and suppresses unknown blocks and deltas")
    func liveSanitization() throws {
        var session = AnthropicPublicStreamSession(originalModel: "claude")
        var frames = try session.start(from: messageStartEvent(id: "msg_live", inputTokens: 1))
        frames += try session.consumePublic(
            contentStartEvent(
                index: 0,
                block: [
                    "type": "text",
                    "text": "",
                    "citations": [webCitation(providerSecret: "nested-start-secret")],
                    "provider_secret": "top-level-start-secret",
                ]
            )
        )
        frames += try session.consumePublic(
            contentDeltaEvent(
                index: 0,
                delta: [
                    "type": "citations_delta",
                    "citation": webCitation(providerSecret: "nested-delta-secret"),
                    "provider_secret": "top-level-delta-secret",
                ]
            )
        )
        frames += try session.consumePublic(
            contentDeltaEvent(
                index: 0,
                delta: [
                    "type": "future_text_metadata_delta",
                    "provider_secret": "unknown-delta-secret",
                ]
            )
        )
        frames += try session.consumePublic(.contentStop(index: 0))
        frames += try session.consumePublic(
            contentStartEvent(
                index: 1,
                block: [
                    "type": "future_provider_block",
                    "provider_secret": "unknown-block-secret",
                ]
            )
        )
        frames += try session.consumePublic(
            contentDeltaEvent(
                index: 1,
                delta: [
                    "type": "future_provider_delta",
                    "provider_secret": "unknown-block-delta-secret",
                ]
            )
        )
        frames += try session.consumePublic(.contentStop(index: 1))
        frames += try closeProviderTurn(&session, stopReason: "end_turn", outputTokens: 2)
        frames += try session.finish(
            turn: terminalTurn(id: "msg_live", stopReason: "end_turn"),
            usage: AnthropicUsage(inputTokens: 1, outputTokens: 2)
        )

        let wire = try utf8String(Data(frames.joined()))
        #expect(!wire.contains("provider_secret"))
        #expect(!wire.contains("future_provider_block"))
        #expect(!wire.contains("future_text_metadata_delta"))

        let events = try parsePublicFrames(frames)
        let starts = events.compactMap { $0.payload["content_block"] as? [String: Any] }
        #expect(starts.map { $0["type"] as? String } == ["text"])
        #expect(Set(try #require(starts.first).keys) == ["type", "text", "citations"])
        let startCitation = try #require(
            (starts[0]["citations"] as? [[String: Any]])?.first
        )
        #expect(Set(startCitation.keys) == webCitationKeys)

        let deltas = events.compactMap { $0.payload["delta"] as? [String: Any] }
        let citationDelta = try #require(
            deltas.first { $0["type"] as? String == "citations_delta" }
        )
        #expect(Set(citationDelta.keys) == ["type", "citation"])
        let deltaCitation = try #require(citationDelta["citation"] as? [String: Any])
        #expect(Set(deltaCitation.keys) == webCitationKeys)
    }

    @Test("Buffered JSON and SSE expose only documented Claude content fields")
    func bufferedSanitizationAndCompatibility() throws {
        let turn = try publicPrivacyFixtureTurn()
        let json = try AnthropicWebSearch.nonStreamingResponse(
            originalModel: "claude",
            traces: [],
            finalTurn: turn,
            usage: turn.usage
        )
        let sse = try AnthropicWebSearch.streamingResponse(
            originalModel: "claude",
            traces: [],
            finalTurn: turn,
            usage: turn.usage
        )

        for wire in [json, sse] {
            let text = try utf8String(wire)
            #expect(!text.contains("provider_secret"))
            #expect(!text.contains("future_provider_block"))
        }

        let response = try liveJSONObject(json)
        let content = try #require(response["content"] as? [[String: Any]])
        #expect(
            content.map { $0["type"] as? String }
                == [
                    "text",
                    "thinking",
                    "redacted_thinking",
                    "tool_use",
                    "server_tool_use",
                    "web_search_tool_result",
                ]
        )
        #expect(Set(content[0].keys) == ["type", "text", "citations"])
        #expect(Set(content[1].keys) == ["type", "thinking", "signature"])
        #expect(Set(content[2].keys) == ["type", "data"])
        #expect(Set(content[3].keys) == ["type", "id", "name", "input", "caller"])
        #expect(Set(content[4].keys) == ["type", "id", "name", "input", "caller"])
        #expect(
            content[4]["caller"] as? [String: String]
                == ["type": "code_execution_20260120", "tool_id": "srvtoolu_code"]
        )
        let result = try #require(
            (content[5]["content"] as? [[String: Any]])?.first
        )
        #expect(
            Set(result.keys)
                == ["type", "url", "title", "encrypted_content", "page_age"]
        )

        let streamedTypes = try bufferedPublicEvents(sse).compactMap {
            ($0.payload["content_block"] as? [String: Any])?["type"] as? String
        }
        #expect(streamedTypes == content.map { $0["type"] as? String })
    }
}

@Suite("Anthropic public sanitizer validation")
struct AnthropicPublicSanitizerValidationTests {
    @Test("Documented citation and caller shapes retain only their public fields")
    func documentedShapes() throws {
        let citations: [[String: Any]] = [
            [
                "type": "char_location",
                "cited_text": "characters",
                "document_index": 0,
                "document_title": "Text",
                "file_id": NSNull(),
                "start_char_index": 1,
                "end_char_index": 4,
                "provider_secret": "char-secret",
            ],
            [
                "type": "page_location",
                "cited_text": "page",
                "document_index": 1,
                "document_title": NSNull(),
                "file_id": "file_1",
                "start_page_number": 1,
                "end_page_number": 2,
                "provider_secret": "page-secret",
            ],
            [
                "type": "content_block_location",
                "cited_text": "blocks",
                "document_index": 2,
                "document_title": "Blocks",
                "start_block_index": 0,
                "end_block_index": 1,
                "provider_secret": "block-secret",
            ],
            [
                "type": "search_result_location",
                "cited_text": "search",
                "search_result_index": 0,
                "source": "source-id",
                "title": NSNull(),
                "start_block_index": 0,
                "end_block_index": 1,
                "provider_secret": "search-secret",
            ],
            webCitation(providerSecret: "web-secret"),
        ]
        let sanitizedText = try AnthropicPublicSanitizer.block([
            "type": "text",
            "text": "Cited",
            "citations": citations,
        ])
        let text = try #require(sanitizedText)
        let publicCitations = try #require(text["citations"] as? [[String: Any]])
        #expect(publicCitations.count == citations.count)
        #expect(publicCitations.allSatisfy { $0["provider_secret"] == nil })
        #expect(
            publicCitations.compactMap { $0["type"] as? String }
                == citations.compactMap { $0["type"] as? String }
        )

        let sanitizedTool = try AnthropicPublicSanitizer.block([
            "type": "tool_use",
            "id": "toolu_1",
            "name": "weather",
            "input": [:],
            "caller": [
                "type": "code_execution_20250825",
                "tool_id": "srvtoolu_1",
                "provider_secret": "caller-secret",
            ],
        ])
        let tool = try #require(sanitizedTool)
        #expect(
            tool["caller"] as? [String: String]
                == ["type": "code_execution_20250825", "tool_id": "srvtoolu_1"]
        )
        let sanitizedFutureCaller = try AnthropicPublicSanitizer.block([
            "type": "tool_use",
            "id": "toolu_2",
            "name": "weather",
            "input": [:],
            "caller": ["type": "future_caller", "provider_secret": "secret"],
        ])
        let futureCaller = try #require(sanitizedFutureCaller)
        #expect(futureCaller["caller"] == nil)
    }

    @Test("Malformed known shapes fail closed while unknown shapes are dropped")
    func failClosedShapes() throws {
        #expect(try AnthropicPublicSanitizer.block(["type": "future_block"]) == nil)
        #expect(try AnthropicPublicSanitizer.delta(["type": "future_delta"]) == nil)
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try AnthropicPublicSanitizer.block(["type": "text"])
        }
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try AnthropicPublicSanitizer.delta(["type": "text_delta", "text": 1])
        }
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try AnthropicPublicSanitizer.block([
                "type": "tool_use",
                "id": "toolu_invalid",
                "name": "weather",
                "input": ["invalid": Date()],
            ])
        }
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try AnthropicPublicSanitizer.block([
                "type": "web_search_tool_result",
                "tool_use_id": "srvtoolu_1",
                "content": [
                    [
                        "type": "web_search_result",
                        "url": "https://example.com/",
                        "title": "Example",
                        "encrypted_content": "opaque",
                    ]
                ],
            ])
        }
    }
}

private let webCitationKeys: Set<String> = [
    "type", "url", "title", "cited_text", "encrypted_index",
]

private func webCitation(providerSecret: String) -> [String: Any] {
    [
        "type": "web_search_result_location",
        "url": "https://swift.org/",
        "title": "Swift.org",
        "cited_text": "Swift documentation",
        "encrypted_index": "opaque-index",
        "provider_secret": providerSecret,
    ]
}

private func publicPrivacyFixtureTurn() throws -> AnthropicModelTurn {
    let content: [[String: Any]] = [
        [
            "type": "text",
            "text": "Answer",
            "citations": [webCitation(providerSecret: "nested-citation-secret")],
            "provider_secret": "text-secret",
        ],
        [
            "type": "thinking",
            "thinking": "Reasoning",
            "signature": "opaque-signature",
            "provider_secret": "thinking-secret",
        ],
        [
            "type": "redacted_thinking",
            "data": "opaque-redaction",
            "provider_secret": "redacted-secret",
        ],
        [
            "type": "tool_use",
            "id": "toolu_weather",
            "name": "weather",
            "input": ["city": "Paris"],
            "caller": ["type": "direct", "provider_secret": "caller-secret"],
            "provider_secret": "tool-secret",
        ],
        [
            "type": "server_tool_use",
            "id": "srvtoolu_code",
            "name": "code_execution",
            "input": ["code": "print(1)"],
            "caller": [
                "type": "code_execution_20260120",
                "tool_id": "srvtoolu_code",
                "provider_secret": "server-caller-secret",
            ],
            "provider_secret": "server-tool-secret",
        ],
        [
            "type": "web_search_tool_result",
            "tool_use_id": "srvtoolu_search",
            "content": [
                [
                    "type": "web_search_result",
                    "url": "https://swift.org/",
                    "title": "Swift.org",
                    "encrypted_content": "opaque-result",
                    "page_age": NSNull(),
                    "provider_secret": "result-secret",
                ]
            ],
            "caller": ["type": "direct", "provider_secret": "result-caller-secret"],
            "provider_secret": "result-block-secret",
        ],
        [
            "type": "future_provider_block",
            "provider_secret": "unknown-block-secret",
        ],
    ]
    return AnthropicModelTurn(
        id: "msg_privacy",
        contentJSON: try jsonData(content),
        stopReason: "end_turn",
        stopSequenceJSON: Data("null".utf8),
        usage: AnthropicUsage(inputTokens: 3, outputTokens: 4),
        webSearchCall: nil
    )
}

private func bufferedPublicEvents(_ stream: Data) throws -> [PublicAnthropicEvent] {
    let text = try utf8String(stream)
    let frames = text.components(separatedBy: "\n\n")
        .filter { !$0.isEmpty }
        .map { Data(($0 + "\n\n").utf8) }
    return try parsePublicFrames(frames)
}
