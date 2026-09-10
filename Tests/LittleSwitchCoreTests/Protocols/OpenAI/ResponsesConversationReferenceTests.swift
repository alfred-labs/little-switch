import Foundation
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("Responses server conversation references")
struct ResponsesConversationReferenceTests {
    @Test("Chat requires complete input instead of a server conversation reference", arguments: referenceFields)
    func chatRejectsServerReferences(field: String) throws {
        for input: Any in ["Continue.", [searchOutput]] {
            let body = try data(["model": "route", "input": input, field: "server_state"])
            for mode: ResponsesChatCompletionsMode in [.buffered, .streaming(toolStream: true)] {
                #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                    try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "test-model", mode: mode)
                }
            }
        }
    }

    @Test(
        "Native adaptation requires complete input instead of a server conversation reference",
        arguments: referenceFields)
    func nativeAdaptationRejectsServerReferences(field: String) throws {
        for var root in adaptedRequests {
            root[field] = "server_state"
            let body = try data(root)
            for configuration: WebSearchConfiguration in [.disabled, .firecrawlCloud] {
                #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                    try OpenAIResponsesWebSearch.prepare(
                        body: body, targetModel: "test-model", configuration: configuration)
                }
            }
        }
    }

    @Test("Conversation objects also require server state and cannot be adapted")
    func conversationObject() throws {
        let body = try data([
            "model": "route", "input": "Continue.", "tools": [["type": "web_search"]],
            "conversation": ["id": "conv_previous"],
        ])
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "test-model")
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try OpenAIResponsesWebSearch.prepare(body: body, targetModel: "test-model", configuration: .disabled)
        }
    }

    @Test("Null references allow complete-history adaptation")
    func nullReferences() throws {
        for var root in adaptedRequests {
            for field in Self.referenceFields { root[field] = NSNull() }
            let body = try data(root)
            let prepared = try #require(
                try OpenAIResponsesWebSearch.prepare(body: body, targetModel: "test-model", configuration: .disabled))
            let upstream = try object(prepared.upstreamBody)
            for field in Self.referenceFields { #expect(upstream[field] is NSNull) }
            let chat = try OpenAIResponsesChatCompletions.prepare(
                body: prepared.upstreamBody, targetModel: "test-model")
            #expect((try object(chat.upstreamBody)["messages"] as? [[String: Any]])?.isEmpty == false)
        }
    }

    @Test("Native transparent requests preserve provider-owned references", arguments: referenceFields)
    func transparentReferences(field: String) throws {
        for value: Any in ["server_state", ["id": "conv_previous"], NSNull()] {
            let body = try data(["model": "route", "input": "Continue.", "tools": [function], field: value])
            #expect(
                try OpenAIResponsesWebSearch.prepare(body: body, targetModel: "test-model", configuration: .disabled)
                    == nil)
            #expect(try OpenAIResponsesNativeNamespacing.normalize(body).body == body)
        }
    }

    private static let referenceFields = ["previous_response_id", "conversation"]

    private var adaptedRequests: [[String: Any]] {
        [
            [
                "model": "route", "input": "Continue.",
                "tools": [["type": "namespace", "name": "files", "tools": [function]]],
            ],
            [
                "model": "route", "input": "Continue.",
                "tools": [
                    [
                        "type": "tool_search", "execution": "client", "description": "Find tools.",
                        "parameters": ["type": "object"],
                    ]
                ],
            ],
            ["model": "route", "input": "Continue.", "tools": [["type": "web_search"]]],
            [
                "model": "route",
                "input": [
                    [
                        "type": "web_search_call", "id": "ws_previous", "status": "completed",
                        "action": ["type": "search", "query": "Swift"],
                    ]
                ],
            ],
            [
                "model": "route",
                "input": [
                    [
                        "type": "function_call", "call_id": "call_read", "name": "read", "namespace": "files",
                        "arguments": "{}",
                    ]
                ],
            ],
            ["model": "route", "input": [searchOutput]],
            ["model": "route", "input": [["type": "additional_tools", "role": "developer", "tools": [function]]]],
        ]
    }

    private var function: [String: Any] {
        ["type": "function", "name": "read", "parameters": ["type": "object"]]
    }

    private var searchOutput: [String: Any] {
        ["type": "tool_search_output", "execution": "client", "call_id": "call_search", "tools": [function]]
    }

    private func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
