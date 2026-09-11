import CoreFoundation
import Foundation

package enum ResponsesCompactionError: Error, Equatable {
    case invalidRequest
    case invalidResponse
    case invalidPayload
    case unsupportedCompaction
}

package enum ResponsesCompactionInputMode: Equatable, Sendable {
    case transcript
    case nativeContinuation
}

package struct ResponsesCompactionResult: Sendable {
    package let itemJSON: Data
    package let usage: ResponsesUsage
}

/// Request-scoped compaction state never converts an original Responses item to a provider dialect.
package struct ResponsesCompactionPlan: Sendable {
    package let originalModel: String
    let requestJSON: Data
    let items: [Data]
    let retention: ResponsesCompactionRetention
    let preservedStateIndices: Set<Int>
    private let providerStateIndices: Set<Int>
    private(set) var retainedStateIndices: Set<Int>

    /// Recovery preserves source positions without changing what the summary model can read.
    package func retainingProviderState() -> Self {
        var result = self
        result.retainedStateIndices.formUnion(providerStateIndices)
        return result
    }

    package static func prepare(body: Data, providerID: UUID? = nil) throws -> Self? {
        let request = try ResponsesCompactionJSON.object(body, error: .invalidRequest)
        guard let rawInput = request["input"] as? [Any],
            rawInput.contains(where: { ($0 as? [String: Any])?["type"] as? String == "compaction_trigger" })
        else { return nil }
        guard let input = rawInput as? [[String: Any]], input.count > 1,
            input.last?["type"] as? String == "compaction_trigger",
            !input.dropLast().contains(where: { $0["type"] as? String == "compaction_trigger" }),
            let stream = request["stream"] as? NSNumber,
            CFGetTypeID(stream) == CFBooleanGetTypeID(), stream.boolValue,
            !ResponsesConversationReferences.hasServerState(in: request),
            let model = ResponsesCompactionJSON.nonempty(request["model"])
        else { throw ResponsesCompactionError.invalidRequest }

        var expanded: [[String: Any]] = []
        var preservedStateIndices = Set<Int>()
        var providerStateIndices = Set<Int>()
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
                if ["reasoning", "compaction", "configuration_update"].contains(entry["type"] as? String ?? "") {
                    providerStateIndices.insert(expanded.count)
                }
                expanded.append(entry)
            }
        }
        return Self(
            originalModel: model,
            requestJSON: body,
            items: try expanded.map(ResponsesCompactionJSON.data),
            retention: try ResponsesCompactionRetention(
                items: expanded,
                preservedStateIndices: preservedStateIndices
            ),
            preservedStateIndices: preservedStateIndices,
            providerStateIndices: providerStateIndices,
            retainedStateIndices: preservedStateIndices
        )
    }
}
