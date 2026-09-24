import CoreFoundation
import Foundation
import LittleSwitchWire

package struct ChatGPTUserMessage: Equatable, Sendable {
    package let id: String
    package let text: String
    package init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

package struct ChatGPTConversationTurn: Equatable, Sendable {
    package enum Role: String, Codable, Sendable { case user, assistant }
    package let role: Role
    package let text: String
    package init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

package struct ChatGPTConversationRequest: Equatable, Sendable {
    package let model: String
    package let conversationID: String?
    package let parentMessageID: String
    package let messages: [ChatGPTUserMessage]
    package let historyAndTrainingDisabled: Bool

    package static func decode(_ data: Data) throws -> Self {
        guard data.count <= ChatGPTConversationLimits.maximumBodyBytes else {
            throw ChatGPTConversationError.limitExceeded
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            root[ChatGPTNativeContract.ConversationField.action.rawValue] as? String
                == ChatGPTNativeContract.Action.next.rawValue,
            let model = root[ChatGPTNativeContract.ConversationField.model.rawValue] as? String, !model.isEmpty,
            model == model.trimmingCharacters(in: .whitespacesAndNewlines),
            let messages = root[ChatGPTNativeContract.ConversationField.messages.rawValue] as? [[String: Any]],
            !messages.isEmpty
        else { throw ChatGPTConversationError.invalidRequest }
        guard messages.count <= ChatGPTConversationLimits.maximumMessages else {
            throw ChatGPTConversationError.limitExceeded
        }
        try ChatGPTRequestValidation.validateContext(root)
        let parent = try ChatGPTRequestValidation.identifier(
            root[ChatGPTNativeContract.ConversationField.parentMessageId.rawValue])
        let conversation: String?
        if let value = root[ChatGPTNativeContract.ConversationField.conversationId.rawValue], !(value is NSNull) {
            conversation = try ChatGPTRequestValidation.identifier(value)
        } else {
            conversation = nil
        }
        var seen = Set([parent])
        let parsed = try messages.map { message in
            let parsed = try ChatGPTRequestValidation.message(message)
            guard seen.insert(parsed.id).inserted else { throw ChatGPTConversationError.invalidRequest }
            return parsed
        }
        try ChatGPTRequestValidation.boundText(parsed.map(\.text))
        return Self(
            model: model,
            conversationID: conversation,
            parentMessageID: parent,
            messages: parsed,
            historyAndTrainingDisabled: try ChatGPTRequestValidation.boolean(
                root[ChatGPTNativeContract.ConversationField.historyAndTrainingDisabled.rawValue]))
    }

    package func responsesBody(history: [ChatGPTConversationTurn]) throws -> Data {
        guard history.count + messages.count <= ChatGPTConversationLimits.maximumHistoryMessages else {
            throw ChatGPTConversationError.limitExceeded
        }
        let turns = history + messages.map { ChatGPTConversationTurn(role: .user, text: $0.text) }
        try ChatGPTRequestValidation.boundText(turns.map(\.text))
        let input: [[String: Any]] = turns.map { turn in
            var part: [String: Any] = [
                OpenAIResponsesInputTextPart.Key.type.rawValue: turn.role == .user
                    ? OpenAIResponsesInputTextPartType.inputText.rawValue
                    : OpenAIResponsesOutputTextType.outputText.rawValue,
                OpenAIResponsesInputTextPart.Key.text.rawValue: turn.text,
            ]
            if turn.role == .assistant { part[OpenAIResponsesOutputText.Key.annotations.rawValue] = [String]() }
            return [
                OpenAIResponsesUserMessage.Key.role.rawValue:
                    (turn.role == .user
                    ? OpenAIResponsesUserMessageRole.user.rawValue : OpenAIResponsesMessageRole.assistant.rawValue),
                OpenAIResponsesUserMessage.Key.content.rawValue: [part],
            ]
        }
        return try JSONSerialization.data(withJSONObject: [
            OpenAIResponsesRoutingRequest.Key.model.rawValue: model,
            ChatGPTResponsesContract.RequestField.stream.rawValue: true,
            ChatGPTResponsesContract.RequestField.store.rawValue: false,
            OpenAIResponsesRequestEnvelope.Key.input.rawValue: input,
        ])
    }
}

enum ChatGPTRequestValidation {
    static func identifier(_ value: Any?) throws -> String {
        guard let value = value as? String, let uuid = UUID(uuidString: value) else {
            throw ChatGPTConversationError.invalidRequest
        }
        return uuid.uuidString.lowercased()
    }

    static func boolean(_ value: Any?) throws -> Bool {
        guard let value else { return false }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw ChatGPTConversationError.invalidRequest
        }
        return number.boolValue
    }

    static func boundText(_ texts: [String]) throws {
        var remaining = ChatGPTConversationLimits.maximumTextBytes
        for text in texts {
            let count = text.utf8.count
            guard count <= remaining else { throw ChatGPTConversationError.limitExceeded }
            remaining -= count
        }
    }

    static func validateContext(_ object: [String: Any]) throws {
        for key in [
            ChatGPTNativeContract.ContextField.tools.rawValue, ChatGPTNativeContract.ContextField.toolChoice.rawValue,
            ChatGPTNativeContract.ContextField.toolChoices.rawValue,
            ChatGPTNativeContract.ContextField.gizmoId.rawValue, ChatGPTNativeContract.ContextField.gizmo.rawValue,
            ChatGPTNativeContract.ContextField.gizmoContext.rawValue,
            ChatGPTNativeContract.ContextField.projectId.rawValue, ChatGPTNativeContract.ContextField.project.rawValue,
            ChatGPTNativeContract.ContextField.projectContext.rawValue,
            ChatGPTNativeContract.ContextField.attachments.rawValue,
        ] {
            guard isEmpty(object[key]) else { throw ChatGPTConversationError.unsupportedRequest }
        }
        if let mode = object[ChatGPTNativeContract.ConversationField.conversationMode.rawValue], !(mode is NSNull) {
            guard let mode = mode as? [String: Any], mode.count == 1,
                mode[ChatGPTNativeContract.ConversationField.kind.rawValue] as? String
                    == ChatGPTNativeContract.ConversationMode.primaryAssistant.rawValue
            else {
                throw ChatGPTConversationError.unsupportedRequest
            }
        }
    }

    static func message(_ object: [String: Any]) throws -> ChatGPTUserMessage {
        let id = try identifier(object[ChatGPTNativeContract.MessageField.id.rawValue])
        guard let author = object[ChatGPTNativeContract.MessageField.author.rawValue] as? [String: Any],
            author[ChatGPTNativeContract.MessageField.role.rawValue] as? String
                == ChatGPTConversationTurn.Role.user.rawValue,
            let content = object[ChatGPTNativeContract.MessageField.content.rawValue] as? [String: Any],
            content[ChatGPTNativeContract.MessageField.contentType.rawValue] as? String
                == ChatGPTNativeContract.ContentType.text.rawValue,
            let parts = content[ChatGPTNativeContract.MessageField.parts.rawValue] as? [String], !parts.isEmpty
        else { throw ChatGPTConversationError.invalidRequest }
        try validateContext(object)
        try validateContext(content)
        if let metadata = object[ChatGPTNativeContract.MessageField.metadata.rawValue] {
            guard let metadata = metadata as? [String: Any] else { throw ChatGPTConversationError.invalidRequest }
            try validateContext(metadata)
        }
        return ChatGPTUserMessage(id: id, text: parts.joined())
    }

    private static func isEmpty(_ value: Any?) -> Bool {
        guard let value else { return true }
        if value is NSNull { return true }
        if let value = value as? [Any] { return value.isEmpty }
        if let value = value as? [String: Any] { return value.isEmpty }
        if let value = value as? String { return value.isEmpty }
        return false
    }
}
