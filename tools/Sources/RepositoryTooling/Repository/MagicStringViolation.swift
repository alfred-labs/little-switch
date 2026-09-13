import Foundation

extension MagicKeyScanner {
    package enum RuleID: String, Codable, Sendable {
        case subscriptKey
        case dictionaryKey
        case discriminantValue

        var diagnostic: String {
            switch self {
            case .subscriptKey: "subscript"
            case .dictionaryKey: "dict-literal"
            case .discriminantValue: "discriminant"
            }
        }
    }

    package struct Literal: Codable, Hashable, Sendable {
        package enum Kind: String, Codable, Sendable { case string, interpolated }
        package let kind: Kind
        package let value: String
    }

    package struct Position: Equatable, Sendable {
        package let line: Int
        package let column: Int
    }

    package struct Violation: Equatable, Sendable {
        package let file: String
        package let position: Position
        package let rule: RuleID
        package let literal: Literal
        package let anchor: String
        package let ordinal: Int

        package var description: String {
            let label = rule == .discriminantValue ? "raw discriminant" : "raw key"
            let value = literal.kind == .interpolated ? "<interpolated>" : literal.value
            return "\(file):\(position.line):\(position.column): \(label) \"\(value)\" (\(rule.diagnostic))"
        }
    }
}
