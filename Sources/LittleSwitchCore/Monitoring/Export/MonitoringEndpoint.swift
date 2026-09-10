import Darwin
import Foundation

public enum MonitoringEndpoint {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidURL
        case unsupportedScheme
        case insecureRemoteHTTP
        case forbiddenComponent
    }

    /// Validates a complete OTLP/HTTP destination without appending a signal path.
    public static func validate(_ raw: String) throws -> URL {
        let forbiddenCharacters = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard !raw.isEmpty, raw.rangeOfCharacter(from: forbiddenCharacters) == nil,
            let components = URLComponents(string: raw, encodingInvalidCharacters: false),
            let scheme = components.scheme?.lowercased()
        else {
            throw Error.invalidURL
        }
        guard scheme == "http" || scheme == "https" else {
            throw Error.unsupportedScheme
        }
        guard let separator = raw.range(of: "://") else {
            throw Error.invalidURL
        }
        guard let host = components.host, !host.isEmpty else {
            throw Error.invalidURL
        }
        guard components.user == nil, components.password == nil,
            components.query == nil, components.fragment == nil
        else {
            throw Error.forbiddenComponent
        }
        let authority = raw[separator.upperBound...].prefix { !"/?#".contains($0) }
        // Foundation represents both a missing port and an overflowing numeric port as nil.
        let hasValidPort = components.port.map { (1...65_535).contains($0) }
        guard !authority.hasSuffix(":"), components.rangeOfPort == nil || hasValidPort == true,
            let url = components.url
        else {
            throw Error.invalidURL
        }
        if scheme == "http", !isLoopback(host) {
            throw Error.insecureRemoteHTTP
        }
        return url
    }

    private static func isLoopback(_ host: String) -> Bool {
        // Darwin accepts IPv6 zone identifiers; HTTP requires an unscoped loopback literal.
        guard !host.contains("%") else {
            return false
        }
        if host.lowercased() == "localhost" {
            return true
        }
        var ipv4 = in_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 {
            return UInt32(bigEndian: ipv4.s_addr) >> 24 == 127
        }
        let address = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        var ipv6 = in6_addr()
        guard inet_pton(AF_INET6, address, &ipv6) == 1 else {
            return false
        }
        return withUnsafeBytes(of: ipv6) { bytes in
            bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
        }
    }
}
