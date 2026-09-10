import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Adapter tool namespace round trip")
struct AdapterToolNamespaceRoundTripTests {
    private func requestBody(input: [[String: Any]] = []) throws -> Data {
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
            status: "completed",
            binding: ResponsesToolNamespaces.Binding(
                namespace: "multi_agent_v1",
                name: "spawn_agent"
            )
        )

        #expect(bound["name"] as? String == "spawn_agent")
        #expect(bound["namespace"] as? String == "multi_agent_v1")

        let unbound = chatFunctionItem(
            itemID: "fc_2",
            callID: "call_2",
            name: "shell",
            arguments: "{}",
            status: "completed"
        )

        #expect(unbound["name"] as? String == "shell")
        #expect(unbound["namespace"] == nil)
    }

    @Test("A streamed namespaced call publishes through the public session")
    func streamedNamespacedCallSurvivesPublicSession() throws {
        var streamingBody = try chatJSONObject(try requestBody())
        streamingBody["stream"] = true
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: try chatJSONData(streamingBody),
            targetModel: "upstream",
            mode: .streaming(toolStream: false)
        )

        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        var events: [ResponsesProviderStreamEvent] = []
        for frame in try [
            chatChunkFrame(choices: [
                chatChoice(delta: ["role": "assistant", "content": "Je crée 1 agent."])
            ]),
            chatChunkFrame(choices: [
                chatChoice(delta: [
                    "tool_calls": [
                        chatToolDelta(
                            index: 0,
                            id: "call_spawn",
                            name: "multi_agent_v1__spawn_agent",
                            arguments: #"{"#
                        )
                    ]
                ])
            ]),
            chatChunkFrame(choices: [
                chatChoice(delta: [
                    "tool_calls": [
                        chatToolDelta(index: 0, arguments: #"prompt":"hi"}"#)
                    ]
                ])
            ]),
            chatChunkFrame(choices: [chatChoice(delta: [:], finishReason: "tool_calls")]),
            chatChunkFrame(
                choices: [],
                usage: [
                    "prompt_tokens": 2,
                    "completion_tokens": 1,
                    "total_tokens": 3,
                ]
            ),
            chatDoneFrame(),
        ] {
            events += try accumulator.consume(frame)
        }
        _ = try accumulator.finish()

        let deltaNames = events.compactMap { event -> String? in
            guard case .functionArgumentsDelta(_, _, _, let name, _) = event else {
                return nil
            }
            return name
        }
        #expect(deltaNames == ["spawn_agent", "spawn_agent"])

        var session = ResponsesPublicStreamSession(chatCompletions: prepared)
        var wire = Data()
        for event in events {
            if session.started {
                wire += try session.consumePublic(event).joined()
                continue
            }
            guard case .responseStarted(let responseJSON) = event else {
                Issue.record("The first streamed event must start the session")
                return
            }
            wire += try session.start(responseJSON: responseJSON).joined()
        }

        let text = try #require(String(bytes: wire, encoding: .utf8))
        #expect(text.contains("response.output_item.added"))
        #expect(text.contains("response.function_call_arguments.delta"))
        #expect(text.contains("\"namespace\":\"multi_agent_v1\""))
        #expect(text.contains(#""name":"spawn_agent""#))
    }

    @Test("Reasoning before a namespaced call mirrors the failing z.ai stream")
    func reasoningThenNamespacedCallSurvivesPublicSession() throws {
        var streamingBody = try chatJSONObject(try requestBody())
        streamingBody["stream"] = true
        streamingBody["tools"] =
            (streamingBody["tools"] as? [[String: Any]] ?? []) + [
                ["type": "web_search"]
            ]
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: try chatJSONData(streamingBody),
            targetModel: "upstream",
            mode: .streaming(toolStream: false)
        )

        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        var events: [ResponsesProviderStreamEvent] = []
        for frame in try [
            chatChunkFrame(choices: [
                chatChoice(delta: ["role": "assistant", "reasoning_content": "Je réfléchis."])
            ]),
            chatChunkFrame(choices: [
                chatChoice(delta: ["role": "assistant", "reasoning_content": "."])
            ]),
            chatChunkFrame(choices: [
                chatChoice(delta: ["role": "assistant", "content": "Je crée 4 agents."])
            ]),
            chatChunkFrame(choices: [
                chatChoice(delta: [
                    "tool_calls": [
                        chatToolDelta(
                            index: 0,
                            id: "call_spawn",
                            name: "multi_agent_v1__spawn_agent",
                            arguments: #"{"#
                        )
                    ]
                ])
            ]),
            chatChunkFrame(choices: [
                chatChoice(delta: [:], finishReason: "tool_calls")
            ]),
            chatChunkFrame(
                choices: [],
                usage: [
                    "prompt_tokens": 2,
                    "completion_tokens": 1,
                    "total_tokens": 3,
                ]
            ),
            chatDoneFrame(),
        ] {
            events += try accumulator.consume(frame)
        }
        _ = try accumulator.finish()

        var session = ResponsesPublicStreamSession(chatCompletions: prepared)
        var wire = Data()
        for event in events {
            if session.started {
                wire += try session.consumePublic(event).joined()
                continue
            }
            guard case .responseStarted(let responseJSON) = event else {
                Issue.record("The first streamed event must start the session")
                return
            }
            wire += try session.start(responseJSON: responseJSON).joined()
        }

        let text = try #require(String(bytes: wire, encoding: .utf8))
        #expect(text.contains("response.function_call_arguments.delta"))
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
