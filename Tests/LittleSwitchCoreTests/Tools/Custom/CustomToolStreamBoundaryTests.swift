import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Custom streaming state rejection boundaries")
struct CustomToolStreamBoundaryTests {
    @Test(
        "Provider terminal failures discard an unfinished envelope",
        arguments: ["error", "response.failed", "response.incomplete"])
    func terminalFailure(type: String) throws {
        var state = try state()
        _ = try send(Self.added, into: &state)
        let failure = #"{"type":""# + type + #"","error":{"message":"fixture"}}"#
        let edit = try send(failure, into: &state)
        guard case .keep = edit else {
            Issue.record("Provider failure bytes must remain unchanged")
            return
        }
        #expect(state.responses.calls.isEmpty)
        #expect(throws: Never.self) { try state.finish() }
        _ = try state.consume(ServerSentEventFrame(event: nil, data: Data(), terminal: true))
        #expect(throws: CustomToolProjection.Error.invalidResponse) { try send("{}", into: &state) }
    }

    @Test("Scalar JSON is not a stream event", arguments: ["[]", "null", "42"])
    func invalidEventContainer(source: String) throws {
        var state = try state()
        #expect(throws: CustomToolProjection.Error.invalidResponse) { try send(source, into: &state) }
    }

    @Test("A completed custom item still requires a stream terminal")
    func missingGlobalTerminal() throws {
        var state = try state()
        _ = try send(Self.added, into: &state)
        _ = try send(Self.argumentsDone, into: &state)
        _ = try send(Self.itemDone, into: &state)
        #expect(throws: CustomToolProjection.Error.invalidResponse) { try state.finish() }
    }

    @Test("A second DONE marker is not accepted")
    func duplicateDoneMarker() throws {
        var state = try state()
        let terminal = ServerSentEventFrame(event: nil, data: Data(), terminal: true)
        _ = try state.consume(terminal)
        #expect(throws: CustomToolProjection.Error.invalidResponse) { try state.consume(terminal) }
    }

    @Test(
        "Tracked argument events cannot omit identities or move output slots",
        arguments: [
            #"{"type":"response.function_call_arguments.delta","output_index":0,"delta":"x"}"#,
            #"{"type":"response.function_call_arguments.delta","item_id":"fc","output_index":1,"delta":"x"}"#,
            #"{"type":"response.function_call_arguments.delta","item_id":"fc","output_index":0,"delta":7}"#,
            #"{"type":"response.function_call_arguments.done","item_id":"fc","output_index":0,"arguments":null}"#,
            #"{"type":"response.function_call_arguments.done","item_id":"fc","output_index":0,"arguments":"{}","name":"other"}"#,
        ])
    func malformedArgumentEvent(source: String) throws {
        var state = try state()
        _ = try send(Self.added, into: &state)
        #expect(throws: CustomToolProjection.Error.invalidResponse) { try send(source, into: &state) }
    }

    @Test("Argument completion cannot be repeated or followed by a delta", arguments: [true, false])
    func argumentAfterCompletion(repeatDone: Bool) throws {
        var state = try state()
        _ = try send(Self.added, into: &state)
        _ = try send(Self.argumentsDone, into: &state)
        let next =
            repeatDone
            ? Self.argumentsDone
            : #"{"type":"response.function_call_arguments.delta","item_id":"fc","output_index":0,"delta":"x"}"#
        #expect(throws: CustomToolProjection.Error.invalidResponse) { try send(next, into: &state) }
    }

    @Test("Item completion must agree with the validated envelope")
    func changedCompletedInput() throws {
        var state = try state()
        _ = try send(Self.added, into: &state)
        _ = try send(Self.argumentsDone, into: &state)
        let changed = Self.itemDone.replacingOccurrences(of: #"\"x\""#, with: #"\"changed\""#)
        #expect(throws: CustomToolProjection.Error.invalidResponse) { try send(changed, into: &state) }
    }

    @Test(
        "Chat choice and tool indices are required",
        arguments: [
            #"{"choices":[{"delta":{}}]}"#,
            #"{"choices":[{"index":-1,"delta":{}}]}"#,
            #"{"choices":[{"index":0,"delta":{"tool_calls":[{"type":"function","function":{"name":"exec"}}]}}]}"#,
        ])
    func missingChatIndices(source: String) throws {
        var state = try state(wire: .chatCompletions)
        #expect(throws: CustomToolProjection.Error.invalidResponse) { try send(source, into: &state) }
    }

    @Test(
        "Retained Chat identities cannot change shape or terminate with truncation",
        arguments: [
            #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"type":"custom"}]}}]}"#,
            #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":7}}]}}]}"#,
            #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":7}}]}}]}"#,
            #"{"choices":[{"index":0,"delta":{},"finish_reason":"length"}]}"#,
        ])
    func changedChatShape(source: String) throws {
        var state = try state(wire: .chatCompletions)
        _ = try send(
            #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call","function":{"name":"ex"}}]}}]}"#,
            into: &state)
        #expect(throws: CustomToolProjection.Error.invalidResponse) { try send(source, into: &state) }
    }

    @Test("Unterminated SSE data fails once and releases the iterator")
    func incompleteFrame() async throws {
        let response = HTTPClientResponse(
            status: .ok,
            headers: ["content-type": "text/event-stream"],
            body: .bytes(ByteBuffer(string: "data: {}")))
        let restored = try await CustomToolResponse.restored(
            response, projection: state().projection, maximumBytes: 4_096)
        var iterator = restored.body.makeAsyncIterator()
        await #expect(throws: ServerSentEventDecoder.Error.incompleteFrame) { try await iterator.next() }
        #expect(try await iterator.next() == nil)
    }

    @Test("Comment records and trailing whitespace remain byte-identical with adaptation enabled")
    func commentOnlyStream() async throws {
        let bytes = Data(": keep\r\nid: 17\r\n\r\n \t".utf8)
        let response = HTTPClientResponse(
            status: .ok, headers: ["content-type": "text/event-stream"], body: .bytes(ByteBuffer(bytes: bytes)))
        let restored = try await CustomToolResponse.restored(
            response, projection: state().projection, maximumBytes: 4_096)
        #expect(Data(try await restored.body.collect(upTo: 4_096).readableBytesView) == bytes)
    }

    private static let added =
        #"{"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc","call_id":"call","name":"exec","arguments":""}}"#
    private static let argumentsDone =
        #"{"type":"response.function_call_arguments.done","output_index":0,"item_id":"fc","arguments":"{\"input\":\"x\"}"}"#
    private static let itemDone =
        #"{"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc","call_id":"call","name":"exec","arguments":"{\"input\":\"x\"}"}}"#

    private func state(wire: ProviderToolContract.Wire = .responses) throws -> CustomToolStreamProjection {
        let request =
            wire == .responses
            ? #"{"tools":[{"type":"custom","name":"exec"}]}"#
            : #"{"tools":[{"type":"custom","custom":{"name":"exec"}}]}"#
        let projection = try CustomToolProjection.prepare(body: Data(request.utf8), wire: wire, adapt: true)
        return CustomToolStreamProjection(projection: projection, maximumBytes: 4_096)
    }

    private func send(
        _ source: String,
        into state: inout CustomToolStreamProjection
    ) throws -> CustomToolFrameRewrite.Edit {
        try state.consume(ServerSentEventFrame(event: nil, data: Data(source.utf8), terminal: false))
    }
}
