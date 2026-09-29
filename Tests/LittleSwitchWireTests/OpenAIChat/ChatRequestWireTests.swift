import Foundation
import LittleSwitchWire
import Testing

@Suite("Official Chat request instructions")
struct ChatRequestWireTests {
    @Test func developerInstructionRequiresItsContent() {
        #expect(throws: WireCodingError.self) {
            try WireCodec.decode(
                OpenAIChatRequestMessage.self,
                from: Data(#"{"role":"developer","name":"instructions"}"#.utf8))
        }
    }

    @Test func developerInstructionRetainsContentAndUnknownFields() throws {
        let data = Data(
            #"{"role":"developer","content":[{"type":"text","text":"Use Swift — 保持工具约束"}],"name":"instructions","vendor":18446744073709551615}"#
                .utf8)
        let document = try WireCodec.decode(OpenAIChatRequestMessage.self, from: data)
        #expect(try JSONValue.parse(WireCodec.encode(document.value)) == JSONValue.parse(data))
    }
}
