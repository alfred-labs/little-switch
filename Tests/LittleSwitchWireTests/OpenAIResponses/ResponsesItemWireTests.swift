import Foundation
import LittleSwitchWire
import Testing

@Suite("Responses item wire codecs")
struct ResponsesItemWireTests {
    @Test("Custom input, namespace, explicit null and unknown fields round trip")
    func preservesOpaqueInputAndExtras() throws {
        let data = Data(
            #"{"type":"custom_tool_call","id":"ct_1","call_id":"call_1","name":"patch","namespace":"workspace","input":"*** Begin Patch\nΔ","status":"completed","vendor":null}"#
                .utf8)
        let document = try WireCodec.decode(OpenAIResponsesOutputItem.self, from: data)
        #expect(document.originalData == data)
        #expect(try JSONValue.parse(WireCodec.encode(document.value)) == JSONValue.parse(data))
    }

    @Test("Input history keeps opaque custom outputs without parsing them as arguments")
    func preservesOpaqueHistoryOutput() throws {
        let data = Data(
            #"{"type":"custom_tool_call_output","call_id":"call_1","output":{"value":18446744073709551617,"tiny":1e-400,"vendor":null}}"#
                .utf8)
        let document = try WireCodec.decode(OpenAIResponsesInputCustomOutput.self, from: data)
        #expect(try JSONValue.parse(WireCodec.encode(document.value)) == JSONValue.parse(data))
    }

    @Test("Wire preserves explicit null fields independently of public normalization")
    func nullFieldsRemainPresent() throws {
        let data = Data(
            #"{"type":"message","id":"m","role":"assistant","status":null,"phase":null,"content":[{"type":"output_text","text":"hi","annotations":null,"logprobs":null}]}"#
                .utf8)
        let document = try WireCodec.decode(OpenAIResponsesOutputItem.self, from: data)
        #expect(try JSONValue.parse(WireCodec.encode(document.value)) == JSONValue.parse(data))
    }

    @Test("A malformed selected custom call cannot fall through as an unknown item")
    func malformedKnownItemFails() {
        let data = Data(#"{"type":"custom_tool_call","call_id":"call_1","input":"opaque"}"#.utf8)
        #expect(throws: WireCodingError.self) {
            try WireCodec.decode(OpenAIResponsesOutputItem.self, from: data)
        }
    }
}
