import Foundation

/// Imports public search history without pretending that another model provider
/// owns its server-side call IDs. The complete readable action remains context.
package enum PortableResponsesHistory {
    package static func message(for item: [String: Any]) throws -> [String: Any] {
        _ = try OpenAIResponsesPublicSanitizer.item(item)
        guard item["type"] as? String == "web_search_call",
            JSONSerialization.isValidJSONObject(item)
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let data = try JSONSerialization.data(
            withJSONObject: item, options: [.sortedKeys, .withoutEscapingSlashes]
        )
        // JSONSerialization guarantees UTF-8; no empty-history fallback is needed.
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: data, as: UTF8.self)
        return [
            "type": "message", "role": "assistant",
            "content": [
                [
                    "type": "output_text",
                    "text": "[Previous web search]\n" + text,
                ]
            ],
        ]
    }
}
