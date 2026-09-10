import Foundation

struct AnthropicServerToolIDSequence: Sendable {
    private let baseID: String
    private var issuedCount = 0

    init(eventID: UUID) {
        let normalizedEventID = eventID.uuidString.replacingOccurrences(of: "-", with: "")
        baseID = "srvtoolu_\(normalizedEventID)"
    }

    mutating func next() -> String {
        issuedCount += 1
        guard issuedCount > 1 else {
            return baseID
        }
        return "\(baseID)_\(issuedCount)"
    }
}
