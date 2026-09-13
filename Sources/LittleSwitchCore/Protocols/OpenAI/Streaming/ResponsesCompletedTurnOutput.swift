import Foundation
import LittleSwitchWire

/// Lite terminal events omit output already delivered by completed-item events.
/// Keep that output for the internal turn while preserving the provider's events.
struct ResponsesCompletedTurnOutput: Sendable {
    private var items: [Int: JSONValue] = [:]

    mutating func record(_ item: JSONValue, at outputIndex: Int) {
        items[outputIndex] = item
    }

    func restoringEmptyOutput(in response: OpenAIResponsesResponse, originalJSON: Data) throws -> Data {
        var completedResponse = response
        guard completedResponse.output?.isEmpty == true, !items.isEmpty else {
            return originalJSON
        }
        completedResponse.output = items.sorted { $0.key < $1.key }.map(\.value)
        return try WireCodec.encode(completedResponse)
    }
}
