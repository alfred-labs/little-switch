import Foundation
import LittleSwitchWire
import Testing

@Suite("Official buffered Chat projection")
struct ChatCompletionWireTests {
    @Test func partialProviderMessageRetainsAbsenceAndOpaqueFields() throws {
        let data = Data(
            #"""
            {"choices":[{"finish_reason":"stop","message":{"vendor":18446744073709551615}}],
             "usage":{"prompt_tokens_details":null,"completion_tokens_details":null,"total_tokens":null},
             "id":null,"created":null,"vendor":1e-400}
            """#
            .utf8)
        let document = try WireCodec.decode(OpenAIChatCompletion.self, from: data)
        let message = try #require(document.value.choices.first?.message)
        #expect(message.content == .absent)
        #expect(message.refusal == .absent)
        #expect(document.value.id == .null)
        #expect(document.value.created == .null)
        #expect(try JSONValue.parse(WireCodec.encode(document.value)) == JSONValue.parse(data))
    }

    @Test func customInputIsAnOpaqueStringAndNamespaceIsOpen() throws {
        let data = Data(
            #"{"type":"custom","id":"call_1","custom":{"name":"patch","input":"*** Begin Patch\nΔ","namespace":"workspace"},"vendor":null}"#
                .utf8)
        let document = try WireCodec.decode(OpenAIChatMessageToolCall.self, from: data)
        guard case .custom(let call) = document.value else {
            Issue.record("The SDK custom branch must retain its typed input")
            return
        }
        #expect(call.custom.input == "*** Begin Patch\nΔ")
        #expect(call.custom.namespace == .value("workspace"))
        #expect(try JSONValue.parse(WireCodec.encode(document.value)) == JSONValue.parse(data))
    }

    @Test func futureToolTagsStayOpaqueAndMalformedKnownTagsFail() throws {
        let data = Data(#"{"type":"future_tool","opaque":1e-400}"#.utf8)
        let document = try WireCodec.decode(OpenAIChatMessageToolCall.self, from: data)
        #expect(document.originalData == data)
        #expect(try JSONValue.parse(WireCodec.encode(document.value)) == JSONValue.parse(data))
        #expect(throws: WireCodingError.self) {
            try WireCodec.decode(
                OpenAIChatMessageToolCall.self,
                from: Data(#"{"type":"function","id":"call_1","function":{"name":"read","arguments":false}}"#.utf8))
        }
    }

    @Test func explicitNullTokenCountIsInvalid() {
        #expect(throws: WireCodingError(.unexpectedNull, path: ["prompt_tokens"])) {
            try WireCodec.decode(OpenAIChatBufferedUsage.self, from: Data(#"{"prompt_tokens":null}"#.utf8))
        }
    }
}
