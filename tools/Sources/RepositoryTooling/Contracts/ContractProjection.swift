import Foundation

enum ContractProjection {
    static func apply(graph: ContractGraph, rule: ContractProjectionRule) throws -> ContractGraph {
        var result = graph
        if result.sourceNodes.isEmpty { result.sourceNodes = graph.nodes }
        result.root = rule.pointer ?? "#"
        result.swiftName = rule.swiftName
        result.importModule = rule.importModule
        result.publicKeys = rule.publicKeys ?? false
        guard ContractSwiftNames.type(rule.swiftName) == rule.swiftName else {
            throw graph.error(result.root, "swiftName must be a stable Swift type identifier")
        }
        if let module = rule.importModule, module != "LittleSwitchWire" {
            throw graph.error(result.root, "Only the LittleSwitchWire fixture import is supported")
        }
        let selected = try result.resolved(result.root)
        let rootSelection = ContractNodeProjection(fields: rule.fields, branches: rule.branches, name: nil)
        try select(rootSelection, at: selected.pointer, graph: &result)
        for pointer in (rule.nodes ?? [:]).keys.sorted() {
            if let selection = rule.nodes?[pointer] { try select(selection, at: pointer, graph: &result) }
        }
        let protected = try ContractTaggedGuard.protectedPointers(graph: result)
        for pointer in rule.opaque ?? [] {
            guard !protected.contains(pointer) else {
                throw graph.error(pointer, "Opaque projection cannot erase a selected tagged branch or discriminator")
            }
            var node = try result.node(pointer)
            node.kind = .opaque
            result.nodes[pointer] = node
            result.projectionNotes.append("opaque " + pointer)
        }
        if result.publicKeys, !(try hasReachableRecordKeys(result.root, graph: result)) {
            throw graph.error(result.root, "Public keys require a selected record with known fields")
        }
        return result
    }

    private static func hasReachableRecordKeys(
        _ pointer: String, graph: ContractGraph, visited: Set<String> = []
    ) throws -> Bool {
        let node = try graph.resolved(pointer)
        guard !visited.contains(node.pointer) else { return false }
        let visited = visited.union([node.pointer])
        switch node.kind {
        // swiftlint:disable:next pattern_matching_keywords
        case .object(let fields, let additional):
            if !fields.isEmpty { return true }
            guard case .typed(let value) = additional else { return false }
            return try hasReachableRecordKeys(value, graph: graph, visited: visited)
        case .union(_, let branches):
            return try branches.contains { try hasReachableRecordKeys($0, graph: graph, visited: visited) }
        case .array(let item):
            return try hasReachableRecordKeys(item, graph: graph, visited: visited)
        case .reference, .scalar, .enumeration, .booleanConstant, .openEnum, .null, .opaque:
            return false
        }
    }

    private static func select(_ rule: ContractNodeProjection, at pointer: String, graph: inout ContractGraph) throws {
        var selected = try graph.resolved(pointer)
        if let name = rule.name {
            guard ContractSwiftNames.type(name) == name else {
                throw graph.error(pointer, "Nested name must be a stable Swift type identifier")
            }
            graph.typeNames[selected.pointer] = name
        }
        if let indexes = rule.branches {
            // swiftlint:disable:next pattern_matching_keywords
            guard case .union(let kind, let branches) = selected.kind,
                !indexes.isEmpty, Set(indexes).count == indexes.count,
                indexes.allSatisfy({ branches.indices.contains($0) })
            else {
                throw graph.error(selected.pointer, "Invalid union branch selection")
            }
            selected.kind = .union(kind, branches.enumerated().filter { indexes.contains($0.offset) }.map(\.element))
            graph.nodes[selected.pointer] = selected
            graph.projectionNotes.append(
                pointer + " branches " + indexes.sorted().map(String.init).joined(separator: ", "))
        }
        if let keys = rule.fields {
            guard case .object(let fields, _) = selected.kind else {
                throw graph.error(selected.pointer, "Field projection requires an object")
            }
            guard Set(keys).count == keys.count, Set(keys).isSubset(of: Set(fields.map(\.key))) else {
                throw graph.error(selected.pointer, "Unknown or repeated projected field")
            }
            let isUnionBranch = try graph.nodes.values.contains { node in
                guard case .union(_, let members) = node.kind else { return false }
                return try members.contains { try graph.resolved($0).pointer == selected.pointer }
            }
            let retained = try fields.filter { field in
                if keys.contains(field.key) { return true }
                guard isUnionBranch else { return false }
                switch try graph.resolved(field.schema).kind {
                case .enumeration(let values): return values.count == 1
                case .booleanConstant: return true
                default: return false
                }
            }
            selected.kind = .object(fields: retained, additional: .allowed)
            graph.nodes[selected.pointer] = selected
            graph.projectionNotes.append(pointer + " fields " + retained.map(\.key).joined(separator: ", "))
        }
    }
}

struct ContractProjectionManifest: Decodable {
    let formatVersion: Int
    let contracts: [ContractProjectionRule]

    static func read(_ data: Data) throws -> Self {
        do { return try decode(data) } catch let error as ContractGenerationError { throw error } catch {
            throw ContractGenerationError(contract: "projections", reason: "Invalid projection manifest: \(error)")
        }
    }

    private static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(ContractSchemaValue.self, from: data)
        guard let object = value.object, Set(object.keys) == ["formatVersion", "contracts"],
            let rules = object["contracts"]?.array
        else {
            throw ContractGenerationError(contract: "projections", reason: "Invalid projection manifest")
        }
        let allowed: Set<String> = [
            "root", "schema", "pointer", "swiftName", "fields", "opaque", "branches", "output", "importModule",
            "publicKeys", "nodes",
        ]
        for rule in rules {
            guard let fields = rule.object, Set(fields.keys).isSubset(of: allowed) else {
                throw ContractGenerationError(contract: "projections", reason: "Unknown projection option")
            }
            if let nodes = fields["nodes"] {
                guard let nodes = nodes.object,
                    nodes.values.allSatisfy({
                        $0.object.map { Set($0.keys).isSubset(of: ["fields", "branches", "name"]) } == true
                    })
                else {
                    throw ContractGenerationError(contract: "projections", reason: "Unknown nested projection option")
                }
            }
        }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.formatVersion == 1 else {
            throw ContractGenerationError(contract: "projections", reason: "Unsupported format version")
        }
        return result
    }
}

struct ContractProjectionRule: Codable {
    let root: String
    let schema: String?
    let pointer: String?
    let swiftName: String
    let fields: [String]?
    let opaque: [String]?
    let branches: [Int]?
    let publicKeys: Bool?
    let output: String?
    let importModule: String?
    let nodes: [String: ContractNodeProjection]?
}

struct ContractNodeProjection: Codable {
    let fields: [String]?
    let branches: [Int]?
    let name: String?
}
