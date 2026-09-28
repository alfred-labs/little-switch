import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

func webSocketStateRequest(
    stream: String? = nil, input: JSONValue = [], previous: String? = nil
) throws -> Data {
    var fields: JSONObject = ["type": "response.create", "model": "route", "input": input]
    fields["stream_id"] = stream.map(JSONValue.string)
    fields["previous_response_id"] = previous.map(JSONValue.string)
    return try JSONValue.object(fields).serializedData()
}

func webSocketStateTurn(_ state: inout ResponsesWebSocketState) throws -> ResponsesWebSocketTurn {
    let next = state.next()
    return try #require(next).get()
}

func webSocketStateInputData(_ turn: ResponsesWebSocketTurn) throws -> Data {
    let body = try JSONValue.parse(turn.body)
    let input = try #require(body.object?["input"]?.array)
    return try JSONValue.array(input).serializedData()
}

func webSocketStateRejection(
    _ result: Result<ResponsesWebSocketTurn, ResponsesWebSocketFailure>?
) throws -> ResponsesWebSocketFailure {
    guard case .failure(let failure) = try #require(result) else {
        Issue.record("Expected a rejected WebSocket request")
        throw WebSocketStateTestError.unexpectedSuccess
    }
    return failure
}

func webSocketStateEnqueueFailure(
    _ frame: Data, state: inout ResponsesWebSocketState
) throws -> ResponsesWebSocketFailure {
    do {
        try state.enqueue(frame)
    } catch let failure as ResponsesWebSocketFailure {
        return failure
    }
    Issue.record("Expected WebSocket validation to reject the frame")
    throw WebSocketStateTestError.unexpectedSuccess
}

func webSocketStateSeed(
    _ state: inout ResponsesWebSocketState, stream: String, responseID: String, input: JSONValue = []
) throws {
    try state.enqueue(webSocketStateRequest(stream: stream, input: input))
    let turn = try webSocketStateTurn(&state)
    try state.finish(turn, completion: .init(responseID: responseID, output: Data("[]".utf8)))
}

private enum WebSocketStateTestError: Error { case unexpectedSuccess }
