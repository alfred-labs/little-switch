import Foundation
import LittleSwitchWire
import Testing

@Suite("Nullable wire values")
struct WireNullableValueTests {
    @Test func nullIsAValueInsideAnArray() throws {
        let data = Data(#"[null,"text",null]"#.utf8)
        let document = try WireCodec.decode([String?].self, from: data)
        #expect(document.value == [nil, "text", nil])
        #expect(try WireCodec.encode(document.value) == data)
    }

    @Test func nullableRootHasNoMissingState() throws {
        #expect(try WireCodec.decode(String?.self, from: Data("null".utf8)).value == nil)
        #expect(try WireCodec.encode(String?.none) == Data("null".utf8))
        #expect(try WireCodec.decode(String?.self, from: Data(#""text""#.utf8)).value == "text")
    }

    @Test func nullableDoesNotPermitWrongNonNullTypes() {
        #expect(throws: WireCodingError(.typeMismatch, path: ["0"])) {
            try WireCodec.decode([String?].self, from: Data("[false]".utf8))
        }
    }
}
