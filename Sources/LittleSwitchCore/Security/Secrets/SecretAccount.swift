import Foundation
import LittleSwitchCommon
import LittleSwitchSearch

public enum SecretAccount: Hashable, Sendable {
    case provider(UUID)
    /// Legacy: the credential-producing script as stored before scripts moved
    /// into the configuration; read once by the migration, then deleted.
    case script(UUID)
    case webSearch(WebSearchProvider)
    case monitoring(UUID)
    /// The gateway TLS leaf's private key. The certificate itself is public
    /// data on disk; only the key is a secret.
    case gatewayTLS

    var keychainAccount: String {
        switch self {
        case .provider(let id):
            id.uuidString
        case .script(let id):
            "script.\(id.uuidString)"
        case .webSearch(let provider):
            "web-search.\(provider.rawValue)"
        case .monitoring(let id):
            "monitoring.\(id.uuidString)"
        case .gatewayTLS:
            "tls.gateway"
        }
    }
}
