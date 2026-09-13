import Foundation
import LittleSwitchWire
import Testing

@Suite("Anthropic SDK stop reasons")
struct AnthropicStopReasonTests {
    @Test func stopReasonIsTypedAndRoundTrips() throws {
        let data = Data(#""tool_use""#.utf8)
        let document = try WireCodec.decode(AnthropicStopReason.self, from: data)
        #expect(document.value == .toolUse)
        #expect(try WireCodec.encode(document.value) == data)
    }

    @Test(arguments: AnthropicStopReason.allCases)
    func everyOfficialValueRoundTrips(_ reason: AnthropicStopReason) throws {
        let data = try WireCodec.encode(reason)
        #expect(try WireCodec.decode(AnthropicStopReason.self, from: data).value == reason)
        let open = try WireCodec.decode(OpenWireValue<AnthropicStopReason>.self, from: data)
        #expect(open.value == .known(reason))
    }

    @Test func compatibilityPreservesFutureValuesWithoutChangingTheOfficialEnum() throws {
        let data = Data(#""future_reason""#.utf8)
        #expect(throws: WireCodingError(.invalidDiscriminator)) {
            try WireCodec.decode(AnthropicStopReason.self, from: data)
        }
        let open = try WireCodec.decode(OpenWireValue<AnthropicStopReason>.self, from: data)
        #expect(open.value == .unknown("future_reason"))
        #expect(try WireCodec.encode(open.value) == data)
        #expect(throws: WireCodingError(.typeMismatch)) {
            try WireCodec.decode(AnthropicStopReason.self, from: Data("false".utf8))
        }
    }
}
