import Foundation
import Testing

@testable import LittleSwitchCore

struct CustomToolFlattenBijectionPublicCall: Equatable {
    let callID: String
    let name: String
    let namespace: String?
    let input: String
}

struct CustomToolFlattenBijectionProviderCall: Equatable {
    let callID: String
    let wireName: String
    let input: String
}

extension CustomToolFlattenBijectionTests {
    typealias PublicCall = CustomToolFlattenBijectionPublicCall
    typealias ProviderCall = CustomToolFlattenBijectionProviderCall

    var rawInput: String { "*** Begin Patch\né🙂\n{\"json\":\"like\"}\n*** End Patch" }

    var format: [String: Any] {
        [
            "type": "grammar",
            "syntax": "lark",
            "definition": "start: WORD\n%import common.WORD",
        ]
    }

    func declarations() -> [[String: Any]] {
        [
            customTool("workspace__patch"),
            namespace("workspace", tools: [customTool("patch", format: format)]),
            namespace("a", tools: [customTool("b__c", format: format)]),
            namespace("a__b", tools: [customTool("c", format: format)]),
            namespace(
                String(repeating: "n", count: 40),
                tools: [customTool(String(repeating: "t", count: 40))]
            ),
        ]
    }

    func publicInput() -> [[String: Any]] {
        [
            ["type": "message", "role": "user", "content": "Apply the patch."],
            namespacedCall(namespace: "workspace", name: "patch", id: "call_old"),
            customOutput(callID: "call_old"),
        ]
    }

    func publicRequest(input: [[String: Any]]) throws -> Data {
        try chatJSONData([
            "model": "client",
            "input": input,
            "tools": declarations(),
            "tool_choice": ["type": "custom", "namespace": "workspace", "name": "patch"],
        ])
    }

    func customOutput(callID: String) -> [String: Any] {
        [
            "type": "custom_tool_call_output",
            "call_id": callID,
            "output": [["type": "input_text", "text": "Applied."]],
        ]
    }

    func nativeProviderResponse(name: String) throws -> Data {
        try responseData(
            responseObject(
                id: "resp_custom",
                createdAt: 1,
                status: "completed",
                output: [
                    [
                        "id": "ct_new",
                        "type": "custom_tool_call",
                        "status": "completed",
                        "call_id": "call_new",
                        "name": name,
                        "input": rawInput,
                    ]
                ],
                usage: ResponsesUsage(inputTokens: 1, outputTokens: 1)
            )
        )
    }

    func chatProviderResponse(name: String) throws -> Data {
        try chatJSONData([
            "id": "chatcmpl_custom",
            "object": "chat.completion",
            "created": 1,
            "model": "upstream",
            "choices": [
                [
                    "index": 0,
                    "finish_reason": "tool_calls",
                    "message": [
                        "role": "assistant",
                        "content": NSNull(),
                        "tool_calls": [
                            [
                                "id": "call_new",
                                "type": "custom",
                                "custom": ["name": name, "input": rawInput],
                            ]
                        ],
                    ],
                ]
            ],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2],
        ])
    }

    func publicCallItem(_ response: Data, callID: String) throws -> [String: Any] {
        let output = try #require(chatJSONObject(response)["output"] as? [[String: Any]])
        return try #require(output.first { $0["call_id"] as? String == callID })
    }

    func publicCall(_ item: [String: Any]) -> PublicCall {
        PublicCall(
            callID: item["call_id"] as? String ?? "",
            name: item["name"] as? String ?? "",
            namespace: item["namespace"] as? String,
            input: item["input"] as? String ?? ""
        )
    }

    func providerDeclarations(_ body: Data, chat: Bool) throws -> Data {
        let root = try chatJSONObject(body)
        let tools = try #require(root["tools"] as? [[String: Any]])
        let declarations: [[String: Any]] =
            chat
            ? tools.compactMap { ($0["custom"] as? [String: Any]) }
            : tools
        return try canonicalData(declarations)
    }

    func providerChoice(_ body: Data) throws -> Data {
        try canonicalData(try #require(chatJSONObject(body)["tool_choice"]))
    }

    func providerCalls(_ body: Data, chat: Bool, callID: String) throws -> [ProviderCall] {
        if chat {
            let messages = try #require(chatJSONObject(body)["messages"] as? [[String: Any]])
            return messages.flatMap { message in
                (message["tool_calls"] as? [[String: Any]] ?? []).compactMap { call in
                    guard call["id"] as? String == callID, call["type"] as? String == "custom",
                        let custom = call["custom"] as? [String: Any],
                        let name = custom["name"] as? String,
                        let input = custom["input"] as? String
                    else { return nil }
                    return ProviderCall(callID: callID, wireName: name, input: input)
                }
            }
        }
        let input = try #require(chatJSONObject(body)["input"] as? [[String: Any]])
        return input.compactMap { item in
            guard item["call_id"] as? String == callID, item["type"] as? String == "custom_tool_call",
                let name = item["name"] as? String,
                let input = item["input"] as? String
            else { return nil }
            return ProviderCall(callID: callID, wireName: name, input: input)
        }
    }

    func canonicalData(_ value: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    func customTool(_ name: String, format: [String: Any]? = nil) -> [String: Any] {
        var tool: [String: Any] = ["type": "custom", "name": name]
        if let format { tool["format"] = format }
        return tool
    }

    func namespace(_ name: String, tools: [[String: Any]]) -> [String: Any] {
        ["type": "namespace", "name": name, "tools": tools]
    }

    func namespacedCall(namespace: String, name: String, id: String) -> [String: Any] {
        [
            "id": id,
            "type": "custom_tool_call",
            "call_id": id,
            "namespace": namespace,
            "name": name,
            "input": rawInput,
        ]
    }

    func wireName(
        _ bindings: [String: ResponsesToolNamespaces.Binding],
        namespace: String,
        name: String
    ) throws -> String {
        let target = ResponsesToolNamespaces.Binding(namespace: namespace, name: name)
        return try #require(bindings.first { $0.value == target }?.key)
    }

    func workspaceAlias(_ bindings: [String: ResponsesToolNamespaces.Binding]) throws -> String {
        try wireName(bindings, namespace: "workspace", name: "patch")
    }
}
