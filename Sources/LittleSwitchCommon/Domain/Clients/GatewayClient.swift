import Foundation

public enum GatewayClient: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case claude
    case codex
}
