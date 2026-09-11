import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Chat Completions streaming")
struct OpenAIChatCompletionsStreamingTests {
    @Test("ZAI streaming tool support matches exact model-family delimiters")
    func supportedToolStreamingModels() {
        let supported = [
            "glm-4.6",
            "GLM-4.7",
            "glm-5",
            "glm-4.6-air",
            "glm-4.7.latest",
            "GLM-5.2",
            "glm-5-flash",
        ]
        let unsupported = [
            "glm-4.5",
            "glm-4.60",
            "glm-47",
            "glm-50",
            "glm-5x",
            "glm-5_2",
            "prefix-glm-5",
            "glm-5 2",
        ]

        #expect(
            supported.allSatisfy {
                OpenAIResponsesChatCompletions.supportsZAIStreamingTools(modelID: $0)
            }
        )
        #expect(
            unsupported.allSatisfy {
                !OpenAIResponsesChatCompletions.supportsZAIStreamingTools(modelID: $0)
            }
        )
    }

    @Test("Streaming preparation enables usage and only supported requested tool streaming")
    func streamingRequestMode() throws {
        let live = try liveChatPrepared()
        let request = try chatJSONObject(live.upstreamBody)
        #expect(request["stream"] as? Bool == true)
        #expect(request["tool_stream"] as? Bool == true)
        #expect(
            (request["stream_options"] as? [String: Any])?["include_usage"] as? Bool
                == true
        )

        let unsupported = try chatJSONObject(
            try liveChatPrepared(targetModel: "glm-50").upstreamBody
        )
        #expect(unsupported["stream"] as? Bool == true)
        #expect(unsupported["tool_stream"] == nil)

        let noTools = try chatJSONObject(
            try liveChatPrepared(includeTools: false).upstreamBody
        )
        #expect(noTools["tool_stream"] == nil)

        let disabled = try chatJSONObject(
            try liveChatPrepared(toolStream: false).upstreamBody
        )
        #expect(disabled["tool_stream"] == nil)
    }

    @Test("Interleaved chunks publish immediately and reconstruct an incomplete turn")
    func interleavedToolCalls() throws {
        let prepared = try liveChatPrepared()
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        var events: [ResponsesProviderStreamEvent] = []
        for frame in try interleavedChatFrames() {
            events += try accumulator.consume(frame)
        }
        let turn = try accumulator.finish()

        #expect(events.compactMap(\.chatStartedResponseJSON).count == 1)
        #expect(events.contains { $0.outputTextDelta == "FIRST " })
        #expect(
            events.contains {
                $0.functionDone
                    == FunctionEventFixture(
                        itemID: "fc_resp_chatcmpl_stream_0",
                        callID: "call_search",
                        name: "web_search",
                        value: #"{"query":"latest Swift"}"#
                    )
            }
        )
        #expect(
            events.contains {
                $0.functionDone
                    == FunctionEventFixture(
                        itemID: "fc_resp_chatcmpl_stream_1",
                        callID: "call_weather",
                        name: "weather",
                        value: #"{"city":"Paris"}"#
                    )
            }
        )
        #expect(events.last?.terminalStatus == .incomplete)

        let root = try chatJSONObject(turn.rootJSON)
        #expect(root["id"] as? String == "resp_chatcmpl_stream")
        #expect(root["status"] as? String == "incomplete")
        #expect(turn.usage == ResponsesUsage(inputTokens: 10, outputTokens: 5))
        #expect(turn.webSearchCall == nil)
        let output = try #require(root["output"] as? [[String: Any]])
        let reconstructedSearch = try #require(
            output.first { $0["id"] as? String == "fc_resp_chatcmpl_stream_0" })
        #expect(
            reconstructedSearch as? [String: String] == [
                "id": "fc_resp_chatcmpl_stream_0",
                "type": "function_call",
                "status": "completed",
                "call_id": "call_search",
                "name": "web_search",
                "arguments": #"{"query":"latest Swift"}"#,
            ])
        #expect(
            output.compactMap { $0["id"] as? String }
                == [
                    "rs_resp_chatcmpl_stream",
                    "msg_resp_chatcmpl_stream",
                    "fc_resp_chatcmpl_stream_0",
                    "fc_resp_chatcmpl_stream_1",
                ]
        )
        let addedToolIndices = Dictionary(
            uniqueKeysWithValues: events.compactMap { event -> (String, Int)? in
                guard case .outputItemAdded(let outputIndex, _) = event,
                    case .outputItemAdded(_, let itemJSON) = event,
                    let item = try? chatJSONObject(itemJSON),
                    item["type"] as? String == "function_call",
                    let itemID = item["id"] as? String
                else {
                    return nil
                }
                return (itemID, outputIndex)
            }
        )
        #expect(addedToolIndices["fc_resp_chatcmpl_stream_0"] == 2)
        #expect(addedToolIndices["fc_resp_chatcmpl_stream_1"] == 3)
        let publicPayloads = events.compactMap(\.chatPayloadJSON) + [turn.rootJSON]
        var publicData = Data()
        for payload in publicPayloads {
            publicData.append(payload)
        }
        let publicJSON = try #require(String(data: publicData, encoding: .utf8))
        #expect(!publicJSON.contains("reasoning_content"))
        #expect(!publicJSON.contains("private chain of thought"))
    }

    @Test(
        "Stop and tool-call finishes become completed Responses turns",
        arguments: ["stop", "tool_calls"]
    )
    func completedFinishReasons(finishReason: String) throws {
        let prepared = try liveChatPrepared(toolNames: ["read_file"])
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        let events = try simpleChatFrames(finishReason: finishReason).flatMap {
            try accumulator.consume($0)
        }
        let turn = try accumulator.finish()
        let root = try chatJSONObject(turn.rootJSON)

        #expect(root["status"] as? String == "completed")
        #expect(events.last?.terminalStatus == .completed)
    }

    @Test("Terminal usage may share ZAI's final choice chunk")
    func terminalUsageAlongsideFinishReason() throws {
        let prepared = try liveChatPrepared()
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        _ = try accumulator.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: ["role": "assistant", "content": "OK"])
            ])
        )
        _ = try accumulator.consume(
            chatChunkFrame(
                choices: [chatChoice(delta: [:], finishReason: "stop")],
                usage: [
                    "prompt_tokens": 2,
                    "completion_tokens": 1,
                    "total_tokens": 3,
                ]
            )
        )
        let terminal = try accumulator.consume(chatDoneFrame())
        let turn = try accumulator.finish()

        #expect(terminal.last?.terminalStatus == .completed)
        #expect(turn.usage == ResponsesUsage(inputTokens: 2, outputTokens: 1))
    }

    @Test("ZAI tool finish accepts its empty assistant-content terminal delta")
    func toolFinishWithEmptyContent() throws {
        let prepared = try liveChatPrepared()
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        _ = try accumulator.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: [
                    "role": "assistant",
                    "tool_calls": [
                        chatToolDelta(
                            index: 0,
                            id: "call_search",
                            name: "web_search",
                            arguments: #"{"query":"Swift"}"#
                        )
                    ],
                ])
            ])
        )
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
        let terminal = try accumulator.consume(chatDoneFrame())
        let turn = try accumulator.finish()

        #expect(terminal.last?.terminalStatus == .completed)
        #expect(turn.webSearchCall?.query == "Swift")
    }

    @Test("ZAI sensitive finish becomes a Responses content-filter incomplete")
    func sensitiveFinishIsIncomplete() throws {
        let prepared = try liveChatPrepared()
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        _ = try accumulator.consume(
            chatChunkFrame(choices: [
                chatChoice(delta: ["role": "assistant", "content": "partial"])
            ])
        )
        _ = try accumulator.consume(
            chatChunkFrame(
                choices: [chatChoice(delta: [:], finishReason: "sensitive")],
                usage: [
                    "prompt_tokens": 2,
                    "completion_tokens": 1,
                    "total_tokens": 3,
                ]
            )
        )
        let terminal = try accumulator.consume(chatDoneFrame())
        let turn = try accumulator.finish()
        let response = try chatJSONObject(turn.rootJSON)

        #expect(terminal.last?.terminalStatus == .incomplete)
        #expect(response["status"] as? String == "incomplete")
        #expect(
            (response["incomplete_details"] as? [String: Any])?["reason"] as? String
                == "content_filter"
        )
    }
}
