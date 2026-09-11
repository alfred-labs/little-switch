import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Chat reasoning round trip")
struct ChatReasoningRoundTripTests {
    @Test("Responses reasoning effort reaches Chat unchanged", arguments: ["low", "medium", "high"])
    func reasoningEffort(effort: String) throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: try chatJSONData([
                "model": "route", "input": "Hello",
                "reasoning": ["effort": effort, "summary": "auto"],
            ]), targetModel: "provider-model"
        )
        let request = try chatJSONObject(prepared.upstreamBody)
        #expect(request["reasoning_effort"] as? String == effort)
        #expect(request["reasoning"] == nil)
    }

    @Test(
        "Chat reasoning survives only its original provider round trip",
        arguments: ["reasoning", "reasoning_content", "both"])
    func reasoningRoundTrip(field: String) throws {
        let fields = chatReasoningFields(field)
        let projected = try chatReasoningProjection(fields: fields)
        let output = try chatReasoningOutput(projected)
        #expect(output.compactMap { $0["type"] as? String } == ["reasoning", "message"])
        let reasoning = try #require(output.first { $0["type"] as? String == "reasoning" })
        #expect((reasoning["summary"] as? [Any])?.isEmpty == true)
        #expect(reasoning["content"] == nil)
        #expect(try !chatReasoningText(projected).contains("SYNTHETIC"))

        let origin = UUID()
        let tagged = try ResponsesProviderState.tag(response: projected, providerID: origin)
        let originalHistory = try chatReasoningHistory(try chatReasoningOutput(tagged))
        let restored = try ResponsesProviderState.normalize(body: originalHistory, providerID: origin)
        let request = try OpenAIResponsesChatCompletions.prepare(body: restored, targetModel: "provider-model")
        var expected: [String: Any] = ["role": "assistant", "content": "Visible answer"]
        for (key, value) in fields { expected[key] = value }
        let expectedMessages: [[String: Any]] = [expected, ["role": "user", "content": "Continue"]]
        #expect(try chatJSONData(chatReasoningMessages(request.upstreamBody)) == chatJSONData(expectedMessages))

        for destination: UUID? in [UUID(), nil] {
            let normalized = try ResponsesProviderState.normalize(body: originalHistory, providerID: destination)
            let input = try #require(chatJSONObject(normalized)["input"] as? [[String: Any]])
            #expect(input.compactMap { $0["type"] as? String } == ["message", "message"])
            #expect(try !chatReasoningText(normalized).contains("little_switch_chat_reasoning"))
        }
        #expect(try ResponsesProviderState.normalize(body: originalHistory, providerID: origin) == restored)
    }

    @Test("Reasoning stays with its tool-calling assistant", arguments: ["reasoning", "reasoning_content"])
    func toolCallingReasoning(field: String) throws {
        let fields = chatReasoningFields(field)
        let call: [String: Any] = [
            "id": "call_reasoning", "type": "function",
            "function": ["name": "inspect", "arguments": "{}"],
        ]
        var message: [String: Any] = ["role": "assistant", "content": NSNull(), "tool_calls": [call]]
        for (key, value) in fields { message[key] = value }
        let projected = try OpenAIResponsesChatCompletions.project(
            responseBody: chatReasoningResponse(message: message, finishReason: "tool_calls"),
            prepared: chatReasoningPrepared()
        )
        let origin = UUID()
        let tagged = try ResponsesProviderState.tag(response: projected, providerID: origin)
        var input = try chatReasoningOutput(tagged)
        input.append(["type": "function_call_output", "call_id": "call_reasoning", "output": "Done"])
        let history = try ResponsesProviderState.normalize(body: chatReasoningHistory(input), providerID: origin)
        let request = try OpenAIResponsesChatCompletions.prepare(body: history, targetModel: "provider-model")
        let expected: [[String: Any]] = [
            message, ["role": "tool", "tool_call_id": "call_reasoning", "content": "Done"],
            ["role": "user", "content": "Continue"],
        ]
        #expect(try chatJSONData(chatReasoningMessages(request.upstreamBody)) == chatJSONData(expected))
    }

    @Test("Native opaque reasoning is never interpreted as Chat reasoning")
    func nativeStateIsOpaque() throws {
        let input: [[String: Any]] = [
            [
                "type": "reasoning", "id": "rs_openai_opaque", "encrypted_content": "opaque-native-cipher",
                "summary": [],
            ],
            ["type": "message", "role": "assistant", "content": "Visible answer"],
        ]
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: chatReasoningHistory(input), targetModel: "provider-model"
        )
        let expected: [[String: Any]] = [
            ["role": "assistant", "content": "Visible answer"], ["role": "user", "content": "Continue"],
        ]
        #expect(try chatJSONData(chatReasoningMessages(prepared.upstreamBody)) == chatJSONData(expected))
    }

    @Test("Malformed Chat reasoning is rejected instead of discarded", arguments: ["reasoning", "reasoning_content"])
    func invalidReasoning(field: String) throws {
        for invalid: Any in [1, ["text": "invalid"]] {
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
                _ = try OpenAIResponsesChatCompletions.project(
                    responseBody: chatReasoningResponse(message: [
                        "role": "assistant", "content": "Visible", field: invalid,
                    ]),
                    prepared: chatReasoningPrepared()
                )
            }
        }
    }
}

func chatReasoningFields(_ field: String = "both") -> [String: String] {
    let all = [
        "reasoning": "SYNTHETIC reasoning α\n retained ",
        "reasoning_content": "SYNTHETIC content β\n distinct ",
    ]
    return field == "both" ? all : all.filter { $0.key == field }
}

func chatReasoningPrepared(streaming: Bool = false) throws -> PreparedResponsesChatCompletionsRequest {
    try OpenAIResponsesChatCompletions.prepare(
        body: chatJSONData(["model": "route", "input": "Hello", "stream": streaming]),
        targetModel: "provider-model",
        mode: streaming ? .streaming(toolStream: false) : .buffered
    )
}

func chatReasoningProjection(fields: [String: String]) throws -> Data {
    var message: [String: Any] = ["role": "assistant", "content": "Visible answer"]
    for (key, value) in fields { message[key] = value }
    return try OpenAIResponsesChatCompletions.project(
        responseBody: chatReasoningResponse(message: message), prepared: chatReasoningPrepared()
    )
}

func chatReasoningResponse(message: [String: Any], finishReason: String = "stop") throws -> Data {
    try chatJSONData([
        "id": "chatcmpl_reasoning", "object": "chat.completion", "created": 100, "model": "provider-model",
        "choices": [["index": 0, "finish_reason": finishReason, "message": message]],
        "usage": ["prompt_tokens": 2, "completion_tokens": 1, "total_tokens": 3],
    ])
}

func chatReasoningOutput(_ response: Data) throws -> [[String: Any]] {
    try #require(chatJSONObject(response)["output"] as? [[String: Any]])
}

func chatReasoningMessages(_ request: Data) throws -> [[String: Any]] {
    try #require(chatJSONObject(request)["messages"] as? [[String: Any]])
}

func chatReasoningText(_ data: Data) throws -> String {
    try #require(String(bytes: data, encoding: .utf8))
}

func chatReasoningHistory(_ output: [[String: Any]], model: String = "route") throws -> Data {
    try chatJSONData([
        "model": model, "input": output + [["type": "message", "role": "user", "content": "Continue"]],
    ])
}
