import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Chat refusal streaming boundaries")
struct ChatRefusalStreamingBoundaryTests {
    @Test("Text and refusal parts keep their stream indices and completed content", arguments: [false, true])
    func mixedContent(refusalFirst: Bool) throws {
        let prepared = try chatReasoningPrepared(streaming: true)
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        var session = ResponsesPublicStreamSession(chatCompletions: prepared)
        let first = refusalFirst ? ["refusal": "Cannot "] : ["content": "Visible "]
        let second = refusalFirst ? ["content": "Visible "] : ["refusal": "Cannot "]
        let frames = try [
            chatChunkFrame(choices: [chatChoice(delta: first)]),
            chatChunkFrame(choices: [chatChoice(delta: second)]),
            chatChunkFrame(choices: [chatChoice(delta: ["content": "answer", "refusal": "comply"])]),
            chatChunkFrame(
                choices: [chatChoice(delta: [:], finishReason: "content_filter")],
                usage: ["prompt_tokens": 0, "completion_tokens": 0]),
            chatDoneFrame(),
        ]
        var publicFrames: [Data] = []
        for frame in frames {
            for event in try accumulator.consume(frame) {
                if case .responseStarted(let data) = event {
                    publicFrames += try session.start(responseJSON: data)
                } else {
                    publicFrames += try session.consumePublic(event)
                }
            }
        }
        let turn = try accumulator.finish()
        publicFrames += try session.finish(responseJSON: turn.rootJSON, usage: turn.usage)
        let events = try publicEvents(publicFrames)
        let parts: [[String: Any]] = [
            ["type": "output_text", "text": "Visible answer", "annotations": [], "logprobs": []],
            ["type": "refusal", "refusal": "Cannot comply"],
        ]
        let expected = refusalFirst ? Array(parts.reversed()) : parts
        let done = try #require(
            events.first { $0.name == "response.output_item.done" }?.payload["item"] as? [String: Any])
        #expect(done["content"] as? NSArray == expected as NSArray)
        let response = try #require(events.last?.payload["response"] as? [String: Any])
        let output = try #require(response["output"] as? [[String: Any]])
        #expect(output.first?["content"] as? NSArray == expected as NSArray)
        let indices = events.filter { $0.name == "response.content_part.added" }.compactMap {
            $0.payload["content_index"] as? Int
        }
        #expect(indices == [0, 1])
        #expect(response["status"] as? String == "incomplete")
    }

    @Test(
        "Late reasoning and malformed or post-tool refusals fail before publication",
        arguments: ["reasoningAfterText", "reasoningAfterTool", "refusalAfterTool", "malformedRefusal"])
    func invalidFragment(_ variant: String) throws {
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: try chatReasoningPrepared(streaming: true))
        if variant == "reasoningAfterText" {
            _ = try accumulator.consume(chatChunkFrame(choices: [chatChoice(delta: ["content": "Visible"])]))
        } else if variant != "malformedRefusal" {
            _ = try accumulator.consume(
                chatChunkFrame(choices: [
                    chatChoice(delta: [
                        "tool_calls": [chatToolDelta(index: 0, id: "call", name: "read", arguments: "{}")]
                    ])
                ]))
        }
        let delta: [String: Any]
        switch variant {
        case "malformedRefusal": delta = ["refusal": 42]
        case "refusalAfterTool": delta = ["refusal": "Cannot comply"]
        default: delta = ["reasoning_content": "SYNTHETIC late reasoning"]
        }
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try accumulator.consume(chatChunkFrame(choices: [chatChoice(delta: delta)]))
        }
    }

    @Test(
        "Public refusal events require a refusal part and a string payload", arguments: ["delta", "done"],
        [false, true])
    func invalidPublicRefusal(event: String, wrongPart: Bool) throws {
        var session = ResponsesPublicStreamSession(chatCompletions: try chatReasoningPrepared(streaming: true))
        _ = try session.start(
            responseJSON: chatStartedResponseJSON(responseID: "resp", created: 1, originalModel: "route"))
        _ = try session.consumePublic(
            .outputItemAdded(
                outputIndex: 0,
                itemJSON: chatJSONData(["id": "msg", "type": "message", "role": "assistant", "content": []])))
        let part: [String: Any] = wrongPart ? ["type": "output_text", "text": ""] : ["type": "refusal", "refusal": ""]
        _ = try session.consumePublic(
            .contentPartAdded(outputIndex: 0, contentIndex: 0, itemID: "msg", partJSON: chatJSONData(part)))
        let type = "response.refusal." + event
        let payload: [String: Any] = [
            "type": type, "output_index": 0, "content_index": 0, "item_id": "msg",
            event == "delta" ? "delta" : "refusal": wrongPart ? "refusal" : 42,
        ]
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try session.consumePublic(.passthrough(type: type, payloadJSON: chatJSONData(payload)))
        }
    }
}
