import Foundation

package enum ResponsesCompactionError: Error, Equatable {
    case invalidRequest
    case invalidResponse
    /// A model selection the summary turn can retry once with the reason.
    case invalidSelection(String)
    case invalidPayload
    case unsupportedCompaction
    case responseTooLarge
}

/// Request-scoped compaction state never converts an original Responses item to a provider dialect.
package struct ResponsesCompactionPlan: Sendable {
    package let originalModel: String
    let requestJSON: Data
    let items: [Data]
    let imageItemIndices: Set<Int>
    let retention: ResponsesCompactionRetention
    let preservedStateIndices: Set<Int>
    private(set) var retainedStateIndices: Set<Int>
    /// Items dropped after a provider context overflow; they stay unquoted and
    /// unretained while their references keep their original positions.
    private(set) var omittedIndices: Set<Int>

    /// Same wording as Ollama's `compactionOmissionNotice`.
    package static func omissionNotice(count: Int) -> String {
        "Compaction warning: \(count) older transcript items were omitted before summarization "
            + "because the model's context limit was exceeded."
    }

    /// Removes the oldest removable items, targeting 20 percent of serialized
    /// transcript bytes — a fallback estimate, not a token budget. User
    /// messages, preserved state, the latest item, and half-finished tool
    /// exchanges stay; completed tool calls leave with their results. Returns
    /// the number of removed items, or zero when no progress is possible.
    /// Ported from Ollama's `TrimForContextLimit`.
    package mutating func trimForContextLimit() throws -> Int {
        // No image has been successfully inspected by this summary attempt yet.
        // Protect its complete dependency group even before an image rejection arrives.
        var protected = preservedStateIndices.union(retention.retaining(imageItemIndices))
        if let latest = items.indices.last { protected.insert(latest) }
        var callByID: [String: Int] = [:]
        var outputByID: [String: Int] = [:]
        var kinds: [Int: String] = [:]
        var roles: [Int: String] = [:]
        for (index, data) in items.enumerated() {
            let item = try ResponsesCompactionJSON.object(data, error: .invalidRequest)
            kinds[index] = item["type"] as? String
            roles[index] = item["role"] as? String
            guard let call = item["call_id"] as? String else { continue }
            if kinds[index] == "function_call" { callByID[call] = index }
            if kinds[index] == "function_call_output" { outputByID[call] = index }
        }
        var peers: [Int: Int] = [:]
        for (call, output) in outputByID {
            guard let input = callByID[call] else { continue }
            peers[input] = output
            peers[output] = input
        }
        let sizes = items.map(\.count)
        let total = sizes.reduce(0, +)
        var omitted: Set<Int> = []
        var removedBytes = 0
        for index in items.indices {
            if removedBytes >= (total + 4) / 5 { break }
            if protected.contains(index) || omitted.contains(index) || omittedIndices.contains(index) { continue }
            if kinds[index] == "function_call" || kinds[index] == "function_call_output" {
                // Half-finished tool state is never shed.
                guard let peer = peers[index], !protected.contains(peer) else { continue }
                omitted.insert(index)
                removedBytes += sizes[index]
                omitted.insert(peer)
                removedBytes += sizes[peer]
            } else if roles[index] == "assistant" {
                omitted.insert(index)
                removedBytes += sizes[index]
            }
        }
        guard !omitted.isEmpty else { return 0 }
        omittedIndices.formUnion(omitted)
        return omitted.count
    }

    package static func prepare(body: Data, providerID: UUID? = nil) throws -> Self? {
        let request = try ResponsesCompactionJSON.object(body, error: .invalidRequest)
        guard let rawInput = request["input"] as? [Any],
            rawInput.contains(where: { ($0 as? [String: Any])?["type"] as? String == "compaction_trigger" })
        else { return nil }
        guard let input = rawInput as? [[String: Any]], input.count > 1,
            input.last?["type"] as? String == "compaction_trigger",
            !input.dropLast().contains(where: { $0["type"] as? String == "compaction_trigger" }),
            request["stream"] as? Bool == true,
            !ResponsesConversationReferences.hasServerState(in: request),
            let model = ResponsesCompactionJSON.nonempty(request["model"])
        else { throw ResponsesCompactionError.invalidRequest }

        var expanded: [[String: Any]] = []
        var preservedStateIndices = Set<Int>()
        for item in input.dropLast() {
            let kind = try ResponsesCompactionJSON.kind(item, error: .invalidRequest)
            guard kind != "item_reference" else { throw ResponsesCompactionError.invalidRequest }
            if kind == "compaction", ResponsesCompactionJSON.nonempty(item["encrypted_content"]) == nil {
                throw ResponsesCompactionError.invalidRequest
            }
            let previous = try ResponsesCompactionPayload.expand(item: item)
            for entry in previous ?? [item] {
                let restoredForeignCheckpoint =
                    providerID != nil && previous != nil && entry["type"] as? String == "compaction"
                let nativeConfiguration = providerID != nil && entry["type"] as? String == "configuration_update"
                let foreignReasoning = try ResponsesProviderState.isForeignReasoning(entry, providerID: providerID)
                if restoredForeignCheckpoint || nativeConfiguration || foreignReasoning {
                    preservedStateIndices.insert(expanded.count)
                }
                expanded.append(entry)
            }
        }
        return Self(
            originalModel: model,
            requestJSON: body,
            items: try expanded.map(ResponsesCompactionJSON.data),
            imageItemIndices: try ResponsesCompactionImageRetention.indices(in: expanded),
            retention: try ResponsesCompactionRetention(
                items: expanded,
                preservedStateIndices: preservedStateIndices
            ),
            preservedStateIndices: preservedStateIndices,
            retainedStateIndices: preservedStateIndices,
            omittedIndices: []
        )
    }
}
