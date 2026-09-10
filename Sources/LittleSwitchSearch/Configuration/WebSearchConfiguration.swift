import Foundation

public enum WebSearchProvider: String, Codable, CaseIterable, Sendable {
    case disabled
    case firecrawl
    case tavily
    case brave
    case exa
}

extension WebSearchProvider {
    /// The result-limit range each provider's API accepts: Tavily's and
    /// Brave's search APIs cap at 20 results, Firecrawl and Exa share the wide
    /// window. The settings stepper, configuration validation, and the
    /// client-side clamp all read this one range.
    public var resultsLimitRange: ClosedRange<Int> {
        switch self {
        case .tavily, .brave:
            1...20
        case .firecrawl, .exa, .disabled:
            1...100
        }
    }
}

public struct WebSearchConfiguration: Codable, Equatable, Sendable {
    public enum Error: Swift.Error, Equatable {
        case invalidResultsLimit
        case invalidMaximumUses
    }

    public static let firecrawlBaseURL = "https://api.firecrawl.dev/v2"
    public static let tavilyBaseURL = "https://api.tavily.com"
    public static let braveBaseURL = "https://api.search.brave.com"
    public static let exaBaseURL = "https://api.exa.ai"
    public static let disabled = WebSearchConfiguration(provider: .disabled)
    public static let firecrawlCloud = WebSearchConfiguration(provider: .firecrawl)
    public static let tavily = WebSearchConfiguration(provider: .tavily)
    public static let brave = WebSearchConfiguration(provider: .brave)

    public var provider: WebSearchProvider
    public var resultsLimit: Int
    public var maximumUses: Int

    public init(
        provider: WebSearchProvider = .firecrawl,
        resultsLimit: Int = 10,
        maximumUses: Int = 3
    ) {
        self.provider = provider
        self.resultsLimit = resultsLimit
        self.maximumUses = maximumUses
    }

    /// Every active provider's endpoint is a constant: stored configurations
    /// carry no URL of their own, so a saved file can never steer requests
    /// off the provider's official API. Disabled search never reaches the
    /// transport, so its fallback value is never dialed.
    public var endpointBaseURL: String {
        switch provider {
        case .disabled, .firecrawl:
            Self.firecrawlBaseURL
        case .tavily:
            Self.tavilyBaseURL
        case .brave:
            Self.braveBaseURL
        case .exa:
            Self.exaBaseURL
        }
    }

    public func normalized() throws -> WebSearchConfiguration {
        guard provider.resultsLimitRange.contains(resultsLimit) else {
            throw Error.invalidResultsLimit
        }
        guard (1...10).contains(maximumUses) else {
            throw Error.invalidMaximumUses
        }
        switch provider {
        case .disabled:
            return .disabled
        case .firecrawl, .tavily, .brave, .exa:
            return self
        }
    }
}
