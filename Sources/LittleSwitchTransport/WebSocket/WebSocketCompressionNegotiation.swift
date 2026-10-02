import Foundation
import NIOHTTP1

/// Transport-owned negotiation: callers cannot inject extension headers. Only
/// one supported extension is accepted; the codec's permissive parser is never
/// used to validate an untrusted upgrade response.
enum WebSocketCompressionNegotiation: Sendable {
    struct Parameters: Sendable {
        let header: String
        let receiveWindow: Int
        let receiveNoContextTakeover: Bool
    }

    case none
    case perMessageDeflate(Parameters)

    static let offer = "permessage-deflate; client_max_window_bits"

    var enabled: Bool {
        if case .perMessageDeflate = self { return true }
        return false
    }

    static func negotiate(_ headers: HTTPHeaders) throws -> Self {
        let values = headers["Sec-WebSocket-Extensions"]
        guard !values.isEmpty else { return .none }
        guard values.count == 1, let value = values.first,
            value.utf8.allSatisfy({ $0 == 9 || (32...126).contains($0) })
        else { throw UpstreamWebSocketFailure(kind: .invalidUpgrade) }
        let parts = value.split(separator: ";", omittingEmptySubsequences: false).map(trim)
        guard parts.first == "permessage-deflate" else { throw UpstreamWebSocketFailure(kind: .invalidUpgrade) }
        var seen: Set<String> = []
        var normalized = ["permessage-deflate"]
        var receiveWindow = 15
        var receiveNoContextTakeover = false
        for part in parts.dropFirst() {
            let parameter = part.split(separator: "=", omittingEmptySubsequences: false).map(trim)
            guard let name = parameter.first, seen.insert(name).inserted else {
                throw UpstreamWebSocketFailure(kind: .invalidUpgrade)
            }
            switch name {
            case "client_no_context_takeover", "server_no_context_takeover":
                guard parameter.count == 1 else { throw UpstreamWebSocketFailure(kind: .invalidUpgrade) }
                normalized.append(name)
                if name == "server_no_context_takeover" { receiveNoContextTakeover = true }
            case "client_max_window_bits", "server_max_window_bits":
                guard parameter.count == 2 else { throw UpstreamWebSocketFailure(kind: .invalidUpgrade) }
                var size = parameter[1]
                if size.hasPrefix("\""), size.hasSuffix("\""), size.count >= 2 {
                    size = String(size.dropFirst().dropLast())
                }
                // The inflater accepts 8 bits, but the outbound raw-zlib
                // compressor needs at least 9. Never round a window upward.
                let minimum = name == "server_max_window_bits" ? 8 : 9
                guard let bits = Int(size), String(bits) == size, (minimum...15).contains(bits) else {
                    throw UpstreamWebSocketFailure(kind: .invalidUpgrade)
                }
                normalized.append("\(name)=\(size)")
                if name == "server_max_window_bits" { receiveWindow = bits }
            default:
                throw UpstreamWebSocketFailure(kind: .invalidUpgrade)
            }
        }
        return .perMessageDeflate(
            Parameters(
                header: normalized.joined(separator: "; "),
                receiveWindow: receiveWindow,
                receiveNoContextTakeover: receiveNoContextTakeover))
    }

    private static func trim(_ value: Substring) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
    }
}
