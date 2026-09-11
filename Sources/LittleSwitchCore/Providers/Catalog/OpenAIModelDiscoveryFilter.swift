import Foundation

/// OpenAI's hosted `/v1/models` catalog lists every artifact family the
/// account can call, not just conversational models. LittleSwitch routes
/// coding-agent conversations, so the hosted OpenAI provider only exposes
/// chat-capable models; every other endpoint keeps its full discovery list.
package enum OpenAIModelDiscoveryFilter {
    private static let deniedPrefixes = [
        "babbage", "code-cushman", "code-davinci", "dall-e", "davinci", "gpt-image",
        "moderation", "omni-moderation", "sora", "text-ada", "text-babbage", "text-curie",
        "text-davinci", "text-embedding", "tts", "whisper",
    ]
    private static let deniedModels: Set<String> = ["gpt-3.5-turbo-instruct"]

    package static func filtered(
        _ models: [DiscoveredModel],
        baseURL: String
    ) -> [DiscoveredModel] {
        guard isHostedCatalog(baseURL) else {
            return models
        }
        return models.filter { keeps($0.id) }
    }

    private static func isHostedCatalog(_ baseURL: String) -> Bool {
        guard let components = URLComponents(string: baseURL),
            let host = components.host?.lowercased()
        else {
            return false
        }
        return host == "api.openai.com"
    }

    private static func keeps(_ id: String) -> Bool {
        let lowered = id.lowercased()
        guard !deniedModels.contains(lowered) else {
            return false
        }
        return !deniedPrefixes.contains { lowered.hasPrefix($0) }
    }
}
