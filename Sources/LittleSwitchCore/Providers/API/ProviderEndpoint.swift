import Foundation
import LittleSwitchCommon
import LittleSwitchTransport

public enum ProviderEndpoint {
    public enum Error: Swift.Error, Equatable {
        case invalidURL
        case unsupportedScheme
        case insecureRemoteHTTP
        case forbiddenComponent
    }

    public enum ForwardingAPI: Sendable {
        case messages
        case countTokens
        case responses
        case chatCompletions
    }

    public static func normalize(_ input: String) throws -> String {
        do {
            return try EndpointURL.normalize(input)
        } catch {
            throw providerError(error)
        }
    }

    public static func appending(_ endpointPath: String, to baseURL: String) throws -> URL {
        try appending(endpointPath, percentEncodedQuery: nil, to: baseURL)
    }

    /// The query-carrying form: Brave's search API is a GET whose parameters
    /// ride the URL, so the shared appending accepts one pre-encoded query
    /// string (nil leaves the URL query-free, byte-identical to the plain
    /// form). Callers encode it themselves because
    /// URLComponents.queryItems leaves a literal '+' unescaped, which
    /// form-style query decoding reads back as a space.
    public static func appending(
        _ endpointPath: String,
        percentEncodedQuery: String?,
        to baseURL: String
    ) throws -> URL {
        do {
            return try EndpointURL.appending(endpointPath, percentEncodedQuery: percentEncodedQuery, to: baseURL)
        } catch {
            throw providerError(error)
        }
    }

    public static func forwarding(
        _ api: ForwardingAPI,
        for provider: Provider
    ) throws -> URL {
        let normalizedBaseURL = try normalize(provider.baseURL)
        // The optional Anthropic surface carries the Claude routes; a
        // provider without it serves messages from the base URL.
        let anthropicBase =
            try provider.anthropicBaseURL.map { try normalize($0) }
            ?? normalizedBaseURL
        switch api {
        case .messages:
            return try appending("/v1/messages", to: anthropicBase)
        case .countTokens:
            return try appending("/v1/messages/count_tokens", to: anthropicBase)
        case .responses:
            return try appending("/v1/responses", to: normalizedBaseURL)
        case .chatCompletions:
            // A split-surface provider (Anthropic URL set) mounts chat
            // completions at its own root; everyone else follows the OpenAI
            // convention under the base URL.
            let path = provider.anthropicBaseURL != nil ? "/chat/completions" : "/v1/chat/completions"
            return try appending(path, to: normalizedBaseURL)
        }
    }

    private static func providerError(_ error: EndpointURL.Error) -> Error {
        switch error {
        case .invalidURL: .invalidURL
        case .unsupportedScheme: .unsupportedScheme
        case .insecureRemoteHTTP: .insecureRemoteHTTP
        case .forbiddenComponent: .forbiddenComponent
        }
    }
}
