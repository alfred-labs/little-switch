import Foundation

enum ContractSwiftNames {
    static func type(_ name: String) -> String { identifier(name, upper: true) }
    static func member(_ name: String) -> String {
        var result = identifier(name, upper: false)
        if result.count == 1, result != "x", result != "y" { result = "value" + result.uppercased() }
        return reserved.contains(result) ? "`\(result)`" : result
    }

    static func enumCase(_ name: String, value: String) -> String {
        let spelling = name.replacingOccurrences(of: "`", with: "")
        return "case " + name + (spelling == value ? "" : " = " + string(value))
    }

    static func string(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 0...31, 127: result += "\\u{\(String(scalar.value, radix: 16))}"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    static func unique(_ values: [String], contract: String, pointer: String) throws {
        guard Set(values).count == values.count else {
            throw ContractGenerationError(contract: contract, pointer: pointer, reason: "Swift name collision")
        }
    }

    private static func identifier(_ value: String, upper: Bool) -> String {
        let words = value.split { !$0.isASCII || !$0.isLetter && !$0.isNumber }
        var result = words.enumerated()
            .map { index, word in
                let text = String(word)
                guard let first = text.first else { return "" }
                return (index == 0 && !upper ? first.lowercased() : first.uppercased()) + text.dropFirst()
            }
            .joined()
        if result.isEmpty { result = "value" }
        if result.first?.isNumber == true { result = "value" + result }
        return result
    }

    private static let reserved: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init", "inout",
        "internal", "let", "open", "operator", "private", "precedencegroup", "protocol", "public", "rethrows", "static",
        "struct", "subscript", "typealias", "var", "break", "case", "continue", "default", "defer", "do", "else",
        "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while", "as", "Any", "catch",
        "false", "is", "nil", "self", "Self", "super", "throw", "throws", "true", "try",
    ]
}
