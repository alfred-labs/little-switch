import Foundation

/// In-memory identity. Durable capability storage hashes the complete endpoint in Core.
public struct CustomToolCapabilityKey: Codable, Hashable, Sendable {
    public let providerID: UUID
    public let modelID: String
    public let endpoint: String
    public let wire: String

    public init(providerID: UUID, modelID: String, endpoint: String, wire: String) {
        self.providerID = providerID
        self.modelID = modelID
        self.endpoint = endpoint
        self.wire = wire
    }
}
