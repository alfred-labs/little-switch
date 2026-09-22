import Foundation
import LittleSwitchCommon
import LittleSwitchSearch
import LittleSwitchWire

/// Gateway-owned search history is self-contained: the native encrypted-content
/// field transports readable results, not encryption or a provider-issued token.
package enum PortableWebSearchHistory {
    package enum Error: Swift.Error, Equatable {
        case invalidResult
        case resultTooLarge
        case unsupportedOpaqueContent
        case unsupportedReplayVersion
    }

    private struct ReplayPayload: Codable {
        let toolUseID: String
        let resultIndex: Int
        let result: WebSearchResult

        enum CodingKeys: String, CodingKey {
            case toolUseID = "tool_use_id"
            case resultIndex = "result_index"
            case result
        }
    }

    private static let tokenPrefix = "little-switch-search:v1:"
    private static let legacyPrefix = "little-switch-opaque:"
    // Match the largest search-service result count and aggregate excerpt budget.
    // Two MiB also accommodates worst-case JSON escaping of all normalized fields.
    private static let maximumResults = 100
    private static let maximumContentBytes = 256 * 1_024
    private static let maximumPayloadBytes = 2 * 1_024 * 1_024
    private static let maximumTokenBytes = tokenPrefix.utf8.count + ((maximumPayloadBytes + 2) / 3) * 4

    package static func anthropicResultText(_ block: JSONObject) throws -> String {
        guard
            block[AnthropicWebSearchToolResultBlock.Key.type.rawValue]?.string
                == AnthropicWebSearchToolResultBlockType.webSearchToolResult.rawValue,
            let toolUseID = block[AnthropicWebSearchToolResultBlock.Key.toolUseId.rawValue]?.string
        else {
            throw Error.invalidResult
        }
        try validateToolUseID(toolUseID)
        let header = "Historical web search result for \(toolUseID):\n"
        if let error = block[AnthropicWebSearchToolResultBlock.Key.content.rawValue]?.anthropicObject {
            guard
                error[AnthropicWebSearchError.Key.type.rawValue]?.string
                    == AnthropicWebSearchErrorType.webSearchToolResultError.rawValue,
                let code = error[AnthropicWebSearchError.Key.errorCode.rawValue]?.string, !code.isEmpty,
                code.utf8.count <= 128
            else {
                throw Error.invalidResult
            }
            return header + "Web search failed: \(code)."
        }
        guard let content = block[AnthropicWebSearchToolResultBlock.Key.content.rawValue]?.anthropicObjects else {
            throw Error.invalidResult
        }
        try validateResultCount(content.count)
        let results = try content.enumerated().map { index, result in
            try readableResult(result, toolUseID: toolUseID, resultIndex: index)
        }
        try validateResults(results)
        return header
            + (results.isEmpty ? "No results were returned." : AnthropicWebSearch.formatResults(results))
    }

    package static func anthropicReplayToken(
        toolUseID: String,
        resultIndex: Int,
        result: WebSearchResult
    ) throws -> String {
        try validateToolUseID(toolUseID)
        guard resultIndex >= 0 else {
            throw Error.invalidResult
        }
        guard resultIndex < maximumResults else {
            throw Error.resultTooLarge
        }
        try validateResult(result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(
            ReplayPayload(toolUseID: toolUseID, resultIndex: resultIndex, result: result)
        )
        return tokenPrefix + data.base64EncodedString()
    }

    static func validateResults(_ results: [WebSearchResult]) throws {
        try validateResultCount(results.count)
        var remainingBytes = maximumContentBytes
        for result in results {
            try validateResult(result)
            let contentBytes = result.content.utf8.count
            guard contentBytes <= remainingBytes else {
                throw Error.resultTooLarge
            }
            remainingBytes -= contentBytes
        }
    }

    private static func validateResultCount(_ count: Int) throws {
        guard count <= maximumResults else {
            throw Error.resultTooLarge
        }
    }

    private static func validateToolUseID(_ id: String) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.invalidResult
        }
        guard id.utf8.count <= 1_024 else {
            throw Error.resultTooLarge
        }
    }

    private static func validateResult(_ result: WebSearchResult) throws {
        guard WebSearchResultShaping.validated(title: result.title, url: result.url, content: result.content) == result
        else {
            throw Error.invalidResult
        }
        guard result.content.utf8.count <= maximumContentBytes else {
            throw Error.resultTooLarge
        }
    }

    private static func readableResult(
        _ object: JSONObject,
        toolUseID: String,
        resultIndex: Int
    ) throws -> WebSearchResult {
        guard
            object[AnthropicWebSearchResult.Key.type.rawValue]?.string
                == AnthropicWebSearchResultType.webSearchResult.rawValue,
            let title = object[AnthropicWebSearchResult.Key.title.rawValue]?.string,
            let url = object[AnthropicWebSearchResult.Key.url.rawValue]?.string,
            let token = object[AnthropicWebSearchResult.Key.encryptedContent.rawValue]?.string, !token.isEmpty
        else {
            throw Error.invalidResult
        }
        try validateResult(WebSearchResult(title: title, url: url, content: ""))
        if token.hasPrefix(legacyPrefix) {
            guard token == "\(legacyPrefix)\(toolUseID):\(resultIndex)" else {
                throw Error.invalidResult
            }
            return WebSearchResult(
                title: title,
                url: url,
                content: "Content unavailable: this legacy LittleSwitch replay token retained only source metadata."
            )
        }
        guard token.hasPrefix(tokenPrefix) else {
            throw token.hasPrefix("little-switch-search:")
                ? Error.unsupportedReplayVersion : Error.unsupportedOpaqueContent
        }
        guard token.utf8.count <= maximumTokenBytes else {
            throw Error.resultTooLarge
        }
        guard let data = Data(base64Encoded: String(token.dropFirst(tokenPrefix.count))) else {
            throw Error.invalidResult
        }
        guard data.count <= maximumPayloadBytes else {
            throw Error.resultTooLarge
        }
        let payload: ReplayPayload
        do {
            payload = try JSONDecoder().decode(ReplayPayload.self, from: data)
        } catch {
            throw Error.invalidResult
        }
        guard payload.toolUseID == toolUseID,
            payload.resultIndex == resultIndex,
            payload.result.title == title,
            payload.result.url == url
        else {
            throw Error.invalidResult
        }
        try validateResult(payload.result)
        return payload.result
    }
}
