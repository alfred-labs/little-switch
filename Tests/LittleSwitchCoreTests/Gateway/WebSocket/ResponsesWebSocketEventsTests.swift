import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Responses WebSocket public events")
struct ResponsesWebSocketEventsTests {
    @Test("Lane envelopes preserve unknown fields and exact numbers")
    func preservesEvents() throws {
        var events = ResponsesWebSocketEvents(streamID: "agent-A", maximumBytes: 4_096)
        let accepted = try events.accept(
            Data(
                #"{"type":"response.future.delta","stream_id":"upstream","sequence_number":9007199254740993,"future":{"mail":"hello"}}"#
                    .utf8))
        let bytes = try #require(accepted)
        #expect(
            try JSONValue.parse(bytes)
                == JSONValue.parse(
                    Data(
                        #"{"type":"response.future.delta","stream_id":"agent-A","sequence_number":9007199254740993,"future":{"mail":"hello"}}"#
                            .utf8)))
        var defaultLane = ResponsesWebSocketEvents(streamID: nil, maximumBytes: 4_096)
        let acceptedDefault = try defaultLane.accept(bytes)
        let defaultBytes = try #require(acceptedDefault)
        #expect(try JSONValue.parse(defaultBytes).object?["stream_id"] == nil)
    }

    @Test("A terminal is held until the session has installed its history")
    func holdsTerminal() throws {
        var events = ResponsesWebSocketEvents(streamID: "A", maximumBytes: 4_096)
        _ = try events.accept(Data(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#.utf8))
        let event = Data(
            #"""
            {"type":"response.completed","response":{"id":"r1","status":"completed",
            "output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"answer"}]}],
            "usage":{"total_tokens":3}}}
            """#
            .utf8)
        #expect(try events.accept(event) == nil)
        let result = try events.finish()
        #expect(result.responseID == "r1")
        #expect(
            try JSONValue.parse(try #require(result.output))
                == JSONValue.parse(
                    Data(
                        #"[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"answer"}]}]"#
                            .utf8)))
        let terminal = try #require(JSONValue.parse(result.terminal).object)
        #expect(terminal["stream_id"] == .string("A"))
        #expect(terminal["response"]?.object?["usage"]?.object?["total_tokens"] == .integer(3))
    }

    @Test("Lite output is restored independently and sorted by output index")
    func liteOutput() throws {
        var events = ResponsesWebSocketEvents(streamID: nil, maximumBytes: 4_096)
        _ = try events.accept(
            Data(
                #"{"type":"response.output_item.done","output_index":1,"item":{"type":"future_item","id":"b","payload":"beta"}}"#
                    .utf8))
        _ = try events.accept(
            Data(
                #"{"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"a","call_id":"c","name":"lookup","arguments":"{}"}}"#
                    .utf8))
        #expect(
            try events.accept(Data(#"{"type":"response.completed","response":{"id":"lite","output":[]}}"#.utf8)) == nil)
        let result = try events.finish()
        let expected = try JSONValue.parse(
            Data(
                #"[{"type":"function_call","id":"a","call_id":"c","name":"lookup","arguments":"{}"},{"type":"future_item","id":"b","payload":"beta"}]"#
                    .utf8))
        #expect(try JSONValue.parse(try #require(result.output)) == expected)
        #expect(try JSONValue.parse(result.terminal).object?["response"]?.object?["output"] == expected)
    }

    @Test("A nonempty terminal snapshot remains authoritative")
    func authoritativeOutput() throws {
        var events = ResponsesWebSocketEvents(streamID: nil, maximumBytes: 4_096)
        _ = try events.accept(
            Data(#"{"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"old"}}"#.utf8))
        _ = try events.accept(
            Data(
                #"{"type":"response.incomplete","response":{"id":"r2","output":[{"type":"message","id":"new"}]}}"#.utf8)
        )
        let result = try events.finish()
        #expect(result.responseID == "r2")
        #expect(
            try JSONValue.parse(try #require(result.output))
                == JSONValue.parse(Data(#"[{"type":"message","id":"new"}]"#.utf8)))
    }

    @Test("HTTP streaming errors become request-scoped WebSocket errors")
    func errorEnvelope() throws {
        var events = ResponsesWebSocketEvents(streamID: "B", maximumBytes: 4_096)
        #expect(
            try events.accept(
                Data(#"{"type":"error","code":"tool_not_allowed","message":"Rejected tool","param":"tools"}"#.utf8))
                == nil)
        let result = try events.finish()
        #expect(result.responseID == nil)
        #expect(result.output == nil)
        #expect(
            try JSONValue.parse(result.terminal)
                == JSONValue.parse(
                    Data(
                        #"{"type":"error","status":502,"stream_id":"B","error":{"type":"server_error","code":"tool_not_allowed","message":"Rejected tool","param":"tools"}}"#
                            .utf8)))
    }

    @Test("Failed responses never produce reusable context")
    func failedResponse() throws {
        var events = ResponsesWebSocketEvents(streamID: nil, maximumBytes: 4_096)
        _ = try events.accept(
            Data(#"{"type":"response.failed","response":{"id":"failed","output":[],"error":{"code":"upstream"}}}"#.utf8)
        )
        let result = try events.finish()
        #expect(result.responseID == nil)
        #expect(result.output == nil)
    }

    @Test("Missing terminals and conflicting response identities are rejected")
    func truncatedOrMixed() throws {
        var events = ResponsesWebSocketEvents(streamID: nil, maximumBytes: 4_096)
        _ = try events.accept(Data(#"{"type":"response.created","response":{"id":"first"}}"#.utf8))
        #expect(throws: ResponsesWebSocketEvents.Error.missingTerminal) { try events.finish() }
        #expect(throws: ResponsesWebSocketEvents.Error.mismatchedResponse) {
            try events.accept(Data(#"{"type":"response.completed","response":{"id":"other","output":[]}}"#.utf8))
        }
        #expect(throws: ResponsesWebSocketEvents.Error.mismatchedResponse) {
            try events.accept(Data(#"{"type":"response.future.delta","response_id":"other"}"#.utf8))
        }
    }

    @Test("Lane metadata and Lite restoration cannot exceed the public event limit")
    func expansionBounds() throws {
        var lane = ResponsesWebSocketEvents(streamID: String(repeating: "x", count: 256), maximumBytes: 64)
        #expect(throws: ResponsesWebSocketEvents.Error.tooLarge) {
            try lane.accept(Data(#"{"type":"future"}"#.utf8))
        }
        var items = ResponsesWebSocketEvents(streamID: nil, maximumBytes: 1_024, maximumOutputItems: 1)
        _ = try items.accept(Data(#"{"type":"response.output_item.done","output_index":0,"item":{"id":"old"}}"#.utf8))
        _ = try items.accept(Data(#"{"type":"response.output_item.done","output_index":0,"item":{"id":"new"}}"#.utf8))
        #expect(throws: ResponsesWebSocketEvents.Error.tooLarge) {
            try items.accept(Data(#"{"type":"response.output_item.done","output_index":1,"item":{"id":"other"}}"#.utf8))
        }
        _ = try items.accept(Data(#"{"type":"response.completed","response":{"id":"r","output":[]}}"#.utf8))
        let result = try items.finish()
        #expect(try JSONValue.parse(try #require(result.output)) == [["id": "new"]])
    }

    @Test(
        "Malformed events cannot enter a reusable history",
        arguments: [
            "not json", "[]", "{}", #"{"type":3}"#,
            #"{"type":"response.output_item.done","output_index":true,"item":{}}"#,
            #"{"type":"response.output_item.done","output_index":-1,"item":{}}"#,
            #"{"type":"response.completed","response":{"id":"r","output":"bad"}}"#,
            #"{"type":"response.completed","response":{"output":[]}}"#,
            #"{"type":"response.completed","response":{"id":"   ","output":[]}}"#,
        ])
    func invalidEvents(value: String) {
        var events = ResponsesWebSocketEvents(streamID: nil, maximumBytes: 4_096)
        #expect(throws: ResponsesWebSocketEvents.Error.invalidEvent) {
            try events.accept(Data(value.utf8))
        }
    }

    @Test("Event and aggregate completed-output bounds stop oversized responses")
    func sizeBounds() throws {
        var events = ResponsesWebSocketEvents(streamID: nil, maximumBytes: 32)
        #expect(throws: ResponsesWebSocketEvents.Error.tooLarge) {
            try events.accept(Data(#"{"type":"response.delta","delta":"too many bytes for this limit"}"#.utf8))
        }
        events = ResponsesWebSocketEvents(streamID: nil, maximumBytes: 320)
        let item = String(repeating: "x", count: 110)
        for index in 0..<2 {
            _ = try events.accept(
                Data(
                    #"{"type":"response.output_item.done","output_index":\#(index),"item":{"type":"future","payload":"\#(item)"}}"#
                        .utf8))
        }
        #expect(throws: ResponsesWebSocketEvents.Error.tooLarge) {
            try events.accept(
                Data(
                    #"{"type":"response.output_item.done","output_index":2,"item":{"type":"future","payload":"\#(item)"}}"#
                        .utf8))
        }
    }

    @Test("A second terminal or trailing semantic event invalidates the stream")
    func afterTerminal() throws {
        var events = ResponsesWebSocketEvents(streamID: nil, maximumBytes: 4_096)
        _ = try events.accept(Data(#"{"type":"response.completed","response":{"id":"r","output":[]}}"#.utf8))
        #expect(throws: ResponsesWebSocketEvents.Error.eventAfterTerminal) {
            try events.accept(Data(#"{"type":"response.output_text.delta","delta":"late"}"#.utf8))
        }
    }
}
