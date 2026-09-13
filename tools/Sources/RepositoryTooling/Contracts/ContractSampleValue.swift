import Foundation

/// Qualification values retain numeric lexemes independently of Foundation's numeric bridging.
indirect enum ContractSampleValue: Equatable, Sendable {
    case object([String: Self])
    case array([Self])
    case string(String)
    case number(String)
    case boolean(Bool)
    case null

    static let opaque: Self = .object([
        "exact_integer": .number("9007199254740993"), "large_number": .number("1e400"), "null": .null,
    ])

    var json: String { json(depth: 0) }

    private func json(depth: Int) -> String {
        let indentation = String(repeating: "  ", count: depth)
        switch self {
        case .object(let fields):
            if fields.isEmpty { return "{}" }
            let entries = fields.sorted { $0.key < $1.key }.map {
                indentation + "  " + Self.quoted($0.key) + ": " + $0.value.json(depth: depth + 1)
            }
            return "{\n" + entries.joined(separator: ",\n") + "\n" + indentation + "}"
        case .array(let values):
            if values.isEmpty { return "[]" }
            let entries = values.map { indentation + "  " + $0.json(depth: depth + 1) }
            return "[\n" + entries.joined(separator: ",\n") + "\n" + indentation + "]"
        case .string(let value): return Self.quoted(value)
        case .number(let value): return value
        case .boolean(let value): return value ? "true" : "false"
        case .null: return "null"
        }
    }

    private static func quoted(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar -> String in
            switch scalar.value {
            case 34: return "\\\""
            case 92: return "\\\\"
            case 0...31: return String(format: "\\u%04x", scalar.value)
            default: return String(scalar)
            }
        }
        return "\"" + scalars.joined() + "\""
    }
}

struct ContractCodecSample {
    let label: String
    let input: ContractSampleValue
    var failure: Failure?
    var operation: String?

    struct Failure: Equatable {
        let kind: String
        var path: [String] = []
    }
}
