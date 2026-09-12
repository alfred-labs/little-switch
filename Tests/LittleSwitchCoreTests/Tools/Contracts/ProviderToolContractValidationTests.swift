import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("Provider tool contract boundary cases")
struct ProviderToolContractValidationTests {
    @Test(
        "Provider tool lifecycle events cannot bypass the item boundary",
        arguments: [
            "response.web_search_call.in_progress", "response.file_search_call.searching",
            "response.code_interpreter_call_code.delta", "response.mcp_list_tools.completed",
            "response.unknown_tool_call.delta",
        ])
    func nativeLifecycleEvents(type: String) throws {
        for mismatched in [false, true] {
            var contract = try make(.responses)
            let frame = ServerSentEventFrame(
                event: type, data: try jsonData(["type": mismatched ? "future_metadata" : type]), terminal: false)
            #expect(throws: ProviderToolContract.Error.providerOwnedTool) { try contract.validateFrame(frame) }
        }
    }

    @Test("A nominal Chat content array cannot hide provider tool blocks")
    func chatContentTools() throws {
        var contract = try make(.chatCompletions)
        let message: [String: Any] = ["content": [["type": "server_tool_use", "name": "native"]]]
        #expect(throws: ProviderToolContract.Error.providerOwnedTool) {
            try contract.validateBuffered(jsonData(["choices": [["message": message]]]))
        }
        #expect(throws: ProviderToolContract.Error.providerOwnedTool) {
            try contract.validateFrame(frame(["choices": [["index": 0, "delta": message]]]))
        }
        let ordinary: [String: Any] = ["content": [["type": "text", "text": "ordinary"], [:]]]
        try contract.validateBuffered(jsonData(["choices": [["message": ordinary]]]))
        try contract.validateFrame(frame(["choices": [["index": 0, "delta": ordinary]]]))
    }

    @Test("Anthropic client builtins authorize only client execution")
    func clientBuiltins() throws {
        for type in ["custom", "computer_20250124", "bash_20250124", "text_editor_20250124", "memory_20250818"] {
            let contract = try make(.anthropic, tools: [["type": type, "name": "client"]])
            try contract.validateBuffered(jsonData(["content": [["type": "tool_use", "name": "client"]]]))
        }
        let native = try make(.anthropic, tools: [["type": "web_search_20250305", "name": "web_search"]])
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "web_search")) {
            try native.validateBuffered(jsonData(["content": [["type": "tool_use", "name": "web_search"]]]))
        }
        for type in [
            "web_fetch_20250910", "code_execution_20250825", "tool_search_tool_regex_20251119",
            "tool_search_tool_bm25_20251119",
        ] {
            let hosted = try make(.anthropic, tools: [["type": type, "name": "hosted"]])
            #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "hosted")) {
                try hosted.validateBuffered(jsonData(["content": [["type": "tool_use", "name": "hosted"]]]))
            }
        }
    }

    @Test("Protocol content parts and deltas cannot hide native tool blocks")
    func toolContentParts() throws {
        var anthropic = try make(.anthropic)
        #expect(throws: ProviderToolContract.Error.providerOwnedTool) {
            try anthropic.validateFrame(
                frame(["type": "content_block_delta", "delta": ["type": "server_tool_use", "name": "native"]]))
        }
        try anthropic.validateFrame(
            frame(["type": "content_block_delta", "delta": ["type": "input_json_delta", "partial_json": "{"]]))
        var responses = try make(.responses)
        #expect(throws: ProviderToolContract.Error.providerOwnedTool) {
            try responses.validateFrame(
                frame(["type": "response.content_part.added", "part": ["type": "server_tool_use", "name": "native"]]))
        }
        try responses.validateFrame(
            frame(["type": "response.content_part.added", "part": ["type": "output_text", "text": "ordinary"]]))
        try responses.validateFrame(frame(["type": "response.reasoning_summary_text.delta", "delta": "ordinary"]))
    }

    @Test("Malformed recognized declarations fail rather than granting a wider identity")
    func malformedDeclarations() throws {
        for tools: Any in [
            "private", [true], [["type": "function", "name": ""]], [["type": "namespace"]],
            [["type": "namespace", "name": "ns", "tools": [:]]],
        ] {
            #expect(throws: ProviderToolContract.Error.invalidRequest) {
                _ = try ProviderToolContract(wire: .responses, requestBody: jsonData(["tools": tools]))
            }
        }
        #expect(throws: ProviderToolContract.Error.invalidRequest) {
            _ = try make(.chatCompletions, tools: [["type": "function", "function": false]])
        }
        let hosted = try make(
            .responses, tools: [["type": "namespace", "name": "ns", "tools": [["type": "web_search"]]]])
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "web_search", namespace: "ns")) {
            try hosted.validateBuffered(
                jsonData(["output": [["type": "function_call", "name": "web_search", "namespace": "ns"]]]))
        }
    }

    @Test("Legacy Chat functions and explicitly declared custom tools retain their type")
    func legacyAndCustomChat() throws {
        let legacy = try ProviderToolContract(
            wire: .chatCompletions, requestBody: jsonData(["functions": [["name": "read"]]]))
        try legacy.validateBuffered(
            jsonData(["choices": [["message": ["function_call": ["name": "read", "arguments": "{}"]]]]]))
        var custom = try make(.chatCompletions, tools: [["type": "custom", "custom": ["name": "patch"]]])
        try custom.validateBuffered(
            jsonData(["choices": [["message": ["tool_calls": [["type": "custom", "custom": ["name": "patch"]]]]]]]))
        try custom.validateFrame(
            frame([
                "choices": [
                    [
                        "index": 0,
                        "delta": ["tool_calls": [["index": 0, "type": "custom", "custom": ["name": "patch"]]]],
                    ]
                ]
            ]))
        try custom.finish()
        var streamedLegacy = legacy
        try streamedLegacy.validateFrame(
            frame(["choices": [["index": 0, "delta": ["function_call": ["name": "read"]]]]]))
        try streamedLegacy.finish()
    }

    @Test("Malformed Chat call envelopes have explicit errors")
    func malformedChatCalls() throws {
        let contract = try make(.chatCompletions)
        for message: Any in [
            "private", ["tool_calls": [["function": ["name": "read"]]]],
            ["tool_calls": [["type": "function", "function": false]]], ["function_call": true],
        ] {
            #expect(throws: ProviderToolContract.Error.invalidResponse) {
                try contract.validateBuffered(jsonData(["choices": [["message": message]]]))
            }
        }
        #expect(throws: ProviderToolContract.Error.providerOwnedTool) {
            try contract.validateBuffered(
                jsonData(["choices": [["message": ["tool_calls": [["type": "web_search"]]]]]]))
        }
    }

    @Test("Responses nested message parts and malformed namespace values are checked")
    func responseContentAndNamespaces() throws {
        let contract = try make(.responses, tools: [["type": "function", "name": "read"]])
        try contract.validateBuffered(
            jsonData(["output": [["type": "message", "content": [["type": "output_text", "text": "ok"]]]]]))
        #expect(throws: ProviderToolContract.Error.providerOwnedTool) {
            try contract.validateBuffered(
                jsonData(["output": [["type": "message", "content": [["type": "server_tool_use"]]]]]))
        }
        for namespace: Any in [false, ""] {
            #expect(throws: ProviderToolContract.Error.invalidResponse) {
                try contract.validateBuffered(
                    jsonData(["output": [["type": "function_call", "name": "read", "namespace": namespace]]]))
            }
        }
        try contract.validateBuffered(
            jsonData(["output": [["type": "function_call", "name": "read", "namespace": NSNull()]]]))
    }

    @Test("Malformed frame structures do not bypass validation")
    func malformedFrames() throws {
        var anthropic = try make(.anthropic)
        #expect(throws: ProviderToolContract.Error.invalidResponse) {
            try anthropic.validateFrame(ServerSentEventFrame(event: nil, data: Data("private".utf8), terminal: false))
        }
        for key in ["message", "content_block"] {
            #expect(throws: ProviderToolContract.Error.invalidResponse) {
                try anthropic.validateFrame(frame([key: false]))
            }
        }
        var responses = try make(.responses)
        for key in ["item", "response", "part"] {
            #expect(throws: ProviderToolContract.Error.invalidResponse) {
                try responses.validateFrame(frame([key: false]))
            }
        }
        try responses.validateFrame(frame(["type": "response.", "status": "in_progress"]))
    }

    @Test("Responses identities cannot change under an existing item ID")
    func responsesItemIdentity() throws {
        var contract = try make(
            .responses, tools: [["type": "function", "name": "read"], ["type": "function", "name": "write"]])
        let start: [String: Any] = [
            "type": "response.output_item.added", "item": ["type": "function_call", "name": "read", "id": "call"],
        ]
        try contract.validateFrame(frame(start))
        try contract.validateFrame(frame(start))
        for payload: [String: Any] in [
            ["type": "response.output_item.done", "item": ["type": "function_call", "name": "write", "id": "call"]],
            ["type": "response.function_call_arguments.done", "name": "write", "item_id": "call"],
            ["type": "response.output_item.added", "item": ["type": "function_call", "name": "read"]],
        ] {
            #expect(throws: ProviderToolContract.Error.invalidResponse) { try contract.validateFrame(frame(payload)) }
        }
        try contract.validateFrame(
            frame(["type": "response.function_call_arguments.done", "name": "read", "item_id": "call"]))
        var custom = try make(.responses, tools: [["type": "custom", "name": "patch"]])
        try custom.validateFrame(
            frame([
                "type": "response.output_item.added",
                "item": ["type": "custom_tool_call", "name": "patch", "id": "call"],
            ]))
        try custom.validateFrame(
            frame(["type": "response.custom_tool_call_input.delta", "item_id": "call", "delta": "diff"]))
    }

    @Test("Chat malformed indices, function fragments, and type changes are rejected")
    func malformedChatFragments() throws {
        let tools: [[String: Any]] = [
            ["type": "function", "function": ["name": "read"]], ["type": "custom", "custom": ["name": "patch"]],
        ]
        for call: [String: Any] in [
            ["index": -1], ["index": true], ["index": "0"], [:],
            ["index": 0, "function": false], ["index": 0, "function": ["name": true]],
        ] {
            var contract = try make(.chatCompletions, tools: tools)
            #expect(throws: ProviderToolContract.Error.invalidResponse) {
                try contract.validateFrame(frame(["choices": [["index": 0, "delta": ["tool_calls": [call]]]]]))
            }
        }
        var contract = try make(.chatCompletions, tools: tools)
        try contract.validateFrame(
            frame(["choices": [["index": 0, "delta": ["tool_calls": [["index": 0, "function": ["name": "read"]]]]]]]))
        #expect(throws: ProviderToolContract.Error.invalidResponse) {
            try contract.validateFrame(
                frame([
                    "choices": [
                        [
                            "index": 0,
                            "delta": ["tool_calls": [["index": 0, "type": "custom", "custom": ["name": "patch"]]]],
                        ]
                    ]
                ]))
        }
        #expect(throws: ProviderToolContract.Error.providerOwnedTool) {
            try contract.validateFrame(
                frame(["choices": [["index": 0, "delta": ["tool_calls": [["index": 1, "type": "server"]]]]]]))
        }
    }

    private func make(_ wire: ProviderToolContract.Wire, tools: [[String: Any]] = []) throws -> ProviderToolContract {
        try ProviderToolContract(wire: wire, requestBody: jsonData(["tools": tools]))
    }

    private func frame(_ payload: [String: Any]) throws -> ServerSentEventFrame {
        ServerSentEventFrame(event: nil, data: try jsonData(payload), terminal: false)
    }
}
