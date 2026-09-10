import Foundation
import Testing

@testable import LittleSwitchCore

// The two public-session round trips of the namespace suite, split out to
// keep the main suite under review. They publish the accumulated provider
// stream back through `ResponsesPublicStreamSession` and assert the restored
// pair on the wire.

extension AdapterToolNamespaceRoundTripTests {
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
}
