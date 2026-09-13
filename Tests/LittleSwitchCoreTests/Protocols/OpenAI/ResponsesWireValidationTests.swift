import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Responses wire validation at public boundaries")
struct ResponsesWireValidationTests {
    @Test(arguments: [
        #"{"type":"function_call","id":"fc","call_id":"call","name":"run","arguments":"{}"}"#,
        #"{"type":"custom_tool_call","id":"ct","call_id":"call","name":"run","input":"opaque"}"#,
        #"{"type":"reasoning","id":"rs","summary":[]}"#,
    ])
    func codexMetadataKeepsOnlyThePublicTurnIdentity(item: String) throws {
        let original = try JSONValue.parse(item)
        var json = try WireObject(original)
        try json.set(
            JSONValue.parse(#"{"turn_id":"turn","private_vendor":{"n":1e400}}"#),
            for: "internal_chat_message_metadata_passthrough")
        let sanitized = try OpenAIResponsesPublicSanitizer.wireItem(json.wireJSON)
        let expectedMetadata = try JSONValue.parse(#"{"turn_id":"turn"}"#)
        #expect(
            sanitized.object?["internal_chat_message_metadata_passthrough"]
                == expectedMetadata)
        #expect(sanitized.object?["id"] == original.object?["id"])
    }

    @Test func unknownItemsCarryCorrelationWithoutGainingPublicVisibility() throws {
        let json = try JSONValue.parse(#"{"type":"future_item","id":"future","arguments":{"n":1e400}}"#)
        let metadata = try ResponsesStreamWireMetadata(OpenAIResponsesOutputItem(wireJSON: json))
        #expect(metadata.id == "future")
        #expect(metadata.type == "future_item")
        #expect(metadata.function == nil)
        #expect(metadata.toolInput == nil)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try OpenAIResponsesPublicSanitizer.wireItem(json)
        }
        for invalid in [#"{"type":"future_item"}"#, #"{"type":"future_item","id":false}"#] {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                try ResponsesStreamWireMetadata(OpenAIResponsesOutputItem(wireJSON: JSONValue.parse(invalid)))
            }
        }
    }

    @Test(arguments: ["web_search_call", "tool_search_call"])
    func serverAndClientSearchMetadataDoesNotBecomeAFunctionCall(type: String) throws {
        let item = try JSONValue.parse("{\"type\":\"\(type)\",\"id\":\"search\"}")
        let metadata = try ResponsesStreamWireMetadata(OpenAIResponsesOutputItem(wireJSON: item))
        #expect(metadata.id == "search")
        #expect(metadata.type == type)
        #expect(metadata.function == nil)
        #expect(metadata.toolInput == nil)
    }

    @Test func publicSearchRejectsNullURLAndMalformedSources() throws {
        let item = try JSONValue.parse(
            #"{"type":"web_search_call","id":"search","action":{"type":"open_page","url":null}}"#)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try OpenAIResponsesPublicSanitizer.wireItem(item)
        }
        for sources in [Array(repeating: "https://example.com/", count: 101), ["ftp://example.com/"]] {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                try OpenAIResponsesWebSearch.nativeSearchItem(
                    id: "search", query: "query", sources: sources, failed: false)
            }
        }
    }

    @Test func adapterObjectsAndToolIdentitiesRejectInvalidShapes() throws {
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try ResponsesWireToolPolicy.objects([.string("tool")])
        }
        for invalid in [
            #"{"type":"function_call","call_id":"","name":"run","arguments":"{}"}"#,
            #"{"type":"custom_tool_call","call_id":"call","name":"run","namespace":"","input":"opaque"}"#,
        ] {
            let item = try OpenAIResponsesOutputItem(wireJSON: JSONValue.parse(invalid))
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) { try responsesFunctionMetadata(item) }
        }
    }

    @Test func bufferedTurnsRequireAnIdentityAndAUsablePrivateCall() {
        for invalid in [
            #"{"id":"","output":[],"usage":{}}"#,
            #"{"id":"resp","output":[{"type":"function_call","call_id":"","name":"web_search","arguments":"{}"}],"usage":{}}"#,
        ] {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                try OpenAIResponsesWebSearch.parseModelTurn(Data(invalid.utf8))
            }
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try OpenAIResponsesWebSearch.modelTerminalStatus(from: ["status": true])
        }
    }
}
