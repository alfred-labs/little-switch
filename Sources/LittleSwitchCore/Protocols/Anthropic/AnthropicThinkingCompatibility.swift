import Foundation

package enum AnthropicThinkingCompatibility {
    /// Adds the provider's fallback only when the caller disabled thinking
    /// without choosing an effort. Every ineligible body retains its bytes.
    package static func applying(
        _ override: ProviderDisabledThinkingOverride?,
        to body: Data
    ) throws -> Data {
        guard override == .lowEffort,
            var root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let thinking = root["thinking"] as? [String: Any],
            thinking["type"] as? String == "disabled",
            root["reasoning_effort"] == nil
        else {
            return body
        }
        var outputConfiguration: [String: Any] = [:]
        if let existing = root["output_config"] {
            guard let object = existing as? [String: Any], object["effort"] == nil else {
                return body
            }
            outputConfiguration = object
        }
        outputConfiguration["effort"] = "low"
        root["output_config"] = outputConfiguration
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }
}
