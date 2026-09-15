import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Custom request projection rejection boundaries")
struct CustomToolMalformedRequestTests {
    @Test("Native and Anthropic projections preserve opaque bytes without parsing")
    func opaqueIdentity() throws {
        let request = Data([0xFF, 0x00, 0x7B])
        let response = Data([0xFE, 0x00, 0x5B])
        let wires: [ProviderToolContract.Wire] = [.responses, .chatCompletions, .anthropic]
        for wire in wires {
            let projection = try CustomToolProjection.prepare(body: request, wire: wire, adapt: wire == .anthropic)
            #expect(projection.originalBody == request)
            #expect(projection.upstreamBody == request)
            #expect(try projection.restoreBuffered(response) == response)
        }
    }

    @Test(
        "Malformed Responses declarations cannot produce an outbound function",
        arguments: [
            "[]", #"{"tools":[null]}"#, #"{"tools":[{"type":"namespace","tools":[]}]}"#,
            #"{"tools":[{"type":"namespace","name":"files","tools":{}}]}"#,
            #"{"tools":[{"type":"custom"}]}"#, #"{"tools":[{"type":"custom","name":""}]}"#,
            #"{"tools":[{"type":"custom","name":"exec"},{"type":"custom","name":"exec"}]}"#,
        ])
    func malformedResponsesDeclarations(_ source: String) {
        #expect(throws: CustomToolProjection.Error.invalidRequest) {
            try project(source, wire: .responses)
        }
    }

    @Test(
        "Malformed Chat declarations and custom selectors fail locally",
        arguments: [
            #"{"tools":[{"type":"custom"}]}"#,
            #"{"tools":[{"type":"custom","custom":null}]}"#,
            #"{"tools":[{"type":"custom","custom":{"name":""}}]}"#,
            #"{"tools":[{"type":"custom","custom":{"name":"exec"}}],"tool_choice":{"type":"custom"}}"#,
            #"{"tools":[{"type":"custom","custom":{"name":"exec"}}],"tool_choice":{"type":"allowed_tools"}}"#,
        ])
    func malformedChatDeclarations(_ source: String) {
        #expect(throws: CustomToolProjection.Error.invalidRequest) {
            try project(source, wire: .chatCompletions)
        }
    }

    @Test(
        "Responses custom history requires one unwrapped input",
        arguments: [
            #"{"type":"custom_tool_call","name":"exec","call_id":"old"}"#,
            #"{"type":"custom_tool_call","name":"exec","call_id":"old","input":null}"#,
            #"{"type":"custom_tool_call","name":"exec","call_id":"old","input":"x","arguments":"{}"}"#,
        ])
    func malformedResponsesHistory(_ item: String) {
        let source = #"{"tools":[{"type":"custom","name":"exec"}],"input":["# + item + "]}"
        #expect(throws: CustomToolProjection.Error.invalidRequest) {
            try project(source, wire: .responses)
        }
    }

    @Test(
        "Chat custom history cannot carry two payload representations",
        arguments: [
            #"{"type":"custom","id":"old"}"#,
            #"{"type":"custom","id":"old","custom":{"name":"exec","input":null}}"#,
            #"{"type":"custom","id":"old","custom":{"name":"exec","input":"x","arguments":"{}"}}"#,
            #"{"type":"custom","id":"old","custom":{"name":"exec","input":"x"},"function":{}}"#,
        ])
    func malformedChatHistory(_ call: String) {
        let source =
            #"{"tools":[{"type":"custom","custom":{"name":"exec"}}],"messages":[{"role":"assistant","tool_calls":["#
            + call + "]}]}"
        #expect(throws: CustomToolProjection.Error.invalidRequest) {
            try project(source, wire: .chatCompletions)
        }
    }

    @Test("Projection retains ordinary history and provider extension fields")
    func ordinaryFields() throws {
        let source = """
            {"tools":[{"type":"custom","name":"exec"},{"type":"function","name":"echo","parameters":{}}],
             "tool_choice":"none","metadata":{"source":"fixture"},
             "input":[{"type":"function_call","call_id":"old","name":"echo","arguments":"{}"},
                      {"type":"function_call_output","call_id":"old","output":"ok"}]}
            """
        let result = try JSONValue.parse(project(source, wire: .responses))
        #expect(result.object?["metadata"] == .object(["source": .string("fixture")]))
        #expect(result.object?["tool_choice"] == .string("none"))
        #expect(
            result.object?["input"]
                == .array([
                    .object([
                        "type": .string("function_call"), "call_id": .string("old"),
                        "name": .string("echo"), "arguments": .string("{}"),
                    ]),
                    .object([
                        "type": .string("function_call_output"), "call_id": .string("old"), "output": .string("ok"),
                    ]),
                ]))
    }

    @Test(
        "Earlier non-string input fields cannot be hidden by a later valid duplicate",
        arguments: [
            #"{"input":null,"input":"later"}"#,
            #"{"input":false,"input":"later"}"#,
            #"{"input":123,"input":"later"}"#,
            #"{"input":[{"nested":["brace }","quote \"","slash \\"]}],"input":"later"}"#,
            #"{"input":{"nested":{"deeper":"escaped \" }"}},"\u0069nput":"later"}"#,
        ])
    func overwrittenNonStringEnvelope(_ arguments: String) {
        #expect(throws: CustomToolInputEnvelope.Error.invalidEnvelope) {
            try CustomToolInputEnvelope.decode(arguments)
        }
    }

    private func project(_ source: String, wire: ProviderToolContract.Wire) throws -> Data {
        var projection = CustomToolRequestProjection(body: Data(source.utf8), wire: wire)
        return try projection.project()
    }
}
