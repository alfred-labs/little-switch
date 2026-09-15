import Foundation
import LittleSwitchWire

package enum ResponsesChatCompletionsImageContent {
    package static func multipart(_ parts: [[String: Any]]) -> [[String: Any]]? {
        var content: [[String: Any]] = []
        for part in parts {
            switch part[OpenAIResponsesUserMessage.Key.type.rawValue] as? String {
            case OpenAIResponsesInputTextPartType.inputText.rawValue, OpenAIResponsesOutputTextType.outputText.rawValue:
                guard let text = part[OpenAIResponsesInputTextPart.Key.text.rawValue] as? String else {
                    return nil
                }
                content.append([
                    OpenAIResponsesInputTextPart.Key.type.rawValue: ResponsesImagePartContract.Kind.chatText.rawValue,
                    OpenAIResponsesInputTextPart.Key.text.rawValue: text,
                ])
            case ResponsesImagePartContract.Kind.inputImage.rawValue:
                guard let url = part[ResponsesImagePartContract.Field.imageURL.rawValue] as? String, !url.isEmpty else {
                    return nil
                }
                var image = [ResponsesImagePartContract.Field.url.rawValue: url]
                if let detail = part[ResponsesImagePartContract.Field.detail.rawValue] as? String {
                    image[ResponsesImagePartContract.Field.detail.rawValue] = detail
                }
                content.append([
                    OpenAIResponsesInputTextPart.Key.type.rawValue: ResponsesImagePartContract.Kind.chatImage.rawValue,
                    ResponsesImagePartContract.Field.imageURL.rawValue: image,
                ])
            default:
                return nil
            }
        }
        return content.isEmpty ? nil : content
    }
}
