import Foundation

package enum ChatGPTConversationError: Error, Equatable, Sendable {
    case invalidRequest
    case unsupportedRequest
    case limitExceeded
    case invalidStream
    case providerFailed
    case unsupportedOutput
    case missingCompletion
    case inconsistentOutput
}

package enum ChatGPTConversationLimits {
    package static let maximumBodyBytes = 8 * 1_024 * 1_024
    package static let maximumTextBytes = 4 * 1_024 * 1_024
    package static let maximumMessages = 8
    package static let maximumHistoryMessages = 128
    package static let maximumFrameBytes = 8 * 1_024 * 1_024
}

package enum ChatGPTConversationID {
    package static func make() -> String {
        "1e1771e5-" + UUID().uuidString.lowercased().dropFirst(9)
    }

    package static func isOwned(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return uuid.uuidString.lowercased().hasPrefix("1e1771e5-")
    }
}
