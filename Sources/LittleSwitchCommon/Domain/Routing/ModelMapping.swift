import Foundation

public struct ModelMapping: Codable, Equatable, Hashable, Sendable {
    public var providerID: UUID
    public var modelID: String

    public init(providerID: UUID, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID
    }
}
