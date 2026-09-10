import CoreFoundation
import Foundation

package enum AnthropicCountTokensRequest {
    package enum Error: Swift.Error, Equatable {
        case invalidRequest
        case invalidResponse
    }

    private static let tokenBearingKeys: Set<String> = [
        "model",
        "messages",
        "system",
        "tools",
        "tool_choice",
        "thinking",
        "output_config",
        "cache_control",
    ]

    package static func project(_ upstreamBody: Data) throws -> Data {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: upstreamBody)
        } catch {
            throw Error.invalidRequest
        }
        guard let root = object as? [String: Any],
            root["model"] is String,
            root["messages"] is [Any]
        else {
            throw Error.invalidRequest
        }

        let projected = try PortableToolHistory.anthropic(root).filter { tokenBearingKeys.contains($0.key) }
        return try JSONSerialization.data(
            withJSONObject: projected,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    package static func parseCount(_ responseBody: Data) throws -> Int {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: responseBody)
        } catch {
            throw Error.invalidResponse
        }
        guard let root = object as? [String: Any],
            let number = root["input_tokens"] as? NSNumber,
            CFGetTypeID(number) == CFNumberGetTypeID()
        else {
            throw Error.invalidResponse
        }

        let count = number.intValue
        guard count > 0,
            number.compare(NSNumber(value: count)) == .orderedSame
        else {
            throw Error.invalidResponse
        }
        return count
    }
}
