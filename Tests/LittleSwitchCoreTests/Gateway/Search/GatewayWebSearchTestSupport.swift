import Foundation
import LittleSwitchSearch

@testable import LittleSwitchCore

func gatewaySearchResponseBody(provider: WebSearchProvider) -> String {
    let searchBody: String
    switch provider {
    case .tavily:
        searchBody =
            #"{"results":[{"title":"Swift.org","url":"https://swift.org/","#
            + #""content":"The Swift project website"}]}"#
    case .brave:
        searchBody =
            #"{"type":"search","web":{"results":[{"title":"Swift.org","url":"https://swift.org/","#
            + #""description":"The Swift project website"}]}}"#
    case .exa:
        searchBody =
            #"{"results":[{"title":"Swift.org","url":"https://swift.org/","highlights":["The Swift project website"]}]}"#
    case .firecrawl, .disabled:
        searchBody =
            #"{"success":true,"data":{"web":[{"title":"Swift.org","#
            + #""url":"https://swift.org/","#
            + #""description":"The Swift project website"}]}}"#
    }
    return searchBody
}

extension GatewayTests {
    func makeWebSearchFixture(
        maximumUses: Int = 3,
        provider: WebSearchProvider = .firecrawl
    ) throws -> GatewayFixture {
        let base = try makeFixture()
        let snapshot = RoutingSnapshot(
            generation: base.snapshot.generation,
            providers: base.snapshot.providers,
            mappings: base.snapshot.mappings,
            webSearch: WebSearchConfiguration(
                provider: provider,
                resultsLimit: 10,
                maximumUses: maximumUses
            )
        )
        try base.secrets.write(
            provider.searchTestCredential,
            account: .webSearch(provider)
        )
        return GatewayFixture(
            snapshot: snapshot,
            state: GatewayState(snapshot: snapshot),
            secrets: base.secrets
        )
    }
}

extension WebSearchProvider {
    /// The deterministic credential each orchestration fixture seeds for
    /// the provider under test; loop tests assert it verbatim on the
    /// upstream search request.
    var searchTestCredential: String {
        switch self {
        case .firecrawl: "firecrawl-secret"
        case .tavily: "tavily-secret"
        case .brave: "brave-secret"
        case .exa: "exa-secret"
        case .disabled: "disabled-secret"
        }
    }
}
