/// Tests qualification witnesses against the supported projected schema semantics.
/// This does not replace or relax the generated wire codecs.
struct ContractSampleMatcher {
    let graph: ContractGraph

    func accepts(_ value: ContractSampleValue, at pointer: String, visiting: Set<String> = []) throws -> Bool {
        let node = try graph.resolved(pointer)
        switch node.kind {
        case .scalar(.string), .openEnum: return if case .string = value { true } else { false }
        case .scalar(.number): return if case .number = value { true } else { false }
        case .scalar(.boolean): return if case .boolean = value { true } else { false }
        case .enumeration(let values):
            return if case .string(let literal) = value { values.contains(literal) } else { false }
        case .booleanConstant(let literal): return value == .boolean(literal)
        case .null: return value == .null
        case .opaque: return true
        case .array(let item):
            guard case .array(let values) = value else { return false }
            return try values.allSatisfy { try accepts($0, at: item) }
        // swiftlint:disable:next pattern_matching_keywords
        case .object(let fields, let additional):
            guard case .object(let values) = value else { return false }
            return try accepts(values, fields: fields, additional: additional)
        // swiftlint:disable:next pattern_matching_keywords
        case .union(let kind, let members):
            return try acceptsUnion(value, members: members, kind: kind, pointer: node.pointer, visiting: visiting)
        case .reference: throw graph.error(pointer, "Unresolved qualification alias")
        }
    }

    private func acceptsUnion(
        _ value: ContractSampleValue,
        members: [String],
        kind: ContractUnionKind,
        pointer: String,
        visiting: Set<String>
    ) throws -> Bool {
        guard !visiting.contains(pointer) else { return false }
        let emitter = ContractEmitter(graph: graph)
        if let tag = try emitter.discriminator(members, pointer: pointer) {
            guard case .object(let fields) = value, case .string(let label)? = fields[tag.key] else { return false }
            guard let index = tag.values.firstIndex(of: label) else { return true }
            return try accepts(value, at: members[index], visiting: visiting.union([pointer]))
        }
        let matched = try members.filter { try accepts(value, at: $0, visiting: visiting.union([pointer])) }.count
        return kind == .oneOf ? matched == 1 : matched > 0
    }

    private func accepts(
        _ values: [String: ContractSampleValue], fields: [ContractField], additional: ContractAdditionalFields
    ) throws -> Bool {
        for field in fields {
            if let value = values[field.key] {
                guard try accepts(value, at: field.schema) else { return false }
            } else if field.required {
                return false
            }
        }
        let known = Set(fields.map(\.key))
        for (key, value) in values where !known.contains(key) {
            switch additional {
            case .allowed: break
            case .forbidden: return false
            case .typed(let schema):
                guard try accepts(value, at: schema) else { return false }
            }
        }
        return true
    }
}
