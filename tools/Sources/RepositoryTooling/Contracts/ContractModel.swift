import Foundation

struct ContractGenerationError: Error, Equatable, Sendable, CustomStringConvertible {
    let contract: String
    let pointer: String
    let reason: String

    init(contract: String, pointer: String = "#", reason: String) {
        self.contract = contract
        self.pointer = pointer
        self.reason = reason
    }

    var description: String { "\(contract) at \(pointer): \(reason)" }
}

struct GeneratedContractFile: Equatable, Sendable {
    let relativePath: String
    let source: String
}

struct ContractGraph: Sendable {
    let rootID: String
    var root: String
    var nodes: [String: ContractNode]
    var sourceNodes: [String: ContractNode] = [:]
    var swiftName: String
    var importModule: String?
    var projectionNotes: [String] = []
    var provenance: [String] = []
    var publicKeys = false
    var typeNames: [String: String] = [:]

    func node(_ pointer: String) throws -> ContractNode {
        guard let node = nodes[pointer] else {
            throw error(pointer, "Unresolved reference")
        }
        return node
    }

    func resolved(_ pointer: String, visited: Set<String> = []) throws -> ContractNode {
        let node = try node(pointer)
        guard case .reference(let target) = node.kind else { return node }
        guard !visited.contains(pointer) else { throw error(pointer, "Cyclic reference aliases") }
        return try resolved(target, visited: visited.union([pointer]))
    }

    func error(_ pointer: String, _ reason: String) -> ContractGenerationError {
        ContractGenerationError(contract: rootID, pointer: pointer, reason: reason)
    }
}

struct ContractNode: Sendable {
    let pointer: String
    var kind: ContractKind
    let annotations: [String: ContractSchemaValue]
}

enum ContractKind: Sendable {
    case scalar(ContractScalar)
    case enumeration([String])
    case booleanConstant(Bool)
    case openEnum(String)
    case null
    case opaque
    case object(fields: [ContractField], additional: ContractAdditionalFields)
    case array(String)
    case union(ContractUnionKind, [String])
    case reference(String)
}

enum ContractScalar: String, Sendable { case string, number, boolean }
enum ContractUnionKind: String, Sendable { case anyOf, oneOf }
enum ContractAdditionalFields: Sendable {
    case allowed, forbidden
    case typed(String)
}

struct ContractField: Sendable {
    let key: String
    let schema: String
    let required: Bool
}

/// Schema numbers are never used as wire values. Numeric assertions are rejected
/// by the bounded reader; wire `number` always maps to exact JSONNumber.
indirect enum ContractSchemaValue: Decodable, Sendable, Equatable {
    case object([String: Self])
    case array([Self])
    case string(String)
    case boolean(Bool)
    case null
    case number

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let text = try? value.decode(String.self) {
            self = .string(text)
        } else if let flag = try? value.decode(Bool.self) {
            self = .boolean(flag)
        } else if let array = try? value.decode([Self].self) {
            self = .array(array)
        } else if let object = try? value.decode([String: Self].self) {
            self = .object(object)
        } else {
            _ = try value.decode(Double.self)
            self = .number
        }
    }

    var object: [String: Self]? { if case .object(let value) = self { value } else { nil } }
    var array: [Self]? { if case .array(let value) = self { value } else { nil } }
    var string: String? { if case .string(let value) = self { value } else { nil } }
    var boolean: Bool? { if case .boolean(let value) = self { value } else { nil } }
}
