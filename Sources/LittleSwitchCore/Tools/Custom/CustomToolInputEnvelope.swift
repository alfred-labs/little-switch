import Foundation
import LittleSwitchWire

/// The one owned JSON field used to carry freeform custom-tool input on a
/// function-shaped wire. The decoder is intentionally narrower than the global
/// JSON parser: duplicate or extra fields must never look like valid input.
package enum CustomToolInputEnvelope {
    package enum Error: Swift.Error, Equatable { case invalidEnvelope }

    /// This strict envelope and its JSON Schema are adapter-owned, not a
    /// Responses input item or any generated provider payload.
    enum Field: String { case input }
    enum SchemaField: String {
        case type
        case properties
        case required
        case additionalProperties
    }
    enum SchemaType: String {
        case object
        case string
    }

    package static func encode(_ input: String) throws -> String {
        try JSONValue.object([Field.input.rawValue: .string(input)]).serialized()
    }

    package static func decode(_ arguments: String) throws -> String {
        let bytes = Array(arguments.utf8)
        var index = 0
        try consume(.leftBrace, in: bytes, index: &index)
        let key = try parseString(in: bytes, index: &index)
        guard key == Field.input.rawValue else { throw Error.invalidEnvelope }
        try consume(.colon, in: bytes, index: &index)
        let input = try parseString(in: bytes, index: &index)
        try consume(.rightBrace, in: bytes, index: &index)
        guard skipWhitespace(in: bytes, from: index) == bytes.count else { throw Error.invalidEnvelope }
        return input
    }

    /// OrderedJSON deliberately keeps the last duplicate when parsing general
    /// JSON. Recognizing exactly `{ string : string }` rejects every duplicate
    /// or extra field without a second, general-purpose JSON parser.
    private static func consume(_ expected: UInt8, in bytes: [UInt8], index: inout Int) throws {
        index = skipWhitespace(in: bytes, from: index)
        guard byteAt(bytes, index) == expected else { throw Error.invalidEnvelope }
        index += 1
    }

    private static func parseString(in bytes: [UInt8], index: inout Int) throws -> String {
        let start = skipWhitespace(in: bytes, from: index)
        guard byteAt(bytes, start) == .quote else { throw Error.invalidEnvelope }
        var end = start + 1
        while let byte = byteAt(bytes, end) {
            if byte == .quote {
                // The existing string codec owns escape and Unicode validity.
                guard let string = (try? JSONValue.parse(Data(bytes[start...end])))?.string else {
                    throw Error.invalidEnvelope
                }
                index = end + 1
                return string
            }
            end += byte == .backslash ? 2 : 1
        }
        throw Error.invalidEnvelope
    }

    private static func skipWhitespace(in bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while let byte = byteAt(bytes, index), byte.isJSONWhitespace {
            index += 1
        }
        return index
    }

    private static func byteAt(_ bytes: [UInt8], _ index: Int) -> UInt8? {
        bytes.indices.contains(index) ? bytes[index] : nil
    }
}

extension UInt8 {
    fileprivate static let backslash: UInt8 = 0x5C
    fileprivate static let carriageReturn: UInt8 = 0x0D
    fileprivate static let colon: UInt8 = 0x3A
    fileprivate static let leftBrace: UInt8 = 0x7B
    fileprivate static let lineFeed: UInt8 = 0x0A
    fileprivate static let quote: UInt8 = 0x22
    fileprivate static let rightBrace: UInt8 = 0x7D
    fileprivate static let space: UInt8 = 0x20
    fileprivate static let tab: UInt8 = 0x09

    fileprivate var isJSONWhitespace: Bool {
        self == .space || self == .tab || self == .carriageReturn || self == .lineFeed
    }
}
