import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Provider tool output ownership")
struct ProviderToolContractTests {
    @Test("Declared Anthropic calls preserve ordinary mixed content")
    func declaredAnthropicCalls() throws {
        let contract = try ProviderToolContract(
            wire: .anthropic,
            requestBody: jsonData(["tools": [["name": "read", "input_schema": ["type": "object"]]]])
        )
        try contract.validateBuffered(
            jsonData([
                "content": [
                    ["type": "text", "text": "before"],
                    ["type": "thinking", "thinking": "private"],
                    ["type": "tool_use", "id": "call", "name": "read", "input": ["path": "test"]],
                    ["type": "future_metadata", "value": "after"],
                ]
            ]))
    }

    @Test("Calls absent from the current catalog fail even if history names them")
    func absentCurrentDeclaration() throws {
        let contract = try ProviderToolContract(
            wire: .anthropic,
            requestBody: jsonData([
                "messages": [
                    [
                        "role": "assistant",
                        "content": [
                            ["type": "tool_use", "name": "previous", "id": "old", "input": [:]]
                        ],
                    ]
                ]
            ])
        )
        #expect(throws: ProviderToolContract.Error.undeclaredTool) {
            try contract.validateBuffered(
                jsonData([
                    "content": [
                        ["type": "tool_use", "id": "new", "name": "previous", "input": [:]]
                    ]
                ]))
        }
    }

    @Test("A gateway private function is accepted only through its explicit declaration")
    func gatewayPrivateFunction() throws {
        let name = "__littleswitch_search_2"
        let body = try jsonData(["output": [["type": "function_call", "name": name, "arguments": "{}"]]])
        let declared = try ProviderToolContract(
            wire: .responses,
            requestBody: jsonData(["tools": [["type": "function", "name": name]]])
        )
        try declared.validateBuffered(body)
        let absent = try ProviderToolContract(wire: .responses, requestBody: jsonData([:]))
        #expect(throws: ProviderToolContract.Error.undeclaredTool) {
            try absent.validateBuffered(body)
        }
    }

    @Test(
        "Provider native tools are forbidden even when familiar or declared",
        arguments: [
            "server_tool_use", "web_search_tool_result", "web_search_call", "file_search_call",
            "code_interpreter_call", "computer_call", "mcp_call", "mcp_list_tools", "tool_search_call",
            "unknown_tool_call", "code_execution_tool_result",
        ])
    func providerOwnedTools(type: String) throws {
        let block: [String: Any] = ["type": type, "name": "web_search", "id": "native", "input": [:]]
        for wire in [ProviderToolContract.Wire.anthropic, .responses] {
            let contract = try ProviderToolContract(
                wire: wire,
                requestBody: jsonData(["tools": [["type": "web_search", "name": "web_search"]]])
            )
            #expect(throws: ProviderToolContract.Error.providerOwnedTool) {
                try contract.validateBuffered(jsonData([wire == .anthropic ? "content" : "output": [block]]))
            }
        }
    }

    @Test("Responses tool type and namespace are part of the explicit identity")
    func responsesIdentities() throws {
        let contract = try ProviderToolContract(
            wire: .responses,
            requestBody: jsonData([
                "tools": [
                    ["type": "namespace", "name": "files", "tools": [["type": "function", "name": "read"]]],
                    ["type": "custom", "name": "patch"],
                ]
            ])
        )
        try contract.validateBuffered(
            jsonData([
                "output": [
                    ["type": "function_call", "namespace": "files", "name": "read", "arguments": "{}"],
                    ["type": "custom_tool_call", "name": "patch", "input": "diff"],
                ]
            ]))
        for item: [String: Any] in [
            ["type": "function_call", "name": "read"],
            ["type": "function_call", "namespace": "other", "name": "read"],
            ["type": "function_call", "name": "patch"],
            ["type": "custom_tool_call", "name": "read"],
        ] {
            #expect(throws: ProviderToolContract.Error.undeclaredTool) {
                try contract.validateBuffered(jsonData(["output": [item]]))
            }
        }
    }

    @Test("Chat Completions checks every choice and ordinary tool call")
    func chatCompletionsChoices() throws {
        let contract = try ProviderToolContract(
            wire: .chatCompletions,
            requestBody: jsonData(["tools": [["type": "function", "function": ["name": "read"]]]])
        )
        let good = ["type": "function", "function": ["name": "read", "arguments": "{}"]] as [String: Any]
        try contract.validateBuffered(
            jsonData(["choices": [["message": ["content": "before", "tool_calls": [good]]]]]))
        #expect(throws: ProviderToolContract.Error.undeclaredTool) {
            try contract.validateBuffered(
                jsonData([
                    "choices": [
                        ["message": ["tool_calls": [good]]],
                        ["message": ["tool_calls": [["type": "function", "function": ["name": "unknown"]]]]],
                    ]
                ]))
        }
    }

    @Test("Empty, status, error, and future non-tool metadata remain transparent")
    func ordinaryMetadata() throws {
        for wire in [ProviderToolContract.Wire.anthropic, .responses, .chatCompletions] {
            let contract = try ProviderToolContract(wire: wire, requestBody: jsonData([:]))
            for payload: [String: Any] in [
                [:], ["error": ["message": "private"]], ["status": "in_progress", "usage": ["count": 2]],
                ["future_metadata": ["type": "tool_call", "name": "metadata-is-not-output"]],
            ] {
                try contract.validateBuffered(jsonData(payload))
            }
        }
    }

    @Test("Malformed tool responses and request catalogs have stable content-free errors")
    func malformedContract() throws {
        #expect(throws: ProviderToolContract.Error.invalidRequest) {
            _ = try ProviderToolContract(wire: .responses, requestBody: Data("private".utf8))
        }
        #expect(throws: ProviderToolContract.Error.invalidRequest) {
            _ = try ProviderToolContract(wire: .responses, requestBody: jsonData(["tools": [["type": "function"]]]))
        }
        let contract = try ProviderToolContract(wire: .anthropic, requestBody: jsonData([:]))
        for body in [
            Data("private".utf8), try jsonData(["content": "private"]),
            try jsonData(["content": [["type": "tool_use"]]]),
        ] {
            #expect(throws: ProviderToolContract.Error.invalidResponse) {
                try contract.validateBuffered(body)
            }
        }
    }
}
