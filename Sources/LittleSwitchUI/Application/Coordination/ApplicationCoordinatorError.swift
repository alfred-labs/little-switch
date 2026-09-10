import Foundation

extension ApplicationCoordinator {
    public enum Error: Swift.Error, LocalizedError, Equatable {
        case codexUnavailable
        case claudeCodeUnavailable
        case claudeCodeRecoveryRequired
        case openCodeUnavailable
        case openCodeRecoveryRequired
        case noExposedOpenCodeModel
        case codexApplyRequiredForOpenCode
        case duplicateProviderName
        case invalidProviderName
        case invalidMaximumParallelRequests
        case providerMutationSuperseded
        case providerDuplicationSourceUnavailable
        case missingOriginalProviderCredential
        case invalidMapping
        case invalidModelContext
        case invalidWebSearchConfiguration
        case missingFirecrawlCredential
        case missingTavilyCredential
        case missingBraveCredential
        case missingExaCredential
        case missingCredentialScript
        case noMappedModel
        case noExposedCodexModel
        case noMappedClaudeCodeModel
        case gatewayUnavailable
        case rollbackFailed
        case relaunchFailed

        public var errorDescription: String? {
            switch self {
            case .codexUnavailable:
                "Codex desktop integration is unavailable."
            case .claudeCodeUnavailable:
                "Claude Code integration is unavailable."
            case .claudeCodeRecoveryRequired:
                "Restore the previous Claude Code settings before connecting."
            case .openCodeUnavailable:
                "OpenCode integration is unavailable."
            case .openCodeRecoveryRequired:
                "Restore the previous OpenCode settings before connecting."
            case .noExposedOpenCodeModel:
                "Expose at least one model before connecting OpenCode."
            case .codexApplyRequiredForOpenCode:
                "Apply the pending Codex model exposure before applying OpenCode."
            case .duplicateProviderName:
                "Provider names must be unique."
            case .invalidProviderName:
                "Enter a provider name."
            case .invalidMaximumParallelRequests:
                "Choose between 1 and 32 parallel requests."
            case .providerMutationSuperseded:
                "The provider changed while this operation was running. Try again."
            case .providerDuplicationSourceUnavailable:
                "The original provider is no longer available. Choose another provider to duplicate."
            case .missingOriginalProviderCredential:
                "The original provider has no saved key. Enter an API token for this copy."
            case .invalidMapping:
                "Choose a model discovered from an available provider."
            case .invalidModelContext:
                "Enter a positive context window for a discovered model."
            case .invalidWebSearchConfiguration:
                "Check the web search limits."
            case .missingFirecrawlCredential:
                "Enter a Firecrawl API key for Cloud search."
            case .missingTavilyCredential:
                "Enter a Tavily API key for web search."
            case .missingBraveCredential:
                "Enter a Brave API key for web search."
            case .missingExaCredential:
                "Enter an Exa API key for web search."
            case .missingCredentialScript:
                "Enter the shell script that prints the credential."
            case .noMappedModel:
                "Map at least one Claude model before connecting."
            case .noExposedCodexModel:
                "Expose at least one model before connecting Codex."
            case .noMappedClaudeCodeModel:
                "Map at least one Claude model before connecting Claude Code."
            case .gatewayUnavailable:
                "Port 11436 is already in use. Quit the other LittleSwitch instance, then reopen the app."
            case .rollbackFailed:
                "Some previous settings could not be restored. Review the affected settings before trying again."
            case .relaunchFailed:
                "Claude Desktop kept its previous settings: the app could not be restarted. Relaunch it manually to pick the change up."
            }
        }
    }
}
