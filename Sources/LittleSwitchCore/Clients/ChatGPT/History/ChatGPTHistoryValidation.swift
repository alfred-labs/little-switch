import Foundation

enum ChatGPTHistoryValidation {
    static func ownedID(_ value: String) -> Bool {
        identifier(value) && ChatGPTConversationID.isOwned(value)
    }

    static func identifier(_ value: String) -> Bool {
        UUID(uuidString: value)?.uuidString.lowercased() == value
    }

    static func owner(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func request(_ request: ChatGPTConversationRequest, owner account: String, now: Double) throws {
        guard owner(account), now.isFinite,
            request.parentMessageID.map(identifier) ?? (request.conversationID == nil),
            !request.messages.isEmpty, request.messages.count <= ChatGPTConversationLimits.maximumMessages,
            !request.model.isEmpty, request.model == request.model.trimmingCharacters(in: .whitespacesAndNewlines),
            request.messages.allSatisfy({ identifier($0.id) })
        else { throw ChatGPTHistoryError.invalidInput }
    }

    static func bounds(_ value: ChatGPTStoredConversation, limits: ChatGPTHistoryStore.Limits) throws {
        guard value.nodes.count <= limits.nodesPerConversation else { throw ChatGPTHistoryError.capacityExceeded }
        var remaining = limits.textBytesPerConversation
        for node in value.nodes.values {
            let size = node.text.utf8.count
            guard size <= remaining else { throw ChatGPTHistoryError.capacityExceeded }
            remaining -= size
        }
    }

    static func stored(_ value: ChatGPTStoredConversation, key: String, limits: ChatGPTHistoryStore.Limits) throws {
        try bounds(value, limits: limits)
        guard key == value.id, ownedID(value.id), owner(value.owner), identifier(value.rootID),
            !value.temporary, value.nodes[value.rootID] == nil, value.contains(value.currentNodeID),
            value.createdAt.isFinite, value.updatedAt.isFinite,
            !value.title.isEmpty, value.title.count <= 256,
            value.title == value.title.trimmingCharacters(in: .whitespacesAndNewlines), !value.nodes.isEmpty
        else { throw ChatGPTHistoryError.invalidStorage }
        var inProgress = 0
        for (key, node) in value.nodes {
            guard key == node.id, identifier(node.id), identifier(node.parentID), value.contains(node.parentID),
                node.createdAt.isFinite, node.updatedAt.isFinite
            else { throw ChatGPTHistoryError.invalidStorage }
            switch node.role {
            case .user:
                guard node.model == nil, node.status == .finishedSuccessfully else {
                    throw ChatGPTHistoryError.invalidStorage
                }
            case .assistant:
                guard let model = node.model, !model.isEmpty,
                    model == model.trimmingCharacters(in: .whitespacesAndNewlines),
                    value.nodes[node.parentID]?.role == .user
                else { throw ChatGPTHistoryError.invalidStorage }
            }
            if node.status == .inProgress {
                inProgress += 1
                guard node.id == value.currentNodeID else { throw ChatGPTHistoryError.invalidStorage }
            }
            _ = try value.ancestry(of: node.id)
        }
        guard inProgress <= 1 else { throw ChatGPTHistoryError.invalidStorage }
    }
}

extension ChatGPTStoredConversation {
    func contains(_ node: String) -> Bool { node == rootID || nodes[node] != nil }

    func ancestry(of parent: String) throws -> [ChatGPTConversationTurn] {
        var turns: [ChatGPTConversationTurn] = []
        var seen = Set<String>()
        var current = parent
        while current != rootID {
            guard seen.insert(current).inserted, let node = nodes[current] else {
                throw ChatGPTHistoryError.invalidStorage
            }
            turns.append(ChatGPTConversationTurn(role: node.role, text: node.text))
            current = node.parentID
        }
        return turns.reversed()
    }
}
