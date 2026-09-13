enum ContractScalarUnion {
    /// An unconstrained scalar subsumes literals of that same scalar. No other
    /// assertion is removed, and null stays an independent union branch.
    static func normalize(_ graph: ContractGraph) throws -> ContractGraph {
        var result = graph
        result.sourceNodes = graph.nodes
        for node in graph.nodes.values {
            guard case .union(.anyOf, let members) = node.kind else { continue }
            let branches = try members.map { try graph.resolved($0) }
            guard let scalarNode = branches.first(where: { if case .scalar = $0.kind { true } else { false } }),
                case .scalar(let scalar) = scalarNode.kind
            else { continue }
            let compatible = branches.allSatisfy { branch in
                switch branch.kind {
                case .scalar(let other): return scalar == other
                case .enumeration: return scalar == .string
                case .booleanConstant: return scalar == .boolean
                case .null: return true
                default: return false
                }
            }
            guard compatible else { continue }
            let null = branches.first { if case .null = $0.kind { true } else { false } }
            var normalized = node
            normalized.kind =
                null.map { .union(.anyOf, [scalarNode.pointer, $0.pointer]) } ?? .reference(scalarNode.pointer)
            result.nodes[node.pointer] = normalized
        }
        return result
    }
}
