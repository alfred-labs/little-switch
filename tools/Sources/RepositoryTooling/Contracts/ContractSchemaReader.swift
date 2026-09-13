import Foundation

enum ContractSchemaReader {
    static func read(data: Data, rootID: String) throws -> ContractGraph {
        let value: ContractSchemaValue
        do { value = try JSONDecoder().decode(ContractSchemaValue.self, from: data) } catch {
            throw ContractGenerationError(contract: rootID, reason: "Invalid schema JSON")
        }
        return try read(value: value, rootID: rootID, pointer: "#")
    }

    static func read(value: ContractSchemaValue, rootID: String, pointer: String) throws -> ContractGraph {
        var reader = Reader(rootID: rootID)
        try reader.read(value, at: pointer)
        let graph = ContractGraph(rootID: rootID, root: pointer, nodes: reader.nodes, swiftName: rootID)
        for node in reader.nodes.values {
            if case .reference(let target) = node.kind { _ = try graph.node(target) }
        }
        return try ContractScalarUnion.normalize(graph)
    }
}

private struct Reader {
    let rootID: String
    var nodes: [String: ContractNode] = [:]
    private static let annotations: Set<String> = [
        "$schema", "$id", "title", "description", "$comment", "default", "examples", "deprecated", "readOnly",
        "writeOnly",
    ]
    private static let assertions: Set<String> = [
        "$ref", "definitions", "type", "properties", "required", "additionalProperties", "items", "anyOf", "oneOf",
        "enum", "const",
    ]

    mutating func read(_ value: ContractSchemaValue, at pointer: String) throws {
        guard let object = value.object else { throw error(pointer, "Expected a schema object") }
        if let unknown = object.keys.sorted().first(where: { !Self.annotations.union(Self.assertions).contains($0) }) {
            throw error(pointer + "/" + escape(unknown), "Unsupported assertion \(unknown)")
        }
        if let dialect = object["$schema"]?.string, dialect != "http://json-schema.org/draft-07/schema#" {
            throw error(pointer + "/$schema", "Unsupported schema dialect")
        }
        if let definitions = object["definitions"] {
            guard let entries = definitions.object else {
                throw error(pointer + "/definitions", "Expected definitions object")
            }
            for key in entries.keys.sorted() {
                if let value = entries[key] { try read(value, at: pointer + "/definitions/" + escape(key)) }
            }
        }
        let assertions = object.filter { !Self.annotations.contains($0.key) && $0.key != "definitions" }
        let kind = try kind(assertions, at: pointer)
        nodes[pointer] = ContractNode(
            pointer: pointer, kind: kind, annotations: object.filter { Self.annotations.contains($0.key) })
    }

    private mutating func kind(_ object: [String: ContractSchemaValue], at pointer: String) throws -> ContractKind {
        if let reference = object["$ref"] {
            guard object.count == 1, let target = reference.string, target == "#" || target.hasPrefix("#/") else {
                throw error(pointer, "Only local references without sibling assertions are supported")
            }
            return .reference(target)
        }
        if object["anyOf"] != nil || object["oneOf"] != nil {
            guard object.count == 1 else { throw error(pointer, "Union with sibling assertions requires a projection") }
            let union: ContractUnionKind = object["anyOf"] == nil ? .oneOf : .anyOf
            guard let branches = object[union.rawValue]?.array, !branches.isEmpty else {
                throw error(pointer, "Expected nonempty union branches")
            }
            let paths = branches.indices.map { pointer + "/\(union.rawValue)/\($0)" }
            for (branch, path) in zip(branches, paths) { try read(branch, at: path) }
            return .union(union, paths)
        }
        if let types = object["type"]?.array {
            return try typeUnion(object, types: types, at: pointer)
        }
        if object["enum"] != nil || object["const"] != nil { return try literal(object, at: pointer) }
        guard let type = object["type"]?.string else {
            guard object.isEmpty else { throw error(pointer, "Schema assertions require an explicit type") }
            return .opaque
        }
        switch type {
        case "object": return try record(object, at: pointer)
        case "array":
            try allow(object, keys: ["type", "items"], at: pointer)
            guard let items = object["items"] else { throw error(pointer + "/items", "Array items are required") }
            try read(items, at: pointer + "/items")
            return .array(pointer + "/items")
        case "string", "number", "boolean":
            try allow(object, keys: ["type"], at: pointer)
            guard let scalar = ContractScalar(rawValue: type) else { throw error(pointer, "Unknown scalar") }
            return .scalar(scalar)
        case "null":
            try allow(object, keys: ["type"], at: pointer)
            return .null
        default:
            throw error(
                pointer + "/type", "Unsupported type \(type); integer specialization needs an explicit sourced rule")
        }
    }

    private mutating func typeUnion(
        _ object: [String: ContractSchemaValue], types: [ContractSchemaValue], at pointer: String
    ) throws -> ContractKind {
        let names = types.compactMap(\.string)
        guard !names.isEmpty, names.count == types.count, Set(names).count == names.count else {
            throw error(pointer + "/type", "Expected distinct JSON type names")
        }
        var paths: [String] = []
        for (index, type) in names.enumerated() {
            var branch = object
            branch["type"] = .string(type)
            if let values = object["enum"]?.array {
                let matching = values.filter { type == "null" ? $0 == .null : $0 != .null }
                if matching.isEmpty { continue }
                if type == "null" { branch["enum"] = nil } else { branch["enum"] = .array(matching) }
            }
            let path = pointer + "/type/\(index)"
            try read(.object(branch), at: path)
            paths.append(path)
        }
        guard !paths.isEmpty else { throw error(pointer, "Unsatisfiable type and enum constraints") }
        if paths.count == 1, let path = paths.first { return .reference(path) }
        return .union(.anyOf, paths)
    }

    private func literal(_ object: [String: ContractSchemaValue], at pointer: String) throws -> ContractKind {
        try allow(object, keys: ["type", "enum", "const"], at: pointer)
        guard object["enum"] == nil || object["const"] == nil else {
            throw error(pointer, "Combined enum and const is unsupported")
        }
        let values = object["enum"]?.array ?? object["const"].map { [$0] } ?? []
        guard !values.isEmpty, Set(values.compactMap(\.string)).count == values.count else {
            let booleanType = object["type"] == nil || object["type"] == .string("boolean")
            if values.count == 1, let flag = values[0].boolean, booleanType {
                return .booleanConstant(flag)
            }
            throw error(pointer, "Only distinct string enums and boolean constants are supported")
        }
        guard object["type"] == nil || object["type"] == .string("string") else {
            throw error(pointer, "Enum type mismatch")
        }
        return .enumeration(values.compactMap(\.string))
    }

    private mutating func record(_ object: [String: ContractSchemaValue], at pointer: String) throws -> ContractKind {
        try allow(object, keys: ["type", "properties", "required", "additionalProperties"], at: pointer)
        let properties = object["properties"]?.object ?? [:]
        guard object["properties"] == nil || object["properties"]?.object != nil else {
            throw error(pointer, "Invalid properties")
        }
        let requiredValues = object["required"]?.array ?? []
        let required = Set(requiredValues.compactMap(\.string))
        guard requiredValues.count == required.count, object["required"] == nil || object["required"]?.array != nil,
            required.isSubset(of: Set(properties.keys))
        else { throw error(pointer + "/required", "Invalid required keys") }
        var fields: [ContractField] = []
        for key in properties.keys.sorted() {
            let path = pointer + "/properties/" + escape(key)
            if let schema = properties[key] { try read(schema, at: path) }
            fields.append(ContractField(key: key, schema: path, required: required.contains(key)))
        }
        let additional: ContractAdditionalFields
        switch object["additionalProperties"] {
        case nil, .boolean(true): additional = .allowed
        case .boolean(false): additional = .forbidden
        case .object:
            let path = pointer + "/additionalProperties"
            if let value = object["additionalProperties"] { try read(value, at: path) }
            additional = .typed(path)
        default: throw error(pointer + "/additionalProperties", "Invalid additional properties schema")
        }
        return .object(fields: fields, additional: additional)
    }

    private func allow(_ object: [String: ContractSchemaValue], keys: Set<String>, at pointer: String) throws {
        if let unsupported = object.keys.sorted().first(where: { !keys.contains($0) }) {
            throw error(pointer + "/" + escape(unsupported), "Unsupported assertion combination")
        }
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }
    private func error(_ pointer: String, _ reason: String) -> ContractGenerationError {
        ContractGenerationError(contract: rootID, pointer: pointer, reason: reason)
    }
}
