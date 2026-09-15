import Foundation
import LittleSwitchWire

enum ResponsesChatCompletionsToolOutput {
    struct Result {
        let toolMessage: [String: Any]
        let imageMessages: [[String: Any]]
    }

    static func project(item: [String: Any]) throws -> Result {
        guard let callID = nonemptyResponsesString(item[OpenAIResponsesInputFunctionOutput.Key.callId.rawValue]),
            let output = item[OpenAIResponsesInputFunctionOutput.Key.output.rawValue]
        else {
            throw OpenAIResponsesChatCompletions.Error.invalidRequest
        }
        let content: String
        var attachments: [[String: Any]] = []
        let parts = output as? [[String: Any]]
        // Text-only and opaque tool outputs keep their original JSON representation.
        // Only a real image requires splitting the tool result into Chat messages.
        let multimodal =
            parts?.contains {
                $0[OpenAIResponsesInputTextPart.Key.type.rawValue] as? String
                    == ResponsesImagePartContract.Kind.inputImage.rawValue
            } ?? false
        if let parts, multimodal {
            var texts: [String] = []
            for part in parts {
                switch part[OpenAIResponsesUserMessage.Key.type.rawValue] as? String {
                case ResponsesImagePartContract.Kind.inputImage.rawValue:
                    guard let image = ResponsesChatCompletionsImageContent.multipart([part]) else {
                        throw OpenAIResponsesChatCompletions.Error.invalidRequest
                    }
                    attachments.append(contentsOf: image)
                case OpenAIResponsesInputTextPartType.inputText.rawValue,
                    OpenAIResponsesOutputTextType.outputText.rawValue:
                    guard let text = part[OpenAIResponsesInputTextPart.Key.text.rawValue] as? String else {
                        throw OpenAIResponsesChatCompletions.Error.invalidRequest
                    }
                    texts.append(text)
                default:
                    texts.append(try stringFragment(part))
                }
            }
            content =
                texts.isEmpty && !attachments.isEmpty ? "[Image attached separately.]" : texts.joined(separator: "\n")
        } else {
            content = try stringFragment(output)
        }
        let tool = OpenAIChatRequestTool(content: .string(content), role: .tool, toolCallId: callID)
        var images: [[String: Any]] = []
        if !attachments.isEmpty {
            let note: [String: Any] = [
                OpenAIResponsesInputTextPart.Key.type.rawValue: ResponsesImagePartContract.Kind.chatText.rawValue,
                OpenAIResponsesInputTextPart.Key.text.rawValue: "Image from tool call \(callID)",
            ]
            let message = OpenAIChatRequestUser(
                content: try WireJSONCompatibility.value([note] + attachments), role: .user)
            images.append(try WireJSONCompatibility.fields(message.wireJSON()))
        }
        return Result(toolMessage: try WireJSONCompatibility.fields(tool.wireJSON()), imageMessages: images)
    }

    private static func stringFragment(_ value: Any) throws -> String {
        if let string = value as? String { return string }
        return try WireJSONCompatibility.value(value).serialized()
    }
}
