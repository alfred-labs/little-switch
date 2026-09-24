import Foundation

package enum ChatGPTHistoryError: Error, Equatable, Sendable {
    case notFound, busy, invalidInput, capacityExceeded, invalidStorage, unsupportedVersion, unsafeStorage,
        persistenceFailed
}

package struct ChatGPTHistoryPatch: Sendable {
    package var title: String?
    package var archived: Bool?
    package var starred: Bool?
    package var currentNodeID: String?

    package init(title: String? = nil, archived: Bool? = nil, starred: Bool? = nil, currentNodeID: String? = nil) {
        self.title = title
        self.archived = archived
        self.starred = starred
        self.currentNodeID = currentNodeID
    }
}

package struct ChatGPTPendingTurn: Sendable {
    package let conversationID: String
    package let assistantID: String
    package let parentID: String
    package let title: String
    package let timestamp: Double
    package let history: [ChatGPTConversationTurn]
}

package struct ChatGPTHistoryNode: Codable, Equatable, Sendable {
    package let id: String
    package let parentID: String
    package let role: ChatGPTConversationTurn.Role
    package var text: String
    package let model: String?
    package let createdAt: Double
    package var updatedAt: Double
    package var status: ChatGPTNativeMessage.Status
}

package struct ChatGPTStoredConversation: Codable, Equatable, Sendable {
    package let id: String
    package let owner: String
    package let rootID: String
    package var title: String
    package let createdAt: Double
    package var updatedAt: Double
    package var currentNodeID: String
    package var archived: Bool
    package var starred: Bool
    package let temporary: Bool
    package var nodes: [String: ChatGPTHistoryNode]
}
