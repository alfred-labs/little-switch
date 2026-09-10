import Foundation
import LittleSwitchSearch

extension OpenAIResponsesPublicSanitizer {
    /// Public search sources carry URL references only. Result text belongs in
    /// the model's answer, never in provider-specific fields on this item.
    static func webSearchSources(_ value: Any) throws -> [[String: String]] {
        guard let sources = value as? [[String: Any]], sources.count <= 100 else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        return try sources.map { source in
            guard source["type"] as? String == "url",
                let url = source["url"] as? String,
                let result = WebSearchResultShaping.validated(title: "Source", url: url, content: ""),
                result.url == url
            else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            return ["type": "url", "url": url]
        }
    }
}
