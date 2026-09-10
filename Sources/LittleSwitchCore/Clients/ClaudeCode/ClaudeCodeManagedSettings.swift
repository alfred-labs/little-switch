import Foundation

public struct ClaudeCodeManagedSettings: Codable, Equatable, Sendable {
    public enum Error: Swift.Error, Equatable {
        case noMappedModel
    }

    public var model: String
    public var environment: [String: String]

    public init(
        model: String,
        environment: [String: String]
    ) {
        self.model = model
        self.environment = environment
    }

    public static func resolve(
        providers: [Provider],
        mappings: [String: ModelMapping],
        configuration: ClaudeCodeConfiguration,
        tlsEnabled: Bool = false
    ) throws -> ClaudeCodeManagedSettings {
        let normalized = configuration.normalized(
            providers: providers,
            mappings: mappings
        )
        guard let defaultRouteID = normalized.defaultModel,
            let mapping = mappings[defaultRouteID],
            let provider = providers.first(where: { $0.id == mapping.providerID }),
            provider.models.contains(where: { $0.id == mapping.modelID })
        else {
            throw Error.noMappedModel
        }
        let model =
            normalized.contextMode == .extended1M
            ? "\(defaultRouteID)[1m]"
            : defaultRouteID

        // https only while the anchor is trusted: unlike the Desktop, the
        // terminal CLI has no in-app fallback, so an untrusted https origin
        // would kill every session it starts.
        var environment: [String: String] = [
            "ANTHROPIC_BASE_URL": tlsEnabled
                ? ClaudeProfileIdentity.gatewayBaseURL
                : ClaudeProfileIdentity.gatewayHTTPBaseURL,
            "ANTHROPIC_API_KEY": "",
            "ANTHROPIC_AUTH_TOKEN": ProductIdentity.gatewayAPIKey,
            "ANTHROPIC_DEFAULT_FABLE_MODEL": "claude-fable-5",
            "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-5",
            "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-5",
            "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5-20251001",
            "CLAUDE_CODE_USE_ANTHROPIC_AWS": "",
            "CLAUDE_CODE_USE_BEDROCK": "",
            "CLAUDE_CODE_USE_FOUNDRY": "",
            "CLAUDE_CODE_USE_MANTLE": "",
            "CLAUDE_CODE_USE_VERTEX": "",
            "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "",
            "CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS": "4",
            "CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY": "4",
            "DISABLE_TELEMETRY": "1",
            "DISABLE_ERROR_REPORTING": "1",
            "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1",
            "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
        ]
        // Tool search (spec 2026-09-03 §4.2): always on — activation is
        // client-driven (the Desktop app owns its native setting; terminal
        // sessions get it here). The kill switch
        // (CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS) is intentionally never
        // written — it disables all experimental betas, including the [1m]
        // context feature, and silently forces standard mode.
        environment["ENABLE_TOOL_SEARCH"] = "true"
        return ClaudeCodeManagedSettings(
            model: model,
            environment: environment
        )
    }
}
