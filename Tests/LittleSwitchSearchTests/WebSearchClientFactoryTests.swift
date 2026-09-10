import AsyncHTTPClient
import Foundation
import Testing

@testable import LittleSwitchSearch

@Suite("Web search client factory")
struct WebSearchClientFactoryTests {
    @Test("The factory hands back the adapter matching the active provider")
    func adapterSelection() {
        let transport = SearchFailingTransport(error: .unavailable)

        #expect(
            WebSearchClientFactory.make(configuration: WebSearchConfiguration(provider: .exa), transport: transport)
                is ExaSearchClient)

        #expect(
            WebSearchClientFactory.make(
                configuration: .firecrawlCloud,
                transport: transport
            ) is FirecrawlSearchClient
        )
        #expect(
            WebSearchClientFactory.make(
                configuration: .tavily,
                transport: transport
            ) is TavilySearchClient
        )
        #expect(
            WebSearchClientFactory.make(
                configuration: .brave,
                transport: transport
            ) is BraveSearchClient
        )
    }

    @Test("Disabled configurations are rejected before transport")
    func disabledSelection() async {
        let transport = SearchRecordingTransport(responses: [])
        let client = WebSearchClientFactory.make(
            configuration: .disabled,
            transport: transport
        )

        await #expect(throws: WebSearchProviderError.unavailable) {
            try await client.search(
                query: "Swift",
                configuration: .disabled,
                credential: nil,
                options: WebSearchFilterOptions()
            )
        }
        #expect(await transport.requests.isEmpty)
    }
}
