import Foundation
import LittleSwitchCommon

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

    /// Update cosmetic labels using the already applied references, not a
    /// draft's mappings or default. The profile journal owns their restoration.
    public func withModelIndicator(_ indicator: ModelIndicator) -> Self {
        var result = self
        for route in ClaudeRoute.all {
            let key = "ANTHROPIC_DEFAULT_\(route.family.uppercased())_MODEL"
            guard let reference = environment[key] else {
                continue
            }
            result.environment["\(key)_NAME"] =
                ClaudeCodeModelChoice(
                    route: route, supports1MContext: reference.hasSuffix("[1m]"), indicator: indicator
                ).label
        }
        return result
    }

    public static func resolve(
        providers: [Provider],
        mappings: [String: ModelMapping],
        configuration: ClaudeCodeConfiguration,
        tlsEnabled: Bool = false,
        modelIndicator: ModelIndicator = .mapsTo
    ) throws -> ClaudeCodeManagedSettings {
        let normalized = configuration.normalized(
            providers: providers,
            mappings: mappings
        )
        let choices = ClaudeCodeModelChoice.available(
            providers: providers, mappings: mappings, indicator: modelIndicator)
        guard let defaultRouteID = normalized.defaultModel,
            let selected = choices.first(where: { $0.route.id == defaultRouteID })
        else {
            throw Error.noMappedModel
        }

        // https only while the anchor is trusted: unlike the Desktop, the
        // terminal CLI has no in-app fallback, so an untrusted https origin
        // would kill every session it starts.
        var environment: [String: String] = [
            "ANTHROPIC_DEFAULT_MODEL": selected.id,
            "ANTHROPIC_BASE_URL": tlsEnabled
                ? ClaudeProfileIdentity.gatewayBaseURL
                : ClaudeProfileIdentity.gatewayHTTPBaseURL,
            "ANTHROPIC_API_KEY": "",
            "ANTHROPIC_AUTH_TOKEN": ProductIdentity.gatewayAPIKey,
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
        for route in ClaudeRoute.all {
            let choice =
                choices.first { $0.route.id == route.id }
                ?? ClaudeCodeModelChoice(route: route, supports1MContext: false, indicator: modelIndicator)
            let key = "ANTHROPIC_DEFAULT_\(route.family.uppercased())_MODEL"
            environment[key] = choice.reference
            environment["\(key)_NAME"] = choice.label
            environment["\(key)_DESCRIPTION"] = choice.description
        }
        // Tool search (spec 2026-09-03 §4.2): always on — activation is
        // client-driven (the Desktop app owns its native setting; terminal
        // sessions get it here). The kill switch
        // (CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS) is intentionally never
        // written — it disables all experimental betas, including the [1m]
        // context feature, and silently forces standard mode.
        environment["ENABLE_TOOL_SEARCH"] = "true"
        return ClaudeCodeManagedSettings(
            model: selected.id,
            environment: environment
        )
    }
}
