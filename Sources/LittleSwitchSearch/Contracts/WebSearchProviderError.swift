/// Why a provider search failed.
public enum WebSearchProviderError: Swift.Error, Equatable {
    case missingCredential
    case unauthorized
    case rateLimited
    case httpStatus(Int)
    case invalidResponse
    case responseTooLarge
    case unavailable
}
