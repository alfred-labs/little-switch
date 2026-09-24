import Foundation

extension ChatGPTStoredConversation {
    package func nativeData() throws -> Data {
        var children: [String: [String]] = [:]
        for node in nodes.values { children[node.parentID, default: []].append(node.id) }
        var mapping: [String: [String: Any]] = [
            rootID: [
                ChatGPTNativeContract.HistoryField.id.rawValue: rootID,
                ChatGPTNativeContract.HistoryField.message.rawValue: NSNull(),
                ChatGPTNativeContract.HistoryField.parent.rawValue: NSNull(),
                ChatGPTNativeContract.HistoryField.children.rawValue:
                    nodes.values.filter { $0.parentID == rootID }.map(\.id).sorted(),
            ]
        ]
        for node in nodes.values {
            let message: Data
            switch node.role {
            case .user:
                message = try ChatGPTNativeMessage.user(
                    message: .init(id: node.id, text: node.text), parentID: node.parentID, timestamp: node.createdAt)
            case .assistant:
                guard let model = node.model else { throw ChatGPTHistoryError.invalidStorage }
                message = try ChatGPTNativeMessage.assistant(
                    identity: .init(id: node.id, parentID: node.parentID),
                    model: model,
                    text: node.text,
                    timestamp: node.createdAt,
                    status: node.status,
                    updateTimestamp: node.updatedAt)
            }
            mapping[node.id] = [
                ChatGPTNativeContract.HistoryField.id.rawValue: node.id,
                ChatGPTNativeContract.HistoryField.message.rawValue: try JSONSerialization.jsonObject(with: message),
                ChatGPTNativeContract.HistoryField.parent.rawValue: node.parentID,
                ChatGPTNativeContract.HistoryField.children.rawValue: (children[node.id] ?? []).sorted(),
            ]
        }
        var result = sharedFields()
        result[ChatGPTNativeContract.HistoryField.conversationId.rawValue] = id
        result[ChatGPTNativeContract.HistoryField.createTime.rawValue] = createdAt
        result[ChatGPTNativeContract.HistoryField.updateTime.rawValue] = updatedAt
        result[ChatGPTNativeContract.HistoryField.currentNode.rawValue] = currentNodeID
        result[ChatGPTNativeContract.HistoryField.mapping.rawValue] = mapping
        return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }

    package func summaryData() throws -> Data {
        let formatter = ISO8601DateFormatter()
        var result = sharedFields()
        result[ChatGPTNativeContract.HistoryField.createTime.rawValue] = formatter.string(
            from: Date(timeIntervalSince1970: createdAt))
        result[ChatGPTNativeContract.HistoryField.updateTime.rawValue] = formatter.string(
            from: Date(timeIntervalSince1970: updatedAt))
        return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }

    private func sharedFields() -> [String: Any] {
        let model = nodes.values.filter { $0.role == .assistant }.max {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        }?.model
        return [
            ChatGPTNativeContract.HistoryField.id.rawValue: id,
            ChatGPTNativeContract.HistoryField.title.rawValue: title,
            ChatGPTNativeContract.HistoryField.isArchived.rawValue: archived,
            ChatGPTNativeContract.HistoryField.isStarred.rawValue: starred,
            ChatGPTNativeContract.HistoryField.isTemporaryChat.rawValue: temporary,
            ChatGPTNativeContract.HistoryField.defaultModelSlug.rawValue: model as Any? ?? NSNull(),
            ChatGPTNativeContract.HistoryField.gizmoId.rawValue: NSNull(),
            ChatGPTNativeContract.HistoryField.conversationTemplateId.rawValue: NSNull(),
        ]
    }
}
