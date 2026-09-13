import Foundation
import OrderedJSON
import Testing

@Suite("Local OrderedJSON string regressions")
struct LocalStringTests {
    @Test(arguments: [
        [0x22, 0xE0, 0x80, 0xAF, 0x22],
        [0x22, 0xF0, 0x80, 0x80, 0xAF, 0x22],
        [0x22, 0xE0, 0x80, 0x80, 0x22],
        [0x7B, 0x22, 0xE0, 0x80, 0xAF, 0x22, 0x3A, 0x30, 0x7D],
    ] as [[UInt8]])
    func publicParserRejectsOverlongUTF8(bytes: [UInt8]) {
        #expect(throws: JSONParseError.self) {
            try JSONValue.parse(Data(bytes))
        }
    }

    @Test func longStringsRetainUnicodeEscapesAndExactNumbers() throws {
        let plain = String(repeating: "history with spaces / and ASCII; ", count: 4096)
        let unicode = "\u{800}\u{10000}\u{10FFFF}e\u{301}"
        let input = Data(
            #"{"history":"\#(plain)","unicode":"\#(unicode)","escaped":"\uD800\uDC00\n\t\"\\","exact":1e-999}"#.utf8
        )
        let expected: JSONValue = .object([
            "history": .string(plain),
            "unicode": .string(unicode),
            "escaped": .string("\u{10000}\n\t\"\\"),
            "exact": .numberLiteral(try JSONNumberLiteral("1e-999")),
        ])
        let decoded = try JSONValue.parse(input)
        #expect(decoded == expected)
        #expect(try JSONValue.parse(decoded.serializedData()) == expected)
    }

    @Test func allControlCharactersKeepTheirExactEscapeSpelling() throws {
        let controls = String(String.UnicodeScalarView((0...31).compactMap(Unicode.Scalar.init)))
        let value = JSONValue.string(controls)
        let expected = #""\u0000\u0001\u0002\u0003\u0004\u0005\u0006\u0007\b\t\n\u000b\f\r\u000e\u000f\u0010\u0011\u0012\u0013\u0014\u0015\u0016\u0017\u0018\u0019\u001a\u001b\u001c\u001d\u001e\u001f""#
        #expect(try value.serializedData() == Data(expected.utf8))
        #expect(try JSONValue.parse(Data(expected.utf8)) == value)
    }

    @Test(arguments: [
        ("", #"{"field":""}"#),
        ("plain / text", #"{"field":"plain / text"}"#),
        ("\n", #"{"field":"\n"}"#),
        ("before\n", #"{"field":"before\n"}"#),
        ("\nafter", #"{"field":"\nafter"}"#),
        ("a\nb\"\\c", #"{"field":"a\nb\"\\c"}"#),
        ("\u{800}e\u{301}\n\u{10000}", "{\"field\":\"\u{800}e\u{301}\\n\u{10000}\"}"),
    ])
    func completeFieldsKeepEscapedAndUnescapedSegments(value: String, expected: String) throws {
        let object: JSONValue = .object(["field": .string(value)])
        #expect(try object.serializedData() == Data(expected.utf8))
        #expect(try JSONValue.parse(Data(expected.utf8)) == object)
    }
}
