import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Responses WebSocket state")
struct ResponsesWebSocketStateTests {
    @Test("Continuation combines public history while using only current request settings")
    func continuation() throws {
        var state = ResponsesWebSocketState()
        try state.enqueue(
            Data(
                #"""
                {"type":"response.create","stream_id":"main","model":"provider-a","input":"First",
                "instructions":"Old instructions","tools":[{"type":"function","name":"old"}],"temperature":0.8}
                """#.utf8))
        let first = try webSocketStateTurn(&state)
        #expect(first.streamID == "main")
        #expect(first.generate)
        #expect(first.previousResponseID == nil)
        try state.finish(
            first,
            completion: .init(
                responseID: "resp_first",
                output: Data(
                    #"[{"type":"function_call","id":"fc_1","call_id":"call_1","name":"old","arguments":"{}","foreign":{"exact":9007199254740993}}]"#
                        .utf8)))
        try state.enqueue(
            Data(
                #"""
                {"type":"response.create","stream_id":"main","model":"provider-b","previous_response_id":"resp_first",
                "input":[{"type":"function_call_output","call_id":"call_1","output":"done"}],"reasoning":{"effort":"low"}}
                """#.utf8))
        let second = try webSocketStateTurn(&state)
        #expect(second.previousResponseID == "resp_first")
        #expect(
            try JSONValue.parse(second.body)
                == JSONValue.parse(
                    Data(
                        #"""
                        {"model":"provider-b","stream":true,"input":[
                        {"type":"message","role":"user","content":[{"type":"input_text","text":"First"}]},
                        {"type":"function_call","id":"fc_1","call_id":"call_1","name":"old","arguments":"{}",
                        "foreign":{"exact":9007199254740993}},
                        {"type":"function_call_output","call_id":"call_1","output":"done"}],"reasoning":{"effort":"low"}}
                        """#.utf8)))
    }

    @Test("An active lane holds its FIFO while another lane can run")
    func laneFIFO() throws {
        var limits = ResponsesWebSocketLimits()
        limits.maxActiveResponses = 2
        var state = ResponsesWebSocketState(limits: limits)
        try state.enqueue(frame(stream: "same", input: "one"))
        try state.enqueue(frame(stream: "same", input: "two"))
        try state.enqueue(frame(stream: "other", input: "three"))
        let first = try webSocketStateTurn(&state)
        let other = try webSocketStateTurn(&state)
        #expect(first.streamID == "same")
        #expect(other.streamID == "other")
        #expect(state.next() == nil)
        try state.finish(first, completion: .init(responseID: "first", output: Data("[]".utf8)))
        let second = try webSocketStateTurn(&state)
        #expect(second.streamID == "same")
        #expect(try JSONValue.parse(webSocketStateInputData(second)) == input("two"))
    }

    @Test("A fork freezes the parent context and a failed fork preserves the source lane")
    func forkFailure() throws {
        var state = ResponsesWebSocketState()
        try state.enqueue(frame(stream: "source", input: "parent"))
        let parent = try webSocketStateTurn(&state)
        try state.finish(parent, completion: .init(responseID: "parent", output: Data("[]".utf8)))
        try state.enqueue(frame(stream: "fork", input: "fork", previous: "parent"))
        let fork = try webSocketStateTurn(&state)
        try state.finish(fork, completion: nil)
        try state.enqueue(frame(stream: "source", input: "source", previous: "parent"))
        let source = try webSocketStateTurn(&state)
        #expect(
            try JSONValue.parse(webSocketStateInputData(source))
                == .array(try #require(input("parent").array) + #require(input("source").array)))
        try state.finish(source, completion: nil)
        try state.enqueue(frame(stream: "source", input: "retry", previous: "parent"))
        let failure = try requestFailure(state.next())
        #expect(failure.code == "previous_response_not_found")
        #expect(failure.streamID == "source")
    }

    @Test("Warmup is chainable without inherited options or generated output")
    func warmup() throws {
        var state = ResponsesWebSocketState()
        try state.enqueue(
            Data(#"{"type":"response.create","model":"route","generate":false,"input":"prepared","tools":[]}"#.utf8))
        let warmup = try webSocketStateTurn(&state)
        #expect(!warmup.generate)
        #expect(try JSONValue.parse(warmup.body).object?["generate"] == nil)
        try state.finish(warmup, completion: .init(responseID: "warmup", output: Data("[]".utf8)))
        try state.enqueue(frame(input: "next", previous: "warmup"))
        let next = try webSocketStateTurn(&state)
        #expect(next.generate)
        #expect(try JSONValue.parse(next.body).object?["tools"] == nil)
        #expect(try #require(JSONValue.parse(webSocketStateInputData(next)).array).count == 2)
    }

    @Test("The WebSocket error envelope nests details and keeps lane correlation")
    func errorEnvelope() throws {
        let error = ResponsesWebSocketFailure(
            status: 400,
            code: "previous_response_not_found",
            message: "Previous response was not found",
            streamID: "agent_1",
            parameter: "previous_response_id")
        #expect(
            try JSONValue.parse(error.encoded())
                == JSONValue.parse(
                    Data(
                        #"""
                        {"type":"error","status":400,"stream_id":"agent_1","error":{"type":"invalid_request_error",
                        "code":"previous_response_not_found","message":"Previous response was not found","param":"previous_response_id"}}
                        """#.utf8)))
    }

    private func frame(stream: String? = nil, input: String, previous: String? = nil) throws -> Data {
        var fields: JSONObject = ["type": "response.create", "model": "route", "input": .string(input)]
        fields["stream_id"] = stream.map(JSONValue.string)
        fields["previous_response_id"] = previous.map(JSONValue.string)
        return try JSONValue.object(fields).serializedData()
    }

    private func input(_ text: String) -> JSONValue {
        [["type": "message", "role": "user", "content": [["type": "input_text", "text": .string(text)]]]]
    }

    private func requestFailure(
        _ result: Result<ResponsesWebSocketTurn, ResponsesWebSocketFailure>?
    ) throws -> ResponsesWebSocketFailure {
        let result = try #require(result)
        guard case .failure(let error) = result else {
            Issue.record("Expected a rejected WebSocket request")
            throw TestFailure.unexpectedSuccess
        }
        return error
    }

    private enum TestFailure: Error { case unexpectedSuccess }
}
