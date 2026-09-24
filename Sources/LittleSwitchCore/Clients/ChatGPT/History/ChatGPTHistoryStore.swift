import Foundation

package actor ChatGPTHistoryStore {
    package struct Limits: Sendable {
        package let conversations: Int
        package let nodesPerConversation: Int
        package let textBytesPerConversation: Int
        package let storageBytes: Int
        package static let `default` = Limits()

        package init(
            conversations: Int = 100,
            nodesPerConversation: Int = 128,
            textBytesPerConversation: Int = 4_194_304,
            storageBytes: Int = 67_108_864
        ) {
            self.conversations = conversations
            self.nodesPerConversation = nodesPerConversation
            self.textBytesPerConversation = textBytesPerConversation
            self.storageBytes = storageBytes
        }
    }

    private let fileURL: URL?
    private let limits: Limits
    private var conversations: [String: ChatGPTStoredConversation]
    private var active: [String: String] = [:]

    package init(fileURL: URL? = nil, limits: Limits = .default) throws {
        guard limits.conversations > 0, limits.nodesPerConversation > 0,
            limits.textBytesPerConversation > 0, limits.storageBytes > 0, limits.storageBytes < Int.max
        else { throw ChatGPTHistoryError.invalidInput }
        self.fileURL = fileURL
        self.limits = limits
        self.conversations = try ChatGPTHistoryPersistence.load(fileURL: fileURL, limits: limits)
    }

    package func begin(
        request: ChatGPTConversationRequest, owner: String, now: Double, newConversationID: String? = nil
    ) throws -> ChatGPTPendingTurn {
        try ChatGPTHistoryValidation.request(request, owner: owner, now: now)
        var value: ChatGPTStoredConversation
        if let id = request.conversationID {
            guard newConversationID == nil else { throw ChatGPTHistoryError.invalidInput }
            value = try conversation(id: id, owner: owner)
            try requireIdle(id)
            guard value.temporary == request.historyAndTrainingDisabled,
                value.contains(request.parentMessageID)
            else { throw ChatGPTHistoryError.invalidInput }
        } else {
            let id = newConversationID ?? ChatGPTConversationID.make()
            guard ChatGPTHistoryValidation.ownedID(id), conversations[id] == nil else {
                throw ChatGPTHistoryError.invalidInput
            }
            guard conversations.count < limits.conversations else { throw ChatGPTHistoryError.capacityExceeded }
            let title = request.messages[0].text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            value = ChatGPTStoredConversation(
                id: id,
                owner: owner,
                rootID: request.parentMessageID,
                title: title.isEmpty ? "New chat" : String(title.prefix(80)),
                createdAt: now,
                updatedAt: now,
                currentNodeID: request.parentMessageID,
                archived: false,
                starred: false,
                temporary: request.historyAndTrainingDisabled,
                nodes: [:])
        }
        let history = try value.ancestry(of: request.parentMessageID)
        var parent = request.parentMessageID
        for message in request.messages {
            guard !value.contains(message.id) else { throw ChatGPTHistoryError.invalidInput }
            value.nodes[message.id] = ChatGPTHistoryNode(
                id: message.id,
                parentID: parent,
                role: .user,
                text: message.text,
                model: nil,
                createdAt: now,
                updatedAt: now,
                status: .finishedSuccessfully)
            parent = message.id
        }
        var assistant = UUID().uuidString.lowercased()
        while value.contains(assistant) { assistant = UUID().uuidString.lowercased() }
        value.nodes[assistant] = ChatGPTHistoryNode(
            id: assistant,
            parentID: parent,
            role: .assistant,
            text: "",
            model: request.model,
            createdAt: now,
            updatedAt: now,
            status: .inProgress)
        value.currentNodeID = assistant
        value.updatedAt = now
        try commit(value)
        active[value.id] = assistant
        return ChatGPTPendingTurn(
            conversationID: value.id,
            assistantID: assistant,
            parentID: parent,
            title: value.title,
            timestamp: now,
            history: history)
    }

    package func update(conversationID: String, owner: String, assistantID: String, text: String) throws {
        var value = try conversation(id: conversationID, owner: owner)
        guard active[conversationID] == assistantID, var node = value.nodes[assistantID] else {
            throw ChatGPTHistoryError.invalidInput
        }
        node.text = text
        value.nodes[assistantID] = node
        try ChatGPTHistoryValidation.bounds(value, limits: limits)
        conversations[conversationID] = value
    }

    package func finish(
        conversationID: String, owner: String, assistantID: String, status: ChatGPTNativeMessage.Status, now: Double
    ) throws {
        var value = try conversation(id: conversationID, owner: owner)
        guard status != .inProgress, now.isFinite, active[conversationID] == assistantID,
            var node = value.nodes[assistantID]
        else { throw ChatGPTHistoryError.invalidInput }
        node.status = status
        node.updatedAt = now
        value.nodes[assistantID] = node
        value.updatedAt = now
        // Completion always releases admission, including failed persistence. Keep
        // the terminal state in memory so a later commit cannot resurrect it.
        active.removeValue(forKey: conversationID)
        conversations[conversationID] = value
        do {
            try commit(value)
        } catch {
            if status == .finishedSuccessfully {
                node.status = .failed
                value.nodes[assistantID] = node
                conversations[conversationID] = value
            }
            throw error
        }
    }

    package func conversation(id: String, owner: String) throws -> ChatGPTStoredConversation {
        guard ChatGPTHistoryValidation.ownedID(id), let value = conversations[id], value.owner == owner else {
            throw ChatGPTHistoryError.notFound
        }
        return value
    }

    package func list(owner: String, archived: Bool, starred: Bool?) -> [ChatGPTStoredConversation] {
        conversations.values.filter {
            $0.owner == owner && !$0.temporary && $0.archived == archived && (starred == nil || $0.starred == starred)
        }
        .sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }
    }

    package func patch(id: String, owner: String, changes: ChatGPTHistoryPatch, now: Double) throws {
        var value = try conversation(id: id, owner: owner)
        try requireIdle(id)
        guard now.isFinite else { throw ChatGPTHistoryError.invalidInput }
        if let title = changes.title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 256 else { throw ChatGPTHistoryError.invalidInput }
            value.title = trimmed
        }
        if let node = changes.currentNodeID {
            guard value.contains(node) else { throw ChatGPTHistoryError.invalidInput }
            value.currentNodeID = node
        }
        if let archived = changes.archived { value.archived = archived }
        if let starred = changes.starred { value.starred = starred }
        value.updatedAt = now
        try commit(value)
    }

    package func remove(id: String, owner: String) throws {
        let value = try conversation(id: id, owner: owner)
        try requireIdle(id)
        var candidate = conversations
        candidate.removeValue(forKey: id)
        if !value.temporary { try ChatGPTHistoryPersistence.save(candidate, fileURL: fileURL, limits: limits) }
        conversations = candidate
    }

    private func requireIdle(_ id: String) throws {
        guard active[id] == nil else { throw ChatGPTHistoryError.busy }
    }

    private func commit(_ value: ChatGPTStoredConversation) throws {
        try ChatGPTHistoryValidation.bounds(value, limits: limits)
        var candidate = conversations
        candidate[value.id] = value
        if !value.temporary { try ChatGPTHistoryPersistence.save(candidate, fileURL: fileURL, limits: limits) }
        conversations = candidate
    }
}
