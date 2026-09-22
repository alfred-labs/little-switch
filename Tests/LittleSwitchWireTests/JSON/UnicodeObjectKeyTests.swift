import Foundation
import LittleSwitchWire
import Testing

@Suite("Unicode field fidelity across generated codecs")
struct UnicodeObjectKeyTests {
    @Test func generatedAdditionalFields() throws {
        let data = Data(#"{"type":"text","text":"ok","\u00e9":1,"e\u0301":2}"#.utf8)
        let decoded = try WireCodec.decode(AnthropicTextParam.self, from: data).value
        #expect(decoded.additionalFields.count == 2)
        let encoded = try WireCodec.encode(decoded)
        let fields = try #require(try WireCodec.decode(JSONValue.self, from: encoded).value.object)
        #expect(fields.count == 4)
        #expect(fields["\u{e9}"] == 1)
        #expect(fields["e\u{301}"] == 2)
    }
}
