import Foundation

/// Lite terminal events omit output already delivered by completed-item events.
/// Keep that output for the internal turn while preserving the provider's events.
struct ResponsesCompletedTurnOutput: Sendable {
    private var items: [Int: Data] = [:]

    mutating func record(_ item: [String: Any], at outputIndex: Int) throws {
        items[outputIndex] = try responsesStreamData(item)
    }

    func restoringEmptyOutput(in response: [String: Any], originalJSON: Data) throws -> Data {
        guard let output = response["output"] as? [Any], output.isEmpty, !items.isEmpty else {
            return originalJSON
        }
        var completedResponse = response
        completedResponse["output"] = try items.sorted { $0.key < $1.key }.map {
            try responsesStreamObject($0.value)
        }
        return try responsesStreamData(completedResponse)
    }
}
