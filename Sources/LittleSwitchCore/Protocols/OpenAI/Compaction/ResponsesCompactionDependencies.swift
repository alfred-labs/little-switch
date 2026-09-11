import Foundation

/// Reasoning IDs require their following assistant outputs; tool calls require their results.
struct ResponsesCompactionDependencies: Sendable {
    private let edges: [Int: [Int]]

    init(items: [[String: Any]], toolPairs: [(Int, Int)]) throws {
        var edges: [Int: [Int]] = [:]
        var reasoningStart: Int?
        for (index, item) in items.enumerated() {
            let kind = try ResponsesCompactionJSON.kind(item, error: .invalidRequest)
            guard Self.isAssistantOutput(item, kind: kind) else {
                reasoningStart = nil
                continue
            }
            if let start = reasoningStart {
                edges[start, default: []].append(index)
                edges[index, default: []].append(start)
            } else if kind == "reasoning" {
                // A preceding synthetic summary is not an output of this reasoning item.
                reasoningStart = index
            }
        }
        for (call, result) in toolPairs {
            edges[call, default: []].append(result)
            edges[result, default: []].append(call)
        }
        self.edges = edges
    }

    func retaining(_ selected: Set<Int>) -> Set<Int> {
        var retained = selected
        var pending = Array(selected)
        while let index = pending.popLast() {
            for dependency in edges[index] ?? [] where retained.insert(dependency).inserted {
                pending.append(dependency)
            }
        }
        return retained
    }

    static func isAssistantOutput(_ item: [String: Any], kind: String) -> Bool {
        kind == "reasoning" || kind.hasSuffix("_call") || (kind == "message" && item["role"] as? String == "assistant")
    }
}
