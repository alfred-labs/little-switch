extension ContractSampleBuilder {
    /// Bounded witnesses: scalar/enum alternatives, union branches, empty/single-item
    /// arrays, and individual record-field alternatives. No Cartesian product is built.
    /// A valid schema may need a projection or a future extension of this search.
    func candidates(_ pointer: String, full: Bool, visiting: Set<String> = []) throws -> [ContractSampleValue] {
        let node = try graph.resolved(pointer)
        switch node.kind {
        case .enumeration(let values): return values.map(ContractSampleValue.string)
        case .scalar(.string): return [.string("wire sample"), .string(futureString()), .string("")]
        case .scalar(.boolean): return [.boolean(full), .boolean(!full)]
        case .openEnum(let known):
            return try candidates(known, full: full, visiting: visiting) + [.string(futureString())]
        case .opaque: return [.opaque, .null, .string("wire sample"), .array([]), .boolean(true), .number("1e400")]
        case .array(let item):
            var result = [try value(pointer, full: full, visiting: visiting), .array([])]
            let items = (try? candidates(item, full: full, visiting: visiting.union([node.pointer]))) ?? []
            for item in items { result.append(.array([item])) }
            return unique(result)
        case .object(let fields, _):
            return try recordCandidates(fields, pointer: node.pointer, full: full, visiting: visiting)
        case .union(_, let members):
            guard !visiting.contains(node.pointer) else { throw graph.error(pointer, "Recursive qualification value") }
            let possible = members.flatMap {
                (try? candidates($0, full: full, visiting: visiting.union([node.pointer]))) ?? []
            }
            return try unique(possible).filter { try ContractSampleMatcher(graph: graph).accepts($0, at: pointer) }
        case .scalar(.number), .booleanConstant, .null:
            return [try value(pointer, full: full, visiting: visiting)]
        case .reference: throw graph.error(pointer, "Unresolved qualification alias")
        }
    }

    private func recordCandidates(
        _ fields: [ContractField], pointer: String, full: Bool, visiting: Set<String>
    ) throws -> [ContractSampleValue] {
        let base = try recordFields(fields, pointer: pointer, full: full, visiting: visiting)
        var result: [ContractSampleValue] = [
            .object(base), .object(try recordFields(fields, pointer: pointer, full: !full, visiting: visiting)),
        ]
        for field in fields {
            let values = (try? candidates(field.schema, full: full, visiting: visiting.union([pointer]))) ?? []
            for value in values {
                var object = base
                object[field.key] = value
                result.append(.object(object))
            }
            if !field.required {
                var object = base
                object[field.key] = nil
                result.append(.object(object))
            }
        }
        return unique(result)
    }

    private func futureString() -> String {
        let values = Set(
            graph.nodes.values.flatMap { node -> [String] in
                if case .enumeration(let values) = node.kind { values } else { [] }
            })
        var value = "__wire_sample__"
        while values.contains(value) { value += "_" }
        return value
    }

    private func unique(_ values: [ContractSampleValue]) -> [ContractSampleValue] {
        values.reduce(into: []) { result, value in if !result.contains(value) { result.append(value) } }
    }
}
