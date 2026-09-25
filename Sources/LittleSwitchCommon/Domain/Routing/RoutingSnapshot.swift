import Foundation

public struct RoutingSnapshot: Equatable, Sendable {
    public var generation: UInt64
    public var providers: [Provider]
    public var mappings: [String: ModelMapping]
    public var codex: CodexConfiguration
    public var chatgpt: ChatGPTConfiguration
    public var webSearch: WebSearchConfiguration
    public var modelIndicator: ModelIndicator

    public init(
        generation: UInt64,
        providers: [Provider],
        mappings: [String: ModelMapping],
        codex: CodexConfiguration = .disconnected,
        chatgpt: ChatGPTConfiguration = .disconnected,
        webSearch: WebSearchConfiguration = .disabled,
        modelIndicator: ModelIndicator = .mapsTo
    ) {
        self.generation = generation
        self.providers = providers
        self.mappings = mappings
        self.codex = codex
        self.chatgpt = chatgpt
        self.webSearch = webSearch
        self.modelIndicator = modelIndicator
    }
}
