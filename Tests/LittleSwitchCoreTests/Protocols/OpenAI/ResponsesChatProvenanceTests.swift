import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Provider-scoped Chat reasoning")
struct ResponsesChatProvenanceTests {
    @Test("Buffered and streamed Chat state belongs to the selected provider", arguments: [false, true])
    func chatRoundTrip(streaming: Bool) throws {
        let provider = UUID()
        let owner = provider
        let sibling = UUID()
        let fields = chatReasoningFields()
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: chatJSONData(["model": "route", "input": "Hello", "stream": streaming]),
            targetModel: "provider-model",
            providerID: owner,
            mode: streaming ? .streaming(toolStream: false) : .buffered)
        let body: Data
        if streaming {
            var accumulator = OpenAIChatCompletionsAccumulator(prepared: prepared)
            let events = try chatReasoningFrames(fields: fields).flatMap { try accumulator.consume($0) }
            let turn = try accumulator.finish()
            body = turn.rootJSON
            let completed = try events.compactMap { event -> [String: Any]? in
                guard case .outputItemDone(_, let itemJSON) = event else { return nil }
                let item = try chatJSONObject(itemJSON)
                return item["type"] as? String == "reasoning" ? item : nil
            }
            #expect(completed.count == 1)
            #expect(
                try ResponsesChatCompletionsReasoning.fields(from: #require(completed.first), providerID: owner)
                    == fields)
        } else {
            var message: [String: Any] = ["role": "assistant", "content": "Visible answer"]
            for (key, value) in fields { message[key] = value }
            body = try OpenAIResponsesChatCompletions.project(
                responseBody: chatReasoningResponse(message: message), prepared: prepared)
        }
        let output = try chatReasoningOutput(body)
        let reasoning = try #require(output.first)
        #expect(try ResponsesChatCompletionsReasoning.fields(from: reasoning, providerID: owner) == fields)
        #expect(try ResponsesChatCompletionsReasoning.fields(from: reasoning, providerID: sibling) == nil)
        let history = try chatReasoningHistory(output)
        for destination in [owner, sibling, owner] {
            let normalized = try ResponsesProviderState.normalize(body: history, providerID: destination)
            let next = try OpenAIResponsesChatCompletions.prepare(
                body: normalized, targetModel: "provider-model", providerID: destination)
            var assistant: [String: Any] = ["role": "assistant", "content": "Visible answer"]
            if destination == owner {
                for (key, value) in fields { assistant[key] = value }
            }
            #expect(
                try chatJSONData(chatReasoningMessages(next.upstreamBody))
                    == chatJSONData([
                        assistant, ["role": "user", "content": "Continue"],
                    ]))
        }
    }

    @Test("Fragmented SSE tags output slots and leaves nested tool data intact")
    func fragmentedSSE() async throws {
        let origin = UUID()
        let item: [String: Any] = ["type": "reasoning", "id": "rs_a", "encrypted_content": "synthetic-private"]
        let nested = #"{"type":"reasoning","encrypted_content":"tool-value"}"#
        let frame = try responsesStreamData([
            "type": "response.output_item.done", "output_index": 0, "item": item,
            "future_tool_arguments": nested,
        ])
        let input = Data("event: response.output_item.done\ndata: ".utf8) + frame + Data("\n\n".utf8)
        let pieces = stride(from: 0, to: input.count, by: 7).map { index in
            ByteBuffer(bytes: input[index..<min(index + 7, input.count)])
        }
        let response = HTTPClientResponse(
            status: .ok,
            headers: ["content-type": "text/event-stream"],
            body: .stream(
                AsyncStream { continuation in
                    for piece in pieces { continuation.yield(piece) }
                    continuation.finish()
                }))
        let tagged = try await ResponsesProviderStateResponse.tagged(response, providerID: origin, maximumBytes: 4_096)
        let collected = try await tagged.body.collect(upTo: 4_096)
        let events = try ResponsesStreamingTestSupport.events(Data(collected.readableBytesView))
        let event = try #require(events.first?.payload)
        let restored = try ResponsesProviderState.restoreTaggedReasoning(
            #require(event["item"] as? [String: Any]), providerID: origin)
        #expect(try responsesStreamData(restored as Any) == responsesStreamData(item))
        #expect(event["future_tool_arguments"] as? String == nested)
    }
}
