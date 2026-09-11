import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("Chat reasoning streaming")
struct ChatReasoningStreamingTests {
    @Test(
        "Fragmented Chat reasoning survives the public stream and replay",
        arguments: ["reasoning", "reasoning_content", "both"])
    func fragmentedReasoning(field: String) throws {
        let fields = chatReasoningFields(field)
        let prepared = try chatReasoningPrepared(streaming: true)
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
        let events = try chatReasoningFrames(fields: fields).flatMap { try accumulator.consume($0) }
        let turn = try accumulator.finish()
        let completed = try events.compactMap { event -> [String: Any]? in
            guard case .outputItemDone(_, let itemJSON) = event else { return nil }
            return try chatJSONObject(itemJSON)
        }
        #expect(completed.filter { $0["type"] as? String == "reasoning" }.count == 1)
        let output = try chatReasoningOutput(turn.rootJSON)
        #expect(output.compactMap { $0["type"] as? String } == ["reasoning", "message"])
        #expect(try !chatReasoningText(turn.rootJSON).contains("SYNTHETIC"))
        let publicBody = try chatReasoningPublicStream(events: events, turn: turn, prepared: prepared)
        let publicEvents = try ResponsesStreamingTestSupport.events(publicBody)
        let terminal = try #require(publicEvents.last?.payload["response"] as? [String: Any])
        #expect(try chatJSONData(chatReasoningOutput(chatJSONData(terminal))) == chatJSONData(output))
        let origin = UUID()
        let tagged = try ResponsesProviderState.tag(response: chatJSONData(terminal), providerID: origin)
        let restored = try ResponsesProviderState.normalize(
            body: chatReasoningHistory(chatReasoningOutput(tagged)), providerID: origin
        )
        let next = try OpenAIResponsesChatCompletions.prepare(body: restored, targetModel: "provider-model")
        var expected: [String: Any] = ["role": "assistant", "content": "Visible answer"]
        for (key, value) in fields { expected[key] = value }
        let messages: [[String: Any]] = [expected, ["role": "user", "content": "Continue"]]
        #expect(try chatJSONData(chatReasoningMessages(next.upstreamBody)) == chatJSONData(messages))
    }

    @Test("Malformed reasoning fragments fail the Chat stream", arguments: ["reasoning", "reasoning_content"])
    func malformedFragment(field: String) throws {
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: try chatReasoningPrepared(streaming: true))
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try accumulator.consume(chatChunkFrame(choices: [chatChoice(delta: [field: 42])]))
        }
    }

    @Test("Chat refusals remain structured in JSON and SSE", arguments: [false, true], ["stop", "content_filter"])
    func refusalProjection(streaming: Bool, finishReason: String) throws {
        let refusal = "I cannot provide that."
        let response: Data
        if streaming {
            let prepared = try chatReasoningPrepared(streaming: true)
            var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
            let frames = try [
                chatChunkFrame(choices: [chatChoice(delta: ["role": "assistant", "refusal": "I cannot "])]),
                chatChunkFrame(choices: [chatChoice(delta: ["refusal": "provide that."])]),
                chatChunkFrame(choices: [chatChoice(delta: [:], finishReason: finishReason)]),
                chatChunkFrame(choices: [], usage: ["prompt_tokens": 2, "completion_tokens": 1, "total_tokens": 3]),
                chatDoneFrame(),
            ]
            let events = try frames.flatMap { try accumulator.consume($0) }
            let turn = try accumulator.finish()
            let stream = try chatReasoningPublicStream(events: events, turn: turn, prepared: prepared)
            let publicEvents = try ResponsesStreamingTestSupport.events(stream)
            response = try chatJSONData(#require(publicEvents.last?.payload["response"] as? [String: Any]))
        } else {
            response = try OpenAIResponsesChatCompletions.project(
                responseBody: chatReasoningResponse(
                    message: ["role": "assistant", "content": NSNull(), "refusal": refusal], finishReason: finishReason
                ), prepared: chatReasoningPrepared()
            )
        }
        let root = try chatJSONObject(response)
        #expect(root["status"] as? String == (finishReason == "stop" ? "completed" : "incomplete"))
        if finishReason == "content_filter" {
            #expect((root["incomplete_details"] as? [String: Any])?["reason"] as? String == "content_filter")
        }
        let output = try chatReasoningOutput(response)
        let content = try #require(output.first?["content"] as? [[String: Any]])
        #expect(try chatJSONData(content) == chatJSONData([["type": "refusal", "refusal": refusal]]))
    }
}

func chatReasoningFrames(fields: [String: String]) throws -> [ServerSentEventFrame] {
    let initial = fields.mapValues { String($0.prefix(9)) }
    let remaining = fields.mapValues { String($0.dropFirst(9)) }
    return try [
        chatChunkFrame(choices: [chatChoice(delta: initial)]),
        chatChunkFrame(choices: [chatChoice(delta: remaining)]),
        chatChunkFrame(choices: [chatChoice(delta: ["role": "assistant", "content": "Visible answer"])]),
        chatChunkFrame(choices: [chatChoice(delta: [:], finishReason: "stop")]),
        chatChunkFrame(choices: [], usage: ["prompt_tokens": 2, "completion_tokens": 1, "total_tokens": 3]),
        chatDoneFrame(),
    ]
}

private func chatReasoningPublicStream(
    events: [ResponsesProviderStreamEvent], turn: ResponsesModelTurn, prepared: PreparedResponsesChatCompletionsRequest
) throws -> Data {
    var session = ResponsesPublicStreamSession(chatCompletions: prepared)
    var body = Data()
    for event in events {
        let frames: [Data]
        if case .responseStarted(let root) = event, !session.started {
            frames = try session.start(responseJSON: root)
        } else {
            frames = try session.consumePublic(event)
        }
        for frame in frames { body.append(frame) }
    }
    for frame in try session.finish(responseJSON: turn.rootJSON, usage: turn.usage) { body.append(frame) }
    return body
}
