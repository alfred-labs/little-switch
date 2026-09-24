import Foundation
import LittleSwitchWire

/// Inspects provider lifecycle payloads without exposing their metadata or reasoning.
enum ChatGPTStreamOutput {
    static func validateLifecycle(_ object: [String: Any], type: String) throws {
        switch type {
        case OpenAIResponsesCreatedEventType.responseCreated.rawValue,
            OpenAIResponsesInProgressEventType.responseInProgress.rawValue,
            OpenAIResponsesQueuedEventType.responseQueued.rawValue:
            guard let response = object[OpenAIResponsesCreatedEvent.Key.response.rawValue] as? [String: Any] else {
                throw ChatGPTConversationError.invalidStream
            }
            if let output = response[OpenAIResponsesResponse.Key.output.rawValue] {
                _ = try outputText(output)
            }
        case OpenAIResponsesOutputItemAddedEventType.responseOutputItemAdded.rawValue,
            OpenAIResponsesOutputItemDoneEventType.responseOutputItemDone.rawValue:
            guard let item = object[OpenAIResponsesOutputItemAddedEvent.Key.item.rawValue] as? [String: Any] else {
                throw ChatGPTConversationError.invalidStream
            }
            _ = try itemText(item)
        case OpenAIContentPartAddedType.responseContentPartAdded.rawValue,
            OpenAIContentPartDoneType.responseContentPartDone.rawValue:
            guard let part = object[OpenAIContentPartAdded.Key.part.rawValue] as? [String: Any] else {
                throw ChatGPTConversationError.invalidStream
            }
            _ = try partText(part)
        case OpenAIResponsesTextDoneEventType.responseOutputTextDone.rawValue:
            guard object[OpenAIResponsesTextDoneEvent.Key.text.rawValue] is String else {
                throw ChatGPTConversationError.invalidStream
            }
        case OpenAIReasoningSummaryPartAddedType.responseReasoningSummaryPartAdded.rawValue,
            OpenAIReasoningSummaryPartDoneType.responseReasoningSummaryPartDone.rawValue,
            OpenAIReasoningSummaryTextDeltaType.responseReasoningSummaryTextDelta.rawValue,
            OpenAIReasoningSummaryTextDoneType.responseReasoningSummaryTextDone.rawValue,
            OpenAIReasoningTextDeltaType.responseReasoningTextDelta.rawValue,
            OpenAIReasoningTextDoneType.responseReasoningTextDone.rawValue,
            OpenAITextAnnotationAddedType.responseOutputTextAnnotationAdded.rawValue:
            break
        default:
            throw ChatGPTConversationError.unsupportedOutput
        }
    }

    static func completedText(_ response: [String: Any]) throws -> String {
        guard let output = response[OpenAIResponsesResponse.Key.output.rawValue] else {
            throw ChatGPTConversationError.invalidStream
        }
        return try outputText(output)
    }

    private static func outputText(_ value: Any) throws -> String {
        guard let items = value as? [[String: Any]] else { throw ChatGPTConversationError.invalidStream }
        let texts = try items.compactMap(itemText)
        return texts.joined()
    }

    private static func itemText(_ item: [String: Any]) throws -> String? {
        guard let type = item[OpenAIResponsesMessage.Key.type.rawValue] as? String else {
            throw ChatGPTConversationError.invalidStream
        }
        if type == OpenAIResponsesReasoningType.reasoning.rawValue { return nil }
        guard type == OpenAIResponsesMessageType.message.rawValue,
            item[OpenAIResponsesMessage.Key.role.rawValue] as? String == OpenAIResponsesMessageRole.assistant.rawValue
        else {
            throw ChatGPTConversationError.unsupportedOutput
        }
        guard let parts = item[OpenAIResponsesMessage.Key.content.rawValue] as? [[String: Any]] else {
            throw ChatGPTConversationError.invalidStream
        }
        let texts = try parts.map(partText)
        return texts.joined()
    }

    private static func partText(_ part: [String: Any]) throws -> String {
        guard
            part[OpenAIResponsesOutputText.Key.type.rawValue] as? String
                == OpenAIResponsesOutputTextType.outputText.rawValue
        else { throw ChatGPTConversationError.unsupportedOutput }
        guard let text = part[OpenAIResponsesOutputText.Key.text.rawValue] as? String else {
            throw ChatGPTConversationError.invalidStream
        }
        return text
    }
}
