import AsyncHTTPClient
import Foundation
import NIOHTTP1

public enum ProviderRequestBuilder {
    public static func discovery(provider: Provider, secret: String?) throws -> HTTPClientRequest {
        // A split-surface provider (Anthropic URL set) mounts models at the
        // root of its base URL; everyone else follows the OpenAI convention.
        let path = provider.anthropicBaseURL != nil ? "/models" : "/v1/models"
        let endpoint = try ProviderEndpoint.appending(path, to: provider.baseURL)
        var request = HTTPClientRequest(url: endpoint.absoluteString)
        request.method = .GET
        try applyAuthentication(provider: provider, secret: secret, headers: &request.headers)
        return request
    }

    public static func ollamaVersion(
        provider: Provider,
        secret: String?
    ) throws -> HTTPClientRequest {
        let endpoint = try ProviderEndpoint.appending("/api/version", to: provider.baseURL)
        var request = HTTPClientRequest(url: endpoint.absoluteString)
        request.method = .GET
        try applyAuthentication(provider: provider, secret: secret, headers: &request.headers)
        return request
    }

    public static func ollamaShow(
        provider: Provider,
        secret: String?,
        modelID: String
    ) throws -> HTTPClientRequest {
        let endpoint = try ProviderEndpoint.appending("/api/show", to: provider.baseURL)
        var request = HTTPClientRequest(url: endpoint.absoluteString)
        request.method = .POST
        request.headers.replaceOrAdd(name: "content-type", value: "application/json")
        try applyAuthentication(provider: provider, secret: secret, headers: &request.headers)
        let body = try JSONSerialization.data(
            withJSONObject: ["model": modelID, "verbose": true],
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        request.body = .bytes(body)
        return request
    }

    public static func message(
        provider: Provider,
        secret: String?,
        headers incomingHeaders: HTTPHeaders,
        body: Data
    ) throws -> HTTPClientRequest {
        try forwardingRequest(
            api: .messages,
            provider: provider,
            secret: secret,
            headers: incomingHeaders,
            body: body
        )
    }

    public static func countTokens(
        provider: Provider,
        secret: String?,
        headers incomingHeaders: HTTPHeaders,
        body: Data
    ) throws -> HTTPClientRequest {
        try forwardingRequest(
            api: .countTokens,
            provider: provider,
            secret: secret,
            headers: incomingHeaders,
            body: body
        )
    }

    public static func responses(
        provider: Provider,
        secret: String?,
        headers incomingHeaders: HTTPHeaders,
        body: Data
    ) throws -> HTTPClientRequest {
        try forwardingRequest(
            api: .responses,
            provider: provider,
            secret: secret,
            headers: incomingHeaders,
            body: body
        )
    }

    public static func chatCompletions(
        provider: Provider,
        secret: String?,
        headers incomingHeaders: HTTPHeaders,
        body: Data
    ) throws -> HTTPClientRequest {
        try forwardingRequest(
            api: .chatCompletions,
            provider: provider,
            secret: secret,
            headers: incomingHeaders,
            body: body
        )
    }

    /// The single forwarding core every public builder delegates to; the
    /// endpoint probe uses it directly to build its empty-body route
    /// requests without inventing a fourth header/auth policy.
    package static func forwarding(
        api: ProviderEndpoint.ForwardingAPI,
        provider: Provider,
        secret: String?,
        headers incomingHeaders: HTTPHeaders,
        body: Data
    ) throws -> HTTPClientRequest {
        try forwardingRequest(
            api: api,
            provider: provider,
            secret: secret,
            headers: incomingHeaders,
            body: body
        )
    }

    private static func forwardingRequest(
        api: ProviderEndpoint.ForwardingAPI,
        provider: Provider,
        secret: String?,
        headers incomingHeaders: HTTPHeaders,
        body: Data
    ) throws -> HTTPClientRequest {
        let endpoint = try ProviderEndpoint.forwarding(api, for: provider)
        var request = HTTPClientRequest(url: endpoint.absoluteString)
        request.method = .POST
        request.headers = incomingHeaders
        let connectionHeaders = request.headers["connection"].flatMap { value in
            value.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        }
        let strippedHeaderNames = Set(
            [
                "authorization",
                "connection",
                "content-encoding",
                "cookie",
                "keep-alive",
                "proxy-authorization",
                "proxy-authenticate",
                "x-api-key",
                "host",
                "content-length",
                "te",
                "trailer",
                "transfer-encoding",
                "upgrade",
                // OpenAI-attested provenance and turn metadata describe a
                // first-party ChatGPT session; third-party providers have no
                // use for them and should not receive them.
                "x-oai-attestation",
                "x-codex-turn-metadata",
            ] + connectionHeaders
        )
        for name in strippedHeaderNames {
            request.headers.remove(name: name)
        }
        try applyAuthentication(provider: provider, secret: secret, headers: &request.headers)
        request.body = .bytes(body)
        return request
    }

    private static func applyAuthentication(
        provider: Provider,
        secret: String?,
        headers: inout HTTPHeaders
    ) throws {
        guard let secret, !secret.isEmpty else {
            return
        }
        switch provider.authMode {
        case .none:
            break
        case .bearer:
            headers.replaceOrAdd(name: "authorization", value: "Bearer \(secret)")
        case .xAPIKey:
            headers.replaceOrAdd(name: "x-api-key", value: secret)
        }
    }
}
