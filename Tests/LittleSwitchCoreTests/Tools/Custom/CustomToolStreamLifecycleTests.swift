import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Custom tool stream lifecycle")
struct CustomToolStreamLifecycleTests {
    @Test("No new JSON events follow a terminal")
    func afterTerminal() throws {
        var state = try makeState()
        _ = try send(#"{"type":"response.completed","response":{"output":[]}}"#, into: &state)
        #expect(throws: (any Swift.Error).self) {
            try send(#"{"type":"response.completed","response":{"output":[]}}"#, into: &state)
        }
    }

    @Test("The final snapshot cannot omit or duplicate the streamed custom call", arguments: ["[]", "duplicate"])
    func finalSetMismatch(output: String) throws {
        var state = try makeState()
        try call(into: &state)
        let array = output == "duplicate" ? "[\(Self.item),\(Self.item)]" : output
        #expect(throws: (any Swift.Error).self) {
            try send("{\"type\":\"response.completed\",\"response\":{\"output\":\(array)}}", into: &state)
        }
    }

    @Test("An output slot cannot change its item or call ID")
    func changedItemID() throws {
        var state = try makeState()
        _ = try send(Self.added, into: &state)
        _ = try send(Self.argumentsDone, into: &state)
        #expect(throws: (any Swift.Error).self) {
            try send(Self.done.replacingOccurrences(of: "\"fc\"", with: "\"other\""), into: &state)
        }
    }

    @Test("Canonically equivalent Unicode must not change a retained wire identity", arguments: ["item_id", "call_id"])
    func unicodeIdentity(field: String) throws {
        var state = try makeState()
        let original = field == "item_id" ? "fc" : "call"
        let added = Self.added.replacingOccurrences(of: "\"\(original)\"", with: "\"é\"")
        _ = try send(added, into: &state)
        let next = field == "item_id" ? Self.argumentsDone : Self.done
        let changed = next.replacingOccurrences(of: "\"\(original)\"", with: "\"e\\u0301\"")
        #expect(throws: CustomToolProjection.Error.invalidResponse) { try send(changed, into: &state) }
    }

    @Test("Aggregate retained tool arguments are bounded")
    func byteLimit() throws {
        var state = try makeState(maximumBytes: 256)
        _ = try send(Self.added, into: &state)
        let event: JSONValue = .object([
            "type": .string("response.function_call_arguments.delta"), "item_id": .string("fc"),
            "output_index": .integer(0), "delta": .string(String(repeating: "x", count: 256)),
        ])
        #expect(throws: CustomToolProjection.Error.limitExceeded) { try send(event.serialized(), into: &state) }
    }

    private static let item =
        #"{"type":"function_call","id":"fc","call_id":"call","name":"exec","arguments":"{\"input\":\"x\"}","status":"completed"}"#
    private static let added = #"""
        {
          "type": "response.output_item.added",
          "output_index": 0,
          "item": {
            "type": "function_call",
            "id": "fc",
            "call_id": "call",
            "name": "exec",
            "arguments": "",
            "status": "in_progress"
          }
        }
        """#
    private static let argumentsDone =
        #"{"type":"response.function_call_arguments.done","output_index":0,"item_id":"fc","arguments":"{\"input\":\"x\"}"}"#
    private static let done = "{\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":\(item)}"

    private func call(into state: inout CustomToolStreamProjection) throws {
        _ = try send(Self.added, into: &state)
        _ = try send(Self.argumentsDone, into: &state)
        _ = try send(Self.done, into: &state)
    }

    private func makeState(maximumBytes: Int = 4_096) throws -> CustomToolStreamProjection {
        let body = Data(#"{"tools":[{"type":"custom","name":"exec"}]}"#.utf8)
        return CustomToolStreamProjection(
            projection: try CustomToolProjection.prepare(body: body, wire: .responses, adapt: true),
            maximumBytes: maximumBytes)
    }

    private func send(
        _ json: String,
        into state: inout CustomToolStreamProjection
    ) throws -> CustomToolFrameRewrite.Edit {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 65_536)
        let source = "data: " + json.replacingOccurrences(of: "\n", with: "\ndata: ") + "\n\n"
        let frame = try #require(decoder.append(ByteBuffer(string: source)).first)
        return try state.consume(frame)
    }
}
