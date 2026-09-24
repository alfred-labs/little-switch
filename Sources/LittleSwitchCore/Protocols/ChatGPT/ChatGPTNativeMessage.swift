import Foundation

package enum ChatGPTNativeMessage {
    private typealias Field = ChatGPTNativeContract.MessageField

    package struct Identity: Equatable, Sendable {
        package let id: String
        package let parentID: String

        package init(id: String, parentID: String) {
            self.id = id
            self.parentID = parentID
        }
    }

    package enum Status: String, Codable, Sendable, CaseIterable {
        case inProgress = "in_progress"
        case finishedSuccessfully = "finished_successfully"
        case failed
        case cancelled
    }

    package static func assistant(
        identity: Identity,
        model: String,
        text: String,
        timestamp: Double,
        status: Status,
        updateTimestamp: Double? = nil
    ) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: assistantRecord(
                identity: identity,
                model: model,
                text: text,
                timestamp: timestamp,
                status: status,
                updateTimestamp: updateTimestamp))
    }

    package static func user(message: ChatGPTUserMessage, parentID: String, timestamp: Double) throws -> Data {
        var messageRecord = try record(
            id: message.id,
            role: ChatGPTConversationTurn.Role.user.rawValue,
            text: message.text,
            timestamps: (timestamp, timestamp),
            status: .finishedSuccessfully)
        messageRecord[Field.metadata.rawValue] = [
            Field.parentId.rawValue: try ChatGPTRequestValidation.identifier(parentID)
        ]
        return try JSONSerialization.data(withJSONObject: messageRecord)
    }

    static func assistantRecord(
        identity: Identity,
        model: String,
        text: String,
        timestamp: Double,
        status: Status,
        updateTimestamp: Double? = nil
    ) throws -> [String: Any] {
        var metadata: [String: Any] = [
            Field.modelSlug.rawValue: model,
            Field.parentId.rawValue: try ChatGPTRequestValidation.identifier(
                identity.parentID),
        ]
        if status == .finishedSuccessfully {
            metadata[Field.finishDetails.rawValue] =
                [
                    Field.type.rawValue: ChatGPTNativeContract.FinishType.stop.rawValue,
                    Field.stopTokens.rawValue: [String](),
                ] as [String: Any]
        }
        var messageRecord = try record(
            id: identity.id,
            role: ChatGPTConversationTurn.Role.assistant.rawValue,
            text: text,
            timestamps: (timestamp, updateTimestamp ?? timestamp),
            status: status)
        messageRecord[Field.metadata.rawValue] = metadata
        return messageRecord
    }

    private static func record(
        id: String, role: String, text: String, timestamps: (created: Double, updated: Double), status: Status
    ) throws -> [String: Any] {
        guard timestamps.created.isFinite, timestamps.updated.isFinite else {
            throw ChatGPTConversationError.invalidRequest
        }
        try ChatGPTRequestValidation.boundText([text])
        return [
            Field.id.rawValue: try ChatGPTRequestValidation.identifier(id),
            Field.author.rawValue: [
                Field.role.rawValue: role,
                Field.name.rawValue: NSNull(),
                Field.metadata.rawValue: [String: String](),
            ] as [String: Any],
            Field.createTime.rawValue: timestamps.created,
            Field.updateTime.rawValue: timestamps.updated,
            Field.content.rawValue: [
                Field.contentType.rawValue: ChatGPTNativeContract.ContentType.text
                    .rawValue,
                Field.parts.rawValue: [text],
            ] as [String: Any],
            Field.status.rawValue: status.rawValue,
            Field.endTurn.rawValue: status != .inProgress,
            Field.weight.rawValue: 1,
            Field.recipient.rawValue: ChatGPTNativeContract.Recipient.all.rawValue,
            Field.channel.rawValue: ChatGPTNativeContract.Channel.final.rawValue,
        ]
    }
}
