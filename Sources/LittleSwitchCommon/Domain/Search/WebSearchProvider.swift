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
