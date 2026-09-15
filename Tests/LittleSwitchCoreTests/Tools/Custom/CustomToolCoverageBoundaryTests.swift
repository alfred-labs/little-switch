import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Custom projection measured boundaries")
struct CustomToolCoverageBoundaryTests {
    @Test("Chat allowed selectors preserve the exact permission subset and grammar without a description")
    func chatAllowedSelection() throws {
        let source = Data(
            #"""
            {"tools":[
              {"type":"custom","custom":{"name":"exec","format":{"type":"grammar","syntax":"lark","definition":"start: /.+/"}}},
              {"type":"custom","custom":{"name":"blocked"}},
              {"type":"function","function":{"name":"echo"}}],
             "tool_choice":{"type":"allowed_tools","allowed_tools":{"mode":"required","tools":[
               {"type":"custom","custom":{"name":"exec"}},
               {"type":"function","function":{"name":"echo"}}]}}}
            """#.utf8)
        let projection = try CustomToolProjection.prepare(body: source, wire: .chatCompletions, adapt: true)
        let root = try JSONValue.parse(projection.upstreamBody)
        let expected = try JSONValue.parse(
            Data(
                #"""
                {"type":"allowed_tools","allowed_tools":{"mode":"required","tools":[
                  {"type":"function","function":{"name":"exec"}},
                  {"type":"function","function":{"name":"echo"}}]}}
                """#.utf8))
        #expect(root.object?["tool_choice"] == expected)
        let payload = root.object?["tools"]?.array?.first?.object?["function"]
        #expect(payload?.object?["format"] == nil)
        #expect(
            payload?.object?["description"]
                == .string(
                    "\nThe input string must follow this custom tool format (instructions, not constrained decoding):\n"
                        + #"{"type":"grammar","syntax":"lark","definition":"start: /.+/"}"#))
        #expect(projection.adapts(.object(["name": .string("exec")])))
        #expect(projection.declares(.object(["name": .string("echo")])))
        #expect(!projection.adapts(.object(["name": .string("echo")])))
        #expect(!projection.adapts(.object(["name": .string("blocked")])))
        #expect(!projection.declares(.object(["name": .string("blocked")])))
    }

    @Test(
        "An incomplete or wrongly typed identity never maps to a declaration",
        arguments: ["null", "{}", #"{"name":""}"#, #"{"name":"exec","namespace":42}"#])
    func invalidIdentity(source: String) throws {
        let projection = try projection()
        let value = try JSONValue.parse(Data(source.utf8))
        #expect(!projection.adapts(value))
        #expect(!projection.declares(value))
    }

    @Test("Several retained Chat calls are released by index even when the terminal has no delta")
    func chatCallOrdering() throws {
        let projection = try projection(wire: .chatCompletions)
        var state = CustomToolChatStreamState()
        let first = try JSONValue.parse(
            Data(
                #"""
                {"choices":[{"index":0,"delta":{"tool_calls":[
                  {"index":2,"id":"second","type":"function","function":{"name":"exec","arguments":"{\"input\":\"two\"}"}},
                  {"index":0,"id":"first","type":"function","function":{"name":"exec","arguments":"{\"input\":\"one\"}"}}]}}]}
                """#.utf8))
        _ = try state.consume(first, projection: projection, maximumBytes: 4_096)
        let terminal = try JSONValue.parse(Data(#"{"choices":[{"index":0,"finish_reason":"tool_calls"}]}"#.utf8))
        let actual = try state.consume(terminal, projection: projection, maximumBytes: 4_096)
        let expected = try JSONValue.parse(
            Data(
                #"""
                {"choices":[{"index":0,"finish_reason":"tool_calls","delta":{"tool_calls":[
                  {"index":0,"id":"first","type":"custom","custom":{"name":"exec","input":"one"}},
                  {"index":2,"id":"second","type":"custom","custom":{"name":"exec","input":"two"}}]}}]}
                """#.utf8))
        #expect(actual == expected)
    }

    @Test("Retained Chat function extension fields stay stable across fragments", arguments: [false, true])
    func chatExtensionIdentity(changes: Bool) throws {
        let projection = try projection(wire: .chatCompletions)
        var state = CustomToolChatStreamState()
        for fragment in [
            #"{"index":0,"function":{"name":"exec","arguments":"{\"input\":\"x\"}"}}"#,
            #"{"index":0,"id":"call"}"#,
            #"{"index":0,"function":{"provider_extension":"first"}}"#,
        ] {
            let event = try chatEvent(fragment)
            _ = try state.consume(event, projection: projection, maximumBytes: 4_096)
        }
        let update =
            changes
            ? #"{"index":0,"function":{"provider_extension":"changed"}}"#
            : #"{"index":0,"function":{"provider_extension":"first"}}"#
        if changes {
            #expect(throws: CustomToolProjection.Error.invalidResponse) {
                try state.consume(chatEvent(update), projection: projection, maximumBytes: 4_096)
            }
        } else {
            _ = try state.consume(chatEvent(update), projection: projection, maximumBytes: 4_096)
            let terminal = try JSONValue.parse(Data(#"{"choices":[{"index":0,"finish_reason":"tool_calls"}]}"#.utf8))
            let result = try state.consume(terminal, projection: projection, maximumBytes: 4_096)
            let payload = result.object?["choices"]?.array?.first?.object?["delta"]?.object?["tool_calls"]?.array?.first
            #expect(
                payload?.object?["custom"]
                    == .object([
                        "name": .string("exec"), "input": .string("x"), "provider_extension": .string("first"),
                    ]))
        }
    }

    @Test("A retained non-object Chat function cannot acquire a second interpretation")
    func malformedRetainedChatFunction() throws {
        let projection = try projection(wire: .chatCompletions)
        var state = CustomToolChatStreamState()
        _ = try state.consume(
            chatEvent(#"{"index":0,"function":42}"#), projection: projection, maximumBytes: 4_096)
        #expect(throws: CustomToolProjection.Error.invalidResponse) {
            try state.consume(
                chatEvent(#"{"index":0,"function":{"name":"exec"}}"#), projection: projection, maximumBytes: 4_096)
        }
    }

    @Test("Adapted Responses items require an actual item ID", arguments: ["null", "\"\""])
    func missingResponseItemID(id: String) throws {
        var state = try responseState()
        let source = Self.added.replacingOccurrences(of: "\"fc\"", with: id)
        #expect(throws: CustomToolProjection.Error.invalidResponse) { try send(source, into: &state) }
    }

    @Test("A final Responses snapshot cannot omit output after a completed item")
    func missingResponseOutput() throws {
        var state = try responseState()
        _ = try send(Self.added, into: &state)
        _ = try send(Self.itemDone, into: &state)
        #expect(throws: CustomToolProjection.Error.invalidResponse) {
            try send(#"{"type":"response.completed","response":{}}"#, into: &state)
        }
    }

    @Test("Responses item.done must include the actual arguments")
    func missingCompletedArguments() throws {
        var state = try responseState()
        _ = try send(Self.added, into: &state)
        let event =
            #"{"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc","call_id":"call","name":"exec"}}"#
        #expect(throws: CustomToolProjection.Error.invalidResponse) { try send(event, into: &state) }
    }

    @Test("The final argument envelope must match all previously received fragments")
    func mismatchedArgumentPrefix() throws {
        var state = try responseState()
        _ = try send(Self.added, into: &state)
        _ = try send(
            #"{"type":"response.function_call_arguments.delta","output_index":0,"item_id":"fc","delta":"{\"input\":\"old"}"#,
            into: &state)
        #expect(throws: CustomToolProjection.Error.invalidResponse) { try send(Self.itemDone, into: &state) }
    }

    private static let added =
        #"{"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc","call_id":"call","name":"exec","arguments":""}}"#
    private static let itemDone =
        #"{"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc","call_id":"call","name":"exec","arguments":"{\"input\":\"x\"}"}}"#

    private func projection(wire: ProviderToolContract.Wire = .responses) throws -> CustomToolProjection {
        let request =
            wire == .responses
            ? #"{"tools":[{"type":"custom","name":"exec"}]}"#
            : #"{"tools":[{"type":"custom","custom":{"name":"exec"}}]}"#
        return try CustomToolProjection.prepare(body: Data(request.utf8), wire: wire, adapt: true)
    }

    private func responseState() throws -> CustomToolStreamProjection {
        try CustomToolStreamProjection(projection: projection(), maximumBytes: 4_096)
    }

    private func chatEvent(_ fragment: String) throws -> JSONValue {
        try JSONValue.parse(Data((#"{"choices":[{"index":0,"delta":{"tool_calls":["# + fragment + "]}}]}").utf8))
    }

    private func send(
        _ source: String,
        into state: inout CustomToolStreamProjection
    ) throws -> CustomToolFrameRewrite.Edit {
        try state.consume(ServerSentEventFrame(event: nil, data: Data(source.utf8), terminal: false))
    }
}
