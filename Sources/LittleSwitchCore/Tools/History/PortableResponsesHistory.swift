import Foundation
import LittleSwitchWire

/// Imports public search history without pretending that another model provider
/// owns its server-side call IDs. The complete readable action remains context.
package enum PortableResponsesHistory {
    static func message(for item: JSONValue) throws -> JSONValue {
        _ = try OpenAIResponsesPublicSanitizer.wireItem(item)
        guard case .webSearchCall = try responsesWireDecode(OpenAIResponsesOutputItem.self, json: item) else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        // JSONValue's serializer emits UTF-8 and preserves exact numeric tokens.
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: try item.serializedData(), as: UTF8.self)
        let part = OpenAIResponsesReplayTextPart(text: "[Previous web search]\n" + text, type: .outputText)
        return try OpenAIResponsesReplayMessage(
            content: [part.wireJSON()], role: .assistant, type: .message
        ).wireJSON()
    }

    package static func message(for item: [String: Any]) throws -> [String: Any] {
        let json = try responsesWireDecode(JSONValue.self, from: responsesStreamData(item))
        return try responsesStreamObject(message(for: json).serializedData())
    }
}
