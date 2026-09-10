import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Chat Completions namespace streaming")
struct ChatNamespaceStreamingTests {
    @Test("A streamed near-miss tool call restores the declared namespace pair")
    func streamedNamespaceNearMiss() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: try chatJSONData([
                "model": "little-switch-route",
                "input": "Spawn the pong agent.",
                "stream": true,
                "tools": [
                    [
                        "type": "namespace",
                        "name": "collaboration",
                        "description": "Collaboration tools.",
                        "tools": [
                            [
                                "type": "function",
                                "name": "spawn_agent",
                                "description": "Spawn an agent.",
                                "parameters": ["type": "object"],
                            ]
                        ],
                    ]
                ],
            ]),
            targetModel: "glm-5.2",
            mode: .streaming(toolStream: true)
        )
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        let startedEvents = try accumulator.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: [
                    "role": "assistant",
                    "tool_calls": [
                        chatToolDelta(
                            index: 0,
                            id: "call_nm",
                            name: "spawn_agent",
                            arguments: #"{"task":"pong"}"#
                        )
                    ],
                ])
            ])
        )
        let started = startedEvents.compactMap { event -> [String: Any]? in
            guard case .outputItemAdded(_, let itemJSON) = event,
                let item = try? chatJSONObject(itemJSON),
                item["type"] as? String == "function_call"
            else {
                return nil
            }
            return item
        }
        #expect(started.count == 1)
        #expect(started[0]["name"] as? String == "spawn_agent")
        #expect(started[0]["namespace"] as? String == "collaboration")

        _ = try accumulator.consume(
            chatChunkFrame(
                choices: [
                    chatChoice(
                        delta: ["role": "assistant", "content": ""],
                        finishReason: "tool_calls"
                    )
                ],
                usage: [
                    "prompt_tokens": 2,
                    "completion_tokens": 1,
                    "total_tokens": 3,
                ]
            )
        )
        _ = try accumulator.consume(chatDoneFrame())
        let turn = try accumulator.finish()
        let root = try chatJSONObject(turn.rootJSON)
        let output = try #require(root["output"] as? [[String: Any]])
        let call = try #require(output.first { $0["type"] as? String == "function_call" })
        #expect(call["name"] as? String == "spawn_agent")
        #expect(call["namespace"] as? String == "collaboration")
        #expect(root["status"] as? String == "completed")
    }
}
