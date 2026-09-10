public struct ProviderPreset: Equatable, Sendable {
    public var name: String
    public var baseURL: String
    public var authMode: AuthMode
    public var maximumParallelRequests: Int = Provider.defaultMaximumParallelRequests
    /// The provider's optional Anthropic surface (z.ai serves Claude on
    /// /api/anthropic while chat completions mount at the coding root).
    public var anthropicBaseURL: String?

    public static let ollama = ProviderPreset(
        name: "Ollama",
        baseURL: "http://127.0.0.1:11434",
        authMode: .none,
        maximumParallelRequests: 4
    )
    public static let openAICompatible = ProviderPreset(
        name: "OpenAI Compatible",
        baseURL: "http://127.0.0.1:8000",
        authMode: .bearer,
        maximumParallelRequests: 4
    )
    /// oMLX and LM Studio both serve OpenAI-compatible endpoints from a single
    /// local model, so their capacity is deliberately small: extra parallel
    /// requests only queue inside the server and slow every one of them.
    public static let omlx = ProviderPreset(
        name: "oMLX",
        baseURL: "http://127.0.0.1:1234",
        authMode: .none,
        maximumParallelRequests: 2
    )
    public static let lmStudio = ProviderPreset(
        name: "LM Studio",
        baseURL: "http://127.0.0.1:1234",
        authMode: .bearer,
        maximumParallelRequests: 2
    )
    public static let openRouter = ProviderPreset(
        name: "OpenRouter",
        baseURL: "https://openrouter.ai/api",
        authMode: .bearer,
        maximumParallelRequests: 8
    )
    public static let zai = ProviderPreset(
        name: "z.ai",
        baseURL: "https://api.z.ai/api/coding/paas/v4",
        authMode: .bearer,
        maximumParallelRequests: 2,
        anthropicBaseURL: "https://api.z.ai/api/anthropic"
    )
    public static let custom = ProviderPreset(
        name: "",
        baseURL: "",
        authMode: .none,
        maximumParallelRequests: 4
    )
}
