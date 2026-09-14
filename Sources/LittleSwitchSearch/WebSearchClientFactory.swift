import LittleSwitchCommon
import LittleSwitchTransport

/// Centralized construction for the active search provider. Orchestration
/// loops never hold a concrete client type.
package enum WebSearchClientFactory {
    package static func make(
        configuration: WebSearchConfiguration,
        transport: any UpstreamTransport
    ) -> any WebSearchSearching {
        switch configuration.provider {
        case .firecrawl:
            FirecrawlSearchClient(transport: transport)
        case .tavily:
            TavilySearchClient(transport: transport)
        case .brave:
            BraveSearchClient(transport: transport)
        case .exa:
            ExaSearchClient(transport: transport)
        case .disabled:
            DisabledSearchClient()
        }
    }
}
