import Foundation
import LittleSwitchWire
import Testing

@Suite("Open protocol enum values")
struct OpenWireValueTests {
    private enum Known: String, Sendable {
        case toolUse = "tool_use"
    }

    @Test func decodingDistinguishesKnownAndFutureValues() throws {
        let known = try WireCodec.decode(OpenWireValue<Known>.self, from: Data(#""tool_use""#.utf8))
        #expect(known.value == .known(.toolUse))
        let futureData = Data(#""future_reason""#.utf8)
        let future = try WireCodec.decode(OpenWireValue<Known>.self, from: futureData)
        #expect(future.value == .unknown("future_reason"))
        #expect(try WireCodec.encode(known.value) == known.originalData)
        #expect(try WireCodec.encode(future.value) == futureData)
    }

    @Test func anOpenEnumStillRequiresAString() {
        #expect(throws: WireCodingError(.typeMismatch)) {
            try WireCodec.decode(OpenWireValue<Known>.self, from: Data("null".utf8))
        }
    }
}
