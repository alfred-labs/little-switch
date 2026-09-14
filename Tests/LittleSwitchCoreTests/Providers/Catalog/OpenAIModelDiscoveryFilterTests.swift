import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI model discovery filter")
struct OpenAIModelDiscoveryFilterTests {
    private static let openAICatalog = [
        "gpt-5.5", "gpt-5.4-mini", "o4-mini", "chatgpt-4o-latest", "codex-mini-latest",
        "text-embedding-3-small", "whisper-1", "tts-1", "tts-1-hd", "dall-e-3",
        "gpt-image-1", "sora-2", "davinci-002", "babbage-002", "text-davinci-003",
        "code-davinci-002", "omni-moderation-latest", "gpt-3.5-turbo-instruct",
    ]
    private static let expectedChatModels = [
        "gpt-5.5", "gpt-5.4-mini", "o4-mini", "chatgpt-4o-latest", "codex-mini-latest",
    ]

    @Test("The hosted OpenAI catalog keeps only chat-capable models")
    func filtersHostedCatalog() {
        let models = Self.openAICatalog.map { DiscoveredModel(id: $0) }

        let filtered = OpenAIModelDiscoveryFilter.filtered(models, baseURL: "https://api.openai.com")

        #expect(filtered.map(\.id) == Self.expectedChatModels)
    }

    @Test(
        "Discovery catalog scoping follows the endpoint host",
        arguments: [
            "https://api.openai.com/v1",
            "https://api.openai.com/",
        ]
    )
    func scopesByHost(baseURL: String) {
        let models = Self.openAICatalog.map { DiscoveredModel(id: $0) }

        let filtered = OpenAIModelDiscoveryFilter.filtered(models, baseURL: baseURL)

        #expect(filtered.map(\.id) == Self.expectedChatModels)
    }

    @Test(
        "Other endpoints keep every discovered model",
        arguments: [
            "https://openrouter.ai/api",
            "http://127.0.0.1:8000",
            "https://api.openai.example.com",
            "https://openai.com",
        ]
    )
    func keepsOtherEndpoints(baseURL: String) {
        let models = Self.openAICatalog.map { DiscoveredModel(id: $0) }

        #expect(OpenAIModelDiscoveryFilter.filtered(models, baseURL: baseURL) == models)
    }

    @Test("An unparseable base URL keeps every discovered model")
    func keepsUnparseableBaseURL() {
        let models = [DiscoveredModel(id: "whisper-1")]

        #expect(OpenAIModelDiscoveryFilter.filtered(models, baseURL: "") == models)
    }
}
