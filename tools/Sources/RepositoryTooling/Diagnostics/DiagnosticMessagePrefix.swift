import Foundation

/// Stable sorted JSON with ASCII Unicode escapes and the spacing of the original
/// diagnostic. Only its first 400 characters participate in the heuristic key.
enum DiagnosticMessagePrefix {
    static func encode(_ value: DiagnosticJSON) -> String {
        switch value {
        case .object(let object):
            let pairs = object.sorted { $0.0.unicodeScalars.lexicographicallyPrecedes($1.0.unicodeScalars) }
            let body = pairs.map { pair in encode(.string(pair.0)) + ": " + encode(pair.1) }
                .joined(separator: ", ")
            return "{" + body + "}"
        case .array(let array):
            return "[" + array.map(encode).joined(separator: ", ") + "]"
        case .scalar(let text): return text
        case .string(let text): return escapedString(text)
        }
    }

    private static func escapedString(_ value: String) -> String {
        var output = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 34: output += "\\\""
            case 92: output += "\\\\"
            case 8: output += "\\b"
            case 12: output += "\\f"
            case 10: output += "\\n"
            case 13: output += "\\r"
            case 9: output += "\\t"
            case 0...31, 127...:
                if scalar.value <= 0xFFFF {
                    output += String(format: "\\u%04x", scalar.value)
                } else {
                    let value = scalar.value - 0x10000
                    output += String(format: "\\u%04x\\u%04x", 0xD800 + (value >> 10), 0xDC00 + (value & 0x3FF))
                }
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        return output + "\""
    }
}
