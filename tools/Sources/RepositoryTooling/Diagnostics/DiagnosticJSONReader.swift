import Foundation

/// A bounded JSON reader for the existing diagnostic's Python-compatible key.
/// Foundation decodes string escapes; numeric lexemes never pass through Decimal.
struct DiagnosticJSONReader {
    enum Failure: Error { case malformed }

    private let bytes: [UInt8]
    private var offset = 0

    static func read(_ data: Data) throws -> DiagnosticJSON {
        var reader = Self(bytes: Array(data))
        let value = try reader.value(depth: 0)
        reader.whitespace()
        guard reader.offset == reader.bytes.count else { throw Failure.malformed }
        return value
    }

    private mutating func value(depth: Int) throws -> DiagnosticJSON {
        whitespace()
        guard depth < 512, offset < bytes.count else { throw Failure.malformed }
        switch bytes[offset] {
        case 123: return try object(depth: depth + 1)
        case 91: return try array(depth: depth + 1)
        case 34: return .string(try string())
        case 116: return try literal("true")
        case 102: return try literal("false")
        case 110: return try literal("null")
        default: return .scalar(try number())
        }
    }

    private mutating func object(depth: Int) throws -> DiagnosticJSON {
        offset += 1
        var pairs: [(String, DiagnosticJSON)] = []
        if consume(125) { return .object(pairs) }
        repeat {
            whitespace()
            let key = try string()
            guard consume(58) else { throw Failure.malformed }
            let entry = try value(depth: depth)
            pairs.removeAll { $0.0.utf8.elementsEqual(key.utf8) }
            pairs.append((key, entry))
            if consume(125) { return .object(pairs) }
        } while consume(44)
        throw Failure.malformed
    }

    private mutating func array(depth: Int) throws -> DiagnosticJSON {
        offset += 1
        var elements: [DiagnosticJSON] = []
        if consume(93) { return .array(elements) }
        repeat {
            elements.append(try value(depth: depth))
            if consume(93) { return .array(elements) }
        } while consume(44)
        throw Failure.malformed
    }

    private mutating func string() throws -> String {
        guard offset < bytes.count, bytes[offset] == 34 else { throw Failure.malformed }
        let start = offset
        offset += 1
        while offset < bytes.count {
            let byte = bytes[offset]
            offset += 1
            if byte == 34 {
                let token = Data(bytes[start..<offset])
                return try JSONDecoder().decode(String.self, from: token)
            }
            if byte == 92 { offset += 1 }
        }
        throw Failure.malformed
    }

    private mutating func number() throws -> String {
        let start = offset
        if offset < bytes.count, bytes[offset] == 45 { offset += 1 }
        guard offset < bytes.count else { throw Failure.malformed }
        if bytes[offset] == 48 {
            offset += 1
        } else {
            guard (49...57).contains(bytes[offset]) else { throw Failure.malformed }
            digits()
        }
        var floating = false
        if offset < bytes.count, bytes[offset] == 46 {
            floating = true
            offset += 1
            try requiredDigits()
        }
        if offset < bytes.count, bytes[offset] == 101 || bytes[offset] == 69 {
            floating = true
            offset += 1
            if offset < bytes.count, bytes[offset] == 43 || bytes[offset] == 45 { offset += 1 }
            try requiredDigits()
        }
        // Numeric grammar above guarantees ASCII bytes.
        // swiftlint:disable:next optional_data_string_conversion
        let token = String(decoding: bytes[start..<offset], as: UTF8.self)
        guard floating else { return token == "-0" ? "0" : token }
        guard let number = Double(token) else { throw Failure.malformed }
        return DiagnosticJSONNumber.floating(number)
    }

    private mutating func requiredDigits() throws {
        let start = offset
        digits()
        guard offset > start else { throw Failure.malformed }
    }

    private mutating func digits() {
        while offset < bytes.count, (48...57).contains(bytes[offset]) { offset += 1 }
    }

    private mutating func literal(_ text: String) throws -> DiagnosticJSON {
        guard bytes[offset...].starts(with: text.utf8) else { throw Failure.malformed }
        offset += text.utf8.count
        return .scalar(text)
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        whitespace()
        guard offset < bytes.count, bytes[offset] == byte else { return false }
        offset += 1
        return true
    }

    private mutating func whitespace() {
        while offset < bytes.count, [9, 10, 13, 32].contains(bytes[offset]) { offset += 1 }
    }
}
