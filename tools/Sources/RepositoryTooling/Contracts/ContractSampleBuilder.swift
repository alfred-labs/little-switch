struct ContractSampleBuilder {
    let graph: ContractGraph

    func value(_ pointer: String, full: Bool = false, visiting: Set<String> = []) throws -> ContractSampleValue {
        let node = try graph.resolved(pointer)
        let presence = try ContractEmitter(graph: graph).presence(pointer)
        if presence.nullable, presence.base != node.pointer {
            return try value(presence.base, full: full, visiting: visiting)
        }
        switch node.kind {
        case .scalar(.string): return .string("wire sample")
        case .scalar(.number): return .number(full ? "1e400" : "9007199254740993")
        case .scalar(.boolean): return .boolean(full)
        case .enumeration(let values):
            guard let first = values.first else { throw graph.error(pointer, "Empty enum cannot be qualified") }
            return .string(first)
        case .booleanConstant(let value): return .boolean(value)
        case .openEnum(let known): return try value(known, full: full, visiting: visiting)
        case .null: return .null
        case .opaque: return .opaque
        case .array(let item):
            guard full, let first = try? value(item, visiting: visiting.union([node.pointer])) else {
                return .array([])
            }
            let nullable = try ContractEmitter(graph: graph).presence(item).nullable
            return .array(nullable ? [first, .null] : [first])
        case .object(let fields, _):
            return .object(try recordFields(fields, pointer: node.pointer, full: full, visiting: visiting))
        case .union(_, let members):
            return try unionValue(members, pointer: node.pointer, full: full, visiting: visiting)
        case .reference: throw graph.error(pointer, "Unresolved qualification alias")
        }
    }

    func recordFields(
        _ fields: [ContractField], pointer: String, full: Bool, visiting: Set<String> = []
    ) throws -> [String: ContractSampleValue] {
        guard !visiting.contains(pointer) else { throw graph.error(pointer, "Recursive qualification value") }
        var object: [String: ContractSampleValue] = [:]
        for field in fields where full || field.required {
            let child = try graph.resolved(field.schema)
            let expand: Bool
            switch child.kind {
            case .object, .union: expand = false
            default: expand = full
            }
            object[field.key] = try value(field.schema, full: expand, visiting: visiting.union([pointer]))
        }
        return object
    }

    private func unionValue(
        _ members: [String], pointer: String, full: Bool, visiting: Set<String>
    ) throws -> ContractSampleValue {
        guard !visiting.contains(pointer) else { throw graph.error(pointer, "Recursive qualification value") }
        let matcher = ContractSampleMatcher(graph: graph)
        for member in members {
            if let baseline = try? value(member, full: full, visiting: visiting.union([pointer])) {
                if try matcher.accepts(baseline, at: pointer) { return baseline }
            }
            let values = (try? candidates(member, full: full, visiting: visiting.union([pointer]))) ?? []
            if let sample = try values.first(where: { try matcher.accepts($0, at: pointer) }) { return sample }
        }
        throw graph.error(pointer, "Automatic qualification cannot construct an accepted union witness")
    }
}
