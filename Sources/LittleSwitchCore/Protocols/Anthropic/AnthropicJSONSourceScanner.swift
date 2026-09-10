import Foundation

struct AnthropicJSONSourceScanner {
    private static let targetPath = ["message", "usage", "input_tokens"]

    private let bytes: [UInt8]
    private var index = 0

    init(data: Data) {
        bytes = Array(data)
    }

    mutating func inputTokenRanges() -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        guard parseValue(path: [], ranges: &ranges) else {
            return []
        }
        skipWhitespace()
        return index == bytes.count ? ranges : []
    }

    private mutating func parseValue(
        path: [String],
        ranges: inout [Range<Int>]
    ) -> Bool {
        skipWhitespace()
        guard index < bytes.count else { return false }
        switch bytes[index] {
        case 0x7B:
            return parseObject(path: path, ranges: &ranges)
        case 0x5B:
            return parseArray(path: path, ranges: &ranges)
        case 0x22:
            return parseString() != nil
        case 0x74:
            return consume("true")
        case 0x66:
            return consume("false")
        case 0x6E:
            return consume("null")
        case 0x2D, 0x30...0x39:
            guard let range = parseNumber() else { return false }
            if path == Self.targetPath {
                ranges.append(range)
            }
            return true
        default:
            return false
        }
    }

    private mutating func parseObject(
        path: [String],
        ranges: inout [Range<Int>]
    ) -> Bool {
        index += 1
        skipWhitespace()
        if consumeByte(0x7D) { return true }

        while index < bytes.count {
            guard let key = parseString() else { return false }
            skipWhitespace()
            guard consumeByte(0x3A),
                parseValue(path: path + [key], ranges: &ranges)
            else {
                return false
            }
            skipWhitespace()
            if consumeByte(0x7D) { return true }
            guard consumeByte(0x2C) else { return false }
            skipWhitespace()
        }
        return false
    }

    private mutating func parseArray(
        path: [String],
        ranges: inout [Range<Int>]
    ) -> Bool {
        index += 1
        skipWhitespace()
        if consumeByte(0x5D) { return true }

        while index < bytes.count {
            guard parseValue(path: path, ranges: &ranges) else { return false }
            skipWhitespace()
            if consumeByte(0x5D) { return true }
            guard consumeByte(0x2C) else { return false }
            skipWhitespace()
        }
        return false
    }

    private mutating func parseString() -> String? {
        guard index < bytes.count, bytes[index] == 0x22 else { return nil }
        let start = index
        index += 1
        while index < bytes.count {
            switch bytes[index] {
            case 0x22:
                index += 1
                return try? JSONDecoder().decode(
                    String.self,
                    from: Data(bytes[start..<index])
                )
            case 0x5C:
                index += 2
            default:
                index += 1
            }
        }
        return nil
    }

    private mutating func parseNumber() -> Range<Int>? {
        let start = index
        _ = consumeByte(0x2D)
        guard index < bytes.count else { return nil }
        if consumeByte(0x30) {
            // A leading zero is complete; JSON validation rejects a following digit.
        } else {
            guard consumeDigits(requireOne: true) else { return nil }
        }
        if consumeByte(0x2E), !consumeDigits(requireOne: true) {
            return nil
        }
        if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {
            index += 1
            if index < bytes.count, bytes[index] == 0x2B || bytes[index] == 0x2D {
                index += 1
            }
            guard consumeDigits(requireOne: true) else { return nil }
        }
        return start..<index
    }

    private mutating func consumeDigits(requireOne: Bool) -> Bool {
        let start = index
        while index < bytes.count, (0x30...0x39).contains(bytes[index]) {
            index += 1
        }
        return !requireOne || index > start
    }

    private mutating func consume(_ literal: StaticString) -> Bool {
        let value = Array(String(describing: literal).utf8)
        guard index + value.count <= bytes.count,
            bytes[index..<(index + value.count)].elementsEqual(value)
        else {
            return false
        }
        index += value.count
        return true
    }

    private mutating func consumeByte(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, isWhitespace(bytes[index]) {
            index += 1
        }
    }

    private func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }
}
