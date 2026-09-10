import Foundation

package enum EndpointURL {
    package enum Error: Swift.Error, Equatable {
        case invalidURL
        case unsupportedScheme
        case insecureRemoteHTTP
        case forbiddenComponent
    }

    package static func normalize(_ input: String) throws(Error) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else {
            throw Error.invalidURL
        }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw Error.unsupportedScheme
        }
        guard let host = components.host?.lowercased(), !host.isEmpty else { throw Error.invalidURL }
        guard components.user == nil, components.password == nil,
            components.query == nil, components.fragment == nil
        else {
            throw Error.forbiddenComponent
        }
        if scheme == "http", !isLoopback(host) {
            throw Error.insecureRemoteHTTP
        }

        components.scheme = scheme
        components.host = host
        while components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        if components.path == "/" {
            components.path = ""
        }
        guard let url = components.url else { throw Error.invalidURL }
        return url.absoluteString
    }

    package static func appending(_ endpointPath: String, to baseURL: String) throws(Error) -> URL {
        try appending(endpointPath, percentEncodedQuery: nil, to: baseURL)
    }

    /// The query-carrying form: Brave's search API is a GET whose parameters
    /// ride the URL, so the shared appending accepts one pre-encoded query
    /// string (nil leaves the URL query-free, byte-identical to the plain
    /// form). Callers encode it themselves because
    /// URLComponents.queryItems leaves a literal '+' unescaped, which
    /// form-style query decoding reads back as a space.
    package static func appending(
        _ endpointPath: String,
        percentEncodedQuery: String?,
        to baseURL: String
    ) throws(Error) -> URL {
        let normalized = try normalize(baseURL)
        guard var components = URLComponents(string: normalized) else { throw Error.invalidURL }
        let suffix = endpointPath.hasPrefix("/") ? endpointPath : "/\(endpointPath)"
        components.path += suffix
        components.percentEncodedQuery = percentEncodedQuery
        guard let url = components.url else { throw Error.invalidURL }
        return url
    }

    private static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || isIPv6Loopback(host) || isIPv4Loopback(host)
    }

    /// URLComponents keeps brackets around IPv6 hosts; strip them before
    /// comparing against the loopback form.
    private static func isIPv6Loopback(_ host: String) -> Bool {
        guard host.hasPrefix("["), host.hasSuffix("]") else { return false }
        return host.dropFirst().dropLast() == "::1"
    }

    /// Accepts only a valid dotted-quad IPv4 literal inside 127.0.0.0/8.
    /// DNS names beginning with "127." (e.g. 127.example.com) and
    /// malformed pseudo-IPv4 forms (127.0.0, 127.0.0.256) are rejected.
    private static func isIPv4Loopback(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        var octets: [Int] = []
        for part in parts {
            guard part.count <= 3, part.allSatisfy(\.isNumber),
                !(part.count > 1 && part.hasPrefix("0")),
                let value = Int(part), (0...255).contains(value)
            else { return false }
            octets.append(value)
        }
        return octets[0] == 127
    }
}
