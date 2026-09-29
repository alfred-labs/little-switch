import AsyncHTTPClient
import Foundation
import NIOHTTP1

public struct UpstreamWebSocketRequest: Sendable {
    public let url: URL
    public let headers: HTTPHeaders

    /// Derives a WebSocket handshake from an HTTP provider request. The
    /// destination and provider headers stay intact; the handshake owns its
    /// upgrade fields and carries no HTTP request body or representation.
    public init(upgrading request: HTTPClientRequest) throws {
        guard var parts = URLComponents(string: request.url), ["http", "https"].contains(parts.scheme ?? "") else {
            throw UpstreamWebSocketFailure(kind: .invalidRequest)
        }
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        guard let url = parts.url else { throw UpstreamWebSocketFailure(kind: .invalidRequest) }
        var headers = request.headers
        for name in Self.upgradeHeaders.union(["content-type", "accept", "content-encoding"]) {
            headers.remove(name: name)
        }
        try self.init(url: url, headers: headers)
    }

    public init(url: URL, headers: HTTPHeaders = .init()) throws {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = parts.scheme?.lowercased(),
            scheme == "ws" || scheme == "wss",
            let host = parts.host, !host.isEmpty,
            parts.user == nil, parts.password == nil, parts.fragment == nil,
            parts.port.map({ (1...65_535).contains($0) }) ?? true,
            headers.allSatisfy({ Self.validField(name: $0.name, value: $0.value) }),
            !headers.contains(where: { Self.upgradeHeaders.contains($0.name.lowercased()) })
        else { throw UpstreamWebSocketFailure(kind: .invalidRequest) }
        self.url = url
        self.headers = headers
    }

    private static let upgradeHeaders: Set<String> = [
        "host", "connection", "upgrade", "sec-websocket-key", "sec-websocket-version",
        "content-length", "transfer-encoding", "sec-websocket-protocol", "sec-websocket-extensions",
    ]

    private static func validField(name: String, value: String) -> Bool {
        let tokenPunctuation = "!#$%&'*+-.^_`|~".utf8
        return !name.isEmpty
            && name.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                    || tokenPunctuation.contains(byte)
            }
            && value.utf8.allSatisfy { $0 == 9 || ($0 >= 32 && $0 != 127) }
    }
}
