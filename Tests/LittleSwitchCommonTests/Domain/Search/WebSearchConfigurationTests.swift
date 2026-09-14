import Foundation
import Testing

@testable import LittleSwitchCommon

@Suite("Web search configuration")
struct WebSearchConfigurationTests {
    @Test("Exa persists without a configurable endpoint or credentials")
    func exaConfiguration() throws {
        #expect(WebSearchProvider.exa.resultsLimitRange == 1...100)
        #expect(try WebSearchConfiguration(provider: .exa).normalized().endpointBaseURL == "https://api.exa.ai")
        let encoded = try JSONEncoder().encode(WebSearchConfiguration(provider: .exa))
        let object = try JSONSerialization.jsonObject(with: encoded) as? NSDictionary
        #expect(object == ["provider": "exa", "resultsLimit": 10, "maximumUses": 3] as NSDictionary)
        #expect(
            try JSONDecoder().decode(WebSearchConfiguration.self, from: encoded)
                == WebSearchConfiguration(provider: .exa))
        let legacy = Data(
            #"{"provider":"exa","resultsLimit":100,"maximumUses":10,"baseURL":"https://untrusted.example"}"#.utf8)
        #expect(
            try JSONDecoder().decode(WebSearchConfiguration.self, from: legacy).normalized().endpointBaseURL
                == "https://api.exa.ai")
    }

    @Test("Disabled and Firecrawl defaults are stable")
    func defaults() throws {
        #expect(WebSearchConfiguration.firecrawlCloud.resultsLimit == 10)
        #expect(WebSearchConfiguration.firecrawlCloud.maximumUses == 3)
        #expect(
            try WebSearchConfiguration.firecrawlCloud.normalized().endpointBaseURL
                == WebSearchConfiguration.firecrawlBaseURL
        )
        #expect(
            try WebSearchConfiguration.tavily.normalized().endpointBaseURL
                == WebSearchConfiguration.tavilyBaseURL
        )
        #expect(try WebSearchConfiguration.tavily.normalized() == .tavily)
        #expect(
            try WebSearchConfiguration.brave.normalized().endpointBaseURL
                == WebSearchConfiguration.braveBaseURL
        )
        #expect(try WebSearchConfiguration.brave.normalized() == .brave)
    }

    @Test("Limits are validated against the provider's own range")
    func validation() {
        #expect(throws: WebSearchConfiguration.Error.invalidResultsLimit) {
            try WebSearchConfiguration(resultsLimit: 101).normalized()
        }
        #expect(throws: WebSearchConfiguration.Error.invalidMaximumUses) {
            try WebSearchConfiguration(maximumUses: 0).normalized()
        }
    }

    @Test("Configurations saved with a deployment and endpoint still decode")
    func legacyDecoding() throws {
        // Files written before the self-hosted deployment existed carry the
        // extra keys; decoding must ignore them and land on the constant
        // Firecrawl Cloud endpoint.
        let legacyJSON = """
            {"provider":"firecrawl","deployment":"self-hosted",\
            "baseURL":"http://127.0.0.1:3002/v2","resultsLimit":25,"maximumUses":4}
            """
        let legacy = Data(legacyJSON.utf8)

        let decoded = try JSONDecoder().decode(WebSearchConfiguration.self, from: legacy)
        let normalized = try decoded.normalized()

        #expect(decoded.provider == .firecrawl)
        #expect(decoded.resultsLimit == 25)
        #expect(decoded.maximumUses == 4)
        #expect(normalized.endpointBaseURL == WebSearchConfiguration.firecrawlBaseURL)
    }

    @Test("Tavily's result ceiling is validated, not silently clamped")
    func tavilyResultsCeiling() {
        #expect(throws: WebSearchConfiguration.Error.invalidResultsLimit) {
            try WebSearchConfiguration(provider: .tavily, resultsLimit: 21).normalized()
        }
        #expect(
            (try? WebSearchConfiguration(provider: .tavily, resultsLimit: 20).normalized())
                != nil
        )
    }

    @Test("Brave's result ceiling is validated, not silently clamped")
    func braveResultsCeiling() {
        #expect(throws: WebSearchConfiguration.Error.invalidResultsLimit) {
            try WebSearchConfiguration(provider: .brave, resultsLimit: 21).normalized()
        }
        #expect(
            (try? WebSearchConfiguration(provider: .brave, resultsLimit: 20).normalized())
                != nil
        )
    }

    @Test("Disabled search normalizes to the canonical disabled configuration")
    func disabledNormalization() throws {
        let disabled = WebSearchConfiguration(
            provider: .disabled,
            resultsLimit: 25,
            maximumUses: 4
        )

        #expect(try disabled.normalized() == .disabled)
    }

}
