import Foundation
import LittleSwitchWire

/// Steering is a control message, never a queued response.create. Its target
/// response identifies the connection; clients cannot select a separate lane.
package struct ResponsesWebSocketSteering: Sendable {
    private typealias EventKey = OpenAIResponsesCreatedEvent.Key
    private typealias InputKey = OpenAIResponsesRequestEnvelope.Key
    private typealias UserKey = OpenAIResponsesUserMessage.Key
    private typealias TextKey = OpenAIResponsesInputTextPart.Key
    private typealias ImageKey = ResponsesImagePartContract.Field
    private typealias RequestField = ResponsesWebSocketContract.RequestField

    /// File input is opaque in the generated user-message content projection.
    private enum FileField: String, CaseIterable {
        case fileID = "file_id"
        case fileData = "file_data"
        case fileURL = "file_url"
    }

    private enum FileKind: String {
        case inputFile = "input_file"
    }

    package let previousResponseID: String
    package let input: [JSONValue]
    package let body: Data

    init(_ envelope: ResponsesWebSocketRequest.Envelope) throws {
        let fields = envelope.fields
        let allowed = [
            EventKey.type.rawValue, RequestField.previousResponseID.rawValue, InputKey.input.rawValue,
        ]
        guard Set(fields.keys).isSubset(of: allowed),
            fields[EventKey.type.rawValue]?.string == ResponsesWebSocketContract.Event.steer.rawValue,
            let previous = envelope.previousResponseID,
            let value = fields[InputKey.input.rawValue]
        else { throw Self.invalid() }
        let messages: [JSONValue]
        if let text = value.string {
            messages = [
                [
                    UserKey.type.rawValue: .string(OpenAIResponsesUserMessageType.message.rawValue),
                    UserKey.role.rawValue: .string(OpenAIResponsesUserMessageRole.user.rawValue),
                    UserKey.content.rawValue: .string(text),
                ]
            ]
        } else if let items = value.array, !items.isEmpty {
            for item in items { try Self.validateMessage(item) }
            messages = items
        } else {
            throw Self.invalid()
        }
        previousResponseID = previous
        input = messages
        body = try JSONValue.object(fields).serializedData()
    }

    private static func validateMessage(_ item: JSONValue) throws {
        guard let message = item.object,
            Set(message.keys).isSubset(of: UserKey.allCases.map(\.rawValue)),
            message[UserKey.role.rawValue]?.string == OpenAIResponsesUserMessageRole.user.rawValue,
            message[UserKey.type.rawValue] == nil
                || message[UserKey.type.rawValue]?.string
                    == OpenAIResponsesUserMessageType.message.rawValue,
            let content = message[UserKey.content.rawValue]
        else { throw invalid() }
        if content.string == nil {
            guard let parts = content.array, !parts.isEmpty else { throw invalid() }
            for part in parts { try validatePart(part) }
        }
    }

    private static func validatePart(_ part: JSONValue) throws {
        guard let object = part.object, let type = object[TextKey.type.rawValue]?.string else {
            throw invalid()
        }
        switch type {
        case OpenAIResponsesInputTextPartType.inputText.rawValue:
            guard object[TextKey.text.rawValue]?.string != nil else { throw invalid() }
        case ResponsesImagePartContract.Kind.inputImage.rawValue:
            guard
                object[ImageKey.imageURL.rawValue]?.string != nil
                    || object[ImageKey.fileID.rawValue]?.string != nil
            else { throw invalid() }
        case FileKind.inputFile.rawValue:
            guard FileField.allCases.contains(where: { object[$0.rawValue]?.string != nil }) else {
                throw invalid()
            }
        default:
            throw invalid()
        }
    }

    private static func invalid() -> ResponsesWebSocketFailure {
        .init(
            status: 400,
            code: "invalid_input",
            message: "Invalid steering input",
            parameter: InputKey.input.rawValue)
    }
}
