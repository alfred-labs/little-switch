import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Custom tool Responses Lite completion")
struct CustomToolResponsesLiteTests {
    @Test(
        "A Lite terminal preserves empty output once custom items are fully closed",
        arguments: [false, true], [0, 3])
    func fullyClosedLiteTerminal(argumentsDone: Bool, outputIndex: Int) throws {
        var state = try makeState()
        _ = try send(at(outputIndex, Self.added), into: &state)
        if argumentsDone { _ = try send(at(outputIndex, Self.argumentsDone), into: &state) }
        let done = try send(at(outputIndex, Self.itemDone), into: &state)
        guard case .replace(let value) = done else {
            Issue.record("The completed function item must restore its custom input")
            return
        }
        let expected = try JSONValue.parse(
            Data(
                at(
                    outputIndex,
                    #"""
                    {"type":"response.output_item.done","output_index":0,
                     "item":{"type":"custom_tool_call","id":"fc","call_id":"call","name":"exec","input":"x","status":"completed"}}
                    """#
                ).utf8))
        #expect(value == expected)
        let terminal = try send(Self.liteTerminal, into: &state)
        guard case .keep = terminal else {
            Issue.record("The provider's empty terminal must remain unchanged")
            return
        }
        #expect(throws: Never.self) { try state.finish() }
    }

    @Test("An empty terminal cannot close an unfinished custom item", arguments: [false, true])
    func incompleteLiteTerminal(argumentsDone: Bool) throws {
        var state = try makeState()
        _ = try send(Self.added, into: &state)
        if argumentsDone { _ = try send(Self.argumentsDone, into: &state) }
        #expect(throws: CustomToolProjection.Error.invalidResponse) { try send(Self.liteTerminal, into: &state) }
    }

    @Test("A completed sibling cannot hide a custom call whose item is still open")
    func partiallyCompletedParallelCalls() throws {
        var state = try makeState()
        _ = try send(Self.added, into: &state)
        _ = try send(Self.itemDone, into: &state)
        let second = at(1, Self.added)
            .replacingOccurrences(of: #""fc""#, with: #""second""#)
            .replacingOccurrences(of: #""call""#, with: #""second-call""#)
        _ = try send(second, into: &state)
        #expect(throws: CustomToolProjection.Error.invalidResponse) { try send(Self.liteTerminal, into: &state) }
    }

    @Test(
        "A nonempty terminal must still contain every unchanged custom call",
        arguments: [
            #"[{"type":"message","id":"message","role":"assistant","content":[]}]"#,
            #"[{"type":"function_call","id":"fc","call_id":"call","name":"exec","arguments":"{\"input\":\"changed\"}"}]"#,
            #"[{"type":"function_call","id":"fc","call_id":"call","name":"exec","arguments":"{\"input\":\"x\"}"},{"type":"function_call","id":"fc","call_id":"call","name":"exec","arguments":"{\"input\":\"x\"}"}]"#,
        ])
    func contradictorySnapshot(output: String) throws {
        var state = try makeState()
        _ = try send(Self.added, into: &state)
        _ = try send(Self.itemDone, into: &state)
        #expect(throws: CustomToolProjection.Error.invalidResponse) {
            try send(#"{"type":"response.completed","response":{"output":"# + output + "}}", into: &state)
        }
    }

    private static let added =
        #"{"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc","call_id":"call","name":"exec","arguments":"","status":"in_progress"}}"#
    private static let argumentsDone =
        #"{"type":"response.function_call_arguments.done","output_index":0,"item_id":"fc","arguments":"{\"input\":\"x\"}"}"#
    private static let itemDone = #"""
        {"type":"response.output_item.done","output_index":0,
         "item":{"type":"function_call","id":"fc","call_id":"call","name":"exec","arguments":"{\"input\":\"x\"}","status":"completed"}}
        """#
    private static let liteTerminal = #"{"type":"response.completed","response":{"output":[]}}"#

    private func makeState() throws -> CustomToolStreamProjection {
        let body = Data(#"{"tools":[{"type":"custom","name":"exec"}]}"#.utf8)
        return CustomToolStreamProjection(
            projection: try CustomToolProjection.prepare(body: body, wire: .responses, adapt: true),
            maximumBytes: 4_096)
    }

    private func at(_ index: Int, _ source: String) -> String {
        source.replacingOccurrences(of: #""output_index":0"#, with: #""output_index":"# + String(index))
    }

    private func send(
        _ source: String, into state: inout CustomToolStreamProjection
    ) throws -> CustomToolFrameRewrite.Edit {
        try state.consume(ServerSentEventFrame(event: nil, data: Data(source.utf8), terminal: false))
    }
}
