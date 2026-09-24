import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore

package struct ChatGPTConversationStream: Sendable {
    private typealias Field = ChatGPTNativeContract.EventField

    package private(set) var text = ""
    package private(set) var completed = false
    private var decoder = ServerSentEventDecoder(maximumFrameBytes: ChatGPTConversationLimits.maximumFrameBytes)
    private var failure: ChatGPTConversationError?
    private var textBytes = 0
    private let conversationID: String
    private let message: ChatGPTNativeMessage.Identity
    private let model: String
    private let timestamp: Double
    private let title: String?

    package init(
        conversationID: String,
        message: ChatGPTNativeMessage.Identity,
        model: String,
        timestamp: Double,
        title: String? = nil
    ) {
        self.conversationID = conversationID
        self.message = message
        self.model = model
        self.timestamp = timestamp
        self.title = title
    }

    package mutating func append(_ buffer: ByteBuffer) throws -> Data {
        if let failure { throw failure }
        do {
            return try project(decoder.append(buffer))
        } catch {
            throw remember(error)
        }
    }

    package mutating func finish() throws -> Data {
        if let failure { throw failure }
        do {
            let output = try project(decoder.finish())
            guard completed else { throw ChatGPTConversationError.missingCompletion }
            return output
        } catch {
            throw remember(error)
        }
    }

    private mutating func remember(_ error: Error) -> ChatGPTConversationError {
        let sanitized: ChatGPTConversationError
        if let error = error as? ChatGPTConversationError {
            sanitized = error
        } else if error as? ServerSentEventDecoder.Error == .frameTooLarge {
            sanitized = .limitExceeded
        } else {
            sanitized = .invalidStream
        }
        failure = sanitized
        completed = false
        return sanitized
    }

    private mutating func project(_ frames: [ServerSentEventFrame]) throws -> Data {
        var output = Data()
        let startingTextBytes = textBytes
        for frame in frames {
            if frame.terminal {
                guard completed else { throw ChatGPTConversationError.missingCompletion }
                continue
            }
            guard !completed,
                let object = try? JSONSerialization.jsonObject(with: frame.data) as? [String: Any],
                let type = object[OpenAIResponsesTextDeltaEvent.Key.type.rawValue] as? String,
                frame.event == nil || frame.event == type
            else { throw ChatGPTConversationError.invalidStream }
            output.append(try projectEvent(object, type: type))
        }
        // One incoming chunk can contain many tiny deltas. Serialize its accumulated
        // text once, so output allocation cannot grow as snapshot size × frame count.
        if !completed, textBytes > startingTextBytes {
            output.append(try snapshot(status: .inProgress))
        }
        return output
    }

    private mutating func projectEvent(_ object: [String: Any], type: String) throws -> Data {
        switch type {
        case OpenAIResponsesTextDeltaEventType.responseOutputTextDelta.rawValue:
            guard let delta = object[OpenAIResponsesTextDeltaEvent.Key.delta.rawValue] as? String else {
                throw ChatGPTConversationError.invalidStream
            }
            let bytes = delta.utf8.count
            guard bytes <= ChatGPTConversationLimits.maximumTextBytes - textBytes else {
                throw ChatGPTConversationError.limitExceeded
            }
            text += delta
            textBytes += bytes
            return Data()
        case OpenAIResponsesCompletedEventType.responseCompleted.rawValue:
            return try complete(object)
        case OpenAIResponsesFailedEventType.responseFailed.rawValue,
            OpenAIResponsesIncompleteEventType.responseIncomplete.rawValue,
            OpenAIResponsesErrorEventType.error.rawValue,
            ChatGPTResponsesContract.CompatibilityEvent.responseError.rawValue:
            throw ChatGPTConversationError.providerFailed
        default:
            try ChatGPTStreamOutput.validateLifecycle(object, type: type)
            return Data()
        }
    }

    private mutating func complete(_ object: [String: Any]) throws -> Data {
        guard let response = object[OpenAIResponsesCompletedEvent.Key.response.rawValue] as? [String: Any] else {
            throw ChatGPTConversationError.invalidStream
        }
        guard
            response[OpenAIResponsesResponse.Key.status.rawValue] as? String
                == OpenAIResponsesStatus.completed.rawValue,
            response[OpenAIResponsesResponse.Key.error.rawValue] == nil
                || response[OpenAIResponsesResponse.Key.error.rawValue] is NSNull,
            response[OpenAIResponsesResponse.Key.incompleteDetails.rawValue] == nil
                || response[OpenAIResponsesResponse.Key.incompleteDetails.rawValue] is NSNull
        else { throw ChatGPTConversationError.providerFailed }
        let fullText = try ChatGPTStreamOutput.completedText(response)
        guard text.isEmpty || text.utf8.elementsEqual(fullText.utf8) else {
            throw ChatGPTConversationError.inconsistentOutput
        }
        try ChatGPTRequestValidation.boundText([fullText])
        text = fullText
        textBytes = fullText.utf8.count
        var output = try snapshot(status: .finishedSuccessfully)
        if let title {
            output.append(
                try Self.event([
                    Field.type.rawValue: ChatGPTNativeContract.EventType.titleGeneration
                        .rawValue,
                    Field.conversationId.rawValue: conversationID,
                    Field.title.rawValue: title,
                ]))
        }
        output.append(
            try Self.event([
                Field.type.rawValue: ChatGPTNativeContract.EventType.messageStreamComplete
                    .rawValue,
                Field.conversationId.rawValue: conversationID,
            ]))
        output.append(Data("data: [DONE]\n\n".utf8))
        completed = true
        return output
    }

    private func snapshot(status: ChatGPTNativeMessage.Status) throws -> Data {
        try Self.event([
            Field.conversationId.rawValue: conversationID,
            Field.message.rawValue: ChatGPTNativeMessage.assistantRecord(
                identity: message,
                model: model,
                text: text,
                timestamp: timestamp,
                status: status),
        ])
    }

    private static func event(_ object: [String: Any]) throws -> Data {
        var output = Data("data: ".utf8)
        output.append(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        output.append(Data("\n\n".utf8))
        return output
    }
}
