import Foundation

enum ContractCompatibility {
    static func apply(
        graph: ContractGraph, rules: [ContractCompatibilityRule], projection: ContractProjectionRule? = nil
    ) throws -> ContractGraph {
        var result = graph
        if result.sourceNodes.isEmpty { result.sourceNodes = graph.nodes }
        var protected = try ContractTaggedGuard.protectedPointers(graph: graph, projection: projection)
        for rule in rules where rule.root == graph.rootID && rule.projection == graph.swiftName {
            guard !protected.contains(rule.pointer) else {
                throw graph.error(rule.pointer, "Compatibility cannot weaken a required tagged discriminator")
            }
            switch rule.operation {
            case .optional: try makeOptional(rule, graph: &result)
            case .additionalField:
                try addField(rule, graph: &result)
                protected.formUnion(try ContractTaggedGuard.protectedPointers(graph: result, projection: projection))
            case .nullable: try makeNullable(rule, graph: &result)
            case .enumValues, .openEnum: try changeEnum(rule, graph: &result)
            }
            result.projectionNotes.append("compatibility \(rule.id): \(rule.operation.rawValue) \(rule.pointer)")
        }
        return result
    }

    private static func fieldParent(_ pointer: String, graph: ContractGraph) throws -> (ContractNode, String) {
        guard let range = pointer.range(of: "/properties/", options: .backwards),
            !pointer[range.upperBound...].contains("/")
        else { throw graph.error(pointer, "Expected a record property pointer") }
        let parent = try graph.resolved(String(pointer[..<range.lowerBound]))
        let key = pointer[range.upperBound...].replacingOccurrences(of: "~1", with: "/")
            .replacingOccurrences(of: "~0", with: "~")
        guard case .object = parent.kind else { throw graph.error(pointer, "Property parent must be an object") }
        return (parent, key)
    }

    private static func makeOptional(_ rule: ContractCompatibilityRule, graph: inout ContractGraph) throws {
        _ = try graph.node(rule.pointer)
        var (parent, key) = try fieldParent(rule.pointer, graph: graph)
        guard case .object(var fields, let additional) = parent.kind,
            let index = fields.firstIndex(where: { $0.key == key }), fields[index].required
        else { throw graph.error(rule.pointer, "Optional compatibility requires a required source field") }
        fields[index] = .init(key: key, schema: fields[index].schema, required: false)
        parent.kind = .object(fields: fields, additional: additional)
        graph.nodes[parent.pointer] = parent
    }

    private static func addField(_ rule: ContractCompatibilityRule, graph: inout ContractGraph) throws {
        var (parent, key) = try fieldParent(rule.pointer, graph: graph)
        guard case .object(var fields, let additional) = parent.kind,
            !fields.contains(where: { $0.key == key }), let schema = rule.schema
        else { throw graph.error(rule.pointer, "Additional compatibility field must be new and have a schema") }
        let added = try ContractSchemaReader.read(value: schema, rootID: graph.rootID, pointer: rule.pointer)
        for (pointer, node) in added.nodes {
            guard graph.nodes[pointer] == nil else { throw graph.error(pointer, "Compatibility node collision") }
            graph.nodes[pointer] = node
        }
        fields.append(.init(key: key, schema: rule.pointer, required: rule.required ?? false))
        parent.kind = .object(fields: fields.sorted { $0.key < $1.key }, additional: additional)
        graph.nodes[parent.pointer] = parent
    }

    private static func makeNullable(_ rule: ContractCompatibilityRule, graph: inout ContractGraph) throws {
        guard !(try ContractEmitter(graph: graph).presence(rule.pointer).nullable) else {
            throw graph.error(rule.pointer, "Nullable compatibility requires a nonnullable source field")
        }
        let original = try graph.node(rule.pointer)
        let value = rule.pointer + "/compatibility/" + rule.id + "/value"
        let null = rule.pointer + "/compatibility/" + rule.id + "/null"
        graph.nodes[value] = .init(pointer: value, kind: original.kind, annotations: original.annotations)
        graph.nodes[null] = .init(pointer: null, kind: .null, annotations: [:])
        graph.nodes[rule.pointer] = .init(
            pointer: rule.pointer, kind: .union(.anyOf, [value, null]), annotations: original.annotations)
    }

    private static func changeEnum(_ rule: ContractCompatibilityRule, graph: inout ContractGraph) throws {
        let shape = try ContractEmitter(graph: graph).presence(rule.pointer)
        let base = try graph.resolved(shape.base)
        guard case .enumeration(let original) = base.kind else {
            throw graph.error(rule.pointer, "Enum compatibility requires a finite string enum")
        }
        let known = rule.pointer + "/compatibility/" + rule.id + "/known"
        let kind: ContractKind
        if rule.operation == .enumValues {
            guard let values = rule.values, !values.isEmpty,
                Set(original + values).count == original.count + values.count
            else { throw graph.error(rule.pointer, "Enum extension requires distinct new string values") }
            kind = .enumeration(original + values)
        } else {
            graph.nodes[known] = .init(pointer: known, kind: .enumeration(original), annotations: base.annotations)
            kind = .openEnum(known)
        }
        if shape.nullable {
            let value = rule.pointer + "/compatibility/" + rule.id + "/value"
            let null = rule.pointer + "/compatibility/" + rule.id + "/null"
            graph.nodes[value] = .init(pointer: value, kind: kind, annotations: base.annotations)
            graph.nodes[null] = .init(pointer: null, kind: .null, annotations: [:])
            graph.nodes[rule.pointer] = .init(
                pointer: rule.pointer, kind: .union(.anyOf, [value, null]), annotations: [:])
        } else {
            graph.nodes[rule.pointer] = .init(pointer: rule.pointer, kind: kind, annotations: base.annotations)
        }
    }
}
