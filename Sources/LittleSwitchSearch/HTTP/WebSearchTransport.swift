import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore

/// The HTTP round-trip every search-provider client shares: the request
/// skeleton (endpoint path, JSON headers, optional bearer) and the response
/// contract (status mapping, bounded body collection, decode normalization).
/// Per-provider policy — credential requirements, rate-limit statuses, request
/// bodies, envelopes — stays in each client.
package enum WebSearchTransport {
    /// The trimmed credential every hosted provider demands before any
    /// request: blank input is indistinguishable from a missing one, and
    /// the clients share this single gate so the rule cannot drift.
    package static func requiredCredential(_ credential: String?) throws -> String {
        guard
            let credential = credential?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        else {
            throw WebSearchProviderError.missingCredential
        }
        return credential
    }

    package static func request(
        path: String,
        configuration: WebSearchConfiguration,
        bearer: String?
    ) throws -> HTTPClientRequest {
        let endpoint = try EndpointURL.appending(path, to: configuration.endpointBaseURL)
        var request = HTTPClientRequest(url: endpoint.absoluteString)
        request.method = .POST
        request.headers.replaceOrAdd(name: "accept", value: "application/json")
        request.headers.replaceOrAdd(name: "content-type", value: "application/json")
        if let bearer {
            request.headers.replaceOrAdd(name: "authorization", value: "Bearer \(bearer)")
        }
        return request
    }

    /// RFC 3986 unreserved bytes — the only ones allowed through a query
    /// component untouched.
    private static let queryAllowedBytes = Set(
        Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~".utf8)
    )

    /// The GET form the query-carrying APIs use: parameters ride the URL,
    /// percent-encoded here by hand — a literal '+' must travel as %2B
    /// because URLComponents.queryItems leaves it unescaped and form-style
    /// query decoding reads it back as a space — and the credential sits
    /// in the provider's subscription header rather than an authorization
    /// bearer.
    package static func getRequest(
        path: String,
        query: [(name: String, value: String)],
        configuration: WebSearchConfiguration,
        subscriptionToken: String
    ) throws -> HTTPClientRequest {
        var percentEncodedQuery = ""
        for (index, item) in query.enumerated() {
            if index > 0 {
                percentEncodedQuery += "&"
            }
            percentEncodedQuery += percentEncodeQueryComponent(item.name)
            percentEncodedQuery += "="
            percentEncodedQuery += percentEncodeQueryComponent(item.value)
        }
        let endpoint = try EndpointURL.appending(
            path,
            percentEncodedQuery: percentEncodedQuery.isEmpty ? nil : percentEncodedQuery,
            to: configuration.endpointBaseURL
        )
        var request = HTTPClientRequest(url: endpoint.absoluteString)
        request.method = .GET
        request.headers.replaceOrAdd(name: "accept", value: "application/json")
        request.headers.replaceOrAdd(name: "x-subscription-token", value: subscriptionToken)
        return request
    }

    /// Percent-encodes one query component byte-wise over its UTF-8: every
    /// byte outside the unreserved set rides as %XX (uppercase hex), so
    /// multi-byte scalars encode per byte exactly like Foundation's encoder.
    package static func percentEncodeQueryComponent(_ value: String) -> String {
        var encoded = ""
        for byte in value.utf8 {
            if queryAllowedBytes.contains(byte) {
                encoded += String(UnicodeScalar(byte))
            } else {
                let hex = String(byte, radix: 16, uppercase: true)
                encoded += byte < 0x10 ? "%0" + hex : "%" + hex
            }
        }
        return encoded
    }

    package static func responseBody(
        _ request: HTTPClientRequest,
        transport: any UpstreamTransport,
        maximumResponseBytes: Int,
        rateLimitedStatuses: Set<UInt> = [429]
    ) async throws -> Data {
        let response: HTTPClientResponse
        do {
            response = try await transport.execute(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WebSearchProviderError.unavailable
        }

        switch response.status.code {
        case 200..<300:
            break
        case 401, 403:
            throw WebSearchProviderError.unauthorized
        case let code where rateLimitedStatuses.contains(code):
            throw WebSearchProviderError.rateLimited
        default:
            throw WebSearchProviderError.httpStatus(Int(response.status.code))
        }

        do {
            let buffer = try await response.body.collect(upTo: maximumResponseBytes)
            return Data(buffer.readableBytesView)
        } catch is CancellationError {
            throw CancellationError()
        } catch is NIOTooManyBytesError {
            throw WebSearchProviderError.responseTooLarge
        } catch {
            throw WebSearchProviderError.unavailable
        }
    }

    package static func decodeEnvelope<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw WebSearchProviderError.invalidResponse
        }
    }
}
