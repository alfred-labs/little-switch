import Foundation
import LittleSwitchWire

/// Lite terminal events omit output already delivered by completed-item events.
/// Keep that output for the internal turn while preserving the provider's events.
struct ResponsesCompletedTurnOutput: Sendable {
    private var items: [Int: JSONValue] = [:]

    mutating func record(_ item: JSONValue, at outputIndex: Int) {
        items[outputIndex] = item
    }

    /// An empty Lite snapshot refers to completed events. A nonempty snapshot
    /// remains authoritative and must be checked against those events by its consumer.
    func resolvedItems(for output: [JSONValue]) -> [(index: Int, item: JSONValue)] {
        if output.isEmpty { return items.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } }
        return output.enumerated().map { ($0.offset, $0.element) }
    }

    func restoringEmptyOutput(in response: OpenAIResponsesResponse, originalJSON: Data) throws -> Data {
        var completedResponse = response
        guard completedResponse.output?.isEmpty == true, !items.isEmpty else {
            return originalJSON
        }
        completedResponse.output = resolvedItems(for: []).map(\.item)
        return try WireCodec.encode(completedResponse)
    }
}
