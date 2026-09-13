import Foundation
import LittleSwitchWire
import Testing

@Suite("Responses SDK routing projection")
struct ResponsesRoutingWireTests {
    @Test func modelRemainsOpenAndEveryOtherFieldIsOpaque() throws {
        let data = Data(#"{"model":"future-model","stream":true,"input":[{"vendor":18446744073709551615}]}"#.utf8)
        let document = try WireCodec.decode(OpenAIResponsesRoutingRequest.self, from: data)
        #expect(document.value.model == "future-model")
        #expect(document.originalData == data)
        #expect(try JSONValue.parse(WireCodec.encode(document.value)) == JSONValue.parse(data))
    }

    @Test func absentModelIsPermittedButNullIsNotAnOfficialModel() throws {
        let data = Data("{}".utf8)
        let document = try WireCodec.decode(OpenAIResponsesRoutingRequest.self, from: data)
        #expect(document.value.model == nil)
        #expect(try WireCodec.encode(document.value) == data)
        #expect(throws: WireCodingError(.unexpectedNull, path: ["model"])) {
            try WireCodec.decode(OpenAIResponsesRoutingRequest.self, from: Data(#"{"model":null}"#.utf8))
        }
        #expect(throws: WireCodingError(.typeMismatch, path: ["model"])) {
            try WireCodec.decode(OpenAIResponsesRoutingRequest.self, from: Data(#"{"model":false}"#.utf8))
        }
    }

    @Test func extrasCannotOverrideTheSelectedModel() {
        let request = OpenAIResponsesRoutingRequest(model: "selected", additionalFields: ["model": .string("hidden")])
        #expect(throws: WireCodingError(.additionalFieldCollision, path: ["model"])) {
            try WireCodec.encode(request)
        }
    }
}
