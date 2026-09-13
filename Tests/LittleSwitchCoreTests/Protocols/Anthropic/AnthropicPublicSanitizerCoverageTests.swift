import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic public sanitizer coverage")
struct AnthropicPublicSanitizerCoverageTests {
    @Test("Invalid block and delta envelopes fail closed")
    func invalidEnvelopes() throws {
        let invalidBlocks: [Any] = [
            NSNull(),
            [String: Any](),
            ["type": 1],
            ["type": ""],
            ["type": "redacted_thinking"],
            ["type": "redacted_thinking", "data": 1],
        ]
        for value in invalidBlocks {
            expectInvalidSanitizerBlock(value)
        }

        let invalidDeltas: [Any] = [
            NSNull(),
            [String: Any](),
            ["type": 1],
            ["type": ""],
        ]
        for value in invalidDeltas {
            expectInvalidSanitizerDelta(value)
        }
        #expect(
            try anthropicPublicDelta([
                "type": "citations_delta"
            ]) == nil
        )
        #expect(
            try anthropicPublicDelta([
                "type": "citations_delta",
                "citation": ["type": "future_citation"],
            ]) == nil
        )
    }

    @Test("Text and thinking optionals are validated and nullable")
    func textAndThinkingOptionals() throws {
        let nullableCitations = try anthropicPublicBlock([
            "type": "text",
            "text": "answer",
            "citations": NSNull(),
        ])
        #expect(nullableCitations?["citations"] is NSNull)
        expectInvalidSanitizerBlock([
            "type": "text",
            "text": "answer",
            "citations": ["not": "an array"],
        ])
        expectInvalidSanitizerBlock([
            "type": "thinking",
            "thinking": "reasoning",
            "signature": 1,
        ])
    }

    @Test("Tool identity, input, and caller shapes fail closed")
    func toolAndCallerValidation() {
        let invalidTools: [[String: Any]] = [
            ["type": "tool_use", "name": "weather", "input": [:]],
            ["type": "tool_use", "id": "", "name": "weather", "input": [:]],
            ["type": "tool_use", "id": "toolu_1", "input": [:]],
            ["type": "tool_use", "id": "toolu_1", "name": "", "input": [:]],
            ["type": "tool_use", "id": "toolu_1", "name": "weather"],
            ["type": "tool_use", "id": "toolu_1", "name": "weather", "input": []],
            [
                "type": "tool_use",
                "id": "toolu_1",
                "name": "weather",
                "input": [:],
                "caller": "direct",
            ],
            [
                "type": "tool_use",
                "id": "toolu_1",
                "name": "weather",
                "input": [:],
                "caller": [String: Any](),
            ],
            [
                "type": "tool_use",
                "id": "toolu_1",
                "name": "weather",
                "input": [:],
                "caller": ["type": 1],
            ],
            [
                "type": "tool_use",
                "id": "toolu_1",
                "name": "weather",
                "input": [:],
                "caller": ["type": "code_execution_20250825"],
            ],
            [
                "type": "tool_use",
                "id": "toolu_1",
                "name": "weather",
                "input": [:],
                "caller": ["type": "code_execution_20260120", "tool_id": ""],
            ],
        ]
        for tool in invalidTools {
            expectInvalidSanitizerBlock(tool)
        }
    }

    @Test("Web search results validate success, error, and content unions")
    func webSearchResultValidation() throws {
        let missingEnvelopeFields: [[String: Any]] = [
            ["type": "web_search_tool_result", "content": []],
            ["type": "web_search_tool_result", "tool_use_id": "", "content": []],
            ["type": "web_search_tool_result", "tool_use_id": "srvtoolu_1"],
            [
                "type": "web_search_tool_result",
                "tool_use_id": "srvtoolu_1",
                "content": "invalid",
            ],
        ]
        for block in missingEnvelopeFields {
            expectInvalidSanitizerBlock(block)
        }

        let errorCodes = [
            "invalid_tool_input",
            "unavailable",
            "max_uses_exceeded",
            "too_many_requests",
            "query_too_long",
            "request_too_large",
        ]
        for code in errorCodes {
            let block = try anthropicPublicBlock([
                "type": "web_search_tool_result",
                "tool_use_id": "srvtoolu_1",
                "content": [
                    "type": "web_search_tool_result_error",
                    "error_code": code,
                ],
            ])
            let error = block?["content"] as? [String: String]
            #expect(error?["error_code"] == code)
        }
        for error in [
            ["type": "future_error", "error_code": "unavailable"],
            ["type": "web_search_tool_result_error"],
            ["type": "web_search_tool_result_error", "error_code": "future_code"],
        ] {
            expectInvalidSanitizerBlock([
                "type": "web_search_tool_result",
                "tool_use_id": "srvtoolu_1",
                "content": error,
            ])
        }

        let stringPageAge = try anthropicPublicBlock([
            "type": "web_search_tool_result",
            "tool_use_id": "srvtoolu_1",
            "content": [
                [
                    "type": "web_search_result",
                    "url": "https://example.com/",
                    "title": "Example",
                    "encrypted_content": "opaque",
                    "page_age": "2026-08-28",
                ]
            ],
        ])
        let results = stringPageAge?["content"] as? [[String: Any]]
        #expect(results?.first?["page_age"] as? String == "2026-08-28")
        expectInvalidSanitizerBlock([
            "type": "web_search_tool_result",
            "tool_use_id": "srvtoolu_1",
            "content": [
                [
                    "type": "web_search_result",
                    "url": "https://example.com/",
                    "title": "Example",
                    "encrypted_content": "opaque",
                    "page_age": 1,
                ]
            ],
        ])
    }
}

private func expectInvalidSanitizerBlock(_ value: Any) {
    #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
        _ = try anthropicPublicBlock(value)
    }
}

private func expectInvalidSanitizerDelta(_ value: Any) {
    #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
        _ = try anthropicPublicDelta(value)
    }
}
