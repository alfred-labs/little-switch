import Foundation
import LittleSwitchCommon
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Responses wire history boundary validation")
struct ResponsesWireHistoryValidationTests {
    @Test func followUpRejectsMalformedOrNonObjectRequests() throws {
        let turn = try OpenAIResponsesWebSearch.parseModelTurn(
            Data(
                #"{"id":"resp","object":"response","status":"completed","output":[],"usage":{}}"#.utf8))
        for body in ["{", "[]"] {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                try OpenAIResponsesWebSearch.followUpRequest(
                    baseBody: Data(body.utf8),
                    turn: turn,
                    toolCall: ResponsesWebSearchToolCall(callID: "call", query: "query"),
                    resultText: "result",
                    mode: .result)
            }
        }
    }

    @Test func retiredCustomHistoryRetainsOutputIdentityWithEmptyNamespace() throws {
        let body = Data(
            #"""
            {"model":"m","input":[
              {"type":"custom_tool_call","call_id":"call","name":"retired","namespace":"","input":"payload"},
              {"type":"custom_tool_call_output","id":"output","call_id":"call","output":"result"}
            ]}
            """#
            .utf8)
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(body)
        let input = try #require(JSONValue.parse(normalized.body).object?["input"]?.array)
        #expect(input.count == 2)
        let original = try #require(JSONValue.parse(body).object?["input"]?.array)
        #expect(try input.map(historyArchiveItem) == original)
        #expect(try historyArchiveItem(input[0]).object?["namespace"] == .string(""))
    }

    @Test func presentEmptyChatUsageDefaultsToZeroCounters() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: Data(#"{"model":"route","input":"hi"}"#.utf8), targetModel: "provider")
        let response = try OpenAIResponsesChatCompletions.project(
            responseBody: Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"ok"}}],"usage":{}}"#.utf8),
            prepared: prepared)
        let turn = try OpenAIResponsesWebSearch.parseModelTurn(response)
        #expect(turn.usage == ResponsesUsage(inputTokens: 0, outputTokens: 0))
    }

    @Test func manuallyConstructedTurnsCannotPublishNamelessCalls() throws {
        let root = try responseData(
            responseObject(
                id: "resp",
                createdAt: 1,
                status: "completed",
                output: [],
                usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)))
        let turn = ResponsesModelTurn(
            id: "resp",
            rootJSON: root,
            outputJSON: Data(#"[{"type":"function_call","id":"fc","call_id":"call","arguments":"{}"}]"#.utf8),
            usage: ResponsesUsage(inputTokens: 0, outputTokens: 0),
            webSearchCall: nil)
        let prepared = try preparedWebSearchRequest()
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try OpenAIResponsesWebSearch.nonStreamingResponse(
                prepared: prepared, traces: [], finalTurn: turn, usage: turn.usage)
        }
    }

    @Test(arguments: [
        #"{"type":"function_call","call_id":"call","name":"run","arguments":"{}"}"#,
        #"{"type":"custom_tool_call","call_id":"call","name":"run","input":"payload"}"#,
    ])
    func streamedCallsRequireAnItemIDInAdditionToCallID(item: String) throws {
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try accumulator.consume(createdFrame(id: "resp", createdAt: 1))
        let event = Data("{\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":\(item)}".utf8)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try accumulator.consume(.init(event: "response.output_item.added", data: event, terminal: false))
        }
    }

    @Test(arguments: [false, true])
    func failedTerminalMayOmitItsErrorObject(explicitNull: Bool) throws {
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try accumulator.consume(createdFrame(id: "resp", createdAt: 1))
        var response: [String: Any] = ["id": "resp", "object": "response", "status": "failed"]
        if explicitNull { response["error"] = NSNull() }
        let events = try accumulator.consume(responsesFrame("response.failed", ["response": response]))
        #expect(events == [.terminal(status: .failed, responseJSON: try responseData(response))])
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) { try accumulator.finish() }
    }
}
