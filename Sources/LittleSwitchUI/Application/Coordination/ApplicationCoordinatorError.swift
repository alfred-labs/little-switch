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
                L10n.string("Codex desktop integration is unavailable.")
            case .claudeCodeUnavailable:
                L10n.string("Claude Code integration is unavailable.")
            case .claudeCodeRecoveryRequired:
                L10n.string("Restore the previous Claude Code settings before connecting.")
            case .openCodeUnavailable:
                L10n.string("OpenCode integration is unavailable.")
            case .openCodeRecoveryRequired:
                L10n.string("Restore the previous OpenCode settings before connecting.")
            case .noExposedOpenCodeModel:
                L10n.string("Expose at least one model before connecting OpenCode.")
            case .codexApplyRequiredForOpenCode:
                L10n.string("Apply the pending Codex model exposure before applying OpenCode.")
            case .duplicateProviderName:
                L10n.string("Provider names must be unique.")
            case .invalidProviderName:
                L10n.string("Enter a provider name.")
            case .invalidMaximumParallelRequests:
                L10n.string("Choose between 1 and 32 parallel requests.")
            case .providerMutationSuperseded:
                L10n.string("The provider changed while this operation was running. Try again.")
            case .providerDuplicationSourceUnavailable:
                L10n.string("The original provider is no longer available. Choose another provider to duplicate.")
            case .missingOriginalProviderCredential:
                L10n.string("The original provider has no saved key. Enter an API token for this copy.")
            case .invalidMapping:
                L10n.string("Choose a model discovered from an available provider.")
            case .invalidModelContext:
                L10n.string("Enter a positive context window for a discovered model.")
            case .invalidWebSearchConfiguration:
                L10n.string("Check the web search limits.")
            case .missingFirecrawlCredential:
                L10n.string("Enter a Firecrawl API key for Cloud search.")
            case .missingTavilyCredential:
                L10n.string("Enter a Tavily API key for web search.")
            case .missingBraveCredential:
                L10n.string("Enter a Brave API key for web search.")
            case .missingExaCredential:
                L10n.string("Enter an Exa API key for web search.")
            case .missingCredentialScript:
                L10n.string("Enter the shell script that prints the credential.")
            case .noMappedModel:
                L10n.string("Map at least one Claude model before connecting.")
            case .noExposedCodexModel:
                L10n.string("Expose at least one model before connecting Codex.")
            case .noMappedClaudeCodeModel:
                L10n.string("Map at least one Claude model before connecting Claude Code.")
            case .gatewayUnavailable:
                L10n.string("Port 11436 is already in use. Quit the other LittleSwitch instance, then reopen the app.")
            case .rollbackFailed:
                L10n.string(
                    "Some previous settings could not be restored. Review the affected settings before trying again.")
            case .relaunchFailed:
                L10n.string(
                    "Claude Desktop kept its previous settings: the app could not be restarted. Relaunch it manually to pick the change up."
                )
            }
        }
    }
}
