import Foundation
import LittleSwitchWire
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Responses WebSocket HTTP projection")
struct ResponsesWebSocketProjectionTests {
    @Test("Fragmented SSE preserves public events and holds the terminal")
    func fragmentedStream() async throws {
        let recorder = WebSocketEventRecorder()
        let projection = ResponsesWebSocketResponseProjection(
            status: 200, streaming: true, streamID: "A", maximumBytes: 4_096
        ) { await recorder.append($0) }
        let stream =
            ": heartbeat\n\nevent: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r\"}}\n\n"
            + "data: {\"type\":\"response.output_text.delta\",\"delta\":\"été\"}\n\n"
            + "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"r\",\"output\":[]}}\n\n"
            + "data: [DONE]\n\n"
        for byte in stream.utf8 { try await projection.append(ByteBuffer(bytes: [byte])) }
        await #expect(throws: ResponsesWebSocketEvents.Error.missingTerminal) { try await projection.result() }
        try await projection.finish()
        let result = try await projection.result()
        #expect(result.responseID == "r")
        let events = try await recorder.values()
        #expect(events.map { $0["type"] } == [.string("response.created"), .string("response.output_text.delta")])
        #expect(events.allSatisfy { $0["stream_id"] == .string("A") })
        #expect(events.last?["delta"] == .string("été"))
        await #expect(throws: ResponsesWebSocketEvents.Error.eventAfterTerminal) { try await projection.finish() }
        await #expect(throws: ResponsesWebSocketEvents.Error.eventAfterTerminal) {
            try await projection.append(ByteBuffer(string: "later"))
        }
    }

    @Test(
        "HTTP errors retain their status and never become reusable responses",
        arguments: [
            #"{"error":{"type":"invalid_request_error","code":"invalid_model","message":"Unknown model"}}"#,
            "unparseable error",
        ])
    func httpFailure(body: String) async throws {
        let recorder = WebSocketEventRecorder()
        let projection = ResponsesWebSocketResponseProjection(
            status: 400, streaming: true, streamID: "B", maximumBytes: 4_096
        ) { await recorder.append($0) }
        try await projection.append(ByteBuffer(string: body))
        try await projection.finish()
        let result = try await projection.result()
        let terminal = try #require(JSONValue.parse(result.terminal).object)
        #expect(terminal["type"] == .string("error"))
        #expect(terminal["status"] == .integer(400))
        #expect(terminal["stream_id"] == .string("B"))
        #expect(result.output == nil)
        #expect(await recorder.isEmpty)
    }

    @Test("Buffered provider replies deliver complete tool items before their terminal", arguments: [false, true])
    func bufferedResponse(omitsStatus: Bool) async throws {
        let recorder = WebSocketEventRecorder()
        let projection = ResponsesWebSocketResponseProjection(
            status: 200, streaming: false, streamID: nil, maximumBytes: 4_096
        ) { await recorder.append($0) }
        let status = omitsStatus ? "" : #""status":"completed","#
        try await projection.append(
            ByteBuffer(
                string:
                    #"{"id":"tool",\#(status)"output":[{"type":"function_call","id":"fc","call_id":"call","name":"lookup","arguments":"{}","future":9007199254740993}]}"#
            ))
        try await projection.finish()
        let result = try await projection.result()
        #expect(result.responseID == "tool")
        let events = try await recorder.values()
        #expect(
            events.map { $0["type"] } == [
                .string("response.created"), .string("response.output_item.added"),
                .string("response.output_item.done"),
            ])
        #expect(events.map { $0["sequence_number"] } == [.integer(0), .integer(1), .integer(2)])
        #expect(events.last?["item"]?.object?["arguments"] == .string("{}"))
        let terminal = try #require(JSONValue.parse(result.terminal).object)
        #expect(terminal["sequence_number"] == .integer(3))
        #expect(terminal["type"] == .string("response.completed"))
    }

    @Test("Incomplete buffered responses are resumable and failed ones are not", arguments: ["incomplete", "failed"])
    func bufferedTerminal(status: String) async throws {
        let projection = ResponsesWebSocketResponseProjection(
            status: 200, streaming: false, streamID: nil, maximumBytes: 4_096
        ) { _ in }
        try await projection.append(ByteBuffer(string: #"{"id":"r","status":"\#(status)","output":[]}"#))
        try await projection.finish()
        let result = try await projection.result()
        #expect(result.responseID == (status == "incomplete" ? "r" : nil))
    }

    @Test(
        "Invalid buffered replies cannot announce success",
        arguments: ["{}", #"{"id":"r","output":[],"status":"queued"}"#])
    func invalidBufferedResponse(body: String) async throws {
        let projection = ResponsesWebSocketResponseProjection(
            status: 200, streaming: false, streamID: nil, maximumBytes: 4_096
        ) { _ in }
        try await projection.append(ByteBuffer(string: body))
        await #expect(throws: ResponsesWebSocketEvents.Error.invalidEvent) { try await projection.finish() }
        await #expect(throws: ResponsesWebSocketEvents.Error.missingTerminal) { try await projection.result() }
    }

    @Test("Error bodies and unclosed event streams are bounded")
    func boundedBodies() async throws {
        let error = ResponsesWebSocketResponseProjection(
            status: 503, streaming: false, streamID: nil, maximumBytes: 8
        ) { _ in }
        try await error.append(ByteBuffer(string: "1234"))
        await #expect(throws: ResponsesWebSocketEvents.Error.tooLarge) {
            try await error.append(ByteBuffer(string: "56789"))
        }
        let stream = ResponsesWebSocketResponseProjection(
            status: 200, streaming: true, streamID: nil, maximumBytes: 64
        ) { _ in }
        await #expect(throws: (any Error).self) {
            try await stream.append(ByteBuffer(string: "data: " + String(repeating: "x", count: 128)))
        }
    }

    @Test("A socket write failure stops reading the HTTP body")
    func failedWrite() async throws {
        let projection = ResponsesWebSocketResponseProjection(
            status: 200, streaming: true, streamID: nil, maximumBytes: 4_096
        ) { _ in throw GatewayTestError.failure }
        await #expect(throws: GatewayTestError.failure) {
            try await projection.append(ByteBuffer(string: "data: {\"type\":\"response.created\"}\n\n"))
        }
    }
}

actor WebSocketEventRecorder {
    private var data: [Data] = []
    var isEmpty: Bool { data.isEmpty }

    func append(_ event: Data) { data.append(event) }

    func values() throws -> [JSONObject] {
        try data.map { try #require(JSONValue.parse($0).object) }
    }

    func wait(type: String, streamID: String? = nil) async throws -> JSONObject {
        try await eventually(description: "WebSocket \(type) on \(streamID ?? "default")") {
            try await self.values().first { $0["type"]?.string == type && $0["stream_id"]?.string == streamID }
        }
    }
}
