import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses adapted model terminal semantics")
struct OpenAIResponsesWebSearchTerminalTests {
    @Test(
        "Buffered JSON and synthetic SSE preserve safe incomplete and failed terminals",
        arguments: ResponsesBufferedTerminalCase.allCases.filter(\.supportsNative)
    )
    func projectionParity(testCase: ResponsesBufferedTerminalCase) throws {
        let prepared = try preparedWebSearchRequest()
        let turn = try OpenAIResponsesWebSearch.parseModelTurn(testCase.body())
        let buffered = try responsesGatewayObject(
            OpenAIResponsesWebSearch.nonStreamingResponse(
                prepared: prepared, traces: [], finalTurn: turn, usage: turn.usage
            ))
        try testCase.expectTerminal(buffered)
        let events = try ResponsesStreamingTestSupport.events(
            OpenAIResponsesWebSearch.streamingResponse(
                prepared: prepared, traces: [], finalTurn: turn, usage: turn.usage
            ))
        let terminal = try #require(events.last)
        #expect(terminal.name == "response.\(testCase.status)")
        let streamed = try #require(terminal.payload["response"] as? [String: Any])
        #expect(NSDictionary(dictionary: streamed).isEqual(to: buffered))
        #expect(
            events.filter { ["response.completed", "response.incomplete", "response.failed"].contains($0.name) }.count
                == 1)
    }

    @Test("An interrupted private call never becomes executable", arguments: ["incomplete", "failed"])
    func interruptedPrivateCall(status: String) throws {
        var response = try responsesGatewayObject(
            ResponsesBufferedTerminalCase.nativeLength.body(privateSearchCall: true))
        response["status"] = status
        let turn = try OpenAIResponsesWebSearch.parseModelTurn(responseData(response))
        #expect(turn.webSearchCall == nil)
    }

    @Test(
        "Explicit nonterminal and unknown statuses are rejected",
        arguments: ["in_progress", "queued", "cancelled", "future", ""])
    func invalidStatus(status: String) throws {
        var response = try responsesGatewayObject(
            ResponsesBufferedTerminalCase.nativeLength.body(privateSearchCall: true))
        response["status"] = status
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try OpenAIResponsesWebSearch.parseModelTurn(responseData(response))
        }
    }

    @Test("Non-string terminal status cannot authorize a private search", arguments: ["null", "42"])
    func malformedStatus(value: String) throws {
        var response = try responsesGatewayObject(
            ResponsesBufferedTerminalCase.nativeLength.body(privateSearchCall: true))
        response["status"] = try JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed])
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try OpenAIResponsesWebSearch.parseModelTurn(responseData(response))
        }
    }

    @Test("Completed and incomplete model turns still require usage", arguments: ["completed", "incomplete"])
    func requiredUsage(status: String) throws {
        for omitted in [false, true] {
            var response = try responsesGatewayObject(ResponsesBufferedTerminalCase.nativeLength.body())
            response["status"] = status
            response["usage"] = omitted ? nil : NSNull()
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                try OpenAIResponsesWebSearch.parseModelTurn(responseData(response))
            }
        }
    }

    @Test("Failed turns reject malformed usage and output instead of treating them as absent")
    func malformedFailedFields() throws {
        for field in ["usage", "output"] {
            var response = try responsesGatewayObject(ResponsesBufferedTerminalCase.nativeFailure.body())
            response[field] = "invalid"
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                try OpenAIResponsesWebSearch.parseModelTurn(responseData(response))
            }
        }
    }
}
