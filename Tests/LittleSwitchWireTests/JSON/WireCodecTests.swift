import Foundation
import LittleSwitchWire
import Testing

@Suite("Lossless wire codec")
struct WireCodecTests {
    @Test func preservesOriginalBytesAndNumericTokens() throws {
        let data = Data(#" { "large":18446744073709551615, "tiny":1e-999, "text":"\u0041" } "#.utf8)
        let document = try WireCodec.decode(JSONValue.self, from: data)
        #expect(document.originalData == data)
        let encoded = try WireCodec.encode(document.value)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(text.contains("18446744073709551615"))
        #expect(text.contains("1e-999"))
        #expect(try JSONValue.parse(encoded) == document.value)
    }

    @Test(arguments: [Data("{private".utf8), Data([0xFF]), Data("NaN".utf8)])
    func invalidInputHasNoPayloadInDiagnostic(data: Data) {
        #expect(throws: WireCodingError(.invalidJSON)) {
            try WireCodec.decode(JSONValue.self, from: data)
        }
    }

    @Test(
        arguments: [
            [0x22, 0xE0, 0x80, 0xAF, 0x22],
            [0x22, 0xF0, 0x80, 0x80, 0xAF, 0x22],
            [0x22, 0xE0, 0x80, 0x80, 0x22],
            [0x7B, 0x22, 0xE0, 0x80, 0xAF, 0x22, 0x3A, 0x30, 0x7D],
            [0x22, 0xED, 0xA0, 0x80, 0x22],
            [0x22, 0xF4, 0x90, 0x80, 0x80, 0x22],
            [0x22, 0xF0, 0x90, 0x80, 0x22],
        ] as [[UInt8]])
    func rejectsMalformedUTF8BeforeDecoding(bytes: [UInt8]) {
        #expect(throws: WireCodingError(.invalidJSON)) {
            try WireCodec.decode(JSONValue.self, from: Data(bytes))
        }
    }

    @Test func validUnicodePreservesOriginalBytesAndExactNumbers() throws {
        let raw = "\u{800}\u{10000}\u{10FFFF}e\u{301}"
        let data = Data(#" { "raw":"\#(raw)", "escaped":"\uD800\uDC00", "exact":1e-999 } "#.utf8)
        let document = try WireCodec.decode(JSONValue.self, from: data)
        let expected: JSONValue = .object([
            "raw": .string(raw),
            "escaped": .string("\u{10000}"),
            "exact": .numberLiteral(try JSONNumber("1e-999")),
        ])
        #expect(document.originalData == data)
        #expect(document.value == expected)
        let encoded = try WireCodec.encode(document.value)
        #expect(try WireCodec.decode(JSONValue.self, from: encoded).value == expected)
    }

    @Test func doesNotRoundFractionalOrLargeIntegers() {
        for token in ["0.5", "18446744073709551615", "1e-999"] {
            #expect(throws: WireCodingError(.unrepresentableNumber)) {
                try WireCodec.decode(Int.self, from: Data(token.utf8))
            }
        }
        #expect(throws: WireCodingError(.typeMismatch)) {
            try WireCodec.decode(Int.self, from: Data("true".utf8))
        }
    }

    @Test func arraysReportTheFailingIndex() {
        #expect(throws: WireCodingError(.typeMismatch, path: ["1"])) {
            try WireCodec.decode([String].self, from: Data(#"["ok",false]"#.utf8))
        }
    }

    @Test func arraysAndScalarsRoundTrip() throws {
        #expect(try WireCodec.encode(["a", "b"]) == Data(#"["a","b"]"#.utf8))
        #expect(try WireCodec.decode(Bool.self, from: Data("false".utf8)).value == false)
        #expect(try WireCodec.encode(7) == Data("7".utf8))
        #expect(try WireCodec.encode(true) == Data("true".utf8))
        #expect(try WireCodec.decode(Int.self, from: Data("7e0".utf8)).value == 7)
    }

    @Test func nonBooleanDoesNotCoerce() {
        #expect(throws: WireCodingError(.typeMismatch)) {
            try WireCodec.decode(Bool.self, from: Data("0".utf8))
        }
    }
}
