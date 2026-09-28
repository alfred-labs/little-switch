import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Responses WebSocket request validation")
struct ResponsesWebSocketRequestTests {
    @Test(
        "Malformed envelopes are rejected before scheduling",
        arguments: [
            #"[]"#, #"{"type":"response.create","model":"route","input":null}"#,
            #"{"type":"response.create","model":"route","input":[1]}"#,
            #"{"type":"response.create","model":""}"#,
            #"{"type":"response.create","model":"  "}"#,
            #"{"type":"response.create","model":4}"#,
            #"{"type":"response.create"}"#,
            #"{"type":"response.create","model":"route","generate":0}"#,
            #"{"type":"response.create","model":"route","generate":null}"#,
            #"{"type":"response.create","model":"route","background":"false"}"#,
            #"{"type":"response.create","model":"route","previous_response_id":0}"#,
            #"{"type":"response.create","model":"route","previous_response_id":""}"#,
            #"{"type":"response.create","model":"route","prompt_cache_options":null}"#,
            #"{"type":"response.create","model":"route","prompt_cache_options":[]}"#,
            #"{"type":"response.create","model":"route","prompt_cache_options":{"prewarm":1}}"#,
            #"{"type":"response.create","model":"route","stream":1}"#,
            #"{"model":"route"}"#,
            #"{"type":"unknown","model":"route"}"#,
            #"{"type":"response.create""#,
        ])
    func invalidEnvelope(text: String) throws {
        var state = ResponsesWebSocketState()
        let failure = try webSocketStateEnqueueFailure(Data(text.utf8), state: &state)
        #expect(failure.status == 400)
        #expect(state.next() == nil)
    }

    @Test("Invalid UTF-8 is rejected without replacement characters")
    func invalidUTF8() throws {
        var state = ResponsesWebSocketState()
        let failure = try webSocketStateEnqueueFailure(Data([0xFF]), state: &state)
        #expect(failure.status == 400)
        #expect(state.next() == nil)
    }

    @Test(
        "Lane names use only the documented ASCII alphabet",
        arguments: ["", "has space", "é", "x/y", String(repeating: "a", count: 257)])
    func invalidStream(stream: String) throws {
        var state = ResponsesWebSocketState()
        let failure = try webSocketStateEnqueueFailure(webSocketStateRequest(stream: stream), state: &state)
        #expect(failure.code == "invalid_stream_id")
        #expect(failure.parameter == "stream_id")
    }

    @Test("A maximum-length lane and the implicit lane remain distinct")
    func namedAndImplicitLanes() throws {
        var state = ResponsesWebSocketState()
        let name = "A_z-9." + String(repeating: "a", count: 250)
        try state.enqueue(webSocketStateRequest(stream: name))
        try state.enqueue(webSocketStateRequest())
        #expect(try webSocketStateTurn(&state).streamID == name)
        #expect(try webSocketStateTurn(&state).streamID == nil)
        let invalid = Data(#"{"type":"response.create","model":"route","stream_id":null}"#.utf8)
        #expect(try webSocketStateEnqueueFailure(invalid, state: &state).code == "invalid_stream_id")
    }

    @Test("Background and server conversation state are explicitly unsupported")
    func unsupportedState() throws {
        for extra in [#""background":true"#, #""conversation":"conv_1""#, #""conversation":{"id":"conv_1"}"#] {
            var state = ResponsesWebSocketState()
            let data = Data("{\"type\":\"response.create\",\"model\":\"route\",\(extra)}".utf8)
            #expect(try webSocketStateEnqueueFailure(data, state: &state).status == 400)
        }
        var state = ResponsesWebSocketState()
        try state.enqueue(
            Data(
                #"{"type":"response.create","model":"route","background":false,"conversation":null,"previous_response_id":null,"stream":false}"#
                    .utf8))
        let body = try #require(JSONValue.parse(webSocketStateTurn(&state).body).object)
        #expect(body["background"] == nil)
        #expect(body["previous_response_id"] == nil)
        #expect(body["stream"] == true)
        #expect(body["input"]?.array?.isEmpty == true)
    }

    @Test("Steering rejects without consuming its parent or admitting work")
    func steeringRejected() throws {
        var state = ResponsesWebSocketState()
        try webSocketStateSeed(&state, stream: "main", responseID: "parent")
        let failure = try webSocketStateEnqueueFailure(
            Data(#"{"type":"response.steer","previous_response_id":"parent","input":"Change"}"#.utf8),
            state: &state)
        #expect(failure.code == "steering_not_supported")
        #expect(state.next() == nil)
        try state.enqueue(webSocketStateRequest(stream: "main", previous: "parent"))
        #expect(try webSocketStateTurn(&state).previousResponseID == "parent")
    }

    @Test("Unsupported steering preserves the valid lane in its error envelope")
    func namedSteeringRejected() throws {
        var state = ResponsesWebSocketState()
        try webSocketStateSeed(&state, stream: "main", responseID: "parent")
        let failure = try webSocketStateEnqueueFailure(
            Data(
                #"{"type":"response.steer","stream_id":"main","previous_response_id":"parent","input":"Change"}"#
                    .utf8),
            state: &state)
        #expect(failure.code == "steering_not_supported")
        #expect(failure.streamID == "main")
        #expect(try JSONValue.parse(failure.encoded()).object?["stream_id"] == "main")
        try state.enqueue(webSocketStateRequest(stream: "main", previous: "parent"))
        #expect(try webSocketStateTurn(&state).previousResponseID == "parent")
    }

    @Test("Prewarm overrides generation but cannot consume a compaction trigger")
    func prewarm() throws {
        var state = ResponsesWebSocketState()
        try state.enqueue(
            Data(
                #"{"type":"response.create","model":"route","generate":true,"prompt_cache_options":{"prewarm":true,"ttl":"30m"}}"#
                    .utf8))
        #expect(try !webSocketStateTurn(&state).generate)
        for option in [#""generate":false"#, #""prompt_cache_options":{"prewarm":true}"#] {
            let body = Data(
                "{\"type\":\"response.create\",\"model\":\"route\",\(option),\"input\":[{\"type\":\"compaction_trigger\"}]}"
                    .utf8)
            #expect(try webSocketStateEnqueueFailure(body, state: &state).status == 400)
        }
    }

    @Test(
        "Prompt cache options without prewarm preserve generation and request settings",
        arguments: [JSONObject(), ["ttl": "30m"]])
    func promptCacheOptionsWithoutPrewarm(options: JSONObject) throws {
        var state = ResponsesWebSocketState()
        let fields: JSONObject = [
            "type": "response.create", "model": "route", "prompt_cache_options": .object(options),
        ]
        try state.enqueue(JSONValue.object(fields).serializedData())
        let turn = try webSocketStateTurn(&state)
        #expect(turn.generate)
        #expect(try JSONValue.parse(turn.body).object?["prompt_cache_options"] == .object(options))
    }

    @Test("Compaction triggers must be unique and last")
    func invalidCompactionOrder() throws {
        var state = ResponsesWebSocketState()
        let trigger: JSONValue = ["type": "compaction_trigger"]
        let message: JSONValue = ["role": "user", "content": "Later"]
        for input: JSONValue in [[trigger, message], [trigger, trigger]] {
            #expect(try webSocketStateEnqueueFailure(webSocketStateRequest(input: input), state: &state).status == 400)
        }
    }

    @Test("Validation failure evicts a same-lane parent but preserves a cross-lane parent")
    func validationEviction() throws {
        var state = ResponsesWebSocketState()
        try webSocketStateSeed(&state, stream: "main", responseID: "parent")
        for stream in ["fork", "main"] {
            let body = Data(
                "{\"type\":\"response.create\",\"stream_id\":\"\(stream)\",\"model\":\"\",\"previous_response_id\":\"parent\"}"
                    .utf8)
            #expect(try webSocketStateEnqueueFailure(body, state: &state).status == 400)
            try state.enqueue(webSocketStateRequest(stream: "check", previous: "parent"))
            if stream == "fork" {
                let turn = try webSocketStateTurn(&state)
                try state.finish(turn, completion: nil)
            } else {
                #expect(try webSocketStateRejection(state.next()).code == "previous_response_not_found")
            }
        }
    }
}
