import AsyncHTTPClient
import Foundation
import LittleSwitchWire
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Custom response inverse rejection boundaries")
struct CustomToolMalformedResponseTests {
    @Test(
        "Adapted Responses calls require a string envelope without an existing input",
        arguments: [
            "[]",
            #"{"output":[{"type":"function_call","name":"exec"}]}"#,
            #"{"output":[{"type":"function_call","name":"exec","arguments":null}]}"#,
            #"{"output":[{"type":"function_call","name":"exec","arguments":"{}","input":"existing"}]}"#,
        ])
    func malformedResponses(_ body: String) throws {
        let projection = try projection()
        #expect(throws: CustomToolProjection.Error.invalidResponse) {
            try projection.restoreBuffered(Data(body.utf8))
        }
    }

    @Test(
        "Adapted Chat calls reject ambiguous or absent payloads",
        arguments: [
            #"{"type":"function","id":"call","function":{"name":"exec"}}"#,
            #"{"type":"function","id":"call","function":{"name":"exec","arguments":null}}"#,
            #"{"type":"function","id":"call","function":{"name":"exec","arguments":"{}","input":"existing"}}"#,
            #"{"type":"function","id":"call","function":{"name":"exec","arguments":"{}"},"custom":{}}"#,
        ])
    func malformedChat(_ call: String) throws {
        let projection = try projection(wire: .chatCompletions)
        let body = #"{"choices":[{"message":{"tool_calls":["# + call + "]}}]}"
        #expect(throws: CustomToolProjection.Error.invalidResponse) {
            try projection.restoreBuffered(Data(body.utf8))
        }
    }

    @Test("An invalid choice container is rejected before restoration")
    func malformedChoice() throws {
        let projection = try projection(wire: .chatCompletions)
        #expect(throws: CustomToolProjection.Error.invalidResponse) {
            try projection.restoreBuffered(Data(#"{"choices":[null]}"#.utf8))
        }
    }

    @Test("Unmapped ordinary output remains byte-identical with an active custom manifest")
    func unmappedOutput() throws {
        let projection = try projection()
        let source = Data(
            #" { "output":[{"type":"function_call","name":"echo","arguments":"{\"input\":\"ordinary\"}"}],"extension":7 } "#
                .utf8)
        #expect(try projection.restoreBuffered(source) == source)
    }

    @Test("Namespaced metadata restores custom children and allowed selectors without changing ordinary siblings")
    func namespacedMetadata() throws {
        let request = """
            {"tools":[{"type":"namespace","name":"files","tools":[
              {"type":"custom","name":"patch","description":"Exact source","format":{"type":"text"}},
              {"type":"function","name":"read","parameters":{}}]}]}
            """
        let projection = try CustomToolProjection.prepare(body: Data(request.utf8), wire: .responses, adapt: true)
        let metadata = try JSONValue.parse(
            Data(
                """
                {"tools":[{"type":"namespace","name":"files","description":"Namespace","tools":[
                  {"type":"function","name":"patch","parameters":{"provider":"echo"}},
                  {"type":"function","name":"read","parameters":{}}]}],
                 "tool_choice":{"type":"allowed_tools","mode":"required","tools":[
                   {"type":"function","name":"patch","namespace":"files"},
                   {"type":"function","name":"read","namespace":"files"}]},
                 "metadata":{"provider":"kept"}}
                """.utf8))
        let restored = try projection.restoreResponseMetadata(metadata)
        let expected = try JSONValue.parse(
            Data(
                """
                {"tools":[{"type":"namespace","name":"files","description":"Namespace","tools":[
                  {"type":"custom","name":"patch","description":"Exact source","format":{"type":"text"}},
                  {"type":"function","name":"read","parameters":{}}]}],
                 "tool_choice":{"type":"allowed_tools","mode":"required","tools":[
                   {"type":"custom","name":"patch","namespace":"files"},
                   {"type":"function","name":"read","namespace":"files"}]},
                 "metadata":{"provider":"kept"}}
                """.utf8))
        #expect(restored == expected)
    }

    @Test(
        "Malformed echoed declaration containers fail rather than guessing their identity",
        arguments: [
            "[]", #"{"tools":[null]}"#, #"{"tools":[{"type":"namespace","name":"files"}]}"#,
            #"{"tools":[{"type":"namespace","tools":[]}]}"#,
        ])
    func malformedMetadata(_ source: String) throws {
        let projection = try projection()
        #expect(throws: CustomToolProjection.Error.invalidResponse) {
            try projection.restoreResponseMetadata(JSONValue.parse(Data(source.utf8)))
        }
    }

    @Test("Restoring retained declaration metadata cannot bypass the response byte limit")
    func expandedMetadataLimit() async throws {
        let request: JSONValue = .object([
            "tools": .array([
                .object([
                    "type": .string("custom"), "name": .string("exec"),
                    "description": .string(String(repeating: "source ", count: 100)),
                ])
            ])
        ])
        let projection = try CustomToolProjection.prepare(
            body: request.serializedData(), wire: .responses, adapt: true)
        let response = HTTPClientResponse(
            status: .ok,
            headers: ["content-type": "application/json"],
            body: .bytes(ByteBuffer(string: #"{"output":[],"tools":[{"type":"function","name":"exec"}]}"#)))
        await #expect(throws: CustomToolProjection.Error.limitExceeded) {
            try await CustomToolResponse.restored(response, projection: projection, maximumBytes: 256)
        }
    }

    private func projection(wire: ProviderToolContract.Wire = .responses) throws -> CustomToolProjection {
        let request =
            wire == .responses
            ? #"{"tools":[{"type":"custom","name":"exec"},{"type":"function","name":"echo"}]}"#
            : #"{"tools":[{"type":"custom","custom":{"name":"exec"}}]}"#
        return try CustomToolProjection.prepare(body: Data(request.utf8), wire: wire, adapt: true)
    }
}
