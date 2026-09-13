import Foundation
import LittleSwitchWire
import Testing

@Suite("Responses event wire codecs")
struct ResponseEventWireTests {
    @Test("A future event retains its original document and flat opaque payload")
    func unknownEventRemainsOpaque() throws {
        let data = Data(#"{"type":"response.vendor.delta","opaque":{"text":"hi","tiny":1e-400}}"#.utf8)
        let document = try WireCodec.decode(OpenAIResponseStreamEvent.self, from: data)
        #expect(document.originalData == data)
        #expect(try WireCodec.encode(document.value) == data)
    }

    @Test("A selected event rejects wrong field types instead of becoming unknown")
    func malformedKnownEventFails() {
        let data = Data(
            #"{"type":"response.output_text.delta","output_index":true,"content_index":0,"item_id":"m","delta":"x"}"#
                .utf8)
        #expect(throws: WireCodingError.self) {
            try WireCodec.decode(OpenAIResponseStreamEvent.self, from: data)
        }
    }

    @Test("Known events encode as flat protocol objects")
    func knownEventEncodingIsFlat() throws {
        let data = Data(
            #"{"type":"response.output_text.delta","output_index":0,"content_index":0,"item_id":"m","delta":"x","provider_extra":null}"#
                .utf8)
        let document = try WireCodec.decode(OpenAIResponseStreamEvent.self, from: data)
        #expect(try JSONValue.parse(WireCodec.encode(document.value)) == JSONValue.parse(data))
    }
}
