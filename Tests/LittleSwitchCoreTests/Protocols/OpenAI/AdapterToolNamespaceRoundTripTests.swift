import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Adapter tool namespace round trip")
struct AdapterToolNamespaceRoundTripTests {
    // Internal so the public-session split (`AdapterToolNamespacePublicSessionTests`)
    // can build the same request body.
    func requestBody(input: [[String: Any]] = []) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "model": "client-model",
                "input": input.isEmpty
                    ? [["type": "message", "role": "user", "content": []]] : input,
                "tools": [
                    [
                        "type": "namespace",
                        "name": "multi_agent_v1",
                        "description": "Agents.",
                        "tools": [
                            [
                                "type": "function",
                                "name": "spawn_agent",
                                "description": "Spawn one.",
                                "parameters": ["type": "object", "properties": [:]],
                            ]
                        ],
                    ]
                ],
            ]
        )
    }

    private func chatResponse(callingTool name: String) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "id": "chatcmpl_1",
                "created": 1,
                "choices": [
                    [
                        "finish_reason": "tool_calls",
                        "message": [
                            "role": "assistant",
                            "content": NSNull(),
                            "tool_calls": [
                                [
                                    "id": "call_1",
                                    "type": "function",
                                    "function": ["name": name, "arguments": "{}"],
                                ]
                            ],
                        ],
                    ]
                ],
            ]
        )
    }

    @Test("The provider receives a flat callable tool")
    func upstreamToolIsFlat() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: try requestBody(),
            targetModel: "upstream"
        )

        let upstream =
            try JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any]
        let tools = upstream?["tools"] as? [[String: Any]]
        let names = tools?.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }

        #expect(names == ["multi_agent_v1__spawn_agent"])
        #expect(prepared.toolBindings.count == 1)
    }

    @Test("The call comes back with the namespace Codex resolves against")
    func callIsRestored() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: try requestBody(),
            targetModel: "upstream"
        )

        let projected = try OpenAIResponsesChatCompletions.project(
            responseBody: try chatResponse(callingTool: "multi_agent_v1__spawn_agent"),
            prepared: prepared
        )

        let response = try JSONSerialization.jsonObject(with: projected) as? [String: Any]
        let output = response?["output"] as? [[String: Any]]
        let call = output?.first { $0["type"] as? String == "function_call" }

        #expect(call?["name"] as? String == "spawn_agent")
        #expect(call?["namespace"] as? String == "multi_agent_v1")
    }

    @Test("A near-miss flat call name resolves against the declared children")
    func nearMissCallIsRestored() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: try requestBody(),
            targetModel: "upstream"
        )
        // The production failure shape: the backend calls the bare child name.
        let projected = try OpenAIResponsesChatCompletions.project(
            responseBody: try chatResponse(callingTool: "spawn_agent"),
            prepared: prepared
        )

        let response = try JSONSerialization.jsonObject(with: projected) as? [String: Any]
        let call = (response?["output"] as? [[String: Any]])?
            .first { $0["type"] as? String == "function_call" }

        #expect(call?["name"] as? String == "spawn_agent")
        #expect(call?["namespace"] as? String == "multi_agent_v1")
    }

    @Test("An unknown flat name is passed through unchanged")
    func unknownNameUntouched() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: try requestBody(),
            targetModel: "upstream"
        )

        let projected = try OpenAIResponsesChatCompletions.project(
            responseBody: try chatResponse(callingTool: "shell"),
            prepared: prepared
        )

        let response = try JSONSerialization.jsonObject(with: projected) as? [String: Any]
        let call = (response?["output"] as? [[String: Any]])?
            .first { $0["type"] as? String == "function_call" }

        #expect(call?["name"] as? String == "shell")
        #expect(call?["namespace"] == nil)
    }

    @Test("A streamed call carries the restored pair, or nothing when unbound")
    func streamedItemRestoresBinding() {
        let bound = chatFunctionItem(
            itemID: "fc_1",
            callID: "call_1",
            name: "multi_agent_v1__spawn_agent",
            arguments: "{}",
            status: .completed,
            binding: ResponsesToolNamespaces.Binding(
                namespace: "multi_agent_v1",
                name: "spawn_agent"
            )
        )

        #expect(bound.name == "spawn_agent")
        #expect(bound.namespace.value == "multi_agent_v1")

        let unbound = chatFunctionItem(
            itemID: "fc_2",
            callID: "call_2",
            name: "shell",
            arguments: "{}",
            status: .completed
        )

        #expect(unbound.name == "shell")
        #expect(unbound.namespace == .absent)
    }

    @Test("Replayed history reuses the flat name the provider saw")
    func replayedHistoryUsesFlatName() throws {
        let history: [[String: Any]] = [
            ["type": "message", "role": "user", "content": []],
            [
                "type": "function_call",
                "call_id": "call_1",
                "name": "spawn_agent",
                "namespace": "multi_agent_v1",
                "arguments": "{}",
            ],
            ["type": "function_call_output", "call_id": "call_1", "output": "done"],
        ]

        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: try requestBody(input: history),
            targetModel: "upstream"
        )

        let upstream =
            try JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any]
        let messages = upstream?["messages"] as? [[String: Any]]
        let names = messages?.compactMap { message -> String? in
            guard let calls = message["tool_calls"] as? [[String: Any]] else { return nil }
            return (calls.first?["function"] as? [String: Any])?["name"] as? String
        }

        #expect(names == ["multi_agent_v1__spawn_agent"])
    }
}
