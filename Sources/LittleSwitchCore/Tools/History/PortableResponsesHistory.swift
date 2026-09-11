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
        return try assistantMessage(
            prefix: "[Previous web search]",
            item: item
        )
    }

    /// A conversation switched away from a native model carries freeform tool
    /// exchanges (`custom_tool_call` / `custom_tool_call_output`) that no
    /// Responses provider accepts; the readable exchange remains context.
    package static func customToolMessage(for item: [String: Any]) throws -> [String: Any] {
        let type = item["type"] as? String
        guard type == "custom_tool_call" || type == "custom_tool_call_output",
            let callID = item["call_id"] as? String, !callID.isEmpty,
            JSONSerialization.isValidJSONObject(item)
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let prefix =
            type == "custom_tool_call"
            ? "[Previous custom tool call]"
            : "[Previous custom tool output]"
        return try assistantMessage(prefix: prefix, item: item)
    }

    private static func assistantMessage(
        prefix: String,
        item: [String: Any]
    ) throws -> [String: Any] {
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
                    "text": prefix + "\n" + text,
                ]
            ],
        ]
    }
}
