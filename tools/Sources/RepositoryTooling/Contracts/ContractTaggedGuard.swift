import Foundation

/// Protects dispatch from schema edits that would turn a selected tagged union
/// into an untagged union with permissive fallback branches.
enum ContractTaggedGuard {
    static func protectedPointers(
        graph: ContractGraph, projection: ContractProjectionRule? = nil
    ) throws -> Set<String> {
        let graph = try selectingBranches(graph, projection: projection)
        let emitter = ContractEmitter(graph: graph)
        var protected: Set<String> = []
        for node in graph.nodes.values {
            guard case .union(_, let branches) = node.kind,
                let tag = try emitter.discriminator(branches, pointer: node.pointer)
            else { continue }
            for branch in branches {
                protected.formUnion(try referenceChain(branch, graph: graph))
                guard case .object(let fields, _) = try graph.resolved(branch).kind,
                    let field = fields.first(where: { $0.key == tag.key })
                else { continue }
                protected.formUnion(try referenceChain(field.schema, graph: graph))
            }
        }
        return protected
    }

    private static func selectingBranches(
        _ graph: ContractGraph, projection: ContractProjectionRule?
    ) throws -> ContractGraph {
        guard let projection else { return graph }
        var result = graph
        var selections: [(String, [Int])] = []
        if let indexes = projection.branches { selections.append((projection.pointer ?? "#", indexes)) }
        for pointer in (projection.nodes ?? [:]).keys.sorted() {
            if let indexes = projection.nodes?[pointer]?.branches { selections.append((pointer, indexes)) }
        }
        for (pointer, indexes) in selections {
            // An additionalField rule may introduce this node later. Full
            // projection validates every pointer after compatibility applies.
            guard result.nodes[pointer] != nil else { continue }
            var node = try result.resolved(pointer)
            // swiftlint:disable:next pattern_matching_keywords
            guard case .union(let kind, let branches) = node.kind,
                !indexes.isEmpty, Set(indexes).count == indexes.count,
                indexes.allSatisfy({ branches.indices.contains($0) })
            else { throw graph.error(pointer, "Invalid union branch selection") }
            node.kind = .union(kind, branches.enumerated().filter { indexes.contains($0.offset) }.map(\.element))
            result.nodes[node.pointer] = node
        }
        return result
    }

    private static func referenceChain(_ pointer: String, graph: ContractGraph) throws -> Set<String> {
        // discriminator() has resolved every selected branch and tag, rejecting
        // alias cycles before this immutable graph's reference paths are collected.
        var result: Set<String> = [pointer]
        var current = pointer
        while case .reference(let next) = try graph.node(current).kind {
            result.insert(next)
            current = next
        }
        return result
    }
}
